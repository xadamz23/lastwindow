import Testing
@testable import LastWindowCore

struct QuitPolicyTests {
    func decide(
        enabled: Bool = true,
        bundleID: String? = "com.apple.TextEdit",
        excluded: Set<String> = [],
        hadStandardWindow: Bool = true,
        axStandardCount: Int = 0,
        knownWindowsAlive: Int = 0
    ) -> QuitDecision {
        QuitPolicy.decide(
            enabled: enabled,
            bundleID: bundleID,
            excluded: excluded,
            hadStandardWindow: hadStandardWindow,
            axStandardCount: axStandardCount,
            knownWindowsAlive: knownWindowsAlive
        )
    }

    @Test func quitsWhenLastWindowGone() {
        #expect(decide() == .quit)
    }

    @Test func keepsWhenDisabled() {
        #expect(decide(enabled: false) == .keep)
    }

    @Test func keepsWhenStandardWindowsRemain() {
        #expect(decide(axStandardCount: 1) == .keep)
    }

    @Test func keepsWhenKnownWindowStillExistsElsewhere() {
        #expect(decide(knownWindowsAlive: 1) == .keep)
    }

    @Test func keepsWhenAppNeverHadAWindow() {
        #expect(decide(hadStandardWindow: false) == .keep)
    }

    @Test func keepsExcludedApps() {
        #expect(decide(excluded: ["com.apple.TextEdit"]) == .keep)
    }

    @Test func alwaysKeepsFinderAndSelf() {
        #expect(decide(bundleID: "com.apple.finder") == .keep)
        #expect(decide(bundleID: "com.adamstahl.LastWindow") == .keep)
    }

    @Test func keepsAppsWithoutBundleID() {
        #expect(decide(bundleID: nil) == .keep)
    }
}
