import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel
    var authManager: HNAuthManager
    @State private var showingLoginSheet = false

    var body: some View {
        Group {
            if let profileURL = viewModel.viewingUserProfileURL {
                VStack(spacing: 0) {
                    if let story = viewModel.selectedStory {
                        storyInfoBar(for: story)
                    }
                    ArticleWebView(url: profileURL)
                }
            } else if let story = viewModel.selectedStory {
                VStack(spacing: 0) {
                    storyInfoBar(for: story)
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("View", selection: $viewModel.preferArticleView) {
                    Text("Article").tag(true)
                    Text("Comments").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(viewModel.selectedStory == nil || viewModel.viewingUserProfileURL != nil)
            }
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
    private func storyInfoBar(for story: HNItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        Divider()
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
