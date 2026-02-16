import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @State private var showingLoginSheet = false

    var body: some View {
        Group {
            if let story = viewModel.selectedStory {
                articleOrCommentsView(for: story)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select a story")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("View", selection: $viewModel.preferArticleView) {
                    Text("Article").tag(true)
                    Text("Comments").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(viewModel.selectedStory == nil)
            }
            ToolbarItem(placement: .automatic) {
                if authManager.isLoggedIn {
                    HStack(spacing: 4) {
                        Text("\(authManager.username) (\(authManager.karma))")
                        Text("|")
                            .foregroundStyle(.separator)
                        Button("Logout") {
                            Task { await authManager.logout() }
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.primary)
                } else {
                    Button("Login") { showingLoginSheet = true }
                        .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingLoginSheet) {
            LoginSheetView(authManager: authManager)
        }
    }

    @ViewBuilder
    private func articleOrCommentsView(for story: HNItem) -> some View {
        if viewModel.preferArticleView, let articleURL = story.displayURL {
            ArticleWebView(url: articleURL)
        } else {
            ArticleWebView(url: story.commentsURL)
        }
    }
}
