import Foundation
import AppKit
import IOKit
import os

private let motionLog = Logger(subsystem: "com.sunmemo.SunMemo", category: "MotionDetector")

/// Detects physical taps and slaps on the MacBook body or desk via the internal
/// Apple Silicon MEMS Accelerometer (SPU HID Device: UsagePage 0xFF00, Usage 3).
///
/// Triggers three tiers of physical motion interactions:
/// 1. 轻拍 (Light Tap / Breeze Shock): 拍一下掌托或轻敲桌面 -> 晾衣绳整体震荡微颤，卡片微风物理晃荡
/// 2. 连拍两下 (Double Tap within 450ms): 快速拍两下机身 -> 展开 / 隐藏晾衣绳 (Toggle Line)
private let kFieldX: UInt32 = (13 << 16) | 0
private let kFieldY: UInt32 = (13 << 16) | 1
private let kFieldZ: UInt32 = (13 << 16) | 2
private typealias IOHIDEventGetFloatValueFunc = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Double
private var globalGetFloatValue: IOHIDEventGetFloatValueFunc?

@MainActor
final class MotionDetector: ObservableObject {
    static let shared = MotionDetector()

    enum SensorStatus: Equatable {
        case checking, waitingForSamples, receiving, unavailable, noSamples
    }

    @Published private(set) var sensorStatus: SensorStatus = .checking

    var statusMessage: String {
        switch sensorStatus {
        case .checking: return L("Checking the motion sensor…")
        case .waitingForSamples: return L("Motion sensor found; waiting for data…")
        case .receiving: return L("Motion sensor connected and receiving data")
        case .unavailable: return L("No accessible motion sensor. Use the shortcut or menu to open the line.")
        case .noSamples: return L("The motion sensor is not sending data. Use the shortcut or menu to open the line.")
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            Demo.defaults.set(isEnabled, forKey: "motionTapEnabled")
            pendingSingleTapWorkItem?.cancel()
            pendingSingleTapWorkItem = nil
            lastTapTime = 0
            hasInitialized = false
        }
    }

    private weak var line: Line?
    private var isRunning = false

