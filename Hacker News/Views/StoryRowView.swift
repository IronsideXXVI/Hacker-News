import SwiftUI

struct StoryRowView: View {
    let story: HNItem
    let rank: Int
    var textScale: Double = 1.0
    var isSelected: Bool = false
    var onUsernameTap: ((String) -> Void)?

    private var adaptiveSecondary: Color {
        isSelected ? .white.opacity(0.7) : .secondary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(rank).")
                .foregroundStyle(adaptiveSecondary)
                .font(.system(size: 10 * textScale))
                .frame(minWidth: 22 * textScale, alignment: .trailing)

            Text("▲")
                .font(.system(size: 9 * textScale))
                .foregroundStyle(isSelected ? .white : .orange)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(story.title ?? "Untitled")
                        .font(.system(size: 13 * textScale))
                        .lineLimit(2)

                    if let domain = story.displayDomain {
                        Text("(\(domain))")
                            .font(.system(size: 10 * textScale))
                            .foregroundStyle(adaptiveSecondary)
                    }
                }

                HStack(spacing: 4) {
                    if let score = story.score {
                        Text("\(score) points")
                    }
                    if let by = story.by {
                        Text("by")
                        Text(by)
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
                            .foregroundStyle(isSelected ? .white : .orange)
                    }
                    Text(story.timeAgo)
                    if let descendants = story.descendants {
                        Text("| \(descendants) comments")
                    }
                }
                .font(.system(size: 10 * textScale))
                .foregroundStyle(adaptiveSecondary)
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.vertical, 2)
        .frame(height: 54 * textScale, alignment: .center)
    }
}
