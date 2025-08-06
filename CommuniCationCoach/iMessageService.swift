import Foundation
import AppKit // Import AppKit for NSWorkspace
import SQLite
import Contacts

class iMessageService {
    private var db: Connection?
    private let chatDbPath = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath
    private let contactStore = CNContactStore()

    // MARK: - Database Schema Definitions
    private let chatTable = Table("chat")
    private let handleTable = Table("handle")
    private let messageTable = Table("message")
    private let chat_handle_join_table = Table("chat_handle_join")
    private let chat_message_join_table = Table("chat_message_join")

    // Common Columns
    private let rowid = Expression<Int64>("ROWID")
    private let idColumn = Expression<String?>("id")

    // Chat Table Columns
    private let displayNameColumn = Expression<String?>("display_name")
    private let chatIdentifierColumn = Expression<String?>("chat_identifier")

    // Join Table Columns
    private let chatIdColumn = Expression<Int64>("chat_id")
    private let handleIdColumn = Expression<Int64>("handle_id")
    private let messageIdColumn = Expression<Int64>("message_id")

    // Message Table Columns
    private let textColumn = Expression<String?>("text")
    private let dateColumn = Expression<Int64>("date")
    private let isFromMeColumn = Expression<Bool>("is_from_me")
    private let serviceColumn = Expression<String?>("service")
    private let attributedBodyColumn = Expression<Data?>("attributedBody")
    // Additional columns for deep debugging
    private let subjectColumn = Expression<String?>("subject")
    private let countryColumn = Expression<String?>("country")
    private let errorColumn = Expression<Int64?>("error")
    private let dateReadColumn = Expression<Int64?>("date_read")
    private let dateDeliveredColumn = Expression<Int64?>("date_delivered")
    private let isDeliveredColumn = Expression<Int64?>("is_delivered")
    private let isFinishedColumn = Expression<Int64?>("is_finished")
    private let isReadColumn = Expression<Int64?>("is_read")
    private let itemTypeColumn = Expression<Int64?>("item_type")
    private let groupActionTypeColumn = Expression<Int64?>("group_action_type")
    private let guidColumn = Expression<String>("guid")

