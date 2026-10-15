import GIMClientKit
import GIMFeatures
import QuickLook
import UIKit
import UniformTypeIdentifiers

/// The chat timeline, newest message at the bottom.
///
/// Every change of the view model is measured by `TimelineLayoutEngine` off the main thread first; the precomputed
/// heights then go to `TimelineCollectionLayout` together with a diffable snapshot, so the collection view never
/// sizes cells itself. Updates apply one at a time; changes that arrive while one is measured are merged into the
/// next. Loading older history keeps the rows on screen in place.
public final class TimelineViewController: UIViewController, UICollectionViewDelegate {
    /// Called by the default context menu's Reply action.
    public var onReply: ((MessageItem) -> Void)?
    /// Builds the long-press menu of a message; `nil` (the default) shows Reply, Copy and, for failed messages,
    /// Retry. Return `nil` from the provider for no menu.
    public var contextMenuProvider: ((MessageItem) -> UIMenu?)?

    private let viewModel: TimelineViewModel
    private let imageLoader: ImageFileLoader
    private let engine = TimelineLayoutEngine()
    private let collectionLayout = TimelineCollectionLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionLayout)
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
    private let jumpButton = UIButton(type: .system)
    private let badgeLabel = UILabel()

    private var fonts: TimelineFonts?
    /// Rows currently in the collection view, with their layouts.
    private var displayed: [TimelineDisplayItem] = []
    private var displayedById: [String: TimelineDisplayItem] = [:]
    private var layoutsById: [String: TimelineItemLayout] = [:]
    private var layoutWidth: CGFloat = 0
    private var updateTask: Task<Void, Never>?
    private var needsUpdate = false
    private var pendingReset = false
    private var loadOlderTask: Task<Void, Never>?
    /// Follows new messages; cleared when the user scrolls away from the bottom.
    private var isPinnedToBottom = true
    /// Incoming messages that arrived while scrolled up.
    private var unreadBelow = 0
    private var lastViewport: CGSize = .zero
    private var quickLookSource: QuickLookSource?

    public init(viewModel: TimelineViewModel, imageLoader: ImageFileLoader) {
        self.viewModel = viewModel
        self.imageLoader = imageLoader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        configureJumpButton()

        fonts = TimelineFonts(traits: traitCollection)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (controller: TimelineViewController, _: UITraitCollection) in
            controller.fonts = TimelineFonts(traits: controller.traitCollection)
            controller.requestUpdate()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification,
            object: nil)
        viewModel.onChange = { [weak self] change in
            self?.requestUpdate(reset: change.isReset)
        }
        requestUpdate()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if collectionView.bounds.width != layoutWidth { requestUpdate() }
        // Keyboard, composer or rotation changed the visible area: stay at the newest message.
        let viewport = CGSize(
            width: collectionView.bounds.width,
            height: collectionView.bounds.height - collectionView.adjustedContentInset.bottom)
        if viewport != lastViewport {
            lastViewport = viewport
            if isPinnedToBottom && !displayed.isEmpty { scrollToBottom(animated: false) }
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestMarkRead()
    }

    @objc private func applicationDidBecomeActive() {
        requestMarkRead()
    }

    // MARK: - Updates

    private func requestUpdate(reset: Bool = false) {
        if reset { pendingReset = true }
        needsUpdate = true
        runUpdateIfNeeded()
    }

    /// Measures the view model's current items off the main thread, then applies them. One update runs at a time.
    private func runUpdateIfNeeded() {
        guard needsUpdate, updateTask == nil, isViewLoaded, let fonts else { return }
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        needsUpdate = false
        let items = viewModel.items
        let isReset = pendingReset
        pendingReset = false
        let engine = engine
        updateTask = Task { [weak self] in
            let layouts = await engine.layouts(for: items, width: width, fonts: fonts)
            guard let self else { return }
            updateTask = nil
            apply(items, layouts: layouts, width: width, isReset: isReset)
            runUpdateIfNeeded()
        }
    }

    private func apply(
        _ items: [TimelineDisplayItem], layouts: [TimelineItemLayout], width: CGFloat, isReset: Bool
    ) {
        guard let dataSource else { return }
        if collectionView.bounds.width != width { needsUpdate = true }
        layoutWidth = width
        let change = TimelineChangeSet(from: displayed, to: items, isReset: isReset || displayed.isEmpty)
        let newById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let anchor = change.isPrepend ? visibleAnchor(keeping: newById) : nil
        let inserted = change.insertedIds.compactMap { newById[$0]?.messageRow }
        let wasPinned = isPinnedToBottom

        displayed = items
        displayedById = newById
        layoutsById = Dictionary(zip(items.map(\.id), layouts), uniquingKeysWith: { first, _ in first })
        collectionLayout.setItemLayouts(layouts)

        if change.isEmpty {
            // Same rows, new sizes (width or Dynamic Type).
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: false)
            if wasPinned { scrollToBottom(animated: false) }
            return
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map(\.id), toSection: 0)
        if change.isReset {
            dataSource.applySnapshotUsingReloadData(snapshot)
            scrollToBottom(animated: false)
        } else if let anchor {
            snapshot.reconfigureItems(change.reloadedIds)
            UIView.performWithoutAnimation {
                dataSource.apply(snapshot, animatingDifferences: false)
                restore(anchor)
            }
        } else {
            snapshot.reconfigureItems(change.reloadedIds)
            dataSource.apply(snapshot, animatingDifferences: true)
            if !change.isPrepend && (wasPinned || inserted.contains(where: \.isOwn)) {
                scrollToBottom(animated: true)
            } else if !change.isPrepend {
                unreadBelow += inserted.filter { !$0.isOwn }.count
            }
        }
        updateJumpButton()
        requestMarkRead()
        loadOlderIfNeeded()
    }

    /// The first visible message that survives the update, and its distance from the top of the viewport.
    private func visibleAnchor(keeping newById: [String: TimelineDisplayItem]) -> (id: String, offset: CGFloat)? {
        for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
            guard displayed.indices.contains(indexPath.item) else { continue }
            let id = displayed[indexPath.item].id
            guard newById[id]?.messageRow != nil,
                let frame = collectionLayout.layoutAttributesForItem(at: indexPath)?.frame
            else { continue }
            return (id, frame.minY - collectionView.contentOffset.y)
        }
        return nil
    }

    private func restore(_ anchor: (id: String, offset: CGFloat)) {
        collectionView.layoutIfNeeded()
        guard let index = displayed.firstIndex(where: { $0.id == anchor.id }),
            let frame = collectionLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame
        else { return }
        let insets = collectionView.adjustedContentInset
        let maxOffset = max(
            -insets.top, collectionView.contentSize.height - collectionView.bounds.height + insets.bottom)
        collectionView.contentOffset.y = min(maxOffset, max(-insets.top, frame.minY - anchor.offset))
    }

    // MARK: - Scrolling

    private var isNearBottom: Bool {
        let visibleBottom =
            collectionView.contentOffset.y + collectionView.bounds.height - collectionView.adjustedContentInset.bottom
        return visibleBottom >= collectionView.contentSize.height - 60
    }

    private func scrollToBottom(animated: Bool) {
        collectionView.layoutIfNeeded()
        let insets = collectionView.adjustedContentInset
        let bottom = max(-insets.top, collectionView.contentSize.height - collectionView.bounds.height + insets.bottom)
        collectionView.setContentOffset(CGPoint(x: 0, y: bottom), animated: animated)
        isPinnedToBottom = true
        unreadBelow = 0
        updateJumpButton()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only user scrolling changes whether the timeline follows new messages.
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        let wasPinned = isPinnedToBottom
        isPinnedToBottom = isNearBottom
        if isPinnedToBottom {
            unreadBelow = 0
            if !wasPinned { requestMarkRead() }
        }
        updateJumpButton()
        loadOlderIfNeeded()
    }

    /// Loads older history when the top of the content is less than one screen away.
    private func loadOlderIfNeeded() {
        guard viewModel.hasMore, loadOlderTask == nil, !displayed.isEmpty else { return }
        let distanceFromTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        guard distanceFromTop < collectionView.bounds.height else { return }
        loadOlderTask = Task { [weak self] in
            await self?.viewModel.loadOlder()
            self?.loadOlderTask = nil
        }
    }

    private func requestMarkRead() {
        guard isViewLoaded, view.window != nil else { return }
        let bottomVisible = isNearBottom
        let appActive = UIApplication.shared.applicationState == .active
        Task { [viewModel] in
            await viewModel.markReadIfNeeded(bottomVisible: bottomVisible, appActive: appActive)
        }
    }

    private func scrollToMessage(_ messageId: String) {
        // Only loaded messages can be shown; older quotes stay where they are.
        guard let indexPath = dataSource?.indexPath(for: TimelineDisplayItem.id(forMessage: messageId)) else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
        isPinnedToBottom = false
        updateJumpButton()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            (self?.collectionView.cellForItem(at: indexPath) as? MessageCell)?.flash()
        }
    }

    // MARK: - Jump to bottom

    private func configureJumpButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .label
        jumpButton.configuration = configuration
        jumpButton.accessibilityLabel = "Scroll to the latest message"
        jumpButton.layer.shadowColor = UIColor.black.cgColor
        jumpButton.layer.shadowOpacity = 0.15
        jumpButton.layer.shadowRadius = 4
        jumpButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        jumpButton.addAction(
            UIAction { [weak self] _ in self?.scrollToBottom(animated: true) }, for: .primaryActionTriggered)

        badgeLabel.font = .preferredFont(forTextStyle: .caption2)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .systemBlue
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.clipsToBounds = true
        badgeLabel.isAccessibilityElement = false

        for subview in [jumpButton, badgeLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.isHidden = true
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            jumpButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            jumpButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            jumpButton.widthAnchor.constraint(equalToConstant: 40),
            jumpButton.heightAnchor.constraint(equalToConstant: 40),
            badgeLabel.centerXAnchor.constraint(equalTo: jumpButton.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: jumpButton.topAnchor, constant: 2),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])
    }

    private func updateJumpButton() {
        let hidden = isPinnedToBottom || displayed.isEmpty
        jumpButton.isHidden = hidden
        badgeLabel.isHidden = hidden || unreadBelow == 0
        badgeLabel.text = unreadBelow > 99 ? " 99+ " : " \(unreadBelow) "
        jumpButton.accessibilityValue = unreadBelow > 0 ? "\(unreadBelow) new" : nil
    }

    // MARK: - Cells

    private func configureDataSource() {
        let messageCell = UICollectionView.CellRegistration<MessageCell, String> { [weak self] cell, _, id in
            self?.configure(cell, id: id)
        }
        let pillCell = UICollectionView.CellRegistration<PillCell, String> { [weak self] cell, _, id in
            guard let self, let item = displayedById[id], let fonts, let pill = layoutsById[id]?.pill else { return }
            switch item.kind {
            case .dateSeparator(let text), .membership(let text):
                cell.configure(text: text, isTyping: false, frame: pill, fonts: fonts)
            case .typing(let text):
                cell.configure(text: text, isTyping: true, frame: pill, fonts: fonts)
            case .message:
                break
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) {
            [weak self] collectionView, indexPath, id in
            if self?.displayedById[id]?.messageRow != nil {
                return collectionView.dequeueConfiguredReusableCell(using: messageCell, for: indexPath, item: id)
            }
            return collectionView.dequeueConfiguredReusableCell(using: pillCell, for: indexPath, item: id)
        }
    }

    private func configure(_ cell: MessageCell, id: String) {
        guard let row = displayedById[id]?.messageRow, let layout = layoutsById[id]?.message, let fonts else { return }
        cell.configure(row, layout: layout, fonts: fonts)
        let messageId = row.message.messageId
        if let reply = row.reply {
            cell.onReplyTap = { [weak self] in self?.scrollToMessage(reply.messageId) }
        } else {
            cell.onReplyTap = nil
        }
        cell.onRetry = { [weak self] in
            guard let viewModel = self?.viewModel else { return }
            Task { await viewModel.retry(messageId: messageId) }
        }
        switch row.body {
        case .image(let media, _, _, _):
            let fileName = Self.fileName(for: media, fileName: nil)
            cell.onMediaTap = { [weak self] in self?.openMedia(media, fileName: fileName) }
            let mediaSize = layout.media?.size ?? .zero
            let maxPixelSize = max(mediaSize.width, mediaSize.height) * traitCollection.displayScale
            let viewModel = viewModel
            let imageLoader = imageLoader
            // Thumbnail first, then the full image once it is downloaded.
            cell.mediaTask = Task { [weak cell] in
                if let path = await viewModel.thumbnailPath(for: media),
                    let image = await imageLoader.image(atPath: path, maxPixelSize: maxPixelSize),
                    !Task.isCancelled
                {
                    cell?.setImage(image)
                }
                if let path = try? await viewModel.mediaFilePath(for: media, fileName: fileName),
                    let image = await imageLoader.image(atPath: path, maxPixelSize: maxPixelSize),
                    !Task.isCancelled
                {
                    cell?.setImage(image)
                }
            }
        case .file(let media, let fileName, _, _):
            cell.onMediaTap = { [weak self] in self?.openMedia(media, fileName: fileName) }
            cell.mediaTask = nil
        case .text, .placeholder:
            cell.onMediaTap = nil
            cell.mediaTask = nil
        }
    }

    /// File name for a downloaded attachment; images without one get an extension from their MIME type so
    /// QuickLook can open them.
    private static func fileName(for media: MediaRef, fileName: String?) -> String {
        if let fileName, !fileName.isEmpty { return fileName }
        let fileExtension = UTType(mimeType: media.mime)?.preferredFilenameExtension ?? "bin"
        return "media.\(fileExtension)"
    }

    private func openMedia(_ media: MediaRef, fileName: String) {
        Task { [weak self, viewModel] in
            do {
                let path = try await viewModel.mediaFilePath(for: media, fileName: fileName)
                self?.presentQuickLook(URL(fileURLWithPath: path))
            } catch {
                self?.presentError(ErrorPresenter.message(for: error))
            }
        }
    }

    private func presentQuickLook(_ url: URL) {
        guard presentedViewController == nil else { return }
        let source = QuickLookSource(url: url)
        quickLookSource = source
        let preview = QLPreviewController()
        preview.dataSource = source
        present(preview, animated: true)
    }

    private func presentError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Can't Open", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Context menu

    public func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let id = dataSource?.itemIdentifier(for: indexPaths[0]),
            let row = displayedById[id]?.messageRow
        else { return nil }
        if case .placeholder = row.body { return nil }
        guard let menu = menu(for: row.message) else { return nil }
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: nil) { _ in menu }
    }

    public func collectionView(
        _ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? MessageCell else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bubbleView.bounds, cornerRadius: TimelineMetrics.bubbleCornerRadius)
        return UITargetedPreview(view: cell.bubbleView, parameters: parameters)
    }

    private func menu(for message: MessageItem) -> UIMenu? {
        if let contextMenuProvider { return contextMenuProvider(message) }
        var actions: [UIMenuElement] = [
            UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in
                self?.onReply?(message)
            }
        ]
        if case .text(let body) = message.content {
            actions.append(
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = body
                })
        }
        if case .failed = message.sendState {
            let viewModel = viewModel
            let messageId = message.messageId
            actions.append(
                UIAction(title: "Retry", image: UIImage(systemName: "arrow.clockwise")) { _ in
                    Task { await viewModel.retry(messageId: messageId) }
                })
        }
        return UIMenu(children: actions)
    }
}

/// Serves one local file to QuickLook.
private final class QuickLookSource: NSObject, QLPreviewControllerDataSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        url as NSURL
    }
}
