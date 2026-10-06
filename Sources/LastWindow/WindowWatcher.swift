import AppKit
import ApplicationServices
import LastWindowCore
import os

private let log = Logger(subsystem: "com.adamstahl.LastWindow", category: "watcher")

/// Private but long-standing API (used by Rectangle, AltTab, etc.) mapping an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// Private SkyLight Spaces APIs (used by yabai, AltTab): which Spaces a window is on, and which are shown.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

/// Watches every regular app via Accessibility and quits it once its last standard window closes.
@MainActor
final class WindowWatcher: NSObject {
    var isEnabled = true
    var excluded: Set<String> = []

    private final class Watched {
        let app: NSRunningApplication
        let element: AXUIElement
        let observer: AXObserver
        var hadStandardWindow = false
        /// Standard windows seen via AX. AX only lists windows on the current Space, so these
        /// let us notice windows that still live on another Space.
        var knownWindowIDs: Set<CGWindowID> = []
        /// Known windows ever seen on more than one Space (assigned to All Desktops).
        var onAllSpaces: Set<CGWindowID> = []
        var pendingCheck: Task<Void, Never>?

        init(app: NSRunningApplication, element: AXUIElement, observer: AXObserver) {
            self.app = app
            self.element = element
            self.observer = observer
        }
    }

    private var watched: [pid_t: Watched] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for app in NSWorkspace.shared.runningApplications {
            watch(app, attemptsLeft: 1)
        }
        log.info("Watching \(self.watched.count) apps")
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // A freshly launched app often isn't ready to accept AX observers yet.
        Task {
            try? await Task.sleep(for: .seconds(1))
            watch(app, attemptsLeft: 5)
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let entry = watched.removeValue(forKey: app.processIdentifier) else { return }
        entry.pendingCheck?.cancel()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
    }

    private func watch(_ app: NSRunningApplication, attemptsLeft: Int) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, !app.isTerminated, watched[pid] == nil,
              pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observerRef: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observerRef) == .success, let observer = observerRef else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Destroyed is registered on the app element: registering it on individual windows
        // succeeds but never fires (macOS 27). On the app it fires for every destroyed descendant.
        var result = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        if result == .success {
            result = AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        guard result == .success else {
            if attemptsLeft > 1 {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    watch(app, attemptsLeft: attemptsLeft - 1)
                }
            } else {
                log.debug("Could not observe \(app.bundleIdentifier ?? "pid \(pid)"): \(result.rawValue)")
            }
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let entry = Watched(app: app, element: element, observer: observer)
        watched[pid] = entry
        remember(windows(of: element), in: entry)
    }

    fileprivate func handle(observer: AXObserver, element: AXUIElement, notification: String) {
        guard let entry = watched.values.first(where: { CFEqual($0.observer, observer) }) else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            remember([element], in: entry)
        case kAXUIElementDestroyedNotification:
            scheduleCheck(entry)
        default:
            break
        }
    }

    /// Debounced so a window that is closed and immediately replaced doesn't trigger a quit.
    private func scheduleCheck(_ entry: Watched) {
        entry.pendingCheck?.cancel()
        entry.pendingCheck = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            check(entry)
        }
    }

    private func check(_ entry: Watched) {
        guard !entry.app.isTerminated else { return }
        let axWindows = windows(of: entry.element)
        let axCount = remember(axWindows, in: entry)
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let knownSpaces = spaces(for: entry.knownWindowIDs)
        entry.onAllSpaces.formUnion(WindowCount.onMultipleSpaces(knownSpaces))
        entry.knownWindowIDs = WindowCount.stillOpen(
            known: entry.knownWindowIDs,
            live: WindowCount.liveWindowIDs(in: infos, pid: entry.app.processIdentifier),
            listedByAX: Set(axWindows.compactMap(windowID)),
            spaces: knownSpaces,
            visibleSpaces: visibleSpaces(),
            onAllSpaces: entry.onAllSpaces,
            onscreen: WindowCount.onscreenWindowIDs(in: infos, pid: entry.app.processIdentifier),
            screenLocked: isScreenLocked()
        )
        entry.onAllSpaces.formIntersection(entry.knownWindowIDs)

        let decision = QuitPolicy.decide(
            enabled: isEnabled,
            bundleID: entry.app.bundleIdentifier,
            excluded: excluded,
            hadStandardWindow: entry.hadStandardWindow,
            axStandardCount: axCount,
            knownWindowsAlive: entry.knownWindowIDs.count
        )
        let name = entry.app.bundleIdentifier ?? "pid \(entry.app.processIdentifier)"
        log.info("\(name, privacy: .public): ax=\(axCount) known=\(entry.knownWindowIDs.count) had=\(entry.hadStandardWindow) -> \(String(describing: decision), privacy: .public)")
        if decision == .quit {
            entry.hadStandardWindow = false
            entry.app.terminate()
        }
    }

    /// Records standard windows among `windows`; returns how many there were.
    @discardableResult
    private func remember(_ windows: [AXUIElement], in entry: Watched) -> Int {
        let standard = windows.filter(isStandardWindow)
        if !standard.isEmpty { entry.hadStandardWindow = true }
        let ids = Set(standard.compactMap(windowID))
        entry.knownWindowIDs.formUnion(ids)
        entry.onAllSpaces.formUnion(WindowCount.onMultipleSpaces(spaces(for: ids)))
        return standard.count
    }

    private func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success ? id : nil
    }

    private func spaces(for windowIDs: Set<CGWindowID>) -> [CGWindowID: Set<UInt64>] {
        let cid = CGSMainConnectionID()
        var result: [CGWindowID: Set<UInt64>] = [:]
        for id in windowIDs {
            let spaces = CGSCopySpacesForWindows(cid, 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] ?? []
            result[id] = Set(spaces.map(\.uint64Value))
        }
        return result
    }

    /// The Space currently shown on each display.
    private func visibleSpaces() -> Set<UInt64> {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] ?? []
        return Set(displays.compactMap { ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64 })
    }

    private func isScreenLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value) == .success else { return false }
        return (value as? String) == kAXStandardWindowSubrole
    }
}

private func axCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    // Observer sources are only ever added to the main run loop, so this is always on the main thread.
    nonisolated(unsafe) let observer = observer, element = element, notification = notification
    MainActor.assumeIsolated {
        watcher.handle(observer: observer, element: element, notification: notification as String)
    }
}
