import SwiftUI

// MARK: - Podcast list row

/// A show row for category and search lists.
struct PodcastListRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: podcast.artworkURL)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(podcast.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle = podcast.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if podcast.programCount > 0 {
                        Text("\(podcast.programCount) 期")
                    }
                    if podcast.subscriberCount > 0 {
                        Text("\(Formatters.playCount(podcast.subscriberCount)) 订阅")
                    }
                    if podcast.isPaid {
                        PodcastPaidBadge()
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Program row

/// One episode row. It follows the song row's contract: no permanently
/// visible play button, hover reveals the actions, double-click (macOS) or a
/// tap (iOS) plays, and the context menu reaches the episode page.
struct PodcastProgramRow: View {
    let program: PodcastProgram
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onOpenDetail: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            leadingIndicator

            CachedAsyncImage(url: program.artworkURL)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(program.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let createTime = program.createTime {
                        Text(Formatters.date(fromMS: Int(createTime)))
                    }
                    if program.durationMS > 0 {
                        Text(Formatters.duration(TimeInterval(program.durationMS) / 1000))
                    }
                    if program.listenerCount > 0 {
                        Text("\(Formatters.playCount(program.listenerCount)) 次播放")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button(action: onOpenDetail) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("节目详情")
                .help("节目详情")
            }

            Text(Formatters.duration(TimeInterval(program.durationMS) / 1000))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        #if os(macOS)
        .onTapGesture(count: 2, perform: onPlay)
        .help("双击播放")
        #else
        .onTapGesture(perform: onPlay)
        #endif
        .contextMenu {
            Button("播放", action: onPlay)
            Button("节目详情", action: onOpenDetail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("播放节目：\(program.name)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        ZStack {
            if isCurrent {
                PlayingIndicator(animating: isPlaying)
            } else if isHovering {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("播放")
            } else {
                Text(String(program.serialNum ?? (index + 1)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 28)
    }
}

// MARK: - Category tile

struct PodcastCategoryTile: View {
    let category: PodcastCategory

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: category.artworkURL)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(category.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paid badge

struct PodcastPaidBadge: View {
    var body: some View {
        Text("付费")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.accent.opacity(0.8), lineWidth: 1)
            )
    }
}
