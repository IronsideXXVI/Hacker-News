import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var showingLoginSheet = false
    @State private var scrollProgress: Double = 0.0
    @State private var isWebViewLoading = true
    @State private var webLoadError: String?

    var body: some View {
        Group {
            if viewModel.showingSettings {
                SettingsView(viewModel: viewModel)
            } else if let profileURL = viewModel.viewingUserProfileURL {
                VStack(spacing: 0) {
                    scrollProgressBar()
                    ZStack {
                        ArticleWebView(url: profileURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                            .id("\(viewModel.webRefreshID)|\(profileURL)")
                        if isWebViewLoading {
                            webLoadingOverlay
                        } else if let error = webLoadError {
                            webErrorView(error: error, url: profileURL)
                        }
                    }
                }
            } else if let story = viewModel.selectedStory {
                VStack(spacing: 0) {
                    storyInfoBar(for: story)
                    scrollProgressBar()
                    ZStack {
                        articleOrCommentsView(for: story)
                        if isWebViewLoading {
                            webLoadingOverlay
                        } else if let error = webLoadError {
                            webErrorView(error: error, url: currentExternalURL)
                        }
                    }
                }
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
        .onChange(of: viewModel.selectedStory) { scrollProgress = 0; isWebViewLoading = true; webLoadError = nil }
        .onChange(of: viewModel.preferArticleView) { scrollProgress = 0; isWebViewLoading = true; webLoadError = nil }
        .onChange(of: viewModel.viewingUserProfileURL) { scrollProgress = 0; isWebViewLoading = true; webLoadError = nil }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button {
                    viewModel.webRefreshID = UUID()
                    Task { await viewModel.loadFeed() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                Button {
                    viewModel.selectedStory = nil
                    viewModel.viewingUserProfileURL = nil
                } label: {
                    Image(systemName: "house")
                }
                .help("Home")
                if let story = viewModel.selectedStory {
                    Button {
                        viewModel.toggleBookmark(story)
                    } label: {
                        Image(systemName: viewModel.isBookmarked(story) ? "bookmark.fill" : "bookmark")
                    }
                    .help(viewModel.isBookmarked(story) ? "Remove Bookmark" : "Add Bookmark")
                }
                if let url = currentExternalURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share")
                }
                if currentExternalURL != nil {
                    Button {
                        if let url = currentExternalURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("Open in Browser")
                }
            }
            ToolbarItem(placement: .navigation) {
                if viewModel.selectedStory != nil && viewModel.viewingUserProfileURL == nil && viewModel.selectedStory?.type != "comment" {
                    Picker("View", selection: $viewModel.preferArticleView) {
                        Text("Post").tag(true)
                        Text("Comments").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            ToolbarItem(placement: .automatic) {
                if authManager.isLoggedIn {
                    Button {
                        viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/submit")
                    } label: {
                        Text("Submit")
                            .foregroundStyle(.primary)
                    }
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                if authManager.isLoggedIn {
                    Button {
                        viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(authManager.username)")
                    } label: {
                        Text("\(authManager.username) (\(authManager.karma))")
                    }
                    Button("Logout") {
                        Task { await authManager.logout() }
                    }
                } else {
                    Button("Login") { showingLoginSheet = true }
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { viewModel.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showingLoginSheet) {
            LoginSheetView(authManager: authManager)
        }
    }

    @ViewBuilder
    private func scrollProgressBar() -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.orange.opacity(0.15))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geometry.size.width * scrollProgress)
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.1), value: scrollProgress)
    }

    @ViewBuilder
    private func storyInfoBar(for story: HNItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if story.type == "comment" {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let by = story.by {
                        Text("Comment by")
                            .font(.body)
                            .fontWeight(.medium)
                        Text(by)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .onTapGesture {
                                viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(by)")
                            }
                    }
                    if let storyTitle = story.storyTitle {
                        Text("on:")
                            .font(.body)
                        Text(storyTitle)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(story.timeAgo)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(story.title ?? "Untitled")
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let domain = story.displayDomain {
                        Text("(\(domain))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let score = story.score {
                        Text("\(score) points")
                    }
                    if let by = story.by {
                        Text("by")
                        Text(by)
                            .foregroundStyle(.orange)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .onTapGesture {
                                viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(by)")
                            }
                    }
                    Text(story.timeAgo)
                    if let descendants = story.descendants {
                        Text("| \(descendants) comments")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        Divider()
    }

    private var webLoadingOverlay: some View {
        Color(.windowBackgroundColor)
            .overlay {
                Color.gray
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 0.25 : 0.0)
                    } animation: { _ in
                        .easeInOut(duration: 1.5)
                    }
            }
    }

    private func webErrorView(error: String, url: URL?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Failed to load page")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    @ViewBuilder
    private func articleOrCommentsView(for story: HNItem) -> some View {
        if story.type == "comment" {
            ArticleWebView(url: story.commentsURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                .id("\(viewModel.webRefreshID)|\(story.commentsURL)")
        } else if viewModel.preferArticleView, let articleURL = story.displayURL {
            ArticleWebView(url: articleURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                .id("\(viewModel.webRefreshID)|\(articleURL)")
        } else {
            ArticleWebView(url: story.commentsURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                .id("\(viewModel.webRefreshID)|\(story.commentsURL)")
        }
    }

    private var currentExternalURL: URL? {
        if let profileURL = viewModel.viewingUserProfileURL {
            return profileURL
        }
        guard let story = viewModel.selectedStory else { return nil }
        if viewModel.preferArticleView, let articleURL = story.displayURL {
            return articleURL
        }
        return story.commentsURL
    }
}
