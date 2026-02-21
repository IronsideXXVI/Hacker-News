import SwiftUI

struct CommentRowView: View {
    let comment: HNItem
    var textScale: Double = 1.0
    var isSelected: Bool = false
    var onUsernameTap: ((String) -> Void)?

    private var adaptiveSecondary: Color {
        isSelected ? .white.opacity(0.7) : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let storyTitle = comment.storyTitle {
                Text(storyTitle)
                    .font(.system(size: 10 * textScale))
                    .foregroundStyle(adaptiveSecondary)
                    .lineLimit(1)
            }

            if let text = comment.text {
                Text(text.strippingHTML())
                    .font(.system(size: 13 * textScale))
                    .lineLimit(3)
            }

            HStack(spacing: 4) {
                if let by = comment.by {
                    Text(by)
                        .foregroundStyle(isSelected ? .white : .orange)
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
            .font(.system(size: 10 * textScale))
            .foregroundStyle(adaptiveSecondary)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.vertical, 2)
    }
}
