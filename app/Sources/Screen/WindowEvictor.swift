import AppKit
import ApplicationServices

enum StuckReason: Equatable { case noAccessibility, matchFailed, moveFailed, fighting, notManaged }
struct StuckWindow: Equatable {
    let pid: pid_t
    let appName: String
    let windowNumber: Int
    let reason: StuckReason
}

/// Lifecycle, providers, reports and logging deduplication are main-thread confined.
/// AX elements, per-scan caches and the retry tracker belong exclusively to axQueue.
/// The main thread never waits for axQueue. Each AX message has a 250 ms timeout.
final class WindowEvictor {
    private let ownPID: pid_t
    private let targetBoundsCG: () -> CGRect?
    private let mainVisibleCG: () -> CGRect?
    var isEnabled = true {
        didSet {
            precondition(Thread.isMainThread)
            guard oldValue != isEnabled else { return }
            invalidateScan()
            if isEnabled {
                if timer != nil { scanNow() }
            } else {
                publish([])
            }
        }
    }
    var movesWindows: Bool = true {
        didSet {
            precondition(Thread.isMainThread)
            guard oldValue != movesWindows else { return }
            invalidateScan()
            scanNow()
        }
    }
    var onStuckChanged: (([StuckWindow]) -> Void)?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var generation = 0
    private var scanningTarget: CGRect?
    private var stuck: [StuckWindow] = []
    private let axQueue = DispatchQueue(label: "Reverie.evictor.ax", qos: .userInitiated)
    private var tracker = EvictionTracker() // axQueue only
    private static let logQueue = DispatchQueue(label: "Reverie.evictor.log")
    // Keep in sync with the standalone scripts/check-window.swift candidate filter.
    // 系统界面按 bundle ID 认：进程名会本地化（中文系统里程序坞叫「程序坞」），按名字认会漏。
    static let systemBundleIDs: Set<String> = [
        "com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.systemuiserver", "com.apple.loginwindow", "com.apple.screencaptureui", "com.apple.ScreenSaver.Engine",
        "com.apple.Spotlight", "com.apple.TextInputMenuAgent", "com.apple.TextInputSwitcher", "com.apple.wallpaper.agent"
    ]
    private static let systemOwners: Set<String> = [
        "Dock", "Window Server", "WindowServer", "Control Center", "ControlCenter",
        "Notification Center", "NotificationCenter", "SystemUIServer", "loginwindow",
        "screencaptureui", "Screenshot", "ScreenSaverEngine"
    ]
    private struct Candidate {
        let pid: pid_t
        let app: String
        let number: Int
        let layer: Int
        let bounds: CGRect
        var key: String { "\(pid):\(number)" }
        func failure(_ reason: StuckReason) -> StuckWindow {
            StuckWindow(pid: pid, appName: app, windowNumber: number, reason: reason)
        }
    }

    private final class Scan {
        // Immutable main-thread snapshot; mutable fields below are axQueue-only.
        let token: Int
        let target: CGRect
        let visible: CGRect?
        let candidates: [Candidate]
        let previous: [StuckWindow]
        var windows: [pid_t: [AXUIElement]] = [:]
        var unresponsive: Set<pid_t> = []
        var completed: Set<String> = []
        var failures: [StuckWindow] = []

        init(token: Int, target: CGRect, visible: CGRect?, candidates: [Candidate], previous: [StuckWindow]) {
            self.token = token
            self.target = target
            self.visible = visible
            self.candidates = candidates
            self.previous = previous
        }

        func previousReason(_ candidate: Candidate) -> StuckReason? {
            previous.first { $0.pid == candidate.pid && $0.windowNumber == candidate.number }?.reason
        }
    }

    private enum Gate { case cancelled, dragging, ready }

    init(ownPID: pid_t = getpid(), targetBoundsCG: @escaping () -> CGRect?,
         mainVisibleCG: @escaping () -> CGRect?) {
        self.ownPID = ownPID
        self.targetBoundsCG = targetBoundsCG
        self.mainVisibleCG = mainVisibleCG
    }

