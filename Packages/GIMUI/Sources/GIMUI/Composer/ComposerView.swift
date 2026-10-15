import GIMClientKit
import GIMFeatures
import SwiftUI

/// The message input of a chat: growing text field, send button, attachments, and the reply or edit bar.
///
/// `replyingTo` and `editing` are the chat screen's targets (set from the message menu); the composer adopts them
/// and clears them when the message is sent or the bar is cancelled.
public struct ComposerView: View {
    @Binding private var replyingTo: MessageItem?
    @Binding private var editing: MessageItem?

    @State private var viewModel: ComposerViewModel
    @State private var showsPhotoPicker = false
    @State private var showsDocumentPicker = false
    @State private var isPreparingAttachment = false

    public init(
        client: any GimClientAPI, chatId: String, drafts: ComposerDrafts, replyingTo: Binding<MessageItem?>,
        editing: Binding<MessageItem?>
    ) {
        _replyingTo = replyingTo
        _editing = editing
        _viewModel = State(initialValue: ComposerViewModel(client: client, chatId: chatId, drafts: drafts))
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            if let message = viewModel.editTarget {
                TargetBar(
                    systemImage: "pencil", title: "Edit Message", text: ComposerViewModel.previewText(for: message)
                ) {
                    viewModel.cancelEdit()
                }
            } else if let message = viewModel.replyTarget {
                TargetBar(
                    systemImage: "arrowshape.turn.up.left",
                    title: message.isOwn ? "Reply to Yourself" : "Reply to \(message.sender.displayName)",
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
                        Text("Message")
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
            "Can't Send",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var attachButton: some View {
        if isPreparingAttachment {
            ProgressView()
                .frame(width: 36, height: 36)
        } else {
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                Button("Files", systemImage: "folder") { showsDocumentPicker = true }
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .disabled(!viewModel.canAttach)
            .accessibilityLabel("Attach")
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
        .accessibilityLabel(viewModel.editTarget == nil ? "Send" : "Save Edit")
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
            .accessibilityLabel("Cancel")
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
