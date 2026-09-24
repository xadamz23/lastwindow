import Foundation
import Testing
@testable import LastWindowCore

struct ConfigTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
    }

    @Test func createsDefaultFileWhenMissing() throws {
        let url = tempURL()
        let config = try Config.loadOrCreate(at: url)
        #expect(config.excluded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func readsExistingFile() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{ "excluded": ["com.apple.Music", "com.apple.mail"] }"#.utf8).write(to: url)
        let config = try Config.loadOrCreate(at: url)
        #expect(config.excluded == ["com.apple.Music", "com.apple.mail"])
    }

    @Test func throwsOnMalformedFile() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try Config.loadOrCreate(at: url) }
    }
}

struct WindowCountTests {
    func info(pid: Int32, id: UInt32) -> [String: Any] {
        ["kCGWindowOwnerPID": pid, "kCGWindowNumber": id]
    }

    @Test func returnsWindowIDsForPIDOnly() {
        let infos = [info(pid: 1, id: 10), info(pid: 1, id: 11), info(pid: 2, id: 20)]
        #expect(WindowCount.liveWindowIDs(in: infos, pid: 1) == [10, 11])
    }

    func stillOpen(known: Set<UInt32>, live: Set<UInt32>, listedByAX: Set<UInt32> = [],
                   spaces: [UInt32: Set<UInt64>] = [:]) -> Set<UInt32> {
        WindowCount.stillOpen(known: known, live: live, listedByAX: listedByAX, spaces: spaces, visibleSpaces: [6])
    }

    @Test func dropsDestroyedWindows() {
        #expect(stillOpen(known: [1], live: []) == [])
    }

    @Test func keepsWindowsAccessibilityStillLists() {
        // Hidden apps (⌘H) keep their windows in AX, with subrole AXDialog.
        #expect(stillOpen(known: [1], live: [1], listedByAX: [1], spaces: [1: [6]]) == [1])
    }

    @Test func keepsWindowsOnSpacesNotShown() {
        #expect(stillOpen(known: [1], live: [1], spaces: [1: [7]]) == [1])
    }

    @Test func dropsWindowsHiddenOnAShownSpace() {
        // Word's start screen: ordered out, still on the current Space, not in AX.
        #expect(stillOpen(known: [1], live: [1], spaces: [1: [6]]) == [])
    }

    @Test func dropsWindowsOnNoSpace() {
        #expect(stillOpen(known: [1], live: [1], spaces: [:]) == [])
    }
}
