import Foundation

extension Date {
    /// gim-core timestamps are Unix epoch milliseconds; presentation code converts them here.
    public init(epochMilliseconds: UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(epochMilliseconds) / 1000)
    }
}
