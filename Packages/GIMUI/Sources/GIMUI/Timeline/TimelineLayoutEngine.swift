import GIMClientKit
import GIMFeatures
import UIKit

/// Fonts the layout engine measures with and the cells draw with, for one content size category.
struct TimelineFonts: @unchecked Sendable {
    // UIFont is immutable and documented as safe to use from any thread.
    let body: UIFont
    let placeholder: UIFont
    let senderName: UIFont
    let replyName: UIFont
    let replyText: UIFont
    let footer: UIFont
    let reaction: UIFont
    let fileName: UIFont
    let separator: UIFont
    let sizeCategory: String

    @MainActor
    init(traits: UITraitCollection) {
        func font(_ style: UIFont.TextStyle, _ weight: UIFont.Weight? = nil) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
            guard let weight else { return base }
            return UIFontMetrics(forTextStyle: style).scaledFont(
                for: .systemFont(ofSize: base.pointSize, weight: weight), compatibleWith: traits)
        }
        body = font(.body)
        let italic = body.fontDescriptor.withSymbolicTraits(.traitItalic) ?? body.fontDescriptor
        placeholder = UIFont(descriptor: italic, size: body.pointSize)
        senderName = font(.subheadline, .semibold)
        replyName = font(.footnote, .semibold)
        replyText = font(.footnote)
        footer = font(.caption2)
        reaction = font(.footnote)
        fileName = font(.subheadline, .medium)
        separator = font(.footnote, .medium)
        sizeCategory = traits.preferredContentSizeCategory.rawValue
    }
}

/// Fixed spacing of the timeline, in points.
enum TimelineMetrics {
    static let sideInset: CGFloat = 10
    static let maxBubbleFraction: CGFloat = 0.78
    static let maxBubbleWidth: CGFloat = 520
    static let bubblePadding = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
    static let bubbleCornerRadius: CGFloat = 18
    static let tailCornerRadius: CGFloat = 4
    static let gapInRun: CGFloat = 2
    static let gapAfterRun: CGFloat = 8
    static let elementSpacing: CGFloat = 4
    static let maxImageSize = CGSize(width: 260, height: 320)
    static let defaultImageSize = CGSize(width: 240, height: 180)
    static let imageCornerRadius: CGFloat = 12
    static let fileRowSize = CGSize(width: 220, height: 44)
    static let fileIconSize: CGFloat = 32
    static let replyBarWidth: CGFloat = 3
    static let replyPadding: CGFloat = 6
    static let statusWidth: CGFloat = 18
    static let reactionHeight: CGFloat = 26
    static let reactionPadding: CGFloat = 10
    static let reactionSpacing: CGFloat = 4
    static let centeredRowPadding = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    static let centeredRowMargin: CGFloat = 8
}

/// Frames inside a message cell. `bubble` and `reactions` are in cell coordinates; the others are relative to the
/// bubble.
struct MessageLayout: Sendable {
    var bubble: CGRect
    var senderName: CGRect?
    var reply: CGRect?
    var media: CGRect?
    var text: CGRect?
    var footer: CGRect
    var reactions: [CGRect]
}

/// Precomputed size of one timeline row; cells are as wide as the collection view.
struct TimelineItemLayout: Sendable {
    var height: CGFloat
    /// Message rows only.
    var message: MessageLayout?
    /// Separator, membership and typing rows: the frame of their rounded label.
    var pill: CGRect?
}

