import Foundation

// Represents a single iMessage conversation
struct Conversation: Identifiable, Hashable {
    let id: Int64 // The unique chat.ROWID for the conversation
    let displayName: String // The name of the person or group chat
}

// Represents a single message within a conversation
struct Message: Identifiable {
    let id: Int
    let text: String
    let sender: String
    let date: Date
    let isFromMe: Bool
}

// Represents one turn of interaction with the assistant
struct Interaction: Identifiable {
    let id = UUID()
    let prompt: String
    let response: String
}

struct DebugEntry: Identifiable {
    let id = UUID()
    let prompt: String
    let response: String
} 