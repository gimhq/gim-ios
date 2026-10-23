import GIMClientKit
import GIMFeatures
import UIKit

/// Text, image or file message: the bubble with sender name, reply preview, body, footer and reaction chips. Frames
/// come from the precomputed `MessageLayout`; the cell measures nothing.
final class MessageCell: UICollectionViewCell {
    /// Shown instead of an attachment that couldn't be downloaded for now; tapping it fetches it again.
    static let mediaRetryText = String(localized: "Couldn't load. Tap to try again.", table: "Chat", bundle: .module)

    let bubbleView = UIView()
    private let bubbleShape = CAShapeLayer()
    private let senderLabel = UILabel()
    private let replyView = ReplyPreviewView()
    private let bodyLabel = UILabel()
    private let imageView = UIImageView()
    private let mediaRetryLabel = UILabel()
    private let fileView = FileRowView()
    private let footerLabel = UILabel()
    private let statusView = StatusTicksView()
    private var reactionLabels: [UILabel] = []
    private var isOwn = false

    var onReplyTap: (() -> Void)?
    var onMediaTap: (() -> Void)?
    var onRetry: (() -> Void)?
    /// The VoiceOver Reply action; the action is offered only while this is set.
    var onReply: (() -> Void)? {
        didSet {
            accessibilityCustomActions =
                onReply == nil
                ? nil
                : [
                    UIAccessibilityCustomAction(name: String(localized: "Reply", table: "Chat", bundle: .module)) {
                        [weak self] _ in
                        guard let onReply = self?.onReply else { return false }
                        onReply()
                        return true
                    }
                ]
        }
    }
    /// Loads the image; cancelled on reuse.
    var mediaTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        bubbleView.layer.insertSublayer(bubbleShape, at: 0)
        contentView.addSubview(bubbleView)
        for label in [senderLabel, bodyLabel, footerLabel] {
            label.adjustsFontForContentSizeCategory = false
            bubbleView.addSubview(label)
        }
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        footerLabel.textColor = .secondaryLabel
        footerLabel.textAlignment = .right
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = TimelineMetrics.imageCornerRadius
        imageView.backgroundColor = .tertiarySystemFill
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mediaTapped)))
        imageView.accessibilityTraits = [.image, .button]
        bodyLabel.accessibilityIdentifier = "timeline.message.text"
        imageView.accessibilityIdentifier = "timeline.message.image"
        // Image views are not accessibility elements by default; the label and traits above need one.
        imageView.isAccessibilityElement = true
        mediaRetryLabel.text = Self.mediaRetryText
        mediaRetryLabel.textAlignment = .center
        mediaRetryLabel.numberOfLines = 0
        mediaRetryLabel.textColor = .secondaryLabel
        mediaRetryLabel.font = .preferredFont(forTextStyle: .footnote)
        mediaRetryLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.85)
        mediaRetryLabel.layer.cornerRadius = 8
        mediaRetryLabel.clipsToBounds = true
        mediaRetryLabel.isAccessibilityElement = false
        imageView.addSubview(mediaRetryLabel)
        replyView.accessibilityIdentifier = "timeline.message.reply"
        statusView.accessibilityIdentifier = "timeline.message.status"
        accessibilityHint = String(localized: "Touch and hold for options", table: "Chat", bundle: .module)
        for view in [replyView, imageView, fileView, statusView] as [UIView] {
            bubbleView.addSubview(view)
        }
        replyView.addAction(UIAction { [weak self] _ in self?.onReplyTap?() }, for: .primaryActionTriggered)
        fileView.addAction(UIAction { [weak self] _ in self?.onMediaTap?() }, for: .primaryActionTriggered)
        statusView.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .primaryActionTriggered)
        // The bubble is a shape layer, so its dynamic color is resolved by hand.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: MessageCell, _: UITraitCollection) in
            cell.updateBubbleColor()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        mediaTask = nil
        imageView.image = nil
        onReplyTap = nil
        onMediaTap = nil
        onRetry = nil
        onReply = nil
    }

    func configure(_ row: TimelineMessageRow, layout: MessageLayout, fonts: TimelineFonts) {
        bubbleView.frame = layout.bubble
        bubbleShape.path =
            Self.bubblePath(
                size: layout.bubble.size, isOwn: row.isOwn, isFirstInRun: row.isFirstInRun, hasTail: row.hasTail
            ).cgPath
        isOwn = row.isOwn
        updateBubbleColor()

        senderLabel.isHidden = layout.senderName == nil
        senderLabel.frame = layout.senderName ?? .zero
        senderLabel.text = row.senderName
        senderLabel.font = fonts.senderName
        senderLabel.textColor = AvatarStyle.uiColor(for: row.message.sender.userId)

        replyView.isHidden = layout.reply == nil
        replyView.frame = layout.reply ?? .zero
        if let reply = row.reply { replyView.configure(reply, fonts: fonts) }

        configureBody(row, layout: layout, fonts: fonts)

        footerLabel.font = fonts.footer
        footerLabel.text = TimelineLayoutEngine.footerText(row)
        let statusWidth = row.status == nil ? 0 : TimelineMetrics.statusWidth + 2
        footerLabel.frame = CGRect(
            x: layout.footer.minX, y: layout.footer.minY, width: layout.footer.width - statusWidth,
            height: layout.footer.height)
        statusView.frame = CGRect(
            x: layout.footer.maxX - TimelineMetrics.statusWidth, y: layout.footer.minY,
            width: TimelineMetrics.statusWidth, height: layout.footer.height)
        statusView.configure(row.status)

        configureReactions(row, frames: layout.reactions, fonts: fonts)
        accessibilityLabel = Self.accessibilityText(row)
    }

    /// Outline of a bubble: `bubbleCornerRadius` on the far side; on the sender side (right for own messages) the
    /// bottom corner is always `tailCornerRadius` and the top one only below the first message of a run, so a run
    /// reads as one block. `hasTail` keeps the squared bottom corner of the run's last bubble.
    static func bubblePath(size: CGSize, isOwn: Bool, isFirstInRun: Bool, hasTail: Bool) -> UIBezierPath {
        let limit = min(size.width, size.height) / 2
        let big = min(TimelineMetrics.bubbleCornerRadius, limit)
        let small = min(TimelineMetrics.tailCornerRadius, limit)
        let senderTop = isFirstInRun ? big : small
        let topLeft = isOwn ? big : senderTop
        let topRight = isOwn ? senderTop : big
        let bottomLeft = isOwn ? big : small
        let bottomRight = isOwn ? small : big
        let (width, height) = (size.width, size.height)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: topLeft, y: 0))
        path.addLine(to: CGPoint(x: width - topRight, y: 0))
        path.addArc(
            withCenter: CGPoint(x: width - topRight, y: topRight), radius: topRight, startAngle: -.pi / 2,
            endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: width, y: height - bottomRight))
        path.addArc(
            withCenter: CGPoint(x: width - bottomRight, y: height - bottomRight), radius: bottomRight, startAngle: 0,
            endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: bottomLeft, y: height))
        path.addArc(
            withCenter: CGPoint(x: bottomLeft, y: height - bottomLeft), radius: bottomLeft, startAngle: .pi / 2,
            endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: topLeft))
        path.addArc(
            withCenter: CGPoint(x: topLeft, y: topLeft), radius: topLeft, startAngle: .pi, endAngle: 3 * .pi / 2,
            clockwise: true)
        path.close()
        return path
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
    }

    /// Briefly highlights the bubble, after jumping to a replied-to message.
    func flash() {
        UIView.animate(withDuration: 0.2) {
            self.bubbleView.alpha = 0.4
        } completion: { _ in
            UIView.animate(withDuration: 0.4) { self.bubbleView.alpha = 1 }
        }
    }

    private func updateBubbleColor() {
        bubbleShape.fillColor =
            (isOwn ? ChatColors.UI.bubbleOwn : ChatColors.UI.bubbleOther)
            .resolvedColor(with: traitCollection).cgColor
    }

    private func configureBody(_ row: TimelineMessageRow, layout: MessageLayout, fonts: TimelineFonts) {
        imageView.isHidden = true
        fileView.isHidden = true
        bodyLabel.textColor = .label
        switch row.body {
        case .text(let text):
            bodyLabel.font = fonts.body
            bodyLabel.text = text
        case .placeholder(let text):
            bodyLabel.font = fonts.placeholder
            bodyLabel.textColor = .secondaryLabel
            bodyLabel.text = text
        case .image(_, _, _, let caption):
            imageView.isHidden = false
            imageView.frame = layout.media ?? .zero
            mediaRetryLabel.isHidden = !row.isMediaUnavailable
            mediaRetryLabel.frame = imageView.bounds.insetBy(dx: 8, dy: 8)
            imageView.accessibilityLabel =
                row.isMediaUnavailable
                ? Self.mediaRetryText : caption ?? String(localized: "Photo", table: "Chat", bundle: .module)
            bodyLabel.font = fonts.body
            bodyLabel.text = caption
        case .file(_, let fileName, let sizeText, let caption):
            fileView.isHidden = false
            fileView.frame = layout.media ?? .zero
            fileView.configure(
                name: fileName, size: row.isMediaUnavailable ? Self.mediaRetryText : sizeText, fonts: fonts)
            bodyLabel.font = fonts.body
            bodyLabel.text = caption
        }
        bodyLabel.isHidden = layout.text == nil
        bodyLabel.frame = layout.text ?? .zero
    }

    private func configureReactions(_ row: TimelineMessageRow, frames: [CGRect], fonts: TimelineFonts) {
        while reactionLabels.count < frames.count {
            let label = UILabel()
            label.textAlignment = .center
            label.clipsToBounds = true
            label.layer.cornerRadius = TimelineMetrics.reactionHeight / 2
            label.accessibilityIdentifier = "timeline.message.reaction"
            contentView.addSubview(label)
            reactionLabels.append(label)
        }
        for (index, label) in reactionLabels.enumerated() {
            guard index < frames.count, index < row.reactions.count else {
                label.isHidden = true
                continue
            }
            let reaction = row.reactions[index]
            label.isHidden = false
            label.frame = frames[index]
            label.font = fonts.reaction
            label.text = TimelineLayoutEngine.reactionText(reaction)
            label.backgroundColor =
                reaction.own ? ChatColors.UI.readTicks.withAlphaComponent(0.2) : .tertiarySystemFill
            label.accessibilityLabel = String(
                localized: "\(reaction.emoji), \(Int(reaction.count))", table: "Chat", bundle: .module)
        }
    }

    @objc private func mediaTapped() {
        onMediaTap?()
    }

    private static func accessibilityText(_ row: TimelineMessageRow) -> String {
        var parts: [String] = []
        if let name = row.senderName { parts.append(name) }
        switch row.body {
        case .text(let text), .placeholder(let text): parts.append(text)
        case .image(_, _, _, let caption):
            parts.append(
                caption.map { String(localized: "Photo, \($0)", table: "Chat", bundle: .module) }
                    ?? String(localized: "Photo", table: "Chat", bundle: .module))
        case .file(_, let name, let size, _):
            parts.append(String(localized: "File \(name), \(size)", table: "Chat", bundle: .module))
        }
        parts.append(row.timeText)
        if row.isEdited { parts.append(String(localized: "edited", table: "Chat", bundle: .module)) }
        return parts.joined(separator: ", ")
    }
}

