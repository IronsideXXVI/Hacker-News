import SwiftUI

struct CommentRowView: View {
    let comment: HNItem
    var onUsernameTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let storyTitle = comment.storyTitle {
                Text(storyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let text = comment.text {
                Text(text.strippingHTML())
                    .font(.body)
                    .lineLimit(3)
            }

            HStack(spacing: 4) {
                if let by = comment.by {
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
                            onUsernameTap?(by)
                        }
                }
                Text(comment.timeAgo)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