    init() {
        if Demo.defaults.object(forKey: "motionTapEnabled") == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = Demo.defaults.bool(forKey: "motionTapEnabled")
        }
    }

    // Function signatures for dynamic linking
    private typealias IOHIDEventSystemClientCreateFunc = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias IOHIDEventSystemClientSetMatchingFunc = @convention(c) (UnsafeMutableRawPointer?, CFDictionary?) -> Void
    private typealias IOHIDEventSystemClientCopyServicesFunc = @convention(c) (UnsafeMutableRawPointer?) -> CFArray?
    private typealias IOHIDServiceClientSetPropertyFunc = @convention(c) (UnsafeMutableRawPointer?, CFString?, CFTypeRef?) -> Bool
    private typealias IOHIDEventSystemClientRegisterEventCallbackFunc = @convention(c) (
        UnsafeMutableRawPointer?,
        @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void,
        UnsafeMutableRawPointer?,
        UnsafeMutableRawPointer?
    ) -> Void
    private typealias IOHIDEventSystemClientScheduleWithRunLoopFunc = @convention(c) (UnsafeMutableRawPointer?, CFRunLoop?, CFString?) -> Void
    private typealias IOHIDEventGetFloatValueFunc = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Double

    // State tracking
    private var hasInitialized = false
    private var lastX: Double = 0
    private var lastY: Double = 0
    private var lastZ: Double = 0

    private var lastImpactTime: TimeInterval = 0
    private var pendingSingleTapWorkItem: DispatchWorkItem?
    private var lastTapTime: TimeInterval = 0

    // Thresholds: elevated slightly to ~0.18g to prevent ordinary typing keystrokes from mis-triggering
    private let kTapThreshold = 0.18        // ~0.18g for physical tap on palm rest / desk
    private let kHardSlapThreshold = 0.68   // ~0.68g for hard physical slap
    private let kImpactDebounce = 0.14      // 140ms debounce to filter ringing oscillations

    func start(line: Line) {
        guard !isRunning else { return }
        self.line = line
        self.isRunning = true

        registerNotificationHooks()
        startHardwareAccelerometer()
    }

    private func registerNotificationHooks() {
        for name in ["com.sunmemo.tapShock", "com.tendedero.tapShock"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard self?.isEnabled == true else { return }
                    self?.line?.triggerTapShock(intensity: 1.2)
                }
            }
        }

        for name in ["com.sunmemo.doubleTap", "com.tendedero.doubleTap"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard self?.isEnabled == true else { return }
                    AppDelegate.shared?.toggle()
                }
            }
        }

        for name in ["com.sunmemo.hardSlap", "com.tendedero.hardSlap"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard self?.isEnabled == true else { return }
                    self?.line?.triggerHardSlap()
                }
            }
        }
    }

    private func startHardwareAccelerometer() {
        Thread { [weak self] in
            self?.runSensorLoop()
        }.start()
    }

    nonisolated private func reportStatus(_ status: SensorStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.sensorStatus = status
        }
    }

    nonisolated private func runSensorLoop() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            motionLog.info("IOKit not available for motion detection")
            reportStatus(.unavailable)
            return
        }

        guard let createSym = dlsym(iokit, "IOHIDEventSystemClientCreate"),
              let matchSym = dlsym(iokit, "IOHIDEventSystemClientSetMatching"),
              let copySym = dlsym(iokit, "IOHIDEventSystemClientCopyServices"),
              let setPropSym = dlsym(iokit, "IOHIDServiceClientSetProperty"),
              let regSym = dlsym(iokit, "IOHIDEventSystemClientRegisterEventCallback"),
              let schedSym = dlsym(iokit, "IOHIDEventSystemClientScheduleWithRunLoop"),
              let getFloatSym = dlsym(iokit, "IOHIDEventGetFloatValue") else {
            motionLog.info("SPU HID functions not found in IOKit")
            reportStatus(.unavailable)
            return
        }

        let clientCreate = unsafeBitCast(createSym, to: IOHIDEventSystemClientCreateFunc.self)
        let setMatching = unsafeBitCast(matchSym, to: IOHIDEventSystemClientSetMatchingFunc.self)
        let copyServices = unsafeBitCast(copySym, to: IOHIDEventSystemClientCopyServicesFunc.self)
        let setProperty = unsafeBitCast(setPropSym, to: IOHIDServiceClientSetPropertyFunc.self)
        let registerCallback = unsafeBitCast(regSym, to: IOHIDEventSystemClientRegisterEventCallbackFunc.self)
        let scheduleRunLoop = unsafeBitCast(schedSym, to: IOHIDEventSystemClientScheduleWithRunLoopFunc.self)
        let getFloatValue = unsafeBitCast(getFloatSym, to: IOHIDEventGetFloatValueFunc.self)

        guard let client = clientCreate(kCFAllocatorDefault) else {
            motionLog.info("Could not create IOHIDEventSystemClient")
            reportStatus(.unavailable)
            return
        }

        // Match AppleSPUHIDDevice Accelerometer (UsagePage 0xFF00, Usage 3)
        let matchDict: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 3
        ]
        setMatching(client, matchDict as CFDictionary)

        if let services = copyServices(client) as? [Any], let service = services.first {
            let servicePtr = Unmanaged<AnyObject>.passUnretained(service as AnyObject).toOpaque()
            // Request 100Hz updates (10,000 microseconds)
            let accepted = setProperty(servicePtr, "ReportInterval" as CFString, 10000 as CFNumber)
            motionLog.info("Found accelerometer; 100Hz request accepted: \(accepted)")
        } else {
            motionLog.info("No Apple SPU Accelerometer found (may be non-laptop or external)")
            reportStatus(.unavailable)
            return
        }

        reportStatus(.waitingForSamples)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.sensorStatus == .waitingForSamples else { return }
            self.sensorStatus = .noSamples
        }
        globalGetFloatValue = getFloatValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        registerCallback(client, { target, refcon, service, event in
            guard let refcon = refcon, let event = event, let getFloat = globalGetFloatValue else { return }
            let detector = Unmanaged<MotionDetector>.fromOpaque(refcon).takeUnretainedValue()
            let x = getFloat(event, kFieldX)
            let y = getFloat(event, kFieldY)
            let z = getFloat(event, kFieldZ)
            // App state, gesture state and pending actions all belong to the
            // main thread. Never read the UI's enabled switch on the HID thread.
            DispatchQueue.main.async {
                detector.processSample(x: x, y: y, z: z)
            }
        }, nil, selfPtr)

        scheduleRunLoop(client, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRun()
    }

    private func processSample(x: Double, y: Double, z: Double) {
        if sensorStatus != .receiving { sensorStatus = .receiving }
        guard isEnabled else { return }
        if !hasInitialized {
            hasInitialized = true
            lastX = x
            lastY = y
            lastZ = z
            return
        }

        let dx = x - lastX
        let dy = y - lastY
        let dz = z - lastZ
        let delta = sqrt(dx * dx + dy * dy + dz * dz)

        lastX = x
        lastY = y
        lastZ = z

        let now = CACurrentMediaTime()
        guard (now - lastImpactTime) > kImpactDebounce else { return }

        if delta >= kHardSlapThreshold {
            lastImpactTime = now
            lastTapTime = 0
            pendingSingleTapWorkItem?.cancel()
            pendingSingleTapWorkItem = nil

            line?.triggerHardSlap()
        } else if delta >= kTapThreshold {
            lastImpactTime = now
            let timeSinceLastTap = now - lastTapTime

            if timeSinceLastTap >= 0.14 && timeSinceLastTap <= 0.48 {
                // Double Tap!
                lastTapTime = 0
                pendingSingleTapWorkItem?.cancel()
                pendingSingleTapWorkItem = nil

                AppDelegate.shared?.toggle()
            } else {
                // First tap: schedule pending single tap
                lastTapTime = now
                pendingSingleTapWorkItem?.cancel()

                let intensity = min(max(delta / 0.28, 0.8), 2.2)
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.isEnabled else { return }
                        self.line?.triggerTapShock(intensity: intensity)
                    }
                }
                pendingSingleTapWorkItem = work
                // Wait for the entire double-tap window before emitting a single tap.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48, execute: work)
            }
        }
    }
}