    func start() {
        precondition(Thread.isMainThread)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.scanNow() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.scanNow()
            }))
        }
        let screens = NotificationCenter.default
        observers.append((screens, screens.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            self?.invalidateScan()
            self?.scanNow()
        }))
        scanNow()
    }

    func stop() {
        precondition(Thread.isMainThread)
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        invalidateScan()
        publish([])
    }

    deinit {
        timer?.invalidate()
        observers.forEach { $0.0.removeObserver($0.1) }
    }

    private func invalidateScan() {
        precondition(Thread.isMainThread)
        generation += 1
        scanningTarget = nil
    }

    func scanNow() {
        precondition(Thread.isMainThread)
        guard isEnabled else { publish([]); return }
        guard let target = targetBoundsCG(), !target.isEmpty else {
            invalidateScan()
            publish([])
            return
        }
        // Coalesce timer ticks while work is in flight, but never keep a stale screen snapshot.
        if let active = scanningTarget {
            if active == target { return }
            invalidateScan()
        }
        guard let candidates = candidates(on: target) else { return }
        generation += 1
        if !movesWindows {
            candidates.forEach { log($0, result: "notManaged") }
            publish(candidates.map { $0.failure(.notManaged) })
            return
        }
        // While dragging, only refresh known failures. Never consume the retry budget.
        if NSEvent.pressedMouseButtons != 0 {
            let keys = Set(candidates.map(\.key))
            publish(stuck.filter { keys.contains("\($0.pid):\($0.windowNumber)") })
            return
        }
        guard !candidates.isEmpty else { publish([]); return }
        let scan = Scan(token: generation, target: target, visible: mainVisibleCG(),
                        candidates: candidates, previous: stuck)
        scanningTarget = target
        axQueue.async { [weak self] in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            for candidate in scan.candidates {
                guard self.mayProceed(candidate, scan: scan) else { continue }
                if !trusted {
                    self.complete(candidate, reason: .noAccessibility, scan: scan)
                } else if let visible = scan.visible, !visible.isEmpty,
                          !ScreenGeometry.isOnTarget(visible, target: scan.target, minOverlap: 0) {
                    self.process(candidate, scan: scan)
                } else {
                    self.complete(candidate, reason: .moveFailed, scan: scan)
                }
            }
        }
    }

    /// Main thread only. A changed screen invalidates the whole round, including partial reports.
    private func isCurrent(_ scan: Scan) -> Bool {
        precondition(Thread.isMainThread)
        guard generation == scan.token, isEnabled, movesWindows else { return false }
        guard targetBoundsCG() == scan.target, mainVisibleCG() == scan.visible else {
            invalidateScan()
            scanNow()
            return false
        }
        return true
    }

    /// Only the AX queue waits for the main thread, never the reverse. Recheck before writes,
    /// because the user may start a drag or disable management during an AX round trip.
    private func gate(_ scan: Scan) -> Gate {
        DispatchQueue.main.sync {
            guard isCurrent(scan) else { return .cancelled }
            return NSEvent.pressedMouseButtons == 0 ? .ready : .dragging
        }
    }

    private func mayProceed(_ candidate: Candidate, scan: Scan) -> Bool {
        switch gate(scan) {
        case .cancelled: return false
        case .dragging:
            complete(candidate, reason: scan.previousReason(candidate), scan: scan)
            return false
        case .ready: return true
        }
    }

    /// Queue results immediately, not just at the end of a round. Keep previous failures for
    /// unfinished windows so a partial success cannot prematurely cover a stuck window.
    private func complete(_ candidate: Candidate, reason: StuckReason?, scan: Scan, moved: Bool = false) {
        guard scan.completed.insert(candidate.key).inserted else { return }
        if let reason { scan.failures.append(candidate.failure(reason)) }
        let failures = scan.failures
        let pendingPrevious = scan.previous.filter {
            !scan.completed.contains("\($0.pid):\($0.windowNumber)")
        }
        let finished = scan.completed.count == scan.candidates.count
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(scan) else { return }
            if let reason { self.log(candidate, result: String(describing: reason)) }
            else if moved { self.log(candidate, result: "moved") }
            if !failures.isEmpty {
                self.publish(failures + pendingPrevious)
            }
            // Publishing can synchronously toggle management or stop the evictor.
            guard finished, self.isCurrent(scan) else { return }
            self.scanningTarget = nil
            // Fullscreen transitions can close/move other windows, and new ones can appear.
            // An empty report means clean: only emit it after a fresh CG snapshot proves it.
            guard let live = self.candidates(on: scan.target) else { return }
            let keys = Set(live.map(\.key))
            let stillStuck = failures.filter { keys.contains("\($0.pid):\($0.windowNumber)") }
            guard live.isEmpty || !stillStuck.isEmpty else { return }
            self.publish(stillStuck)
        }
    }

    private func candidates(on target: CGRect) -> [Candidate]? {
        precondition(Thread.isMainThread)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  let app = info[kCGWindowOwnerName as String] as? String,
                  !Self.systemOwners.contains(app),
                  !Self.systemBundleIDs.contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""),
                  let number = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int, (0...24).contains(layer),
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw),
                  ScreenGeometry.isOnTarget(bounds, target: target) else { return nil }
            return Candidate(pid: pid, app: app, number: number, layer: layer, bounds: bounds)
        }
    }

    // Everything below up to publish runs exclusively on axQueue.
    private func note(_ result: AXError, pid: pid_t, scan: Scan) {
        // Stop contacting a process after a transport timeout (or global AX disablement).
        // AttributeUnsupported / NoValue are window-local and must not poison other windows.
        if result == .cannotComplete || result == .apiDisabled {
            scan.unresponsive.insert(pid)
        }
    }

    private func attribute(_ window: AXUIElement, _ name: String,
                           candidate: Candidate, scan: Scan) -> CFTypeRef? {
        guard !scan.unresponsive.contains(candidate.pid) else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, name as CFString, &value)
        note(result, pid: candidate.pid, scan: scan)
        return result == .success ? value : nil
    }

    private func match(_ candidate: Candidate, scan: Scan) -> AXUIElement? {
        guard !scan.unresponsive.contains(candidate.pid) else { return nil }
        if scan.windows[candidate.pid] == nil {
            // Cache failure as well as success: kAXWindows is requested at most once per PID.
            scan.windows[candidate.pid] = []
            let app = AXUIElementCreateApplication(candidate.pid)
            let timeout = AXUIElementSetMessagingTimeout(app, 0.25)
            note(timeout, pid: candidate.pid, scan: scan)
            guard timeout == .success else { return nil }
            guard let windows = attribute(app, kAXWindowsAttribute, candidate: candidate, scan: scan)
                    as? [AXUIElement] else { return nil }
            scan.windows[candidate.pid] = windows
        }
        var matches: [AXUIElement] = []
        for window in scan.windows[candidate.pid] ?? [] {
            guard !scan.unresponsive.contains(candidate.pid), gate(scan) == .ready else { return nil }
            let timeout = AXUIElementSetMessagingTimeout(window, 0.25)
            note(timeout, pid: candidate.pid, scan: scan)
            guard timeout == .success else { continue }
            guard let r = bounds(window, candidate: candidate, scan: scan) else { continue }
            let c = candidate.bounds
            if abs(r.minX - c.minX) <= 2 && abs(r.minY - c.minY) <= 2
                && abs(r.width - c.width) <= 2 && abs(r.height - c.height) <= 2 {
                matches.append(window)
            }
        }
        return !scan.unresponsive.contains(candidate.pid) && matches.count == 1 ? matches[0] : nil
    }

    private func bounds(_ window: AXUIElement, candidate: Candidate, scan: Scan) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute, candidate: candidate, scan: scan),
              let sizeValue = attribute(window, kAXSizeAttribute, candidate: candidate, scan: scan),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func fullscreen(_ window: AXUIElement, candidate: Candidate, scan: Scan) -> Bool? {
        (attribute(window, "AXFullScreen", candidate: candidate, scan: scan) as? NSNumber)?.boolValue
    }

    private func process(_ candidate: Candidate, scan: Scan) {
        guard let window = match(candidate, scan: scan) else {
            guard mayProceed(candidate, scan: scan) else { return }
            complete(candidate, reason: .matchFailed, scan: scan)
            return
        }
        let isFullscreen = fullscreen(window, candidate: candidate, scan: scan)
        guard mayProceed(candidate, scan: scan) else { return }
        guard !scan.unresponsive.contains(candidate.pid) else {
            complete(candidate, reason: .matchFailed, scan: scan)
            return
        }
        if isFullscreen == true {
            // Check budget before exiting fullscreen too: giveUp means no mutations.
            guard tracker.decide(windowKey: candidate.key, now: ProcessInfo.processInfo.systemUptime) != .giveUp else {
                complete(candidate, reason: .fighting, scan: scan)
                return
            }
            let result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            note(result, pid: candidate.pid, scan: scan)
            guard result == .success else {
                complete(candidate, reason: .moveFailed, scan: scan)
                return
            }
            waitForFullscreen(window, candidate: candidate, scan: scan,
                              deadline: ProcessInfo.processInfo.systemUptime + 1.5)
        } else {
            move(window, candidate: candidate, scan: scan, budgetConsumed: false)
        }
    }

    private func waitForFullscreen(_ window: AXUIElement, candidate: Candidate, scan: Scan,
                                   deadline: TimeInterval) {
        axQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.mayProceed(candidate, scan: scan) else { return }
            guard !scan.unresponsive.contains(candidate.pid) else {
                self.complete(candidate, reason: .matchFailed, scan: scan)
                return
            }
            if self.fullscreen(window, candidate: candidate, scan: scan) == false {
                self.move(window, candidate: candidate, scan: scan, budgetConsumed: true)
            } else if scan.unresponsive.contains(candidate.pid)
                        || ProcessInfo.processInfo.systemUptime >= deadline {
                self.complete(candidate, reason: .moveFailed, scan: scan)
            } else {
                self.waitForFullscreen(window, candidate: candidate, scan: scan, deadline: deadline)
            }
        }
    }

    private func move(_ window: AXUIElement, candidate: Candidate, scan: Scan, budgetConsumed: Bool) {
        guard mayProceed(candidate, scan: scan) else { return }
        guard !scan.unresponsive.contains(candidate.pid) else {
            complete(candidate, reason: .matchFailed, scan: scan)
            return
        }
        guard AXIsProcessTrusted() else {
            complete(candidate, reason: .noAccessibility, scan: scan)
            return
        }
        guard let current = bounds(window, candidate: candidate, scan: scan), let visible = scan.visible else {
            complete(candidate, reason: .moveFailed, scan: scan)
            return
        }
        guard ScreenGeometry.isOnTarget(current, target: scan.target) else {
            complete(candidate, reason: nil, scan: scan)
            return
        }
        guard mayProceed(candidate, scan: scan) else { return }
        if !budgetConsumed && tracker.decide(windowKey: candidate.key, now: ProcessInfo.processInfo.systemUptime) == .giveUp {
            complete(candidate, reason: .fighting, scan: scan)
            return
        }
        let destination = ScreenGeometry.relocate(current, from: scan.target, into: visible)
        var size = destination.size
        var point = destination.origin
        var resized = true
        if size != current.size {
            let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString,
                                                     AXValueCreate(.cgSize, &size)!)
            note(result, pid: candidate.pid, scan: scan)
            resized = result == .success
        }
        // Resizing is another blocking AX message: revalidate before the position write.
        guard mayProceed(candidate, scan: scan) else { return }
        guard !scan.unresponsive.contains(candidate.pid) else {
            complete(candidate, reason: .moveFailed, scan: scan)
            return
        }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString,
                                                 AXValueCreate(.cgPoint, &point)!)
        note(result, pid: candidate.pid, scan: scan)
        let actual = bounds(window, candidate: candidate, scan: scan)
        let success = resized && result == .success && actual.map {
            !ScreenGeometry.isOnTarget($0, target: scan.target) && visible.contains($0)
        } == true
        complete(candidate, reason: success ? nil : .moveFailed, scan: scan, moved: success)
    }

    private func publish(_ failures: [StuckWindow]) {
        precondition(Thread.isMainThread)
        let sorted = failures.sorted { ($0.pid, $0.windowNumber) < ($1.pid, $1.windowNumber) }
        guard sorted != stuck else { return }
        stuck = sorted
        onStuckChanged?(sorted)
    }

    private var lastLogged: [String: String] = [:]

    private func log(_ candidate: Candidate, result: String) {
        precondition(Thread.isMainThread)
        // 同一窗口结果没变就不重复写（让出期间每 0.5 秒扫一次）。
        guard lastLogged[candidate.key] != result else { return }
        lastLogged[candidate.key] = result
        if lastLogged.count > 200 { lastLogged.removeAll() }
        let date = Date()
        let app = candidate.app
        let layer = candidate.layer
        Self.logQueue.async {
            do {
                let directory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/Reverie", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("evictor.log")
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let record: [String: Any] = ["time": ISO8601DateFormatter().string(from: date),
                                            "app": app, "layer": layer, "result": result]
                var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                data.append(0x0A)
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: data)
            } catch {
                NSLog("Reverie evictor log write failed: %@", error.localizedDescription)
            }
        }
    }
}
