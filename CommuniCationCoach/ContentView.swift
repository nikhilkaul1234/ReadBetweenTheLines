//
//  ContentView.swift
//  CommuniCationCoach
//
//  Created by Lucas on 7/18/25.
//

import SwiftUI
import Contacts // Added for CNContactStore
import AppKit

// InputMode enum is declared in AssistantViewModel.swift; just ensure visible
struct ContentView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var windowRef: NSWindow?

    private func desiredSize() -> NSSize {
        // Determine height based on current app state
        if viewModel.needsPermissions || viewModel.needsContactPermissions || !viewModel.ollamaModelAvailable {
            return NSSize(width: 480, height: 300)
        } else if viewModel.selectedConversation == nil {
            return NSSize(width: 480, height: 30)
        } else {
            return NSSize(width: 480, height: 480)
        }
    }

    private func applyWindowSize(animated: Bool = true) {
        guard let win = windowRef else { return }
        let size = desiredSize()
        if animated {
            win.animator().setContentSize(size)
        } else {
            win.setContentSize(size)
        }
    }

    var body: some View {
        ZStack {
            // Translucent glass backdrop filling the entire window
            VisualEffectView(material: .hudWindow)
                .ignoresSafeArea()
            
            VStack {
            if viewModel.needsPermissions {
                PermissionsView(viewModel: viewModel)
            } else if viewModel.needsContactPermissions {
                ContactPermissionsView(viewModel: viewModel)
            } else if !viewModel.ollamaModelAvailable {
                OllamaNotAvailableView(language: viewModel.selectedLanguage)
            } else {
                AssistantView(viewModel: viewModel)
            }
        }
        // No fixed frame so content can expand with window
        .didMoveToWindow { window in
            window.isOpaque = false
            window.backgroundColor = .clear
            windowRef = window
            // Start compact height (approx 1/6 of full, e.g., 100)
            applyWindowSize(animated: false)
        }
        // React to state changes affecting size
        .onChange(of: viewModel.selectedConversation) { _ in applyWindowSize() }
        .onChange(of: viewModel.needsPermissions) { _ in applyWindowSize() }
        .onChange(of: viewModel.needsContactPermissions) { _ in applyWindowSize() }
        .onChange(of: viewModel.ollamaModelAvailable) { _ in applyWindowSize() }
        }
    }
}

struct ContextButton: View {
    @ObservedObject var viewModel: AssistantViewModel
    var isLarge: Bool = false
    
    var body: some View {
        Menu {
            ForEach(ContextLevel.allCases, id: \.self) { level in
                Button(action: {
                    viewModel.contextLevel = level
                }) {
                    HStack {
                        Text(level.rawValue)
                        Spacer()
                        Text(level.description(in: viewModel.selectedLanguage))
                            .foregroundColor(.secondary)
                        if viewModel.contextLevel == level {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: isLarge ? 10 : 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: isLarge ? 18 : 14))
                Text("\(viewModel.tr("Context")): \(viewModel.contextLevel.rawValue)")
                    .font(isLarge ? .system(.title3, weight: .medium) : .system(.caption, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: isLarge ? 16 : 10))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, isLarge ? 26 : 12)
            .padding(.vertical, isLarge ? 14 : 6)
            .background(isLarge ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.secondary.opacity(0.1)), in: RoundedRectangle(cornerRadius: isLarge ? 8 : 6))
            .overlay(
                RoundedRectangle(cornerRadius: isLarge ? 8 : 6)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            )
        }
        .menuStyle(.borderlessButton)
    }
}

