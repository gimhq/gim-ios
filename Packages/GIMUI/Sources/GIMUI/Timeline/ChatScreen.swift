import GIMClientKit
import SwiftUI

/// Placeholder until the timeline subtask lands.
public struct ChatScreen: View {
    let client: any GimClientAPI
    let chatId: String

    public init(client: any GimClientAPI, chatId: String) {
        self.client = client
        self.chatId = chatId
    }

    public var body: some View {
        ContentUnavailableView("Chat \(chatId)", systemImage: "bubble.left.and.bubble.right")
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
    }
}
