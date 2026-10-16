import Foundation
import GIMClientKit

/// The Notification Service Extension's per-push metrics, one line per push appended to a log file in the App Group
/// container (`gim-nse.log`, copied back by scripts/mac-gate.sh as `nse.log`).
public struct PushMetricsLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Appends and returns `nse seq=<n> footprint_bytes=<v> elapsed_ms=<v> kind=<k>`; `seq` numbers the lines of the
    /// file from 1.
    @discardableResult
    public func append(footprintBytes: UInt64, elapsedMs: Int, kind: NotificationKind) throws -> String {
        let fileManager = FileManager.default
        let existing = fileManager.contents(atPath: url.path) ?? Data()
        let seq = existing.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 } + 1
        let line = "nse seq=\(seq) footprint_bytes=\(footprintBytes) elapsed_ms=\(elapsedMs) kind=\(kind)"
        guard fileManager.fileExists(atPath: url.path) else {
            try Data((line + "\n").utf8).write(to: url)
            return line
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
        return line
    }
}
