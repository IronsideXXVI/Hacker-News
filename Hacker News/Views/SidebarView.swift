import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: FeedViewModel

    var body: some View {
        VStack(spacing: 0) {
            FeedToolbar(viewModel: viewModel)
            Divider()

            if viewModel.currentFeed.hasStoryList {
                storyListView
            } else if let webURL = viewModel.currentFeed.webURL {
                ArticleWebView(url: webURL)
            }
        }
    }

    private var storyListView: some View {
        Group {
            if viewModel.isLoading && viewModel.stories.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading stories...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.stories.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("Failed to load stories")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.loadFeed() }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $viewModel.selectedStory) {
                    ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, story in
                        StoryRowView(story: story, rank: index + 1) { username in
                            viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(username)")
                        }
                        .tag(story)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(currentItem: story) }
                            }
                    }

                    if viewModel.isLoading && !viewModel.stories.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}