    // MARK: - Attributed Body Decoding Helper
    /// Attempts to extract a human-readable string from the archived `attributedBody` blob.
    /// Messages are sometimes stored as an `NSAttributedString` archived with either the legacy
    /// `NSArchiver` format **or** the modern `NSKeyedArchiver` format.  We therefore try both
    /// approaches before giving up.
    private func decodeAttributedBody(_ data: Data) -> String? {
        // 1. Legacy (non-keyed) archiver – most common for older message rows
        if let attr = NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString {
            return attr.string
        }
        // 2. Modern keyed archiver (macOS 11+) – wrap in a `try?` so any failure just returns nil
        if let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            return attr.string
        }
        // 3. Fallback – attempt to interpret the bytes as a UTF-8 string directly
        if let utf8Fallback = String(data: data, encoding: .utf8), !utf8Fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return utf8Fallback
        }
        return nil
    }

    init() {
        connectToDatabase()
        requestContactAccess()
    }

    private func connectToDatabase() {
        do {
            db = try Connection(chatDbPath, readonly: true)
            print("Successfully connected to chat.db")
        } catch {
            db = nil
            print("Error connecting to chat.db: \(error)")
        }
    }

    // MARK: - Contact Access
    private func requestContactAccess() {
        contactStore.requestAccess(for: .contacts) { [weak self] granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Contact access granted")
                } else {
                    print("Contact access denied: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }

    private func lookupContactName(for identifier: String) -> String? {
        print("DEBUG: Looking up contact for identifier: '\(identifier)'")
        
        // Clean the identifier - remove formatting and get just the digits
        let cleanedIdentifier = identifier.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        guard !cleanedIdentifier.isEmpty else { 
            print("DEBUG: No digits found in identifier")
            return nil 
        }
        
        print("DEBUG: Cleaned identifier: '\(cleanedIdentifier)'")
        
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        
        do {
            // Try multiple phone number variations for better matching
            let phoneVariations = [
                identifier,  // Original format
                cleanedIdentifier,  // Just digits
                "+\(cleanedIdentifier)",  // With + prefix
                "+1\(cleanedIdentifier.hasSuffix("1") ? String(cleanedIdentifier.dropLast()) : cleanedIdentifier)"  // US format
            ]
            
            for phoneVariation in phoneVariations {
                print("DEBUG: Trying phone variation: '\(phoneVariation)'")
                
                let contacts = try contactStore.unifiedContacts(matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phoneVariation)), keysToFetch: keysToFetch)
                
                print("DEBUG: Found \(contacts.count) contacts for '\(phoneVariation)'")
                
                if let contact = contacts.first {
                    let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                    let finalName = fullName.isEmpty ? contact.givenName : fullName
                    print("DEBUG: Found contact: '\(finalName)'")
                    return finalName.isEmpty ? nil : finalName
                }
            }
            
            // If no direct match, try searching all contacts manually
            print("DEBUG: No direct match found, searching all contacts...")
            let allContactsRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
            
            var foundContact: CNContact?
            try contactStore.enumerateContacts(with: allContactsRequest) { contact, stop in
                for phoneNumber in contact.phoneNumbers {
                    let contactPhone = phoneNumber.value.stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    if contactPhone.contains(cleanedIdentifier) || cleanedIdentifier.contains(contactPhone) {
                        print("DEBUG: Found matching contact through enumeration: \(contact.givenName) \(contact.familyName)")
                        foundContact = contact
                        stop.pointee = true
                        return
                    }
                }
            }
            
            if let contact = foundContact {
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let finalName = fullName.isEmpty ? contact.givenName : fullName
                return finalName.isEmpty ? nil : finalName
            }
            
        } catch {
            print("Error looking up contact for \(identifier): \(error)")
        }
        
        print("DEBUG: No contact found for identifier: '\(identifier)'")
        return nil
    }

    func fetchConversations() -> [Conversation] {
        var conversations: [Conversation] = []
        guard let db = db else {
            print("DEBUG: Database connection is nil.")
            return conversations
        }

        print("DEBUG: Starting to fetch conversations...")

        // Step 1: Get the ROWIDs of the 10 most recent chats based on last message date.
        let recent_chats_subquery = messageTable
            .join(chat_message_join_table, on: messageTable[rowid] == chat_message_join_table[messageIdColumn])
            .group(chat_message_join_table[chatIdColumn])
            .order(messageTable[dateColumn].max.desc)
            .limit(10)
            .select(chat_message_join_table[chatIdColumn])

        do {
            let chat_ids = try db.prepare(recent_chats_subquery).map { try $0.get(chat_message_join_table[chatIdColumn]) }
            print("DEBUG: Found \(chat_ids.count) recent chat IDs: \(chat_ids)")

            // Step 2: Fetch the details for each of those recent chats.
            for id in chat_ids {
                print("\nDEBUG: Processing chat_id: \(id)")
                
                let details_query = chatTable
                    .filter(chatTable[rowid] == id)
                    .limit(1)

                if let conversationRow = try db.pluck(details_query) {
                    let displayName = try conversationRow.get(displayNameColumn)
                    let chatIdentifier = try conversationRow.get(chatIdentifierColumn)
                    let chatId = try conversationRow.get(rowid)

                    // For 1-on-1 chats, the display name is often null or empty.
                    // The chat_identifier is the other person's handle (e.g., phone number).
                    let finalDisplayName: String
                    if let dn = displayName, !dn.isEmpty {
                        finalDisplayName = dn
                    } else if let identifier = chatIdentifier {
                        // Try to map phone number to contact name
                        if let contactName = lookupContactName(for: identifier) {
                            finalDisplayName = contactName
                            print("DEBUG: Mapped \(identifier) to contact: \(contactName)")
                        } else {
                            // Format phone number nicely if no contact found
                            finalDisplayName = formatPhoneNumber(identifier)
                            print("DEBUG: No contact found for \(identifier), using formatted: \(finalDisplayName)")
                        }
                    } else {
                        finalDisplayName = "Unknown Chat"
                    }
                    print("DEBUG: Details: chat.displayName='\(displayName ?? "nil")', chat.chat_identifier='\(chatIdentifier ?? "nil")'. Using: '\(finalDisplayName)'")

                    if !finalDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && finalDisplayName != "Unknown Chat" {
                        let conversation = Conversation(id: chatId, displayName: finalDisplayName)
                        
                        if !conversations.contains(where: { $0.id == conversation.id }) {
                            conversations.append(conversation)
                            print("DEBUG: SUCCESS - Added conversation: \(conversation.displayName)")
                        } else {
                            print("DEBUG: SKIPPED - Duplicate conversation ID.")
                        }
                    } else {
                        print("DEBUG: SKIPPED - Conversation has no valid name.")
                    }

                } else {
                    print("DEBUG: SKIPPED - Could not find details for chat_id: \(id)")
                }

                if conversations.count >= 5 {
                    print("DEBUG: Reached 5 conversations. Stopping.")
                    break
                }
            }
        } catch {
            print("DEBUG: An error occurred during fetching: \(error)")
        }

        print("\nDEBUG: Finished fetching. Total conversations loaded: \(conversations.count)\n")
        return conversations
    }

    func fetchMessages(for chatId: Int64, limit: Int = 25) -> [Message] {
        var messages = [Message]()
        guard let db = db else { return messages }

        let query = messageTable
            .join(.leftOuter, handleTable, on: messageTable[handleIdColumn] == handleTable[rowid])
            .join(chat_message_join_table, on: messageTable[rowid] == chat_message_join_table[messageIdColumn])
            .filter(chat_message_join_table[chatIdColumn] == chatId)
            .order(messageTable[dateColumn].desc)
            .limit(limit)

        print("\nDEBUG: Fetching messages for chat_id: \(chatId)")
        do {
            for row in try db.prepare(query) {
                let id = try row.get(messageTable[rowid])
                let text = try row.get(messageTable[textColumn])
                let attributedBody = try row.get(messageTable[attributedBodyColumn])
                let sender = try row.get(handleTable[idColumn]) ?? ""
                let date = try row.get(messageTable[dateColumn])
                let isFromMe = try row.get(messageTable[isFromMeColumn])
                
                var messageText = text ?? ""

                // If the main text is empty, try to extract it from the attributedBody.
                if messageText.isEmpty, let bodyData = attributedBody {
                    print("DEBUG: Attempting to decode attributedBody for message ROWID \(id) (bytes: \(bodyData.count))")
                    if let decoded = decodeAttributedBody(bodyData) {
                        messageText = decoded
                        print("DEBUG: Decoded attributedBody -> '\(messageText)'")
                    } else {
                        print("DEBUG: FAILED to decode attributedBody for message ROWID \(id)")
                    }
                }

                // The date is in Core Data timestamp format, so we need to convert it.
                let dateAsTimeInterval = TimeInterval(date) / 1_000_000_000 + 978307200

                let message = Message(
                    id: Int(id),
                    text: messageText,
                    sender: sender,
                    date: Date(timeIntervalSinceReferenceDate: dateAsTimeInterval),
                    isFromMe: isFromMe
                )
                messages.append(message)
            }
        } catch {
            print("Error fetching messages: \(error)")
        }

        print("DEBUG: Finished fetching messages.\n")
        return messages.reversed() // Return in chronological order
    }

    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Basic phone number formatting for display
        let digits = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if digits.count == 11 && digits.hasPrefix("1") {
            // US number with country code: +1 (123) 456-7890
            let area = String(digits.dropFirst().prefix(3))
            let firstThree = String(digits.dropFirst(4).prefix(3))
            let lastFour = String(digits.suffix(4))
            return "+1 (\(area)) \(firstThree)-\(lastFour)"
        } else if digits.count == 10 {
            // US number without country code: (123) 456-7890
            let area = String(digits.prefix(3))
            let firstThree = String(digits.dropFirst(3).prefix(3))
            let lastFour = String(digits.suffix(4))
            return "(\(area)) \(firstThree)-\(lastFour)"
        } else {
            // Return as-is for international or unusual formats
            return phoneNumber
        }
    }

    // Check for Full Disk Access and guide the user if not enabled.
    func checkPermissions() -> Bool {
        // A simple check to see if we can access the file.
        // This is not a perfect check, but it's a good first step.
        return FileManager.default.isReadableFile(atPath: chatDbPath)
    }
    
    // Open a new window with instructions and a button to open System Settings.
    func requestPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
} 
