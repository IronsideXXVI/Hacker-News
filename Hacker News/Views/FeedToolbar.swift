import SwiftUI

struct FeedToolbar: View {
    @Bindable var viewModel: FeedViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HNFeedType.allCases, id: \.self) { feed in
                    Button {
                        viewModel.switchFeed(to: feed)
                    } label: {
                        Text(feed.displayName)
                            .font(feed == .top ? .headline : .subheadline)
                            .fontWeight(viewModel.currentFeed == feed ? .bold : .regular)
                            .foregroundStyle(viewModel.currentFeed == feed ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
