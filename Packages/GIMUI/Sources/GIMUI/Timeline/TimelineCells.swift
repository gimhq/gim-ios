import GIMClientKit
import GIMFeatures
import SwiftUI
import UIKit

enum TimelineColors {
    static let ownBubble = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.29, blue: 0.52, alpha: 1) : UIColor(red: 0.86, green: 0.93, blue: 1, alpha: 1)
    }
    static let otherBubble = UIColor.secondarySystemBackground
    static let readTicks = UIColor.systemBlue
}

/// Text, image or file message: the bubble with sender name, reply preview, body, footer and reaction chips. Frames
/// come from the precomputed `MessageLayout`; the cell measures nothing.
final class MessageCell: UICollectionViewCell {
    /// Shown instead of an attachment that couldn't be downloaded for now; tapping it fetches it again.
    static let mediaRetryText = "Couldn't load — Tap to retry"

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
    }

    func configure(_ row: TimelineMessageRow, layout: MessageLayout, fonts: TimelineFonts) {
        bubbleView.frame = layout.bubble
        var corners = UIRectCorner.allCorners
        if row.hasTail { corners.remove(row.isOwn ? .bottomRight : .bottomLeft) }
        bubbleShape.path =
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: layout.bubble.size), byRoundingCorners: corners,
                cornerRadii: CGSize(
                    width: TimelineMetrics.bubbleCornerRadius, height: TimelineMetrics.bubbleCornerRadius)
            ).cgPath
        isOwn = row.isOwn
        updateBubbleColor()

        senderLabel.isHidden = layout.senderName == nil
        senderLabel.frame = layout.senderName ?? .zero
        senderLabel.text = row.senderName
        senderLabel.font = fonts.senderName
        senderLabel.textColor = UIColor(AvatarStyle.palette[AvatarStyle.colorIndex(for: row.message.sender.userId)])

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
            (isOwn ? TimelineColors.ownBubble : TimelineColors.otherBubble)
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
            imageView.accessibilityLabel = row.isMediaUnavailable ? Self.mediaRetryText : caption ?? "Photo"
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
                reaction.own ? TimelineColors.readTicks.withAlphaComponent(0.2) : .tertiarySystemFill
            label.accessibilityLabel = "\(reaction.emoji), \(reaction.count)"
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
        case .image(_, _, _, let caption): parts.append(caption.map { "Photo, \($0)" } ?? "Photo")
        case .file(_, let name, let size, _): parts.append("File \(name), \(size)")
        }
        parts.append(row.timeText)
        if row.isEdited { parts.append("edited") }
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
        accessibilityHint = "Shows the original message"
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
        accessibilityLabel = "Reply to \(reply.senderName): \(reply.text)"
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
        accessibilityLabel = "File \(name), \(size)"
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
            accessibilityLabel = "Sending"
        case .sent:
            first.image = checkmark
            first.tintColor = .secondaryLabel
            accessibilityLabel = "Sent"
        case .delivered, .read:
            let color = status == .read ? TimelineColors.readTicks : .secondaryLabel
            first.image = checkmark
            second.image = checkmark
            first.tintColor = color
            second.tintColor = color
            second.isHidden = false
            accessibilityLabel = status == .read ? "Read" : "Delivered"
        case .failed(_, let cause):
            first.image = UIImage(systemName: "exclamationmark.circle.fill")
            first.tintColor = .systemRed
            isEnabled = true
            accessibilityTraits = .button
            accessibilityLabel = "Not sent"
            // `TimelineViewModel.retry` explains a cause that can't be retried instead of resending.
            let canRetry = MessageActionsViewModel.canRetry(cause)
            accessibilityHint = canRetry ? "Sends the message again" : "Shows why it wasn't sent"
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
        // A larger touch target for the retry button.
        bounds.insetBy(dx: -12, dy: -12).contains(point)
    }
}

/// Rounded label row: day separators and membership changes (centered) and the typing row.
final class PillCell: UICollectionViewCell {
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

    func configure(text: String, isTyping: Bool, frame: CGRect, fonts: TimelineFonts) {
        pill.frame = frame
        pill.layer.cornerRadius = min(frame.height / 2, 12)
        pill.backgroundColor = isTyping ? TimelineColors.otherBubble : .tertiarySystemFill
        label.frame = pill.bounds.inset(by: TimelineMetrics.centeredRowPadding)
        label.font = isTyping ? fonts.footer : fonts.separator
        label.textColor = .secondaryLabel
        label.text = text
        accessibilityLabel = text
        isAccessibilityElement = true
        accessibilityTraits = isTyping ? .updatesFrequently : .header
    }
}
