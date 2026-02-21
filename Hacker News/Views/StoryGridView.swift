import SwiftUI

struct StoryGridView: View {
    @Bindable var viewModel: FeedViewModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280 * viewModel.textScale, maximum: 400 * viewModel.textScale), spacing: 16)]
    }

    var body: some View {
        Group {
            if viewModel.stories.isEmpty && viewModel.showLoadingIndicator {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading stories...")
                        .font(.system(size: 13 * viewModel.textScale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.stories.isEmpty {
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
                        ForEach(viewModel.stories) { story in
                            StoryCardView(story: story, textScale: viewModel.textScale)
                                .onTapGesture {
                                    viewModel.selectedStory = story
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
    }
}
