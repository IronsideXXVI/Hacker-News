import SwiftUI

struct ContentView: View {
    @State private var viewModel = FeedViewModel()
    @State private var authManager = HNAuthManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility
        ) {
            Group {
                SidebarView(viewModel: viewModel)
                    .toolbar(removing: .sidebarToggle)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 375, max: 375)
        } detail: {
            DetailView(viewModel: viewModel, authManager: authManager, columnVisibility: $columnVisibility)
        }
        .task {
            await authManager.restoreSession()
            viewModel.loggedInUsername = authManager.isLoggedIn ? authManager.username : nil
            await viewModel.loadFeed()
        }
        .onChange(of: authManager.isLoggedIn) {
            viewModel.loggedInUsername = authManager.isLoggedIn ? authManager.username : nil
            if !authManager.isLoggedIn && viewModel.contentType.requiresAuth {
                viewModel.contentType = .all
            }
        }
        .onAppear {
            applyAppearance(viewModel.appearanceMode)
        }
        .onChange(of: viewModel.appearanceMode) {
            applyAppearance(viewModel.appearanceMode)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(tabTitle)
        .focusedSceneValue(\.feedViewModel, viewModel)
    }

    private var tabTitle: String {
        if viewModel.showingSettings {
            return "Settings"
        }
        if viewModel.viewingUserProfileURL != nil {
            return "Profile"
        }
        if let story = viewModel.selectedStory {
            return story.title ?? story.storyTitle ?? "Hacker News"
        }
        return "Hacker News"
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}
