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

final class MotionDetector: ObservableObject {
    static let shared = MotionDetector()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "motionTapEnabled")
            if !isEnabled {
                pendingSingleTapWorkItem?.cancel()
                pendingSingleTapWorkItem = nil
            }
        }
    }

    private weak var line: Line?
    private var isRunning = false
    private var client: UnsafeMutableRawPointer?

    init() {
        if UserDefaults.standard.object(forKey: "motionTapEnabled") == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "motionTapEnabled")
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

    private func runSensorLoop() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            motionLog.info("IOKit not available for motion detection")
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
            return
        }
        self.client = client

        // Match AppleSPUHIDDevice Accelerometer (UsagePage 0xFF00, Usage 3)
        let matchDict: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 3
        ]
        setMatching(client, matchDict as CFDictionary)

        if let services = copyServices(client) as? [Any], let service = services.first {
            let servicePtr = Unmanaged<AnyObject>.passUnretained(service as AnyObject).toOpaque()
            // Request 100Hz updates (10,000 microseconds)
            _ = setProperty(servicePtr, "ReportInterval" as CFString, 10000 as CFNumber)
            motionLog.info("Activated Apple Silicon Accelerometer at 100Hz")
        } else {
            motionLog.info("No Apple SPU Accelerometer found (may be non-laptop or external)")
            return
        }

        globalGetFloatValue = getFloatValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        registerCallback(client, { target, refcon, service, event in
            guard let refcon = refcon, let event = event, let getFloat = globalGetFloatValue else { return }
            let detector = Unmanaged<MotionDetector>.fromOpaque(refcon).takeUnretainedValue()
            let x = getFloat(event, kFieldX)
            let y = getFloat(event, kFieldY)
            let z = getFloat(event, kFieldZ)
            detector.processSample(x: x, y: y, z: z)
        }, nil, selfPtr)

        scheduleRunLoop(client, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        CFRunLoopRun()
    }

    private func processSample(x: Double, y: Double, z: Double) {
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
            pendingSingleTapWorkItem?.cancel()
            pendingSingleTapWorkItem = nil

            DispatchQueue.main.async { [weak self] in
                self?.line?.triggerHardSlap()
            }
        } else if delta >= kTapThreshold {
            lastImpactTime = now
            let timeSinceLastTap = now - lastTapTime

            if timeSinceLastTap >= 0.14 && timeSinceLastTap <= 0.48 {
                // Double Tap!
                lastTapTime = 0
                pendingSingleTapWorkItem?.cancel()
                pendingSingleTapWorkItem = nil

                DispatchQueue.main.async {
                    AppDelegate.shared?.toggle()
                }
            } else {
                // First tap: schedule pending single tap
                lastTapTime = now
                pendingSingleTapWorkItem?.cancel()

                let intensity = min(max(delta / 0.28, 0.8), 2.2)
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        self?.line?.triggerTapShock(intensity: intensity)
                    }
                }
                pendingSingleTapWorkItem = work
                // Dwell 320ms to distinguish from double tap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
            }
        }
    }
}
