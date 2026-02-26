import SwiftUI

struct StoryGridView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @State private var showingLoginSheet = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280 * viewModel.textScale, maximum: 400 * viewModel.textScale), spacing: 16)]
    }

    var body: some View {
        Group {
            if viewModel.visibleStories.isEmpty && viewModel.showLoadingIndicator {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading stories...")
                        .font(.system(size: 13 * viewModel.textScale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleStories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48 * viewModel.textScale))
                        .foregroundStyle(.tertiary)
                    Text("No stories to display")
                        .font(.system(size: 17 * viewModel.textScale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.visibleStories) { story in
                            StoryCardView(story: story, textScale: viewModel.textScale)
                                .onTapGesture {
                                    viewModel.navigate(to: story)
                                }
                                .contextMenu {
                                    Button {
                                        viewModel.toggleBookmark(story)
                                    } label: {
                                        Label(viewModel.isBookmarked(story) ? "Remove Bookmark" : "Bookmark", systemImage: viewModel.isBookmarked(story) ? "bookmark.fill" : "bookmark")
                                    }
                                    Button {
                                        if authManager.isLoggedIn {
                                            Task {
                                                if viewModel.isHidden(story) {
                                                    await viewModel.unhideStory(story)
                                                } else {
                                                    await viewModel.hideStory(story)
                                                }
                                            }
                                        } else {
                                            showingLoginSheet = true
                                        }
                                    } label: {
                                        Label(viewModel.isHidden(story) ? "Unhide" : "Hide", systemImage: viewModel.isHidden(story) ? "eye" : "eye.slash")
                                    }
                                    Divider()
                                    if let url = story.displayURL ?? Optional(story.commentsURL) {
                                        ShareLink(item: url) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button {
                                            NSWorkspace.shared.open(url)
                                        } label: {
                                            Label("Open in Browser", systemImage: "safari")
                                        }
                                    }
                                }
                                .onAppear {
                                    Task { await viewModel.loadMoreIfNeeded(currentItem: story) }
                                }
                        }
                    }
                    .padding(20)
                }
                .background(Color(.windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingLoginSheet) {
            LoginSheetView(authManager: authManager, textScale: viewModel.textScale)
        }
    }
}
