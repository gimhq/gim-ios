import GIMClientKit

/// One list operation, independent of the concrete gim-core diff enum.
public enum ListOperation<Element> {
    case reset([Element])
    case insert(Int, Element)
    case update(Int, Element)
    case remove(Int)
}

public protocol ListDiff {
    associatedtype Element
    var operation: ListOperation<Element> { get }
}

extension ChatListDiff: ListDiff {
    public var operation: ListOperation<ChatSummary> {
        switch self {
        case .reset(let items): .reset(items)
        case .insert(let index, let item): .insert(Int(index), item)
        case .update(let index, let item): .update(Int(index), item)
        case .remove(let index): .remove(Int(index))
        }
    }
}

extension TimelineDiff: ListDiff {
    public var operation: ListOperation<TimelineMessage> {
        switch self {
        case .reset(let items): .reset(items)
        case .insert(let index, let item): .insert(Int(index), item)
        case .update(let index, let item): .update(Int(index), item)
        case .remove(let index): .remove(Int(index))
        }
    }
}

/// Changes made by one batch of diffs, in `UICollectionView.performBatchUpdates` terms: `deletions` and `reloads`
/// are indexes in the list before the batch, `insertions` are indexes in the list after it. When `isReset` is set,
/// the whole list must be reloaded and the index arrays are empty.
public struct ListChangeSet: Sendable, Hashable {
    public var isReset: Bool
    public var deletions: [Int]
    public var insertions: [Int]
    public var reloads: [Int]

    public init(isReset: Bool = false, deletions: [Int] = [], insertions: [Int] = [], reloads: [Int] = []) {
        self.isReset = isReset
        self.deletions = deletions
        self.insertions = insertions
        self.reloads = reloads
    }

    public var isEmpty: Bool {
        !isReset && deletions.isEmpty && insertions.isEmpty && reloads.isEmpty
    }
}

public enum DiffApplierError: Error, Sendable, Hashable {
    /// `index` was out of range for a list of `count` elements when the diff at `diffIndex` was applied.
    case invalidIndex(diffIndex: Int, index: Int, count: Int)
}

public enum DiffApplier {
    /// Applies `diffs` in order. On an invalid index nothing is applied and `DiffApplierError` is thrown.
    @discardableResult
    public static func apply<Diff: ListDiff>(_ diffs: [Diff], to list: inout [Diff.Element]) throws -> ListChangeSet {
        var result = list
        // Original index of each current slot; nil for slots inserted by this batch.
        var origins: [Int?] = Array(list.indices)
        var deleted: Set<Int> = []
        var reloaded: Set<Int> = []
        var isReset = false

        for (diffIndex, diff) in diffs.enumerated() {
            switch diff.operation {
            case .reset(let items):
                result = items
                origins = Array(repeating: nil, count: items.count)
                isReset = true
            case .insert(let index, let item):
                guard (0...result.count).contains(index) else {
                    throw DiffApplierError.invalidIndex(diffIndex: diffIndex, index: index, count: result.count)
                }
                result.insert(item, at: index)
                origins.insert(nil, at: index)
            case .update(let index, let item):
                guard result.indices.contains(index) else {
                    throw DiffApplierError.invalidIndex(diffIndex: diffIndex, index: index, count: result.count)
                }
                result[index] = item
                if let origin = origins[index] { reloaded.insert(origin) }
            case .remove(let index):
                guard result.indices.contains(index) else {
                    throw DiffApplierError.invalidIndex(diffIndex: diffIndex, index: index, count: result.count)
                }
                result.remove(at: index)
                if let origin = origins.remove(at: index) { deleted.insert(origin) }
            }
        }

        list = result
        if isReset { return ListChangeSet(isReset: true) }
        return ListChangeSet(
            deletions: deleted.sorted(),
            insertions: origins.indices.filter { origins[$0] == nil },
            reloads: reloaded.subtracting(deleted).sorted())
    }
}
