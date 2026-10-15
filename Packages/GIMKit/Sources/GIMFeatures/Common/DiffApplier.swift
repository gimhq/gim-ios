import GIMClientKit

/// One eyeball-im `VectorDiff` operation, independent of the concrete gim-core diff enum.
public enum VectorDiff<Element> {
    case append([Element])
    case clear
    case pushFront(Element)
    case pushBack(Element)
    case popFront
    case popBack
    case insert(Int, Element)
    case set(Int, Element)
    case remove(Int)
    case truncate(Int)
    case reset([Element])

    /// The same operation on transformed elements (for example chat summaries mapped to rows).
    public func map<T>(_ transform: (Element) -> T) -> VectorDiff<T> {
        switch self {
        case .append(let values): .append(values.map(transform))
        case .clear: .clear
        case .pushFront(let value): .pushFront(transform(value))
        case .pushBack(let value): .pushBack(transform(value))
        case .popFront: .popFront
        case .popBack: .popBack
        case .insert(let index, let value): .insert(index, transform(value))
        case .set(let index, let value): .set(index, transform(value))
        case .remove(let index): .remove(index)
        case .truncate(let length): .truncate(length)
        case .reset(let values): .reset(values.map(transform))
        }
    }
}

public protocol VectorDiffConvertible {
    associatedtype Element
    var vectorDiff: VectorDiff<Element> { get }
}

extension VectorDiff: VectorDiffConvertible {
    public var vectorDiff: VectorDiff<Element> { self }
}

extension ChatListDiff: VectorDiffConvertible {
    public var vectorDiff: VectorDiff<ChatSummary> {
        switch self {
        case .append(let values): .append(values)
        case .clear: .clear
        case .pushFront(let value): .pushFront(value)
        case .pushBack(let value): .pushBack(value)
        case .popFront: .popFront
        case .popBack: .popBack
        case .insert(let index, let value): .insert(Int(index), value)
        case .set(let index, let value): .set(Int(index), value)
        case .remove(let index): .remove(Int(index))
        case .truncate(let length): .truncate(Int(length))
        case .reset(let values): .reset(values)
        }
    }
}

extension TimelineDiff: VectorDiffConvertible {
    public var vectorDiff: VectorDiff<TimelineItem> {
        switch self {
        case .append(let values): .append(values)
        case .clear: .clear
        case .pushFront(let value): .pushFront(value)
        case .pushBack(let value): .pushBack(value)
        case .popFront: .popFront
        case .popBack: .popBack
        case .insert(let index, let value): .insert(Int(index), value)
        case .set(let index, let value): .set(Int(index), value)
        case .remove(let index): .remove(Int(index))
        case .truncate(let length): .truncate(Int(length))
        case .reset(let values): .reset(values)
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
    /// `index` (an index, or a length for `truncate`) was out of range for a list of `count` elements when the diff
    /// at `diffIndex` was applied. `popFront`/`popBack` on an empty list report index 0.
    case invalidIndex(diffIndex: Int, index: Int, count: Int)
}

/// Applies gim-core list diffs with eyeball-im `VectorDiff` semantics: diffs of one batch apply in order and each
/// index refers to the list after the previous diff.
public enum DiffApplier {
    /// Applies `diffs` in order. On an invalid index nothing is applied and `DiffApplierError` is thrown.
    @discardableResult
    public static func apply<Diff: VectorDiffConvertible>(
        _ diffs: [Diff], to list: inout [Diff.Element]
    ) throws -> ListChangeSet {
        var batch = Batch(list)
        for (diffIndex, diff) in diffs.enumerated() {
            try batch.apply(diff.vectorDiff, diffIndex: diffIndex)
        }
        list = batch.result
        return batch.changeSet
    }

    private struct Batch<Element> {
        var result: [Element]
        /// Original index of each current slot; nil for slots inserted by this batch.
        var origins: [Int?]
        var deleted: Set<Int> = []
        var reloaded: Set<Int> = []
        var isReset = false

        init(_ list: [Element]) {
            result = list
            origins = Array(list.indices)
        }

        var changeSet: ListChangeSet {
            if isReset { return ListChangeSet(isReset: true) }
            return ListChangeSet(
                deletions: deleted.sorted(),
                insertions: origins.indices.filter { origins[$0] == nil },
                reloads: reloaded.subtracting(deleted).sorted())
        }

        mutating func apply(_ diff: VectorDiff<Element>, diffIndex: Int) throws {
            func check(_ index: Int, in range: ClosedRange<Int>?) throws {
                guard let range, range.contains(index) else {
                    throw DiffApplierError.invalidIndex(diffIndex: diffIndex, index: index, count: result.count)
                }
            }
            let slots = result.isEmpty ? nil : 0...(result.count - 1)
            switch diff {
            case .reset(let values):
                result = values
                origins = Array(repeating: nil, count: values.count)
                isReset = true
            case .clear:
                remove(0..<result.count)
            case .append(let values):
                insert(values, at: result.count)
            case .pushFront(let value):
                insert([value], at: 0)
            case .pushBack(let value):
                insert([value], at: result.count)
            case .insert(let index, let value):
                try check(index, in: 0...result.count)
                insert([value], at: index)
            case .popFront:
                try check(0, in: slots)
                remove(0..<1)
            case .popBack:
                try check(0, in: slots)
                remove((result.count - 1)..<result.count)
            case .set(let index, let value):
                try check(index, in: slots)
                result[index] = value
                if let origin = origins[index] { reloaded.insert(origin) }
            case .remove(let index):
                try check(index, in: slots)
                remove(index..<(index + 1))
            case .truncate(let length):
                try check(length, in: 0...result.count)
                remove(length..<result.count)
            }
        }

        private mutating func insert(_ values: [Element], at index: Int) {
            result.insert(contentsOf: values, at: index)
            origins.insert(contentsOf: Array(repeating: nil, count: values.count), at: index)
        }

        private mutating func remove(_ range: Range<Int>) {
            result.removeSubrange(range)
            for origin in origins[range] {
                if let origin { deleted.insert(origin) }
            }
            origins.removeSubrange(range)
        }
    }
}
