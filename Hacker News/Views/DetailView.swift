import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    var hideManager: HNHideManager
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
    @State private var webViewID = UUID()

    // Split mode: comments pane state
    @State private var commentsScrollProgress: Double = 0.0
    @State private var isCommentsWebViewLoading = true
    @State private var commentsWebLoadError: String?
    @State private var showCommentsError = false
    @State private var commentsErrorRevealTask: Task<Void, Never>?
    @State private var showCommentsContent = false
    @State private var commentsMinDelayMet = false
    @State private var commentsMinDelayTask: Task<Void, Never>?
    @State private var commentsWebViewProxy = WebViewProxy()
    @State private var commentsWebViewID = UUID()

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.showingSettings {
            SettingsView(viewModel: viewModel)
        } else if let profileURL = viewModel.viewingUserProfileURL {
            profileContentView(url: profileURL)
        } else if let story = viewModel.selectedStory {
            storyContentView(for: story)
        } else {
            StoryGridView(viewModel: viewModel, authManager: authManager)
        }
    }

    private var contentWithChangeHandlers: some View {
        mainContent
            .onChange(of: viewModel.selectedStory) { beginNavigation() }
            .onChange(of: viewModel.viewingUserProfileURL) { beginNavigation() }
            .onChange(of: webLoadError) { if webLoadError == nil { showError = false; errorRevealTask?.cancel() } }
            .onChange(of: isWebViewLoading) { handlePrimaryLoadingChange() }
            .onChange(of: minDelayMet) { if minDelayMet && !isWebViewLoading { showContent = true } }
            .onChange(of: commentsWebLoadError) { if commentsWebLoadError == nil { showCommentsError = false; commentsErrorRevealTask?.cancel() } }
            .onChange(of: isCommentsWebViewLoading) { handleCommentsLoadingChange() }
            .onChange(of: commentsMinDelayMet) { if commentsMinDelayMet && !isCommentsWebViewLoading { showCommentsContent = true } }
    }

    var body: some View {
        contentWithChangeHandlers
            .onChange(of: viewModel.webRefreshID) { webViewID = UUID(); commentsWebViewID = UUID() }
            .onChange(of: viewModel.showFindBar) { if !viewModel.showFindBar { viewModel.findQuery = ""; activeWebViewProxy.clearSelection() } }
            .onChange(of: viewModel.findNextTrigger) { activeWebViewProxy.findNext(viewModel.findQuery) }
            .onChange(of: viewModel.findPreviousTrigger) { activeWebViewProxy.findPrevious(viewModel.findQuery) }
            .onChange(of: viewModel.goBackTrigger) {
                if activeWebViewProxy.canGoBack { activeWebViewProxy.goBack() }
                else { viewModel.navigateBack() }
            }
            .onChange(of: viewModel.goForwardTrigger) {
                if activeWebViewProxy.canGoForward { activeWebViewProxy.goForward() }
                else { viewModel.navigateForward() }
            }
            .onChange(of: viewModel.refreshTrigger) { webViewID = UUID(); commentsWebViewID = UUID(); Task { await viewModel.loadFeed() } }
            .onChange(of: viewModel.readerModeTrigger) {
                if viewModel.selectedStory != nil,
                   viewModel.selectedStory?.displayURL != nil,
                   viewModel.viewMode != .comments,
                   viewModel.viewingUserProfileURL == nil,
                   viewModel.isReaderModeAvailable || viewModel.isReaderModeActive {
                    toggleReaderMode()
                }
            }
            .toolbar { detailToolbarContent }
            .sheet(isPresented: $showingLoginSheet) {
                LoginSheetView(authManager: authManager, textScale: viewModel.textScale)
            }
    }

    @ToolbarContentBuilder
    private var detailToolbarContent: some ToolbarContent {
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
            if activeWebViewProxy.canGoBack || activeWebViewProxy.canGoForward || viewModel.canNavigateBack || viewModel.canNavigateForward {
                Button {
                    if activeWebViewProxy.canGoBack { activeWebViewProxy.goBack() }
                    else { viewModel.navigateBack() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .disabled(!activeWebViewProxy.canGoBack && !viewModel.canNavigateBack)
                Button {
                    if activeWebViewProxy.canGoForward { activeWebViewProxy.goForward() }
                    else { viewModel.navigateForward() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")
                .disabled(!activeWebViewProxy.canGoForward && !viewModel.canNavigateForward)
            }
            Button {
                webViewID = UUID()
                commentsWebViewID = UUID()
                Task { await viewModel.loadFeed() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            Button {
                viewModel.navigateHome()
            } label: {
                Image(systemName: "house")
            }
            .help("Home")
            if viewModel.selectedStory != nil,
               viewModel.selectedStory?.displayURL != nil,
               viewModel.viewMode != .comments,
               viewModel.viewingUserProfileURL == nil {
                Button {
                    toggleReaderMode()
                } label: {
                    Image(systemName: viewModel.isReaderModeActive ? "doc.plaintext.fill" : "doc.plaintext")
                }
                .help(viewModel.isReaderModeActive ? "Exit Reader Mode" : "Reader Mode")
                .disabled(!viewModel.isReaderModeAvailable && !viewModel.isReaderModeActive)
            }
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
                Picker("View", selection: Binding(
                    get: { viewModel.viewMode },
                    set: { viewModel.changeViewMode(to: $0) }
                )) {
                    Text("Post").tag(ViewMode.post)
                    Text("Comments").tag(ViewMode.comments)
                    Image(systemName: "rectangle.split.2x1").tag(ViewMode.both)
                }
                .pickerStyle(.segmented)
            }
        }
        ToolbarItem(placement: .automatic) {
            if authManager.isLoggedIn {
                Button {
                    if let url = URL(string: "https://news.ycombinator.com/submit") {
                        viewModel.navigateToProfile(url: url)
                    }
                } label: {
                    Text("Submit")
                        .foregroundStyle(.primary)
                }
            }
        }
        ToolbarItemGroup(placement: .automatic) {
            if authManager.isLoggedIn {
                Button {
                    if let url = URL(string: "https://news.ycombinator.com/user?id=\(authManager.username)") {
                        viewModel.navigateToProfile(url: url)
                    }
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
            Button { viewModel.navigateToSettings() } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    @ViewBuilder
    private func findBar() -> some View {
        let proxy = activeWebViewProxy
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Find in page...", text: $viewModel.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        proxy.findNext(viewModel.findQuery)
                    }
                    .onKeyPress(.escape) {
                        viewModel.showFindBar = false
                        return .handled
                    }
                    .onChange(of: viewModel.findQuery) {
                        let query = viewModel.findQuery
                        if query.isEmpty {
                            proxy.clearSelection()
                        } else {
                            Task {
                                await proxy.countMatches(query)
                                proxy.findFirst(query)
                            }
                        }
                    }
                if !viewModel.findQuery.isEmpty {
                    Text("\(proxy.currentMatch) of \(proxy.matchCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        viewModel.findQuery = ""
                        proxy.clearSelection()
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
                proxy.findPrevious(viewModel.findQuery)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.findQuery.isEmpty)

            Button {
                proxy.findNext(viewModel.findQuery)
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

    private var activeWebViewProxy: WebViewProxy {
        if let story = viewModel.selectedStory, story.type != "comment", story.displayURL != nil, viewModel.viewMode == .comments {
            return commentsWebViewProxy
        }
        return webViewProxy
    }

    @ViewBuilder
    private func scrollProgressBar() -> some View {
        let progress = activeWebViewProxy === commentsWebViewProxy ? commentsScrollProgress : scrollProgress
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.orange.opacity(0.15))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.1), value: scrollProgress)
        .animation(.linear(duration: 0.1), value: commentsScrollProgress)
    }

    @ViewBuilder
    private func profileContentView(url profileURL: URL) -> some View {
        VStack(spacing: 0) {
            scrollProgressBar()
            if viewModel.showFindBar { findBar() }
            ZStack {
                ArticleWebView(url: profileURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, textScale: viewModel.textScale, webViewProxy: webViewProxy, onNavigateToItem: { viewModel.navigateToStory(id: $0, viewMode: $1, currentWebURL: $2) }, onHideToggled: handleHideToggled, onLoginRequired: { showingLoginSheet = true }, isLoggedIn: authManager.isLoggedIn, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                    .id(webViewID)
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
    }

    @ViewBuilder
    private func storyContentView(for story: HNItem) -> some View {
        VStack(spacing: 0) {
            storyInfoBar(for: story)
            scrollProgressBar()
            if viewModel.showFindBar { findBar() }
            if story.type != "comment", let articleURL = story.displayURL {
                dualPaneView(articleURL: articleURL, commentsURL: story.commentsURL)
            } else {
                ZStack {
                    ArticleWebView(url: story.commentsURL, adBlockingEnabled: viewModel.adBlockingEnabled, popUpBlockingEnabled: viewModel.popUpBlockingEnabled, textScale: viewModel.textScale, webViewProxy: webViewProxy, onCommentSortChanged: handleCommentSortChanged, onNavigateToItem: { viewModel.navigateToStory(id: $0, viewMode: $1, currentWebURL: $2) }, onHideToggled: handleHideToggled, onLoginRequired: { showingLoginSheet = true }, isLoggedIn: authManager.isLoggedIn, scrollProgress: $scrollProgress, isLoading: $isWebViewLoading, loadError: $webLoadError)
                        .id(webViewID)
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
        }
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
                                if let url = URL(string: "https://news.ycombinator.com/user?id=\(by)") {
                                    viewModel.navigateToProfile(url: url)
                                }
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
                                if let url = URL(string: "https://news.ycombinator.com/user?id=\(by)") {
                                    viewModel.navigateToProfile(url: url)
                                }
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

    private func handlePrimaryLoadingChange() {
        if isWebViewLoading {
            showContent = false
            minDelayMet = false
            minDelayTask?.cancel()
            minDelayTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                minDelayMet = true
            }
        } else if minDelayMet {
            showContent = true
        }
    }

    private func handleCommentsLoadingChange() {
        if isCommentsWebViewLoading {
            showCommentsContent = false
            commentsMinDelayMet = false
            commentsMinDelayTask?.cancel()
            commentsMinDelayTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                commentsMinDelayMet = true
            }
        } else if commentsMinDelayMet {
            showCommentsContent = true
        }
    }

    private func beginNavigation() {
        webViewProxy.commentSort = viewModel.commentSort
        commentsWebViewProxy.commentSort = viewModel.commentSort
        scrollProgress = 0
        isWebViewLoading = true
        webLoadError = nil
        showError = false
        showContent = false
        minDelayMet = false
        viewModel.showFindBar = false
        webViewID = UUID()
        scheduleErrorReveal()
        minDelayTask?.cancel()
        minDelayTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            minDelayMet = true
        }

        commentsScrollProgress = 0
        isCommentsWebViewLoading = true
        commentsWebLoadError = nil
        showCommentsError = false
        showCommentsContent = false
        commentsMinDelayMet = false
        commentsWebViewID = UUID()
        scheduleCommentsErrorReveal()
        commentsMinDelayTask?.cancel()
        commentsMinDelayTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commentsMinDelayMet = true
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

    private func scheduleCommentsErrorReveal() {
        commentsErrorRevealTask?.cancel()
        commentsErrorRevealTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, commentsWebLoadError != nil else { return }
            showCommentsError = true
        }
    }

    private func toggleReaderMode() {
        if viewModel.isReaderModeActive {
            viewModel.isReaderModeActive = false
            if let articleURL = viewModel.selectedStory?.displayURL {
                webViewProxy.deactivateReaderMode(url: articleURL)
            }
        } else {
            viewModel.isReaderModeActive = true
            webViewProxy.prepareForReaderMode()
            Task {
                await webViewProxy.activateReaderMode(pageZoom: CGFloat(viewModel.textScale))
            }
        }
    }

    private func handleHideToggled(itemID: Int, isUnhide: Bool) {
        guard authManager.isLoggedIn else { return }
        hideManager.onItemHiddenFromWeb(id: itemID, isUnhide: isUnhide)
    }

    private func handleCommentSortChanged(_ mode: String) {
        if let sort = HNCommentSort(rawValue: mode) {
            viewModel.commentSort = sort
            webViewProxy.commentSort = sort
            commentsWebViewProxy.commentSort = sort
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
    private func dualPaneView(articleURL: URL, commentsURL: URL) -> some View {
        HStack(spacing: 0) {
            // Article pane — always alive, hidden when in comments-only mode
            ZStack {
                ArticleWebView(
                    url: articleURL,
                    adBlockingEnabled: viewModel.adBlockingEnabled,
                    popUpBlockingEnabled: viewModel.popUpBlockingEnabled,
                    textScale: viewModel.textScale,
                    webViewProxy: webViewProxy,
                    onReadabilityChecked: { isReaderable in
                        viewModel.isReaderModeAvailable = isReaderable
                        if viewModel.isReaderModeActive && isReaderable {
                            // Keep loading overlay visible while reader mode activates
                            webViewProxy.prepareForReaderMode()
                            Task {
                                await webViewProxy.activateReaderMode(pageZoom: CGFloat(viewModel.textScale))
                            }
                        } else {
                            // No reader mode activation — reveal content now
                            isWebViewLoading = false
                        }
                    },
                    onNavigateToItem: { viewModel.navigateToStory(id: $0, viewMode: $1, currentWebURL: $2) },
                    scrollProgress: $scrollProgress,
                    isLoading: $isWebViewLoading,
                    loadError: $webLoadError
                )
                .id(webViewID)
                .opacity(showContent ? 1 : 0)
                .animation(.easeIn(duration: 0.2), value: showContent)

                if !showContent {
                    webLoadingOverlay
                }
                if showError, let error = webLoadError {
                    webErrorView(error: error, url: articleURL)
                }
            }
            .frame(maxWidth: viewModel.viewMode == .comments ? 0 : .infinity)
            .opacity(viewModel.viewMode == .comments ? 0 : 1)
            .clipped()

            // Comments pane — always alive, hidden when in post-only mode
            ZStack {
                ArticleWebView(
                    url: commentsURL,
                    adBlockingEnabled: viewModel.adBlockingEnabled,
                    popUpBlockingEnabled: viewModel.popUpBlockingEnabled,
                    textScale: viewModel.textScale,
                    webViewProxy: commentsWebViewProxy,
                    onCommentSortChanged: handleCommentSortChanged,
                    onNavigateToItem: { viewModel.navigateToStory(id: $0, viewMode: $1, currentWebURL: $2) },
                    onHideToggled: handleHideToggled,
                    onLoginRequired: { showingLoginSheet = true },
                    isLoggedIn: authManager.isLoggedIn,
                    scrollProgress: $commentsScrollProgress,
                    isLoading: $isCommentsWebViewLoading,
                    loadError: $commentsWebLoadError
                )
                .id(commentsWebViewID)
                .opacity(showCommentsContent ? 1 : 0)
                .animation(.easeIn(duration: 0.2), value: showCommentsContent)

                if !showCommentsContent {
                    webLoadingOverlay
                }
                if showCommentsError, let error = commentsWebLoadError {
                    webErrorView(error: error, url: commentsURL)
                }
            }
            .frame(maxWidth: viewModel.viewMode == .post ? 0 : .infinity)
            .opacity(viewModel.viewMode == .post ? 0 : 1)
            .clipped()
        }
    }

    private var currentExternalURL: URL? {
        if let profileURL = viewModel.viewingUserProfileURL {
            return profileURL
        }
        guard let story = viewModel.selectedStory else { return nil }
        switch viewModel.viewMode {
        case .post, .both:
            if let articleURL = story.displayURL { return articleURL }
            return story.commentsURL
        case .comments:
            return story.commentsURL
        }
    }
}
