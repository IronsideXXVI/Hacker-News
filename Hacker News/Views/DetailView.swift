import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @State private var showingLoginSheet = false
    @State private var scrollProgress: Double = 0.0

    var body: some View {
        Group {
            if let profileURL = viewModel.viewingUserProfileURL {
                VStack(spacing: 0) {
                    scrollProgressBar()
                    ArticleWebView(url: profileURL, scrollProgress: $scrollProgress)
                        .id(viewModel.webRefreshID)
                }
            } else if let story = viewModel.selectedStory {
                VStack(spacing: 0) {
                    storyInfoBar(for: story)
                    scrollProgressBar()
                    articleOrCommentsView(for: story)
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
        .onChange(of: viewModel.selectedStory) { scrollProgress = 0 }
        .onChange(of: viewModel.preferArticleView) { scrollProgress = 0 }
        .onChange(of: viewModel.viewingUserProfileURL) { scrollProgress = 0 }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    viewModel.webRefreshID = UUID()
                    Task { await viewModel.loadFeed() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .help("Refresh")
                Button {
                    viewModel.selectedStory = nil
                    viewModel.viewingUserProfileURL = nil
                } label: {
                    Image(systemName: "house")
                        .imageScale(.medium)
                }
                .help("Home")
                if let url = currentExternalURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .imageScale(.medium)
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
                            .imageScale(.medium)
                    }
                    .help("Open in Browser")
                }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .navigation) {
                Picker("View", selection: $viewModel.preferArticleView) {
                    Text("Posts").tag(true)
                    Text("Comments").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(viewModel.selectedStory == nil || viewModel.viewingUserProfileURL != nil || viewModel.selectedStory?.type == "comment")
            }
            ToolbarItem(placement: .automatic) {
                if authManager.isLoggedIn {
                    Button {
                        viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/submit")
                    } label: {
                        Text("Submit")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .automatic) {
                if authManager.isLoggedIn {
                    Button {
                        viewModel.viewingUserProfileURL = URL(string: "https://news.ycombinator.com/user?id=\(authManager.username)")
                    } label: {
                        Text("\(authManager.username) (\(authManager.karma))")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .automatic) {
                if authManager.isLoggedIn {
                    Button("Logout") {
                        Task { await authManager.logout() }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                } else {
                    Button("Login") { showingLoginSheet = true }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                }
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

    @ViewBuilder
    private func articleOrCommentsView(for story: HNItem) -> some View {
        if story.type == "comment" {
            ArticleWebView(url: story.commentsURL, scrollProgress: $scrollProgress)
                .id(viewModel.webRefreshID)
        } else if viewModel.preferArticleView, let articleURL = story.displayURL {
            ArticleWebView(url: articleURL, scrollProgress: $scrollProgress)
                .id(viewModel.webRefreshID)
        } else {
            ArticleWebView(url: story.commentsURL, scrollProgress: $scrollProgress)
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
