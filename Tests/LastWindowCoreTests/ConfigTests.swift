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
}
