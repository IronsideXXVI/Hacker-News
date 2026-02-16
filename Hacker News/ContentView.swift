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
                .navigationSplitViewColumnWidth(min: 350, ideal: 420, max: 550)
        } detail: {
            DetailView(viewModel: viewModel, authManager: authManager)
        }
        .task {
            await viewModel.loadFeed()
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