/// Measures timeline rows off the main thread and caches the result by item id, content revision, container width
/// and content size category. The cache is dropped when the width or the category changes.
actor TimelineLayoutEngine {
    private struct Key: Hashable {
        var id: String
        var revision: Int
        var width: CGFloat
        var sizeCategory: String
    }

    private var cache: [Key: TimelineItemLayout] = [:]
    private var width: CGFloat = 0
    private var sizeCategory = ""

    /// Layouts for `items`, in the same order.
    func layouts(for items: [TimelineDisplayItem], width: CGFloat, fonts: TimelineFonts) -> [TimelineItemLayout] {
        if width != self.width || fonts.sizeCategory != sizeCategory {
            cache = [:]
            self.width = width
            sizeCategory = fonts.sizeCategory
        }
        var used: [Key: TimelineItemLayout] = [:]
        let result = items.map { item in
            let key = Key(id: item.id, revision: item.contentRevision, width: width, sizeCategory: sizeCategory)
            let layout = cache[key] ?? Self.layout(item, width: width, fonts: fonts)
            used[key] = layout
            return layout
        }
        // Only the current rows stay cached; edits and status changes leave stale revisions behind otherwise.
        cache = used
        return result
    }

    static func layout(_ item: TimelineDisplayItem, width: CGFloat, fonts: TimelineFonts) -> TimelineItemLayout {
        switch item.kind {
        case .message(let row):
            return messageLayout(row, width: width, fonts: fonts)
        case .dateSeparator(let text), .membership(let text):
            return pillLayout(text, font: fonts.separator, width: width, centered: true)
        case .typing(let text):
            return pillLayout(text, font: fonts.footer, width: width, centered: false)
        }
    }

    static func footerText(_ row: TimelineMessageRow) -> String {
        row.isEdited ? "edited  \(row.timeText)" : row.timeText
    }

    /// Display size of an image: the media size clamped to `maxImageSize`, keeping the aspect ratio.
    static func imageSize(width: UInt32?, height: UInt32?) -> CGSize {
        guard let width, let height, width > 0, height > 0 else { return TimelineMetrics.defaultImageSize }
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let scale = min(
            1, TimelineMetrics.maxImageSize.width / size.width, TimelineMetrics.maxImageSize.height / size.height)
        return CGSize(width: max(60, (size.width * scale).rounded()), height: max(60, (size.height * scale).rounded()))
    }

    static func measure(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return CGSize(width: min(maxWidth, ceil(rect.width)), height: ceil(rect.height))
    }

    private static func singleLine(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGSize {
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return CGSize(width: min(maxWidth, width), height: ceil(font.lineHeight))
    }

    /// Separators are centered; the typing row sits where incoming bubbles start.
    private static func pillLayout(_ text: String, font: UIFont, width: CGFloat, centered: Bool) -> TimelineItemLayout {
        let padding = TimelineMetrics.centeredRowPadding
        let margin = TimelineMetrics.centeredRowMargin
        let textSize = measure(text, font: font, maxWidth: max(40, width - 4 * margin - padding.left - padding.right))
        let pillSize = CGSize(
            width: textSize.width + padding.left + padding.right, height: textSize.height + padding.top + padding.bottom
        )
        let x = centered ? ((width - pillSize.width) / 2).rounded() : TimelineMetrics.sideInset
        let pill = CGRect(x: x, y: margin, width: pillSize.width, height: pillSize.height)
        return TimelineItemLayout(height: pill.maxY + margin, message: nil, pill: pill)
    }

    private static func messageLayout(_ row: TimelineMessageRow, width: CGFloat, fonts: TimelineFonts)
        -> TimelineItemLayout
    {
        let padding = TimelineMetrics.bubblePadding
        let spacing = TimelineMetrics.elementSpacing
        let maxBubble = min(
            TimelineMetrics.maxBubbleWidth, (width - 2 * TimelineMetrics.sideInset) * TimelineMetrics.maxBubbleFraction)
        let inner = max(60, maxBubble - padding.left - padding.right)
        var y = padding.top
        var contentWidth: CGFloat = 0
        var layout = MessageLayout(bubble: .zero, footer: .zero, reactions: [])

        func place(_ size: CGSize) -> CGRect {
            let frame = CGRect(x: padding.left, y: y, width: size.width, height: size.height)
            y = frame.maxY + spacing
            contentWidth = max(contentWidth, size.width)
            return frame
        }

        if let name = row.senderName {
            layout.senderName = place(singleLine(name, font: fonts.senderName, maxWidth: inner))
        }
        if let reply = row.reply {
            let textInset = TimelineMetrics.replyBarWidth + TimelineMetrics.replyPadding
            let nameSize = singleLine(reply.senderName, font: fonts.replyName, maxWidth: inner - textInset)
            let textSize = singleLine(reply.text, font: fonts.replyText, maxWidth: inner - textInset)
            layout.reply = place(
                CGSize(
                    width: max(nameSize.width, textSize.width) + textInset + TimelineMetrics.replyPadding,
                    height: nameSize.height + textSize.height + 2 * TimelineMetrics.replyPadding))
        }
        let caption: String?
        switch row.body {
        case .text(let text):
            layout.text = place(measure(text, font: fonts.body, maxWidth: inner))
            caption = nil
        case .placeholder(let text):
            layout.text = place(measure(text, font: fonts.placeholder, maxWidth: inner))
            caption = nil
        case .image(_, let mediaWidth, let mediaHeight, let imageCaption):
            let size = imageSize(width: mediaWidth, height: mediaHeight)
            let scale = min(1, inner / size.width)
            layout.media = place(CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded()))
            caption = imageCaption
        case .file(_, _, _, let fileCaption):
            layout.media = place(
                CGSize(width: min(inner, TimelineMetrics.fileRowSize.width), height: TimelineMetrics.fileRowSize.height)
            )
            caption = fileCaption
        }
        if let caption, !caption.isEmpty {
            layout.text = place(measure(caption, font: fonts.body, maxWidth: inner))
        }

        let footerSize = singleLine(footerText(row), font: fonts.footer, maxWidth: inner)
        let footerWidth = footerSize.width + (row.status == nil ? 0 : TimelineMetrics.statusWidth + 2)
        contentWidth = max(contentWidth, footerWidth)
        layout.footer = CGRect(
            x: padding.left + contentWidth - footerWidth, y: y - spacing / 2, width: footerWidth,
            height: footerSize.height)
        let bubbleSize = CGSize(
            width: contentWidth + padding.left + padding.right, height: layout.footer.maxY + padding.bottom)

        let top = row.isFirstInRun ? TimelineMetrics.gapAfterRun / 2 : TimelineMetrics.gapInRun / 2
        let bubbleX = row.isOwn ? width - TimelineMetrics.sideInset - bubbleSize.width : TimelineMetrics.sideInset
        layout.bubble = CGRect(origin: CGPoint(x: bubbleX, y: top), size: bubbleSize)
        var bottom = layout.bubble.maxY

        if !row.reactions.isEmpty {
            var x: CGFloat = 0
            var lineY = bottom + TimelineMetrics.reactionSpacing
            var frames: [CGRect] = []
            for reaction in row.reactions {
                let label = singleLine(reactionText(reaction), font: fonts.reaction, maxWidth: inner)
                let chipWidth = label.width + 2 * TimelineMetrics.reactionPadding
                if x > 0 && x + chipWidth > maxBubble {
                    x = 0
                    lineY += TimelineMetrics.reactionHeight + TimelineMetrics.reactionSpacing
                }
                frames.append(CGRect(x: x, y: lineY, width: chipWidth, height: TimelineMetrics.reactionHeight))
                x += chipWidth + TimelineMetrics.reactionSpacing
            }
            // Chips line up with the bubble's outer edge.
            layout.reactions = frames.map { frame in
                row.isOwn
                    ? frame.offsetBy(dx: layout.bubble.maxX - rowWidth(frames, frame.minY), dy: 0)
                    : frame.offsetBy(dx: layout.bubble.minX, dy: 0)
            }
            bottom = (layout.reactions.map(\.maxY).max() ?? bottom)
        }
        let gapBelow = row.hasTail ? TimelineMetrics.gapAfterRun / 2 : TimelineMetrics.gapInRun / 2
        return TimelineItemLayout(height: ceil(bottom + gapBelow), message: layout, pill: nil)
    }

    static func reactionText(_ reaction: ReactionGroup) -> String {
        reaction.count > 1 ? "\(reaction.emoji) \(reaction.count)" : reaction.emoji
    }

    /// Width of the chip line starting at `lineY`.
    private static func rowWidth(_ frames: [CGRect], _ lineY: CGFloat) -> CGFloat {
        let line = frames.filter { $0.minY == lineY }
        return (line.map(\.maxX).max() ?? 0) - (line.map(\.minX).min() ?? 0)
    }
}