struct PermissionsView: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 12) {
                Text(viewModel.tr("Full Disk Access Required"))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                
                Text(viewModel.tr("This app needs access to your iMessage data to provide contextual assistance. Your data stays completely offline, private, and secure."))
                    .font(.system(.body, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            Button(action: {
                viewModel.requestPermissions()
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text(viewModel.tr("Open System Settings"))
                }
                .font(.system(.body, design: .default, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.blue, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContactPermissionsView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var contactStatus = CNContactStore.authorizationStatus(for: .contacts)

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundColor(iconColor)
            
            VStack(spacing: 12) {
                Text(titleText)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                
                Text(descriptionText)
                    .font(.system(.body, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    HStack {
                        Image(systemName: primaryButtonIcon)
                        Text(primaryButtonText)
                    }
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(primaryButtonColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    viewModel.skipContactPermissions()
                }) {
                    Text(viewModel.tr("Skip for Now"))
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            contactStatus = CNContactStore.authorizationStatus(for: .contacts)
            print("DEBUG: ContactPermissionsView appeared. Status: \(contactStatus.rawValue)")
        }
    }
    
    private var iconName: String {
        switch contactStatus {
        case .denied: return "person.crop.circle.badge.xmark"
        case .restricted: return "person.crop.circle.badge.exclamationmark"
        default: return "person.crop.circle.badge.plus"
        }
    }
    
    private var iconColor: Color {
        switch contactStatus {
        case .denied: return .red
        case .restricted: return .orange
        default: return .green
        }
    }
    
    private var titleText: String {
        switch contactStatus {
        case .denied: return viewModel.tr("Contact Access Previously Denied")
        case .restricted: return viewModel.tr("Contact Access Restricted")
        default: return viewModel.tr("Contact Access Recommended")
        }
    }
    
    private var descriptionText: String {
        switch contactStatus {
        case .denied:
            return viewModel.tr("Contact access was previously denied. To see friendly names instead of phone numbers, please enable contact access in System Settings > Privacy & Security > Contacts.")
        case .restricted:
            return viewModel.tr("Contact access is restricted by system policy. The app will show formatted phone numbers instead of contact names.")
        default:
            return viewModel.tr("Grant contact access to see friendly names instead of phone numbers in your conversation list. This makes it easier to identify your conversations.")
        }
    }
    
    private var primaryButtonText: String {
        switch contactStatus {
        case .denied: return viewModel.tr("Open Privacy Settings")
        case .restricted: return viewModel.tr("Continue Without Contacts")
        default: return viewModel.tr("Grant Contact Access")
        }
    }
    
    private var primaryButtonIcon: String {
        switch contactStatus {
        case .denied: return "gear"
        case .restricted: return "arrow.right"
        default: return "person.circle"
        }
    }
    
    private var primaryButtonColor: Color {
        switch contactStatus {
        case .denied: return .blue
        case .restricted: return .secondary
        default: return .green
        }
    }
    
    private func primaryAction() {
        switch contactStatus {
        case .denied:
            viewModel.openContactPrivacySettings()
        case .restricted:
            viewModel.skipContactPermissions()
        default:
            viewModel.requestContactAccess()
            // Update status after request
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                contactStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
        }
    }
}

struct OllamaNotAvailableView: View {
    let language: Language

    private func tr(_ english: String) -> String {
        language.translate(english)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            VStack(spacing: 12) {
                Text(tr("Ollama Model Not Found"))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                
                Text(tr("Please ensure Ollama is running the 'gemma3n:e4b' model in a separate terminal window. You can install it with the following command:"))
                    .font(.system(.body, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            Text("ollama run gemma3n:e4b")
                .font(.system(.body, design: .monospaced, weight: .medium))
                .foregroundColor(.primary)
                .padding(12)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AssistantView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var showDebugPane = false
    private let showContextSelectorInUI = false // toggle to show/hide context selector
    private let debugEnabled = false // toggle to enable debug disclosure

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header Controls (Conversation + Context)
            let largeMode = viewModel.selectedConversation == nil
            HStack(spacing: 12) {
                // Conversation selector menu, styled flat, with "To:" prefix
                Menu {
                    ForEach(viewModel.conversations) { conversation in
                        Button(conversation.displayName) {
                            viewModel.selectedConversation = conversation
                        }
                    }
                } label: {
                    Text(viewModel.selectedConversation?.displayName ?? viewModel.tr("Conversation"))
                        .font(largeMode ? .system(.title3, weight: .semibold) : .system(.callout, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, largeMode ? 20 : 12)
                        .padding(.vertical, largeMode ? 10 : 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                        )
                }
                .menuStyle(.borderlessButton)
                .onChange(of: viewModel.selectedConversation) {
                    showDebugPane = false
                    viewModel.onConversationSelected()
                }

                // Optional in-window context selector
                if showContextSelectorInUI {
                    ContextButton(viewModel: viewModel, isLarge: largeMode)
                        .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)

            // Main Content Area
            if viewModel.selectedConversation != nil {
                VStack(spacing: 0) {
                    // Debug Pane (Optional)
                    if debugEnabled && !viewModel.lastPrompt.isEmpty {
                        DisclosureGroup(viewModel.tr("Debug: Last Prompt"), isExpanded: $showDebugPane) {
                            ScrollView {
                                Text(viewModel.lastPrompt)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 120)
                            .background(.secondary.opacity(0.05))
                            .cornerRadius(8)
                            .padding(.top, 8)
                        }
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }

                    // Assistant Interactions
                    ScrollView {
                        if viewModel.interactions.isEmpty && !viewModel.isLoading {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                
                                Text(viewModel.tr("Start a conversation"))
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Text(viewModel.tr("Select a conversation to see an interpretation"))
                                    .font(.system(.caption, design: .default))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(viewModel.interactions) { interaction in
                                    if interaction.prompt == "Suggested Reply" || interaction.prompt == viewModel.tr("Suggested Reply") {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(viewModel.tr("Suggested Response"))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            SuggestedReplyCard(text: interaction.response)
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            // divider and label
                                            HStack(spacing: 6) {
                                                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                                                if !interaction.prompt.isEmpty {
                                                    Text(interaction.prompt)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                                            }

                                            let responseText = interaction.response
                                            let quotedSegments = responseText.allQuotedSegments()
                                            
                                            if quotedSegments.isEmpty {
                                                Text(responseText)
                                                    .font(.system(.body, design: .default, weight: .medium))
                                                    .foregroundColor(.primary)
                                            } else {
                                                // Create segments of text and quotes
                                                let textSegments = responseText.createTextSegments(with: quotedSegments)
                                                
                                                ForEach(Array(textSegments.enumerated()), id: \.offset) { index, segment in
                                                    switch segment {
                                                    case .text(let text):
                                                        if !text.isEmpty {
                                                            Text(text)
                                                                .font(.system(.body, design: .default, weight: .medium))
                                                                .foregroundColor(.primary)
                                                        }
                                                    case .quote(let text):
                                                        SuggestedReplyCard(text: text)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Loading animation
                                if viewModel.isLoading {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(viewModel.currentInput.isEmpty ? viewModel.tr("Draft Request") : viewModel.currentInput)
                                            .font(.system(.caption, design: .default, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 16, height: 16)
                                            
                                            Text(viewModel.tr("Thinking..."))
                                                .font(.system(.body, design: .default))
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 4)
                                    }
                                }
                                
                                // Draft button removed
                            }
                            .padding(20)
                        }
                    }
                    .frame(maxHeight: .infinity)

                    // Privacy Indicator
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text(viewModel.tr("All processing on device"))
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Input Area
                    VStack(spacing: 12) {
                        Divider()
                        
                        VStack(spacing: 8) {
                            // Mode picker removed

                            // Input + send
                            HStack(spacing: 12) {
                                TextField(viewModel.inputMode == .draft ? viewModel.tr("(optional) Add context or draft…") : viewModel.tr("Ask a question…"), text: $viewModel.currentInput)
                                    .textFieldStyle(.plain)
                                    .font(.system(.body, design: .default))
                                    .padding(10)
                                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .disabled(viewModel.isLoading)
                                    .onSubmit {
                                        if !viewModel.isLoading {
                                            viewModel.submitUserInput()
                                        }
                                    }

                                Button(action: {
                                    viewModel.submitUserInput()
                                }) {
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Text(buttonTitle(for: viewModel.inputMode))
                                            .font(.system(.body, design: .default, weight: .medium))
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    viewModel.isLoading ? Color.secondary : Color.accentColor,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .buttonStyle(.plain)
                                .disabled(sendDisabled(viewModel))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .background(.ultraThinMaterial)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers for button state

extension AssistantView {
    private func buttonTitle(for mode: InputMode) -> String {
        switch mode {
        case .draft: return viewModel.tr("Draft")
        case .interpret: return viewModel.tr("Interpret")
        }
    }

    private func sendDisabled(_ vm: AssistantViewModel) -> Bool {
        if vm.isLoading { return true }
        switch vm.inputMode {
        case .draft:
            return false // always allow (can suggest or refine)
        case .interpret:
            return vm.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum TextSegment {
    case text(String)
    case quote(String)
}

extension String {
    /// Returns first substring enclosed in straight or smart quotes, without quotes.
    func firstQuotedSegment() -> String? {
        let quoteChars: [Character] = ["\"", "\u{201C}", "\u{201D}"]
        var startIndex: String.Index? = nil
        for (i,ch) in self.enumerated() {
            if quoteChars.contains(ch) {
                if let s = startIndex {
                    let start = s ..< self.index(self.startIndex, offsetBy: i)
                    return String(self[start]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    startIndex = self.index(self.startIndex, offsetBy: i+1)
                }
            }
        }
        return nil
    }
    
    func rangeOfFirstQuoteSegment() -> Range<String.Index>? {
        let pattern = "[\"\\u{201C}\\u{201D}][^\"\\u{201C}\\u{201D}]+[\"\\u{201C}\\u{201D}]"
        if let r = self.range(of: pattern, options: .regularExpression) { return r } else { return nil }
    }
    
    func allQuotedSegments() -> [(text: String, range: Range<String.Index>)] {
        let pattern = "[\"\\u{201C}\\u{201D}][^\"\\u{201C}\\u{201D}]+[\"\\u{201C}\\u{201D}]"
        var results: [(text: String, range: Range<String.Index>)] = []
        var searchRange = self.startIndex..<self.endIndex
        
        while let range = self.range(of: pattern, options: .regularExpression, range: searchRange) {
            let quotedRaw = String(self[range])
            let quoted = quotedRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}"))
            results.append((text: quoted, range: range))
            searchRange = range.upperBound..<self.endIndex
        }
        
        return results
    }
    
    func createTextSegments(with quotedSegments: [(text: String, range: Range<String.Index>)]) -> [TextSegment] {
        var segments: [TextSegment] = []
        var currentIndex = self.startIndex
        
        for quotedSegment in quotedSegments {
            // Add text before this quote
            if currentIndex < quotedSegment.range.lowerBound {
                let beforeText = String(self[currentIndex..<quotedSegment.range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !beforeText.isEmpty {
                    segments.append(.text(beforeText))
                }
            }
            
            // Add the quote
            segments.append(.quote(quotedSegment.text))
            
            // Update current index
            currentIndex = quotedSegment.range.upperBound
        }
        
        // Add remaining text after all quotes
        if currentIndex < self.endIndex {
            let afterText = String(self[currentIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterText.isEmpty {
                segments.append(.text(afterText))
            }
        }
        
        return segments
    }
}

func extractQuotedText(from text: String) -> String? {
    return text.firstQuotedSegment()
}

struct SuggestedReplyCard: View {
    let text: String
    @State private var copied = false
    var body: some View {
        HStack {
            Text(text)
                .font(.system(.body, design: .default))
                .foregroundColor(.primary)
                .padding(12)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }
}

struct DebugView: View {
    @ObservedObject var viewModel: AssistantViewModel
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.debugEntries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.prompt)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            Text("Response")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.response)
                                .font(.system(.body, design: .default))
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle(viewModel.tr("Debug"))
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AssistantViewModel())
    }
}