/// Quoted message above a reply: accent bar, sender and one line of text. Tapping it jumps to the quoted message.
final class ReplyPreviewView: UIControl {
    private let bar = UIView()
    private let nameLabel = UILabel()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 6
        clipsToBounds = true
        bar.backgroundColor = .tintColor
        nameLabel.textColor = .tintColor
        textLabel.textColor = .secondaryLabel
        for view in [bar, nameLabel, textLabel] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(localized: "Shows the original message", table: "Chat", bundle: .module)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ reply: ReplyPreview, fonts: TimelineFonts) {
        nameLabel.font = fonts.replyName
        textLabel.font = fonts.replyText
        nameLabel.text = reply.senderName
        textLabel.text = reply.text
        accessibilityLabel = String(
            localized: "Reply to \(reply.senderName): \(reply.text)", table: "Chat", bundle: .module)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding = TimelineMetrics.replyPadding
        let textX = TimelineMetrics.replyBarWidth + padding
        bar.frame = CGRect(x: 0, y: 0, width: TimelineMetrics.replyBarWidth, height: bounds.height)
        let nameHeight = ceil(nameLabel.font.lineHeight)
        nameLabel.frame = CGRect(x: textX, y: padding, width: bounds.width - textX - padding, height: nameHeight)
        textLabel.frame = CGRect(
            x: textX, y: nameLabel.frame.maxY, width: nameLabel.frame.width, height: ceil(textLabel.font.lineHeight))
    }
}

