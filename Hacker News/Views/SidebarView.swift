import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @State private var showingLoginSheet = false

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
        .sheet(isPresented: $showingLoginSheet) {
            LoginSheetView(authManager: authManager, textScale: viewModel.textScale)
        }
    }

    private var storyListView: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.stories.isEmpty {
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
                let stories = viewModel.visibleStories
                List {
                    ForEach(stories) { item in
                        let isSelected = viewModel.selectedStory?.id == item.id
                        Group {
                            if item.type == "comment" {
                                CommentRowView(comment: item, textScale: viewModel.textScale, isSelected: isSelected) { username in
                                    if let url = URL(string: "https://news.ycombinator.com/user?id=\(username)") {
                                        viewModel.navigateToProfile(url: url)
                                    }
                                }
                            } else {
                                let rank = (stories.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
                                StoryRowView(story: item, rank: rank, textScale: viewModel.textScale, isSelected: isSelected) { username in
                                    if let url = URL(string: "https://news.ycombinator.com/user?id=\(username)") {
                                        viewModel.navigateToProfile(url: url)
                                    }
                                }
                            }
                        }
                        .listRowBackground(
                            isSelected
                                ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor)
                                : nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.navigate(to: item)
                        }
                        .contextMenu {
                            Button {
                                viewModel.toggleBookmark(item)
                            } label: {
                                Label(viewModel.isBookmarked(item) ? "Remove Bookmark" : "Bookmark", systemImage: viewModel.isBookmarked(item) ? "bookmark.fill" : "bookmark")
                            }
                            Button {
                                if authManager.isLoggedIn {
                                    Task {
                                        if viewModel.isHidden(item) {
                                            await viewModel.unhideStory(item)
                                        } else {
                                            await viewModel.hideStory(item)
                                        }
                                    }
                                } else {
                                    showingLoginSheet = true
                                }
                            } label: {
                                Label(viewModel.isHidden(item) ? "Unhide" : "Hide", systemImage: viewModel.isHidden(item) ? "eye" : "eye.slash")
                            }
                            Divider()
                            if let url = item.displayURL ?? Optional(item.commentsURL) {
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

