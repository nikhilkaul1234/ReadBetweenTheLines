//
//  CommuniCationCoachApp.swift
//  CommuniCationCoach
//
//  Created by Lucas on 7/18/25.
//

import SwiftUI

@main
struct CommuniCationCoachApp: App {
    @StateObject private var viewModel = AssistantViewModel()
    @State private var showDebug = false
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .background(.clear)
                .sheet(isPresented: $showDebug) {
                    DebugView(viewModel: viewModel)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandMenu(viewModel.tr("Language")) {
                ForEach(Language.allCases, id: \.self) { language in
                    Button(language.rawValue) {
                        viewModel.selectedLanguage = language
                    }
                    .keyboardShortcut(language == .english ? "e" : "s", modifiers: [.command, .option])
                    if viewModel.selectedLanguage == language {
                        Image(systemName: "checkmark")
                    }
                }
            }
            CommandMenu(viewModel.tr("Context")) {
                ForEach(ContextLevel.allCases, id: \.self) { level in
                    Button(action: { viewModel.contextLevel = level }) {
                        HStack {
                            Text(level.rawValue)
                            if viewModel.contextLevel == level {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            CommandMenu(viewModel.tr("Debug")) {
                Button(viewModel.tr("Open Debug")) { showDebug = true }
            }
        }
    }
}