/// Attachment row: document icon, file name and size. Tapping it opens the file.
final class FileRowView: UIControl {
    private let iconView = UIImageView(image: UIImage(systemName: "doc.fill"))
    private let nameLabel = UILabel()
    private let sizeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.tintColor = .tintColor
        iconView.contentMode = .scaleAspectFit
        nameLabel.lineBreakMode = .byTruncatingMiddle
        sizeLabel.textColor = .secondaryLabel
        for view in [iconView, nameLabel, sizeLabel] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(name: String, size: String, fonts: TimelineFonts) {
        nameLabel.font = fonts.fileName
        sizeLabel.font = fonts.footer
        nameLabel.text = name
        sizeLabel.text = size
        accessibilityLabel = String(localized: "File \(name), \(size)", table: "Chat", bundle: .module)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let icon = TimelineMetrics.fileIconSize
        iconView.frame = CGRect(x: 0, y: (bounds.height - icon) / 2, width: icon, height: icon)
        let textX = icon + 8
        let nameHeight = ceil(nameLabel.font.lineHeight)
        let sizeHeight = ceil(sizeLabel.font.lineHeight)
        let top = max(0, (bounds.height - nameHeight - sizeHeight) / 2)
        nameLabel.frame = CGRect(x: textX, y: top, width: bounds.width - textX, height: nameHeight)
        sizeLabel.frame = CGRect(x: textX, y: nameLabel.frame.maxY, width: nameLabel.frame.width, height: sizeHeight)
    }
}

