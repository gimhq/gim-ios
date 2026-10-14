import GIMClientKit
import SwiftUI

/// Placeholder until the chat list subtask lands.
public struct ChatListScreen: View {
    let client: any GimClientAPI
    let onOpen: (ChatId) -> Void

    public init(client: any GimClientAPI, onOpen: @escaping (ChatId) -> Void) {
        self.client = client
        self.onOpen = onOpen
    }

    public var body: some View {
        List {
            Button("Open demo chat") { onOpen(FakeGimClient.demoDirectChatId) }
            Button("Open demo group") { onOpen(FakeGimClient.demoGroupChatId) }
        }
        .navigationTitle("Chats")
    }
}
