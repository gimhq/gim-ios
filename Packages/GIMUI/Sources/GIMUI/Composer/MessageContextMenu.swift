import GIMClientKit
import GIMFeatures
import UIKit

/// The long-press menu of a message: Reply, the quick reactions, Copy, Edit, Delete and Retry, as offered by
/// `MessageActionsViewModel.actions(for:isReadOnly:)`.
@MainActor
enum MessageContextMenu {
    static func menu(
        for message: MessageItem, context: MessageMenuContext, actions: MessageActionsViewModel
    ) -> UIMenu? {
        let available = MessageActionsViewModel.actions(for: message, isReadOnly: context.timeline.isReadOnly)
        guard !available.isEmpty else { return nil }
        let children: [UIMenuElement] = available.map { action in
            switch action {
            case .reply:
                return UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { _ in
                    context.reply(message)
                }
            case .react:
                let reactions = MessageActionsViewModel.quickReactions.map { emoji in
                    UIAction(
                        title: emoji,
                        state: MessageActionsViewModel.hasOwnReaction(message, emoji: emoji) ? .on : .off
                    ) { _ in
                        Task { await actions.toggleReaction(emoji, on: message) }
                    }
                }
                return UIMenu(options: .displayInline, preferredElementSize: .small, children: reactions)
            case .copy:
                return UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = MessageActionsViewModel.copyText(for: message)
                }
            case .edit:
                return UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                    context.edit(message)
                }
            case .delete:
                return UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) {
                    _ in
                    actions.requestDelete(message)
                }
            case .retry:
                let timeline = context.timeline
                return UIAction(title: "Retry", image: UIImage(systemName: "arrow.clockwise")) { _ in
                    Task { await timeline.retry(messageId: message.messageId) }
                }
            }
        }
        return UIMenu(children: children)
    }
}
