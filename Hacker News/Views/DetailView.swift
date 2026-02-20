import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var showingLoginSheet = false
    @State private var scrollProgress: Double = 0.0
    @State private var isWebViewLoading = true
    @State private var webLoadError: String?
    @State private var showError = false
    @State private var errorRevealTask: Task<Void, Never>?
    @State private var showContent = false
    @State private var minDelayMet = false
    @State private var minDelayTask: Task<Void, Never>?
    @State private var webViewProxy = WebViewProxy()

    var body: some View {
        Group {
            if viewModel.showingSettings {
                SettingsView(viewModel: viewModel)
            } else if let profileURL = viewModel.viewingUserProfileURL {
                VStack(spacing: 0) {
                    scrollProgressBar()
                    if viewModel.showFindBar { findBar() }
                    ZStack {
                        ArticleWebView(url: profileURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, textScale: viewModel.textScale, webViewProxy: webViewProxy, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                            .id(viewModel.webRefreshID)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeIn(duration: 0.2), value: showContent)
                        if !showContent {
                            webLoadingOverlay
                        }
                        if showError, let error = webLoadError {
                            webErrorView(error: error, url: profileURL)
                        }
                    }
                }
            } else if let story = viewModel.selectedStory {
                VStack(spacing: 0) {
                    storyInfoBar(for: story)
                    scrollProgressBar()
                    if viewModel.showFindBar { findBar() }
                    ZStack {
                        articleOrCommentsView(for: story)
                            .opacity(showContent ? 1 : 0)
                            .animation(.easeIn(duration: 0.2), value: showContent)
                        if !showContent {
                            webLoadingOverlay
                        }
                        if showError, let error = webLoadError {
                            webErrorView(error: error, url: currentExternalURL)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48 * viewModel.textScale))
                        .foregroundStyle(.tertiary)
                    Text("Select a story")
                        .font(.system(size: 17 * viewModel.textScale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: viewModel.selectedStory) { beginNavigation() }
        .onChange(of: viewModel.preferArticleView) { beginNavigation() }
        .onChange(of: viewModel.viewingUserProfileURL) { beginNavigation() }
        .onChange(of: webLoadError) { if webLoadError == nil { showError = false; errorRevealTask?.cancel() } }
        .onChange(of: isWebViewLoading) { if !isWebViewLoading && minDelayMet { showContent = true } }
        .onChange(of: minDelayMet) { if minDelayMet && !isWebViewLoading { showContent = true } }
        .onChange(of: viewModel.showFindBar) {
            if !viewModel.showFindBar {
                viewModel.findQuery = ""
                webViewProxy.clearSelection()
            }
        }
        .onChange(of: viewModel.findNextTrigger) {
            webViewProxy.findNext(viewModel.findQuery)
        }
        .onChange(of: viewModel.findPreviousTrigger) {
            webViewProxy.findPrevious(viewModel.findQuery)
        }
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
                    viewModel.showingSettings = false
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
                if viewModel.selectedStory != nil && viewModel.viewingUserProfileURL == nil && viewModel.selectedStory?.type != "comment" && viewModel.selectedStory?.displayURL != nil {
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
            LoginSheetView(authManager: authManager, textScale: viewModel.textScale)
        }
    }

    @ViewBuilder
    private func findBar() -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Find in page...", text: $viewModel.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        webViewProxy.findNext(viewModel.findQuery)
                    }
                    .onKeyPress(.escape) {
                        viewModel.showFindBar = false
                        return .handled
                    }
                    .onChange(of: viewModel.findQuery) {
                        let query = viewModel.findQuery
                        if query.isEmpty {
                            webViewProxy.clearSelection()
                        } else {
                            Task {
                                await webViewProxy.countMatches(query)
                                webViewProxy.findFirst(query)
                            }
                        }
                    }
                if !viewModel.findQuery.isEmpty {
                    Text("\(webViewProxy.currentMatch) of \(webViewProxy.matchCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        viewModel.findQuery = ""
                        webViewProxy.clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button {
                webViewProxy.findPrevious(viewModel.findQuery)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.findQuery.isEmpty)

            Button {
                webViewProxy.findNext(viewModel.findQuery)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.findQuery.isEmpty)

            Spacer()

            Button {
                viewModel.showFindBar = false
            } label: {
                Text("Done")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        Divider()
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
                            .font(.system(size: 13 * viewModel.textScale))
                            .fontWeight(.medium)
                        Text(by)
                            .font(.system(size: 13 * viewModel.textScale))
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
                            .font(.system(size: 13 * viewModel.textScale))
                        Text(storyTitle)
                            .font(.system(size: 13 * viewModel.textScale))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(story.timeAgo)
                }
                .font(.system(size: 10 * viewModel.textScale))
                .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(story.title ?? "Untitled")
                        .font(.system(size: 13 * viewModel.textScale))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let domain = story.displayDomain {
                        Text("(\(domain))")
                            .font(.system(size: 10 * viewModel.textScale))
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
                .font(.system(size: 10 * viewModel.textScale))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        Divider()
    }

    private func beginNavigation() {
        scrollProgress = 0
        isWebViewLoading = true
        webLoadError = nil
        showError = false
        showContent = false
        minDelayMet = false
        viewModel.showFindBar = false
        scheduleErrorReveal()
        minDelayTask?.cancel()
        minDelayTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            minDelayMet = true
        }
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

    private func scheduleErrorReveal() {
        errorRevealTask?.cancel()
        errorRevealTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, webLoadError != nil else { return }
            showError = true
        }
    }

    private func webErrorView(error: String, url: URL?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36 * viewModel.textScale))
                .foregroundStyle(.secondary)
            Text("Failed to load page")
                .font(.system(size: 15 * viewModel.textScale, weight: .semibold))
            Text(error)
                .font(.system(size: 10 * viewModel.textScale))
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
            ArticleWebView(url: story.commentsURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, textScale: viewModel.textScale, webViewProxy: webViewProxy, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                .id(viewModel.webRefreshID)
        } else if viewModel.preferArticleView, let articleURL = story.displayURL {
            ArticleWebView(url: articleURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, textScale: viewModel.textScale, webViewProxy: webViewProxy, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                .id(viewModel.webRefreshID)
        } else {
            ArticleWebView(url: story.commentsURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, textScale: viewModel.textScale, webViewProxy: webViewProxy, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                .id(viewModel.webRefreshID)
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
