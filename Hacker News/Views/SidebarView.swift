import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: FeedViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Content", selection: $viewModel.contentType) {
                    ForEach(HNContentType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Sort", selection: $viewModel.displaySort) {
                    ForEach(HNDisplaySort.allCases) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                Picker("Date", selection: $viewModel.dateRange) {
                    ForEach(HNDateRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Spacer().frame(height: 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search stories...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await viewModel.searchStories() }
                    }
                if viewModel.isSearchActive {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Spacer().frame(height: 6)
            Divider()

            storyListView
        }
    }

    private var storyListView: some View {
        Group {
            if viewModel.contentType.isBookmarks && viewModel.stories.isEmpty && !viewModel.isSearchActive {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Bookmarks")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Bookmark stories to save them here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.isLoading && viewModel.stories.isEmpty {
                VStack {
                    Spacer()
                    ProgressView(viewModel.contentType.isComments ? "Loading comments..." : viewModel.contentType.isAll ? "Loading feed..." : "Loading stories...")
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
                    ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if item.type == "comment" {
                                CommentRowView(comment: item) { username in
                                    viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(username)")
                                }
                            } else {
                                StoryRowView(story: item, rank: index + 1) { username in
                                    viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(username)")
                                }
                            }
                        }
                        .tag(item)
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentItem: item) }
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
