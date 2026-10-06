public enum WindowCount {
    /// Window IDs owned by `pid` in a `CGWindowListCopyWindowInfo` result. Apps keep
    /// hidden helper windows here too, so callers should only compare against IDs
    /// they have already seen through Accessibility.
    public static func liveWindowIDs(in infos: [[String: Any]], pid: Int32) -> Set<UInt32> {
        Set(infos.compactMap { info in
            (info["kCGWindowOwnerPID"] as? Int32) == pid ? info["kCGWindowNumber"] as? UInt32 : nil
        })
    }

    /// Window IDs owned by `pid` that the window server is currently drawing.
    public static func onscreenWindowIDs(in infos: [[String: Any]], pid: Int32) -> Set<UInt32> {
        Set(infos.compactMap { info in
            (info["kCGWindowOwnerPID"] as? Int32) == pid && (info["kCGWindowIsOnscreen"] as? Bool) == true
                ? info["kCGWindowNumber"] as? UInt32 : nil
        })
    }

    /// Windows on more than one Space, i.e. apps assigned to All Desktops.
    public static func onMultipleSpaces(_ spaces: [UInt32: Set<UInt64>]) -> Set<UInt32> {
        Set(spaces.filter { $0.value.count > 1 }.keys)
    }

    /// Which previously seen windows still count as open. A window counts if it still
    /// exists and either Accessibility lists it (any subrole — hidden apps report AXDialog)
    /// or it sits on a Space that isn't currently shown. Anything else is ordered out,
    /// like Word's start screen, which stays alive on the current Space after closing.
    ///
    /// Windows seen on all Spaces always overlap the shown Space, and apps like Slack and
    /// Teams only order them out on close. While the screen is locked AX stops listing
    /// them, and just after unlock their Spaces can briefly read as empty, so they only
    /// count as closed when the screen is unlocked, they're off screen, and they still
    /// report a Space.
    public static func stillOpen(
        known: Set<UInt32>,
        live: Set<UInt32>,
        listedByAX: Set<UInt32>,
        spaces: [UInt32: Set<UInt64>],
        visibleSpaces: Set<UInt64>,
        onAllSpaces: Set<UInt32>,
        onscreen: Set<UInt32>,
        screenLocked: Bool
    ) -> Set<UInt32> {
        known.intersection(live).filter { id in
            if listedByAX.contains(id) { return true }
            if onAllSpaces.contains(id) {
                return screenLocked || onscreen.contains(id) || (spaces[id]?.isEmpty ?? true)
            }
            guard let windowSpaces = spaces[id], !windowSpaces.isEmpty else { return false }
            return windowSpaces.isDisjoint(with: visibleSpaces)
        }
    }
}
