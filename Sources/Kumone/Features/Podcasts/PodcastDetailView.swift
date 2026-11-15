import SwiftUI

struct PodcastDetailView: View {
    let podcastID: Int

    @State private var podcast: Podcast?
    @State private var programs: [PodcastProgram] = []
    @State private var totalCount = 0
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingPrograms = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var programsError: String?
    @State private var order: PodcastProgramOrder = .newest
    @State private var isSubscribing = false
    @State private var isDescriptionExpanded = false

    private let player = PlayerService.shared
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin
    @Environment(\.openDestination) private var openDestination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool {
        #if os(iOS)
        return LayoutSizeClass.isCompact(horizontal: horizontalSizeClass, vertical: verticalSizeClass,
                                         fallback: UIDevice.current.userInterfaceIdiom == .phone)
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                if let podcast {
                    if isCompact {
                        compactHeader(podcast).padding(.horizontal, 16).padding(.top, 12)
                    } else {
                        regularHeader(podcast).padding(.horizontal, Theme.Layout.contentInset).padding(.top, 16)
                    }
                    programList
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                    .frame(minHeight: 400)
                }
                PlayerClearanceSpacer()
            }
        }
        #if os(macOS)
        .navigationTitle(podcast?.name ?? String(localized: "播客"))
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: podcastID) {
            await load()
        }
        .onChange(of: order) { _ in
            Task { await loadPrograms(reset: true) }
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            podcast = try await MusicAPI.podcast(id: podcastID)
            await loadPrograms(reset: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadPrograms(reset: Bool) async {
        programsError = nil
        if reset {
            programs = []
            isLoadingPrograms = true
        }
        defer { if reset { isLoadingPrograms = false } }
        do {
            let offset = reset ? 0 : programs.count
            let page = try await MusicAPI.podcastPrograms(
                radioID: podcastID, offset: offset, ascending: order.ascending)
            var known = Set(programs.map(\.id))
            programs += page.programs.filter { known.insert($0.id).inserted }
            totalCount = max(page.totalCount, podcast?.programCount ?? 0, programs.count)
            hasMore = page.hasMore
        } catch {
            programsError = error.localizedDescription
            hasMore = false
        }
    }

    // MARK: - Header

    private func regularHeader(_ podcast: Podcast) -> some View {
        HStack(alignment: .center, spacing: 28) {
            CachedAsyncImage(url: podcast.picUrl?.resizedImageURL(512))
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("播客")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(podcast.name)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(3)
                if let host = podcast.host, !host.nickname.isEmpty {
                    Text(host.nickname)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                metaLine(podcast)
                actions(podcast)
            }
            Spacer(minLength: 0)
        }
    }

    private func compactHeader(_ podcast: Podcast) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                CachedAsyncImage(url: podcast.picUrl?.resizedImageURL(384))
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 5) {
                    Text("播客")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(podcast.name)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(3)
                    metaLine(podcast)
                }
            }
            actions(podcast)
        }
    }

    private func metaLine(_ podcast: Podcast) -> some View {
        HStack(spacing: 10) {
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
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func actions(_ podcast: Podcast) -> some View {
        HStack(spacing: 10) {
            Button {
                playLatest()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("播放最新一期")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.accentGradient, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.pressable)

            if account.isLoggedIn {
                Button {
                    Task { await toggleSubscription() }
                } label: {
                    HStack(spacing: 5) {
                        if isSubscribing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: podcast.isSubscribed ? "checkmark" : "plus")
                        }
                        Text(podcast.isSubscribed ? "已订阅" : "订阅")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(podcast.isSubscribed ? Theme.accent : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(isSubscribing)
            }
        }
    }

    // MARK: - Programs

    private var programList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if podcast?.podcastDescription?.isEmpty == false {
                descriptionBlock()
                    .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)
            }

            HStack {
                SectionHeader(title: "节目", subtitle: totalCount > 0 ? "\(totalCount)" : nil)
                Picker("", selection: $order) {
                    ForEach(PodcastProgramOrder.allCases) { order in
                        Text(order == .newest ? "最新" : "最早").tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.horizontal, isCompact ? 16 : Theme.Layout.contentInset)

            if programs.isEmpty {
                if isLoadingPrograms {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let programsError {
                    ErrorStateView(message: programsError) {
                        Task { await loadPrograms(reset: true) }
                    }
                    .frame(minHeight: 200)
                } else {
                    EmptyStateView(icon: "mic", title: "暂无节目")
                        .frame(minHeight: 200)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(programs.enumerated()), id: \.element.id) { _, program in
                        PodcastProgramRow(
                            program: program,
                            isCurrent: player.currentTrack?.podcastMetadata?.programID == program.id,
                            isPlaying: player.isPlaying,
                            onPlay: { play(program) },
                            onOpenDetail: { openDestination(.podcastProgram(program.id)) }
                        )
                    }
                }
                .padding(.horizontal, isCompact ? 10 : Theme.Layout.contentInset - 10)

                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else if let programsError {
                    HStack(spacing: 8) {
                        Text(programsError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Button("重试") {
                            Task {
                                hasMore = true
                                await loadMore()
                            }
                        }
                        .font(.system(size: 11.5))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 12)
                } else if hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { Task { await loadMore() } }
                }
            }
        }
    }

    private func descriptionBlock() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("简介")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(podcast?.podcastDescription ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(isDescriptionExpanded ? nil : 4)
                .textSelection(.enabled)
            Button(isDescriptionExpanded ? "收起" : "展开") {
                withAnimation(AppAnimation.quick) { isDescriptionExpanded.toggle() }
            }
            .font(.system(size: 11.5))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    // MARK: - Actions

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        await loadPrograms(reset: false)
    }

    /// Plays the tapped episode with the loaded episodes as the queue, so
    /// next/previous walk the show like a playlist.
    private func play(_ program: PodcastProgram) {
        guard let track = program.playbackTrack else { return }
        let tracks = programs.compactMap(\.playbackTrack)
        player.play(tracks: tracks.isEmpty ? [track] : tracks, source: .none, startAt: track)
    }

    private func playLatest() {
        Task {
            if programs.isEmpty, errorMessage == nil {
                await loadPrograms(reset: true)
            }
            guard let track = programs.first?.playbackTrack else {
                ToastCenter.shared.show(String(localized: "暂无可播放的节目"))
                return
            }
            player.play(tracks: [track], source: .none)
        }
    }

    private func toggleSubscription() async {
        guard let podcast else { return }
        let subscribing = !podcast.isSubscribed
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            try await MusicAPI.setPodcastSubscribed(id: podcast.id, subscribed: subscribing)
            self.podcast?.isSubscribed = subscribing
            ToastCenter.shared.show(subscribing
                ? String(localized: "已订阅播客")
                : String(localized: "已取消订阅"))
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
}
