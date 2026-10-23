import GIMClientKit
import GIMFeatures
import SwiftUI

/// The message input of a chat: growing text field, send button, attachments, and the reply or edit bar.
///
/// `replyingTo` and `editing` are the chat screen's targets (set from the message menu); the composer adopts them
/// and clears them when the message is sent or the bar is cancelled. While the chat is leaving or left it only shows a
/// banner saying so.
public struct ComposerView: View {
    @Binding private var replyingTo: MessageItem?
    @Binding private var editing: MessageItem?

    @State private var viewModel: ComposerViewModel
    @State private var showsPhotoPicker = false
    @State private var showsDocumentPicker = false
    @State private var isPreparingAttachment = false

    /// - Parameter timeline: the chat's timeline, which knows the chat's state; the composer is disabled unless the
    ///   chat is active.
    public init(
        client: any GimClientAPI, chatId: String, drafts: ComposerDrafts, timeline: TimelineViewModel? = nil,
        replyingTo: Binding<MessageItem?>, editing: Binding<MessageItem?>
    ) {
        _replyingTo = replyingTo
        _editing = editing
        _viewModel = State(
            initialValue: ComposerViewModel(
                client: client, chatId: chatId, drafts: drafts, timeline: timeline))
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            if let text = viewModel.readOnlyText {
                readOnlyBar(text)
            } else {
                input
            }
        }
        .background(.bar)
        .onChange(of: replyingTo, initial: true) { _, message in
            viewModel.setReplyTarget(message)
        }
        .onChange(of: editing, initial: true) { _, message in
            if let message {
                viewModel.beginEdit(message)
            } else {
                viewModel.cancelEdit()
            }
        }
        .onChange(of: viewModel.replyTarget) { _, message in
            replyingTo = message
        }
        .onChange(of: viewModel.editTarget) { _, message in
            editing = message
        }
        .onDisappear { viewModel.disappear() }
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoPicker(isPresented: $showsPhotoPicker, onStart: { isPreparingAttachment = true }) { result in
                send(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsDocumentPicker) {
            DocumentPicker(isPresented: $showsDocumentPicker, onStart: { isPreparingAttachment = true }) { result in
                send(result)
            }
            .ignoresSafeArea()
        }
        .alert(
            Text("Couldn't send", tableName: "Chat", bundle: .module),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } })
        ) {
            Button(String(localized: "OK", table: "Common", bundle: .module), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var input: some View {
        if let message = viewModel.editTarget {
            TargetBar(
                systemImage: "pencil", title: String(localized: "Edit message", table: "Chat", bundle: .module),
                text: ComposerViewModel.previewText(for: message)
            ) {
                viewModel.cancelEdit()
            }
        } else if let message = viewModel.replyTarget {
            TargetBar(
                systemImage: "arrowshape.turn.up.left",
                title: message.isOwn
                    ? String(localized: "Reply to yourself", table: "Chat", bundle: .module)
                    : String(
                        localized: "Reply to \(UserLabel.name(for: message.sender))", table: "Chat", bundle: .module),
                text: ComposerViewModel.previewText(for: message)
            ) {
                viewModel.setReplyTarget(nil)
            }
        }
        HStack(alignment: .bottom, spacing: 8) {
            attachButton
            ZStack(alignment: .topLeading) {
                GrowingTextView(text: viewModel.text) { viewModel.textChanged($0) }
                if viewModel.text.isEmpty {
                    Text("Message", tableName: "Chat", bundle: .module)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            sendButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// "Leaving…" with a spinner, or that the chat was left.
    private func readOnlyBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            if viewModel.chatState == .leaving { ProgressView() }
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("composer.readOnly")
    }

    @ViewBuilder
    private var attachButton: some View {
        if isPreparingAttachment {
            ProgressView()
                .frame(width: 36, height: 36)
        } else {
            Menu {
                Button(
                    String(localized: "Photo Library", table: "Chat", bundle: .module),
                    systemImage: "photo.on.rectangle"
                ) {
                    showsPhotoPicker = true
                }
                Button(String(localized: "Files", table: "Chat", bundle: .module), systemImage: "folder") {
                    showsDocumentPicker = true
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .disabled(!viewModel.canAttach)
            .accessibilityLabel(Text("Attach a photo or file", tableName: "Chat", bundle: .module))
            .accessibilityIdentifier("composer.attach")
        }
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.send() }
        } label: {
            Image(systemName: viewModel.editTarget == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 30))
                .frame(width: 36, height: 36)
        }
        .disabled(!viewModel.canSend)
        .accessibilityLabel(
            viewModel.editTarget == nil
                ? Text("Send message", tableName: "Chat", bundle: .module)
                : Text("Save edit", tableName: "Chat", bundle: .module))
        .accessibilityIdentifier("composer.send")
    }

    private func send(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await viewModel.sendAttachment(atPath: url.path)
                TemporaryAttachment.remove(url)
                isPreparingAttachment = false
            }
        case .failure(let error):
            isPreparingAttachment = false
            viewModel.attachmentFailed(error)
        }
    }
}

/// The reply or edit bar above the input, with a cancel button.
private struct TargetBar: View {
    let systemImage: String
    let title: String
    let text: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            Rectangle()
                .fill(.tint)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("Cancel", tableName: "Common", bundle: .module))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    @Previewable @State var replyingTo: MessageItem?
    @Previewable @State var editing: MessageItem?
    VStack {
        Spacer()
        ComposerView(
            client: FakeGimClient.demo(), chatId: FakeGimClient.demoDirectChatId, drafts: ComposerDrafts(),
            replyingTo: $replyingTo, editing: $editing)
    }
}
