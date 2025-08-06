import Foundation
import SwiftUI
import Contacts

// MARK: - Language Support
enum Language: String, CaseIterable {
    case english = "English"
    case spanish = "Spanish"
    
    var localeIdentifier: String {
        switch self {
        case .english: return "en"
        case .spanish: return "es"
        }
    }

    // Global translation helper
    private static let spanishMap: [String: String] = [
        "Start a conversation": "Iniciar una conversación",
        "Context": "Contexto",
        "Draft": "Borrador",
        "Interpret": "Interpretar",
        "Draft Request": "Solicitud de borrador",
        "Conversation": "Conversación",
        "Debug: Last Prompt": "Depurar: Última solicitud",
        "Select a conversation to see an interpretation": "Selecciona una conversación para ver una interpretación",
        "Thinking...": "Pensando...",
        "Draft a response": "Redactar una respuesta",
        "All processing on device": "Todo el procesamiento en el dispositivo",
        "Full Disk Access Required": "Se requiere acceso total al disco",
        "This app needs access to your iMessage data to provide contextual assistance. Your data stays completely private and secure - everything is processed locally on your device with no internet connection. Please grant Full Disk Access in System Settings.": "Esta aplicación necesita acceso a tus datos de iMessage para proporcionar asistencia contextual. Tus datos permanecen completamente privados y seguros - todo se procesa localmente en tu dispositivo sin necesidad de conexión a internet. Por favor, otorga Acceso Total al Disco en Configuración del Sistema.",
        "Open System Settings": "Abrir Configuración del Sistema",
        "Contact Access Previously Denied": "Acceso a contactos denegado previamente",
        "Contact Access Restricted": "Acceso a contactos restringido",
        "Contact Access Recommended": "Se recomienda acceso a contactos",
        "Contact access was previously denied. To see friendly names instead of phone numbers, please enable contact access in System Settings > Privacy & Security > Contacts.": "El acceso a contactos fue denegado anteriormente. Para ver nombres en lugar de números de teléfono, habilita el acceso a contactos en Configuración del Sistema > Privacidad y Seguridad > Contactos.",
        "Contact access is restricted by system policy. The app will show formatted phone numbers instead of contact names.": "El acceso a contactos está restringido por la política del sistema. La aplicación mostrará números de teléfono formateados en lugar de nombres de contactos.",
        "Grant contact access to see friendly names instead of phone numbers in your conversation list. This makes it easier to identify your conversations.": "Otorga acceso a contactos para ver nombres en lugar de números de teléfono en tu lista de conversaciones. Esto hace que sea más fácil identificar tus conversaciones.",
        "Open Privacy Settings": "Abrir Configuración de Privacidad",
        "Continue Without Contacts": "Continuar sin contactos",
        "Grant Contact Access": "Otorgar acceso a contactos",
        "Skip for Now": "Omitir por ahora",
        "Ollama Model Not Found": "Modelo de Ollama no encontrado",
        "Please ensure Ollama is running the 'gemma3n:e4b' model in a separate terminal window. You can install it with the following command:": "Asegúrate de que Ollama esté ejecutándose y que el modelo 'gemma3n:e4b' esté instalado. Puedes instalarlo con el siguiente comando:",
        "Mode": "Modo",
        "Ask a question…": "Haz una pregunta…",
        "(optional) Add context or draft…": "(opcional) Agrega contexto o borrador…",
        "Thinking…": "Pensando…",
        "Language": "Idioma",
        "Add Context": "Agregar contexto",
        "This person is my..": "Esta persona es mi..",
        "Add": "Agregar",
        "To:": "Para:",
        "Type below to chat more about the conversation": "Escribe abajo para hablar más sobre la conversación",
        "Suggested Reply": "Respuesta sugerida",
        "Suggested Response": "Respuesta sugerida",
        "Debug": "Depurar",
        "Open Debug": "Abrir depuración"
    ]

    func translate(_ english: String) -> String {
        switch self {
        case .english: return english
        case .spanish: return Language.spanishMap[english] ?? english
        }
    }
}

extension AssistantViewModel {
    /// Convenience translator using selectedLanguage
    func tr(_ english: String) -> String {
        selectedLanguage.translate(english)
    }
}

@MainActor
class AssistantViewModel: ObservableObject {
    
    // Services
    private let messageService = iMessageService()
    private let ollamaService = OllamaService()
    private let contactStore = CNContactStore()
    
    // Published properties for the UI
    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var interactions: [Interaction] = []
    @Published var debugEntries: [DebugEntry] = []
    @Published var currentInput: String = ""
    @Published var isLoading: Bool = false
    @Published var lastPrompt: String = ""
    @Published var contextLevel: ContextLevel = .medium
    // New: input mode (Draft / Interpret)
    @Published var inputMode: InputMode = .interpret
    @Published var selectedLanguage: Language = .english
    
