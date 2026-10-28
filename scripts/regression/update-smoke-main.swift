import AppKit
import Sparkle

// Runs only in a separate fixture bundle with its own bundle ID and preferences.
// The replacement fixture uses this launcher with the real app's frameworks and
// resources, so relaunch can be checked without reading personal memo files.
@MainActor
final class UpdateSmoke: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.infoDictionary?["CFBundleVersion"] as? String == "9000001" {
            let result = Bundle.main.infoDictionary?["SunMemoSmokeResultPath"] as! String
            try! Data("installed-and-relaunched".utf8).write(to: URL(fileURLWithPath: result))
            NSApp.terminate(nil)
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: self, userDriverDelegate: nil)
        controller!.startUpdater()
        controller!.checkForUpdates(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { UpdateSmoke() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
