import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: FeedViewModel
    @State private var listSelection: HNItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Content", selection: $viewModel.contentType) {
                    ForEach(HNContentType.allCases.filter { !$0.requiresAuth || viewModel.loggedInUsername != nil }) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                Picker("Sort", selection: $viewModel.displaySort) {
                    ForEach(HNDisplaySort.allCases) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .labelsHidden()
                Picker("Date", selection: $viewModel.dateRange) {
                    ForEach(HNDateRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Spacer().frame(height: 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $viewModel.searchQuery)
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
                        .font(.system(size: 36 * viewModel.textScale))
                        .foregroundStyle(.tertiary)
                    Text("No Bookmarks")
                        .font(.system(size: 15 * viewModel.textScale, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Bookmark stories to save them here.")
                        .font(.system(size: 10 * viewModel.textScale))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.showLoadingIndicator && viewModel.stories.isEmpty {
                VStack {
                    Spacer()
                    ProgressView(viewModel.contentType.isComments ? "Loading comments..." : viewModel.contentType.isThreads ? "Loading threads..." : viewModel.contentType.isAll ? "Loading feed..." : "Loading stories...")
                        .font(.system(size: 13 * viewModel.textScale))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.stories.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("Failed to load stories")
                        .font(.system(size: 15 * viewModel.textScale, weight: .semibold))
                    Text(error)
                        .font(.system(size: 10 * viewModel.textScale))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.loadFeed() }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $listSelection) {
                    ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if item.type == "comment" {
                                CommentRowView(comment: item, textScale: viewModel.textScale) { username in
                                    if let url = URL(string: "https://news.ycombinator.com/user?id=\(username)") {
                                        viewModel.navigateToProfile(url: url)
                                    }
                                }
                            } else {
                                StoryRowView(story: item, rank: index + 1, textScale: viewModel.textScale) { username in
                                    if let url = URL(string: "https://news.ycombinator.com/user?id=\(username)") {
                                        viewModel.navigateToProfile(url: url)
                                    }
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
                .onChange(of: listSelection) { _, newValue in
                    if let story = newValue {
                        viewModel.navigate(to: story)
                    }
                }
                .onChange(of: viewModel.selectedStory) { _, newValue in
                    if listSelection != newValue {
                        listSelection = newValue
                    }
                }
            }
        }
    }
}