    // Status properties
    @Published var needsPermissions: Bool = false
    @Published var needsContactPermissions: Bool = false
    @Published var ollamaModelAvailable: Bool = false
    
    private var senderAliasMapping: [String: String] = [:]
    private var nextSenderAliasIndex = 1
    
    init() {
        checkPrerequisites()
    }
    
    private func checkPrerequisites() {
        // Check for Full Disk Access
        needsPermissions = !messageService.checkPermissions()
        
        // Check for Contact Access
        checkContactPermissions()
        
        // If we have permissions, load the conversations
        if !needsPermissions {
            loadConversations()
        }
        
        // Check for Ollama model availability
        ollamaService.checkModelAvailability { [weak self] available in
            DispatchQueue.main.async {
                self?.ollamaModelAvailable = available
            }
        }
    }
    
    private func checkContactPermissions() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        print("DEBUG: Contact permission status: \(status.rawValue)")
        print("DEBUG: Status details - notDetermined=0, restricted=1, denied=2, authorized=3")
        
        switch status {
        case .notDetermined:
            print("DEBUG: Contacts not determined (0) - will request permission")
            needsContactPermissions = true
            // Don't auto-request here, let user initiate
        case .authorized:
            print("DEBUG: Contacts already authorized (3)")
            needsContactPermissions = false
        case .denied:
            print("DEBUG: Contacts denied (2) - need manual settings change")
            needsContactPermissions = true
        case .restricted:
            print("DEBUG: Contacts restricted (1) - cannot access")
            needsContactPermissions = true
        @unknown default:
            print("DEBUG: Unknown contact permission status: \(status.rawValue)")
            needsContactPermissions = true
        }
    }
    
    private func requestContactPermissions() {
        let statusBefore = CNContactStore.authorizationStatus(for: .contacts)
        print("DEBUG: Requesting contact permissions... Status before: \(statusBefore.rawValue)")
        
        contactStore.requestAccess(for: .contacts) { [weak self] granted, error in
            let statusAfter = CNContactStore.authorizationStatus(for: .contacts)
            print("DEBUG: Contact permission request completed")
            print("DEBUG: - Granted: \(granted)")
            print("DEBUG: - Error: \(error?.localizedDescription ?? "none")")
            print("DEBUG: - Status after: \(statusAfter.rawValue)")
            
            DispatchQueue.main.async {
                self?.needsContactPermissions = !granted
                if granted {
                    print("DEBUG: Contact access granted, reloading conversations...")
                    self?.loadConversations()
                } else {
                    print("DEBUG: Contact access denied or failed")
                }
            }
        }
    }
    
    func requestPermissions() {
        messageService.requestPermissions()
    }
    
    func requestContactAccess() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        print("DEBUG: User requested contact access. Current status: \(status.rawValue)")
        
        switch status {
        case .denied:
            print("DEBUG: Status is denied (2), opening System Settings")
            openContactPrivacySettings()
        case .notDetermined:
            print("DEBUG: Status is not determined (0), making permission request")
            requestContactPermissions()
        case .restricted:
            print("DEBUG: Status is restricted (1), cannot request")
            // Show message that contacts are restricted
        case .authorized:
            print("DEBUG: Already authorized (3), reloading conversations")
            loadConversations()
        @unknown default:
            print("DEBUG: Unknown status \(status.rawValue), attempting request")
            requestContactPermissions()
        }
    }
    
    func openContactPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func skipContactPermissions() {
        print("DEBUG: User skipped contact permissions")
        needsContactPermissions = false
        loadConversations()
    }
    
    func loadConversations() {
        print("DEBUG: Loading conversations...")
        self.conversations = messageService.fetchConversations()
        print("DEBUG: Loaded \(conversations.count) conversations")
    }
    
    func onConversationSelected() {
        guard let selectedConversation = selectedConversation else {
            messages = []
            return
        }
        
        // Clear previous state
        interactions.removeAll()
        lastPrompt = ""
        senderAliasMapping.removeAll()
        nextSenderAliasIndex = 1
        
        isLoading = true
        messages = messageService.fetchMessages(for: selectedConversation.id)
        
        // Get initial interpretation from Ollama only if in interpret mode
        if inputMode == .interpret {
            let prompt = createInitialInterpretationPrompt(for: messages)
            self.lastPrompt = prompt
            ollamaService.executePrompt(prompt: prompt) { [weak self] response in
                DispatchQueue.main.async {
                    if let self = self {
                        let chatMore = self.tr("Type below to chat more about the conversation")
                        self.interactions.append(Interaction(prompt: "Conversation Interpretation", response: response + "\n\n" + chatMore))
                    }
                    self?.isLoading = false
                    self?.debugEntries.append(DebugEntry(prompt: prompt, response: response))
                    // After interpretation is done, fetch a suggested reply
                    self?.fetchSuggestedReply()
                }
            }
        } else {
            isLoading = false
        }
    }
    
    private func createInitialInterpretationPrompt(for messages: [Message]) -> String {
        let history = formatHistoryForPrompt(messages)
        let contextPart = ""
        let basePrompt = selectedLanguage == .english ?
            "You are a communication expert analyzing my conversation. Here is a recent conversation. \n\n\(history)\n\nProvide ONLY a brief, casual, high level interpretation of the last few messages. Do NOT suggest any replies. Respond in English, informal, concise tone. Remember you are talking to me about my conversation with other person" :
            "Eres un experto en comunicación analizando mi conversación. Aquí hay una conversación reciente. \n\n\(history)\n\nProporciona SOLO una interpretación breve, casual y de alto nivel de los últimos mensajes. NO sugieras respuestas. Responde en español con tono informal y conciso. Recuerda que me estás hablando sobre mi conversación con otra persona"
        
        return "\(basePrompt)\(contextPart)"
    }
    
    func onModeChanged(to newMode: InputMode) {
        // If switching to interpret mode and we have a conversation but no interpretation yet
        if newMode == .interpret && 
           selectedConversation != nil && 
           interactions.isEmpty && 
           !isLoading {
            
            let prompt = createInitialInterpretationPrompt(for: messages)
            self.lastPrompt = prompt
            isLoading = true
            
            ollamaService.executePrompt(prompt: prompt) { [weak self] response in
                DispatchQueue.main.async {
                    if let self = self {
                        let chatMore = self.tr("Type below to chat more about the conversation")
                        self.interactions.append(Interaction(prompt: "Conversation Interpretation", response: response + "\n\n" + chatMore))
                    }
                    self?.isLoading = false
                    self?.debugEntries.append(DebugEntry(prompt: prompt, response: response))
                    self?.fetchSuggestedReply()
                }
            }
        }
    }
    
    func switchToDraftMode() {
        inputMode = .draft
    }
    
    func submitUserInput() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch inputMode {
        case .draft:
            // Draft mode: help with a new reply - text is optional for suggestions, or can be provided for refinement
            let draftText = trimmed.isEmpty ? nil : trimmed
            executePrompt(promptType: .draft(text: draftText), userPrompt: draftText ?? "Draft Request")
            currentInput = ""
        case .interpret:
            // Interpret mode: understand what already exists - must have question text
            guard !trimmed.isEmpty else { return }
            executePrompt(promptType: .interpret(question: trimmed), userPrompt: trimmed)
            currentInput = ""
        }
    }
    
    private func executePrompt(promptType: PromptType, userPrompt: String? = nil) {
        // Determine what we should display for the user's message in the conversation view.
        let displayedPrompt: String
        if let userPrompt = userPrompt {
            displayedPrompt = userPrompt
        } else if !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayedPrompt = currentInput
        } else {
            // Empty input indicates a draft request
            displayedPrompt = "Draft Request"
        }
        
        isLoading = true
        let prompt = createPrompt(for: promptType)
        self.lastPrompt = prompt
        
        ollamaService.executePrompt(prompt: prompt) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let formattedResponse = self.boldHeaderLines(in: response)
                self.interactions.append(Interaction(prompt: displayedPrompt, response: formattedResponse))
                self.debugEntries.append(DebugEntry(prompt: prompt, response: response))
                self.isLoading = false
            }
        }
    }
    
    private func createPrompt(for type: PromptType) -> String {
        let history = formatHistoryForPrompt(messages)
        let contextPart = ""
        
        switch type {
        case .draft(let text):
            if let draftText = text {
                // User provided text to refine
                let basePrompt = selectedLanguage == .english ?
                    "You are an expert editor specializing in clear, emotionally-intelligent communication. I want to send the following message. Analyse my draft and provide an improved version for clarity and tone. Output the revised message first, then on a new line provide a ONE-sentence explanation IN ENGLISH of your key changes. Keep the revised message in the same language as the conversation." :
                    "Eres un editor experto especializado en comunicación clara y emocionalmente inteligente. Quiero enviar el siguiente mensaje. Analiza mi borrador y proporciona una versión mejorada para mayor claridad y tono. Muestra primero el mensaje revisado y, en la línea siguiente, proporciona UNA frase de explicación EN ESPAÑOL con tus cambios clave. Mantén el mensaje revisado en el mismo idioma que la conversación."
                
                return "\(basePrompt)\n\nConversation History:\n\(history)\(contextPart)\n\nMy Draft:\n\(draftText)"
            } else {
                // User wants a suggestion for a new reply
                let basePrompt = selectedLanguage == .english ?
                    "You are an expert communicator. Based on the following conversation, write a thoughtful, relevant reply I could send. Keep it casual and concise. Output ONLY that suggested reply text and nothing else. Keep the reply in the same language as the conversation." :
                    "Eres un experto en comunicación. Basándote en la siguiente conversación, redacta una respuesta reflexiva y relevante que yo podría enviar. Manténla casual y concisa. Devuelve SOLO ese texto sugerido y nada más. Mantén la respuesta en el mismo idioma que la conversación."
                
                return "\(basePrompt)\n\nConversation History:\n\(history)\(contextPart)"
            }
        case .interpret(let question):
            let header = selectedLanguage == .english ?
                "You are a friendly, concise communication coach. Based on the following conversation and any context, answer my question in ENGLISH" :
                "Eres un coach de comunicación amigable y conciso. Basándote en la siguiente conversación y cualquier contexto, responde a mi pregunta EN ESPAÑOL"

            let adviseLine = selectedLanguage == .english ?
                "Advise me based on the conversation history and my question." :
                "Aconséjame basándote en el historial de la conversación y mi pregunta."

            return "\(header)\n\nConversation History:\n\(history)\(contextPart)\n\nMy question:\n\(question)\n\n\(adviseLine)\n"
        }
    }
    
    private func formatHistoryForPrompt(_ messages: [Message]) -> String {
        // Remove reaction (tapback) messages that start with verbs like "Liked" etc.
        let nonReactionMessages = messages.filter { !isReaction($0.text) }

        // Apply context limit based on selected level AFTER filtering
        let limitedMessages = Array(nonReactionMessages.suffix(contextLevel.messageLimit))

        return limitedMessages.map { message -> String in
            if message.isFromMe {
                return "Me: \(message.text)"
            } else {
                let senderId = message.sender
                if senderAliasMapping[senderId] == nil {
                    senderAliasMapping[senderId] = "Other person \(nextSenderAliasIndex)"
                    nextSenderAliasIndex += 1
                }
                let senderAlias = senderAliasMapping[senderId] ?? "Other person"
                return "\(senderAlias): \(message.text)"
            }
        }.joined(separator: "\n")
    }

    /// Simple heuristic to detect iMessage reaction/tapback lines such as "Liked \"Sure!\"".
    private func isReaction(_ text: String) -> Bool {
        let verbs = ["liked", "loved", "disliked", "laughed at", "emphasized", "questioned", "le gustó", "les gustó", "le encantó", "le disgustó", "se rió de", "enfatizó", "preguntó"]
        let lower = text.lowercased()
        for verb in verbs {
            if lower.hasPrefix(verb + " ") { return true }
        }
        return false
    }
    
    // MARK: - Response Post-processing

    /// Detect lines that look like section headers (e.g. "Explanation:") and make them bold using Markdown.
    private func boldHeaderLines(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let transformed = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Heuristic: a line ending with ':' (and reasonably short) is considered a header.
            if trimmed.hasSuffix(":") && trimmed.count <= 80 {
                return "**\(trimmed)**"
            }
            // Also treat markdown header starting with '#' and convert to bold plain text.
            if trimmed.hasPrefix("#") {
                let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                return "**\(stripped)**"
            }
            return String(line)
        }
        return transformed.joined(separator: "\n")
    }
    
    private enum PromptType {
        case draft(text: String?)
        case interpret(question: String)
    }

    private func fetchSuggestedReply() {
        let prompt = createPrompt(for: .draft(text: nil))
        ollamaService.executePrompt(prompt: prompt) { [weak self] response in
            DispatchQueue.main.async {
                let formatted = self?.boldHeaderLines(in: response) ?? response
                self?.interactions.append(Interaction(prompt: "Suggested Reply", response: formatted))
                self?.debugEntries.append(DebugEntry(prompt: prompt, response: response))
            }
        }
    }
}

enum ContextLevel: String, CaseIterable {
    case low = "Low"
    case medium = "Medium" 
    case maximum = "Maximum"
    
    var messageLimit: Int {
        switch self {
        case .low: return 4
        case .medium: return 10
        case .maximum: return 20
        }
    }
    
    func description(in language: Language) -> String {
        let messageCount = String(messageLimit)
        switch language {
        case .english:
            return "Last \(messageCount) messages"
        case .spanish:
            return "Últimos \(messageCount) mensajes"
        }
    }
} 

// MARK: - InputMode

enum InputMode: String, CaseIterable {
    case draft = "Draft"
    case interpret = "Interpret"
} 
