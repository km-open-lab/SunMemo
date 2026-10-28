import AppKit
import Combine
import Sparkle

/// Sparkle owns checking, verified downloads, installation and relaunch.
@MainActor
final class UpdateChecker: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()

    @Published private(set) var isChecking = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var checkStatus = ""

    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    private var pendingInstallation: (() -> Void)?
    private var editingTimer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var autoCheckEnabled: Bool {
        get {
            controller?.updater.automaticallyChecksForUpdates ??
                (Demo.defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ??
                 Demo.defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true)
        }
        set {
            // Preserve the existing preference when migrating; Sparkle owns it afterwards.
            Demo.defaults.set(newValue, forKey: "SUEnableAutomaticChecks")
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func start() {
        guard !Demo.isActive, controller == nil else { return }
        if Demo.defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let previous = Demo.defaults.object(forKey: "autoCheckUpdates") as? Bool {
            Demo.defaults.set(previous, forKey: "SUEnableAutomaticChecks")
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                       updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in self?.isChecking = !canCheck }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        controller.startUpdater()
    }

    func checkForUpdates(userInitiated: Bool = false) {
        start()
        guard let controller, controller.updater.canCheckForUpdates else { return }
        checkStatus = "正在检查更新..."
        if userInitiated {
            controller.checkForUpdates(nil)
        } else {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        checkStatus = "发现新版本 v\(item.displayVersionString)，可在应用内安装并重启"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error as NSError? {
            if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
                availableVersion = nil
                checkStatus = "已是最新版本 (v\(currentVersion))"
            } else {
                checkStatus = "更新未完成：\(error.localizedDescription)"
            }
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        deferInstallationIfEditing(installHandler)
    }

    /// Do not terminate the process while a memo editor has unsaved content.
    /// Sparkle resumes only after the user saves or closes the editor.
    func deferInstallationIfEditing(_ installHandler: @escaping () -> Void) -> Bool {
        guard Self.mustWaitForEditing else { return false }
        pendingInstallation = installHandler
        checkStatus = "更新已就绪，请先保存或关闭正在编辑的便签，随后将安装并重启"
        editingTimer?.invalidate()
        editingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeInstallationIfReady() }
        }
        return true
    }

    private static var mustWaitForEditing: Bool {
        QuickMemoWindowController.shared.hasUnsavedChanges ||
            MemoPreviewWindowController.shared.isEditingActive
    }

    func resumeInstallationIfReady() {
        guard !Self.mustWaitForEditing, let install = pendingInstallation else { return }
        pendingInstallation = nil
        editingTimer?.invalidate()
        editingTimer = nil
        install()
    }
}
