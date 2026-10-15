import UIKit

/// Single-section vertical layout that stacks rows with precomputed heights. When the rows do not fill the screen
/// they sit at the bottom, next to the composer.
final class TimelineCollectionLayout: UICollectionViewLayout {
    private var itemLayouts: [TimelineItemLayout] = []
    private var attributes: [UICollectionViewLayoutAttributes] = []
    /// Attributes before the last `setItemLayouts`, for the disappearing-row animation.
    private var previousAttributes: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var insertedIndexPaths: Set<IndexPath> = []
    private var deletedIndexPaths: Set<IndexPath> = []

    static let fallbackHeight: CGFloat = 44

    /// Replaces the row heights; call right before applying the matching snapshot.
    func setItemLayouts(_ layouts: [TimelineItemLayout]) {
        previousAttributes = attributes
        itemLayouts = layouts
        invalidateLayout()
    }

    func itemLayout(at index: Int) -> TimelineItemLayout? {
        itemLayouts.indices.contains(index) ? itemLayouts[index] : nil
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let width = collectionView.bounds.width
        let heights = (0..<count).map { itemLayout(at: $0)?.height ?? Self.fallbackHeight }
        let total = heights.reduce(0, +)
        let insets = collectionView.adjustedContentInset
        var y = max(0, collectionView.bounds.height - insets.top - insets.bottom - total)
        attributes = heights.enumerated().map { index, height in
            let item = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            item.frame = CGRect(x: 0, y: y, width: width, height: height)
            y += height
            return item
        }
        contentHeight = y
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // Rows are sorted by y: binary search the first row reaching into `rect`.
        var low = 0
        var high = attributes.count
        while low < high {
            let mid = (low + high) / 2
            if attributes[mid].frame.maxY <= rect.minY { low = mid + 1 } else { high = mid }
        }
        var result: [UICollectionViewLayoutAttributes] = []
        var index = low
        while index < attributes.count, attributes[index].frame.minY < rect.maxY {
            result.append(attributes[index])
            index += 1
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // The height matters too: short timelines are pinned to the bottom.
        newBounds.size != collectionView?.bounds.size
    }

    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        insertedIndexPaths = Set(updateItems.filter { $0.updateAction == .insert }.compactMap(\.indexPathAfterUpdate))
        deletedIndexPaths = Set(updateItems.filter { $0.updateAction == .delete }.compactMap(\.indexPathBeforeUpdate))
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedIndexPaths = []
        deletedIndexPaths = []
    }

    override func initialLayoutAttributesForAppearingItem(
        at itemIndexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard insertedIndexPaths.contains(itemIndexPath) else {
            return super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
        }
        guard let final = layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        else { return nil }
        final.alpha = 0
        return final
    }

    override func finalLayoutAttributesForDisappearingItem(
        at itemIndexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard deletedIndexPaths.contains(itemIndexPath) else {
            return super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
        }
        guard previousAttributes.indices.contains(itemIndexPath.item),
            let initial = previousAttributes[itemIndexPath.item].copy() as? UICollectionViewLayoutAttributes
        else { return nil }
        initial.alpha = 0
        return initial
    }
}
