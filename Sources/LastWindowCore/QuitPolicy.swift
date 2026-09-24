public enum QuitDecision: Equatable, Sendable {
    case quit
    case keep
}

public enum QuitPolicy {
    /// Never quit these, regardless of config.
    public static let alwaysExcluded: Set<String> = ["com.apple.finder", "com.adamstahl.LastWindow"]

    /// - Parameters:
    ///   - hadStandardWindow: the app has shown at least one standard window since we started watching it.
    ///   - axStandardCount: standard windows reported by Accessibility (includes minimized).
    ///   - knownWindowsAlive: windows previously seen via Accessibility that still exist (catches other Spaces).
    public static func decide(
        enabled: Bool,
        bundleID: String?,
        excluded: Set<String>,
        hadStandardWindow: Bool,
        axStandardCount: Int,
        knownWindowsAlive: Int
    ) -> QuitDecision {
        guard enabled, let bundleID else { return .keep }
        if alwaysExcluded.contains(bundleID) || excluded.contains(bundleID) { return .keep }
        guard hadStandardWindow else { return .keep }
        return axStandardCount == 0 && knownWindowsAlive == 0 ? .quit : .keep
    }
}
