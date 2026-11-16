import SwiftUI

struct PodcastProgramDetailView: View {
    let programID: Int

    @State private var program: PodcastProgram?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isDescriptionExpanded = false

    private let player = PlayerService.shared

    private var isCurrent: Bool {
        player.currentTrack?.podcastMetadata?.programID == program?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let program {
                    header(program)
                    if program.radio.id > 0 {
                        NavigationLink(value: Destination.podcast(program.radio.id)) {
                            HStack(spacing: 10) {
                                CachedAsyncImage(url: program.radio.picUrl?.resizedImageURL(96), animated: false)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("所属播客")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                    Text(program.radio.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let description = program.programDescription, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("简介")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(description)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(isDescriptionExpanded ? nil : 8)
                                .textSelection(.enabled)
                            if description.count > 160 {
                                Button(isDescriptionExpanded ? "收起" : "展开") {
                                    withAnimation(AppAnimation.quick) { isDescriptionExpanded.toggle() }
                                }
                                .font(.system(size: 11.5))
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                    .frame(minHeight: 300)
                }
                PlayerClearanceSpacer()
            }
            .padding(.horizontal, Theme.Layout.contentInset)
            .padding(.top, Theme.Layout.pageTopPadding)
        }
        #if os(macOS)
        .navigationTitle(program?.name ?? String(localized: "节目详情"))
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: programID) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            program = try await MusicAPI.podcastProgramDetail(id: programID)
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func header(_ program: PodcastProgram) -> some View {
        VStack(spacing: 14) {
            CachedAsyncImage(url: program.artworkURL)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .frame(maxWidth: .infinity)

            Text(program.name)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let host = program.host, !host.nickname.isEmpty {
                Text(host.nickname)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            metaLine(program)

            Button {
                play(program)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    Text(isCurrent && player.isPlaying ? "暂停" : "播放")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Theme.accentGradient, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.pressable)
            .disabled(program.playbackTrack == nil)
        }
    }

    private func metaLine(_ program: PodcastProgram) -> some View {
        HStack(spacing: 12) {
            if let createTime = program.createTime {
                Text(Formatters.date(fromMS: Int(createTime)))
            }
            if program.durationMS > 0 {
                Text(Formatters.duration(TimeInterval(program.durationMS) / 1000))
            }
            if program.listenerCount > 0 {
                Text("\(Formatters.playCount(program.listenerCount)) 次播放")
            }
            if program.likedCount > 0 {
                Text("\(Formatters.playCount(program.likedCount)) 点赞")
            }
            if program.isPaid {
                PodcastPaidBadge()
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
    }

    private func play(_ program: PodcastProgram) {
        guard let track = program.playbackTrack else { return }
        if isCurrent {
            player.togglePlayPause()
            return
        }
        player.play(tracks: [track], source: .none)
    }
}
