import SwiftUI

struct StoryCardView: View {
    let story: HNItem
    var textScale: Double = 1.0
    @State private var isHovered = false
    @State private var cardImage: NSImage?
    @State private var imageLoaded = false
    @Environment(\.colorScheme) private var colorScheme

    private var imageHeight: CGFloat { 140 * textScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
                .frame(height: imageHeight)

            textSection
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(red: 51/255, green: 51/255, blue: 51/255) : Color(red: 234/255, green: 234/255, blue: 234/255))
                .shadow(color: colorScheme == .dark ? .white.opacity(isHovered ? 0.15 : 0.08) : .black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 8 : 4, y: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .task(id: story.id) {
            guard let pageURL = story.url else {
                imageLoaded = true
                return
            }
            if let ogURLString = await OpenGraphService.shared.fetchImageURL(for: pageURL),
               let ogURL = URL(string: ogURLString) {
                cardImage = await ImageCacheService.shared.image(for: ogURL)
            }
            imageLoaded = true
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        GeometryReader { geo in
            ZStack {
                if let cardImage {
                    Image(nsImage: cardImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if imageLoaded {
                    defaultImage
                } else {
                    defaultImage
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var defaultImage: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.orange.opacity(0.45), Color.orange.opacity(0.20), Color.orange.opacity(0.075)]
                    : [Color.orange.opacity(0.45), Color.orange.opacity(0.20), Color.orange.opacity(0.075)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "doc.richtext")
                .font(.system(size: 32 * textScale))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.25) : Color.orange.opacity(0.3))
        }
    }

    // MARK: - Text Section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let domain = story.displayDomain {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 9 * textScale))
                    Text(domain)
                        .lineLimit(1)
                }
                .font(.system(size: 10 * textScale))
                .foregroundStyle(.secondary)
            } else if story.type == "job" {
                Label("Job", systemImage: "briefcase")
                    .font(.system(size: 10 * textScale))
                    .foregroundStyle(.orange)
            }

            if story.type == "comment" {
                if let storyTitle = story.storyTitle {
                    Text(storyTitle)
                        .font(.system(size: 10 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(story.text?.strippingHTML() ?? "")
                    .font(.system(size: 13 * textScale))
                    .lineLimit(3)
            } else {
                Text(story.title ?? "Untitled")
                    .font(.system(size: 14 * textScale, weight: .semibold))
                    .lineLimit(3)

                if story.url == nil, let text = story.text {
                    Text(text.strippingHTML())
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                if let score = story.score {
                    HStack(spacing: 2) {
                        Text("▲")
                            .font(.system(size: 8 * textScale))
                            .foregroundStyle(.orange)
                        Text("\(score)")
                    }
                }
                if let by = story.by {
                    Text(by)
                        .foregroundStyle(.orange)
                }
                Text(story.timeAgo)
                if let descendants = story.descendants {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 9 * textScale))
                        Text("\(descendants)")
                    }
                }
            }
            .font(.system(size: 10 * textScale))
            .foregroundStyle(.secondary)
        }
    }
}
