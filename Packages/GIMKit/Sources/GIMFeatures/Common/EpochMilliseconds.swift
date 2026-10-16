import Foundation

extension Date {
    /// gim-core timestamps are Unix epoch milliseconds; presentation code converts them here.
    public init(epochMilliseconds: UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(epochMilliseconds) / 1000)
    }

    /// Unix epoch milliseconds, as gim-core timestamps; 0 before 1970.
    public var epochMilliseconds: UInt64 {
        UInt64(max(0, (timeIntervalSince1970 * 1000).rounded()))
    }
}
