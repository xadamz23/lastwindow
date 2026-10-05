public enum WindowCount {
    /// Window IDs owned by `pid` in a `CGWindowListCopyWindowInfo` result. Apps keep
    /// hidden helper windows here too, so callers should only compare against IDs
    /// they have already seen through Accessibility.
    public static func liveWindowIDs(in infos: [[String: Any]], pid: Int32) -> Set<UInt32> {
        Set(infos.compactMap { info in
            (info["kCGWindowOwnerPID"] as? Int32) == pid ? info["kCGWindowNumber"] as? UInt32 : nil
        })
    }

    /// Windows on more than one Space, i.e. apps assigned to All Desktops.
    public static func onMultipleSpaces(_ spaces: [UInt32: Set<UInt64>]) -> Set<UInt32> {
        Set(spaces.filter { $0.value.count > 1 }.keys)
    }

    /// Which previously seen windows still count as open. A window counts if it still
    /// exists and either Accessibility lists it (any subrole — hidden apps report AXDialog),
    /// it has been seen on all Spaces, or it sits on a Space that isn't currently shown.
    /// Anything else is ordered out, like Word's start screen, which stays alive on the
    /// current Space after closing.
    ///
    /// All-Spaces windows always overlap the shown Space, and around screen lock and unlock
    /// AX can stop listing them and their Spaces can briefly read as empty, so they count as
    /// open for as long as they exist.
    public static func stillOpen(
        known: Set<UInt32>,
        live: Set<UInt32>,
        listedByAX: Set<UInt32>,
        spaces: [UInt32: Set<UInt64>],
        visibleSpaces: Set<UInt64>,
        onAllSpaces: Set<UInt32>
    ) -> Set<UInt32> {
        known.intersection(live).filter { id in
            if listedByAX.contains(id) || onAllSpaces.contains(id) { return true }
            guard let windowSpaces = spaces[id], !windowSpaces.isEmpty else { return false }
            return windowSpaces.isDisjoint(with: visibleSpaces)
        }
    }
}
