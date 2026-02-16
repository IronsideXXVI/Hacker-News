import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: FeedViewModel

    var body: some View {
        Group {
            if let story = viewModel.selectedStory {
                articleOrCommentsView(for: story)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Picker("View", selection: $viewModel.preferArticleView) {
                                Text("Article").tag(true)
                                Text("Comments").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
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
