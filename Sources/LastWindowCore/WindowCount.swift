public enum WindowCount {
    /// Window IDs owned by `pid` in a `CGWindowListCopyWindowInfo` result. Apps keep
    /// hidden helper windows here too, so callers should only compare against IDs
    /// they have already seen through Accessibility.
    public static func liveWindowIDs(in infos: [[String: Any]], pid: Int32) -> Set<UInt32> {
        Set(infos.compactMap { info in
            (info["kCGWindowOwnerPID"] as? Int32) == pid ? info["kCGWindowNumber"] as? UInt32 : nil
        })
    }
}