/// Delivery ticks of an own message: clock, one checkmark, two checkmarks, two tinted checkmarks when read, or a
/// red exclamation mark that retries when tapped.
final class StatusTicksView: UIControl {
    private let first = UIImageView()
    private let second = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [first, second] {
            view.contentMode = .center
            view.isUserInteractionEnabled = false
            view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2, scale: .small)
            addSubview(view)
        }
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ status: MessageStatus?) {
        isHidden = status == nil
        isEnabled = false
        second.isHidden = true
        accessibilityTraits = .staticText
        let checkmark = UIImage(systemName: "checkmark")
        switch status {
        case nil:
            return
        case .sending:
            first.image = UIImage(systemName: "clock")
            first.tintColor = .secondaryLabel
            accessibilityLabel = String(localized: "Sending", table: "Chat", bundle: .module)
        case .sent:
            first.image = checkmark
            first.tintColor = .secondaryLabel
            accessibilityLabel = String(localized: "Sent", table: "Chat", bundle: .module)
        case .delivered, .read:
            let color = status == .read ? ChatColors.UI.readTicks : .secondaryLabel
            first.image = checkmark
            second.image = checkmark
            first.tintColor = color
            second.tintColor = color
            second.isHidden = false
            accessibilityLabel =
                status == .read
                ? String(localized: "Read", table: "Chat", bundle: .module)
                : String(localized: "Delivered", table: "Chat", bundle: .module)
        case .failed(_, let cause):
            first.image = UIImage(systemName: "exclamationmark.circle.fill")
            first.tintColor = .systemRed
            isEnabled = true
            accessibilityTraits = .button
            accessibilityLabel = String(localized: "Not sent", table: "Chat", bundle: .module)
            // `TimelineViewModel.retry` explains a cause that can't be retried instead of resending.
            let canRetry = MessageActionsViewModel.canRetry(cause)
            accessibilityHint =
                canRetry
                ? String(localized: "Sends the message again", table: "Chat", bundle: .module)
                : String(localized: "Shows why it wasn't sent", table: "Chat", bundle: .module)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - (second.isHidden ? 0 : 5)
        first.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        second.frame = first.frame.offsetBy(dx: 5, dy: 0)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // A 44 pt touch target for the retry button.
        bounds.insetBy(dx: -13, dy: -13).contains(point)
    }
}

/// Centered day chip or membership change, or the typing row.
final class PillCell: UICollectionViewCell {
    enum Style {
        /// A capsule chip, read as a heading.
        case date
        /// Plain secondary text, no background.
        case membership
        /// A small bubble where incoming messages start.
        case typing
    }

    private let pill = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.clipsToBounds = true
        label.numberOfLines = 0
        label.textAlignment = .center
        contentView.addSubview(pill)
        pill.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String, style: Style, frame: CGRect, fonts: TimelineFonts) {
        pill.frame = frame
        label.frame = pill.bounds.inset(by: TimelineMetrics.centeredRowPadding)
        label.textColor = .secondaryLabel
        label.text = text
        accessibilityLabel = text
        isAccessibilityElement = true
        switch style {
        case .date:
            pill.layer.cornerRadius = frame.height / 2
            pill.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
            label.font = fonts.separator
            accessibilityTraits = .header
        case .membership:
            pill.layer.cornerRadius = 0
            pill.backgroundColor = .clear
            label.font = fonts.separator
            accessibilityTraits = .staticText
        case .typing:
            pill.layer.cornerRadius = min(frame.height / 2, 12)
            pill.backgroundColor = ChatColors.UI.bubbleOther
            label.font = fonts.footer
            accessibilityTraits = .updatesFrequently
        }
    }
}
