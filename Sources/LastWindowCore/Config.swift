import Foundation

public struct Config: Codable, Equatable, Sendable {
    /// Bundle identifiers that should never be auto-quit.
    public var excluded: [String]

    public init(excluded: [String] = []) {
        self.excluded = excluded
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LastWindow")
            .appendingPathComponent("config.json")
    }

    /// Reads the config at `url`, writing an empty default first if the file doesn't exist.
    public static func loadOrCreate(at url: URL = defaultURL) throws -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            try encoder.encode(Config()).write(to: url)
        }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }
}
