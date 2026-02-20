import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: FeedViewModel
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
            await viewModel.loadFeed()
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
