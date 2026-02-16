import SwiftUI

struct ContentView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        NavigationSplitView(
            columnVisibility: .constant(.all)
        ) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 350, ideal: 420, max: 550)
        } detail: {
            DetailView(viewModel: viewModel)
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
