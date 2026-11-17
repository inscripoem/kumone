import SwiftUI

@MainActor
final class PodcastHomeModel: ObservableObject {
    /// Shared so the loaded page survives sidebar switches (no skeleton flash).
    static let shared = PodcastHomeModel()

    enum State {
        case idle, loading, loaded
        case error(String)
    }

    @Published var state: State = .idle
    @Published var recommended: [Podcast] = []
    @Published var personalized: [Podcast] = []
    @Published var categories: [PodcastCategory] = []
    @Published var subscriptions: [Podcast] = []
    /// Which login state the loaded content belongs to; signing in or out
    /// refreshes the personalized and subscribed sections.
    private var loadedLoggedIn: Bool?

    func load(loggedIn: Bool) async {
        if case .loaded = state, loadedLoggedIn == loggedIn { return }
        state = .loading

        do {
            async let recommendedTask = MusicAPI.recommendedPodcasts()
            async let categoriesTask = MusicAPI.podcastCategories()
            let recommended = try await recommendedTask
            let categories = try await categoriesTask
            self.recommended = recommended
            self.categories = categories

            if loggedIn {
                personalized = (try? await MusicAPI.personalizedPodcasts(limit: 18)) ?? []
                subscriptions = (try? await MusicAPI.subscribedPodcasts(limit: 100))?.podcasts ?? []
            } else {
                personalized = []
                subscriptions = []
            }

            loadedLoggedIn = loggedIn
            state = recommended.isEmpty && categories.isEmpty
                ? .error(String(localized: "网络连接失败"))
                : .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func reload(loggedIn: Bool) async {
        state = .idle
        await load(loggedIn: loggedIn)
    }
}

struct PodcastHomeView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var player: PlayerService
    @StateObject private var model = PodcastHomeModel.shared

    var body: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading:
                loadingBody
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await model.reload(loggedIn: account.isLoggedIn) }
                }
                .frame(minHeight: 400)
            case .loaded:
                loadedBody
            }
        }
        .navigationTitle("播客")
        .task(id: account.isLoggedIn) {
            await model.load(loggedIn: account.isLoggedIn)
        }
    }

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonView(cornerRadius: Theme.Radius.large)
                            .frame(width: 230, height: 132)
                    }
                }
            }
            SkeletonShelf()
            SkeletonShelf()
        }
        .padding(Theme.Layout.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadedBody: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            if !model.subscriptions.isEmpty {
                Shelf(title: "我的订阅", rowHeight: Theme.Layout.coverShelfHeight) {
                    ForEach(Array(model.subscriptions.prefix(12).enumerated()), id: \.element.id) { index, podcast in
                        podcastCard(podcast, index: index, key: "podsub")
                    }
                }
            }

            if !model.recommended.isEmpty {
                Shelf(title: "精选播客", rowHeight: Theme.Layout.coverShelfHeight) {
                    ForEach(Array(model.recommended.prefix(12).enumerated()), id: \.element.id) { index, podcast in
                        podcastCard(podcast, index: index, key: "podrec")
                    }
                }
            }

            if !model.personalized.isEmpty {
                Shelf(title: "为你推荐", rowHeight: Theme.Layout.coverShelfHeight) {
                    ForEach(Array(model.personalized.prefix(12).enumerated()), id: \.element.id) { index, podcast in
                        podcastCard(podcast, index: index, key: "podper")
                    }
                }
            }

            if !model.categories.isEmpty {
                SectionHeader(title: "全部分类")
                    .padding(.horizontal, Theme.Layout.contentInset)
                CardGrid(minWidth: 200) {
                    ForEach(model.categories) { category in
                        NavigationLink(value: Destination.podcastCategory(id: category.id, name: category.name)) {
                            PodcastCategoryTile(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Layout.contentInset)
            }

            PlayerClearanceSpacer()
        }
        .padding(.top, Theme.Layout.pageTopPadding)
    }

    private func podcastCard(_ podcast: Podcast, index: Int, key: String) -> some View {
        NavigationLink(value: Destination.podcast(podcast.id)) {
            CoverCardBody(
                coverURL: podcast.artworkURL,
                title: podcast.name,
                subtitle: podcast.subtitle,
                playCount: podcast.playCount
            ) {
                playShow(podcast)
            }
        }
        .buttonStyle(.plain)
        .staggeredAppearance(index: index, id: "\(key)-\(podcast.id)")
    }

    /// Play a show's latest episode, queueing the page it came from so the
    /// queue matches the one a row tap inside the show would build.
    private func playShow(_ podcast: Podcast) {
        Task {
            do {
                let page = try await MusicAPI.podcastPrograms(radioID: podcast.id, limit: 50)
                let tracks = page.programs.compactMap(\.playbackTrack)
                guard let first = tracks.first else {
                    ToastCenter.shared.show(String(localized: "暂无可播放的节目"))
                    return
                }
                player.play(tracks: tracks, source: .none, startAt: first)
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }
}
