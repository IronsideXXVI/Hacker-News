import SwiftUI

struct StoryRowView: View {
    let story: HNItem
    let rank: Int
    var onUsernameTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(rank).")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 22, alignment: .trailing)

                Text("▲")
                    .font(.caption2)
                    .foregroundStyle(.orange)

                Text(story.title ?? "Untitled")
                    .font(.body)
                    .lineLimit(2)

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
                        .foregroundStyle(.orange)
                }
                Text(story.timeAgo)
                if let descendants = story.descendants {
                    Text("| \(descendants) comments")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 30)
        }
        .padding(.vertical, 2)
        .frame(height: 54, alignment: .center)
    }
}
