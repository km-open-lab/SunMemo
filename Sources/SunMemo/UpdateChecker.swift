import AppKit
import SwiftUI

/// Release information parsed from GitHub Releases API
struct ReleaseInfo: Equatable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: URL
    let dmgDownloadUrl: URL?
    let publishedAt: Date?

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }
}

/// Automatically checks GitHub Releases for new SunMemo versions and notifies the user.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var isChecking: Bool = false
    @Published var availableUpdate: ReleaseInfo? = nil
    @Published var lastCheckedDate: Date? = nil
    @Published var checkStatus: String = ""

    private let repoOwner = "km-open-lab"
    private let repoName = "SunMemo"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }

    private var checkTimer: Timer?

    // MARK: - Lifecycle

    func start() {
        guard autoCheckEnabled else { return }

        // Initial check 4 seconds after app launch so startup is instant
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.checkForUpdates(userInitiated: false)
        }

        // Periodic check once every 24 hours
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoCheckEnabled else { return }
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    // MARK: - Check Logic

    func checkForUpdates(userInitiated: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        checkStatus = "正在检查更新..."

        let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("SunMemo-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isChecking = false
                self.lastCheckedDate = Date()

                if let error {
                    self.checkStatus = "检查失败：网络不可用"
                    if userInitiated {
                        self.showErrorAlert(message: "无法连接到更新服务器，请检查网络连接。\n(\(error.localizedDescription))")
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlUrlStr = json["html_url"] as? String,
                      let htmlUrl = URL(string: htmlUrlStr) else {
                    self.checkStatus = "暂未发现更新"
                    if userInitiated {
                        self.showUpToDateAlert()
                    }
                    return
                }

                let name = json["name"] as? String ?? tagName
                let body = json["body"] as? String ?? ""

                // Extract DMG asset download URL if available
                var dmgUrl: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let assetName = asset["name"] as? String,
                           assetName.lowercased().hasSuffix(".dmg"),
                           let downloadStr = asset["browser_download_url"] as? String,
                           let url = URL(string: downloadStr) {
                            dmgUrl = url
                            break
                        }
                    }
                }

                let release = ReleaseInfo(
                    tagName: tagName,
                    name: name,
                    body: body,
                    htmlUrl: htmlUrl,
                    dmgDownloadUrl: dmgUrl,
                    publishedAt: nil
                )

                if Self.isVersion(release.version, newerThan: self.currentVersion) {
                    self.availableUpdate = release
                    self.checkStatus = "发现新版本 v\(release.version)"

                    let ignoredVersion = UserDefaults.standard.string(forKey: "ignoredUpdateVersion")
                    if userInitiated || ignoredVersion != release.version {
                        self.showUpdateAlert(for: release)
                    }
                } else {
                    self.availableUpdate = nil
                    self.checkStatus = "已是最新版本 (v\(self.currentVersion))"
                    if userInitiated {
                        self.showUpToDateAlert()
                    }
                }
            }
        }.resume()
    }

    // MARK: - UI Alerts

    func showUpdateAlert(for release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "✨ 发现 SunMemo 新版本 v\(release.version)"
        alert.informativeText = "当前版本：v\(currentVersion)\n最新版本：v\(release.version)\n\n\(release.name)\n\n更新说明：\n\(release.body.trimmingCharacters(in: .whitespacesAndNewlines))"
        alert.alertStyle = .informational

        alert.addButton(withTitle: "🚀 立即下载安装")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "忽略此版本")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Direct download DMG or open release page
            if let dmgUrl = release.dmgDownloadUrl {
                NSWorkspace.shared.open(dmgUrl)
            } else {
                NSWorkspace.shared.open(release.htmlUrl)
            }
        } else if response == .alertThirdButtonReturn {
            UserDefaults.standard.set(release.version, forKey: "ignoredUpdateVersion")
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "当前已是最新版本"
        alert.informativeText = "SunMemo v\(currentVersion) 已经是最新版本，无需更新。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Version Comparison

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let rParts = remote.split(separator: ".").compactMap { Int($0) }
        let lParts = local.split(separator: ".").compactMap { Int($0) }
        let count = max(rParts.count, lParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
