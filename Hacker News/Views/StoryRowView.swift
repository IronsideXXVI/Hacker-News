import SwiftUI

struct StoryRowView: View {
    let story: HNItem
    let rank: Int
    var textScale: Double = 1.0
    var isSelected: Bool = false
    var onUsernameTap: ((String) -> Void)?

    private var adaptiveSecondary: Color {
        isSelected ? .white : .secondary
    }

    private var titleLineHeight: CGFloat {
        ceil(13 * textScale * 1.2)
    }

    private var metadataText: Text {
        var result = Text("")
        if let score = story.score {
            result = result + Text("\(score) points ")
        }
        if let by = story.by {
            result = result + Text("by ") + Text(by).foregroundColor(isSelected ? .white : .orange) + Text(" ")
        }
        result = result + Text(story.timeAgo)
        if let descendants = story.descendants {
            result = result + Text(" | \(descendants) comments")
        }
        return result
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
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Line 1: title (truncated to fit alongside domain)
                        Text(story.title ?? "Untitled")
                            .font(.system(size: 13 * textScale))
                            .lineLimit(1)

                        // Line 2: title continuation (same width as line 1, collapses for short titles)
                        Text(story.title ?? "Untitled")
                            .font(.system(size: 13 * textScale))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, -titleLineHeight)
                            .clipped()
                    }

                    if let domain = story.displayDomain {
                        Text(" (\(domain))")
                            .font(.system(size: 10 * textScale))
                            .foregroundStyle(adaptiveSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                metadataText
                    .font(.system(size: 10 * textScale))
                    .foregroundStyle(adaptiveSecondary)
                    .lineLimit(1)
                    .onTapGesture {
                        if let by = story.by {
                            onUsernameTap?(by)
                        }
                    }
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.vertical, 2)
        .frame(height: 54 * textScale, alignment: .center)
    }
}
