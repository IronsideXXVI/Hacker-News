import SwiftUI

struct ContentView: View {
    @State private var viewModel = FeedViewModel()
    @State private var authManager = HNAuthManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility
        ) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 375, max: 500)
                .toolbar(removing: .sidebarToggle)
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

#Preview {
    ContentView()
}
