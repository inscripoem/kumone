import SwiftUI

struct PodcastCategoryView: View {
    let category: PodcastCategory

    @State private var podcasts: [Podcast] = []
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if podcasts.isEmpty {
                    emptyState
                } else {
                    ForEach(podcasts) { podcast in
                        NavigationLink(value: Destination.podcast(podcast.id)) {
                            PodcastListRow(podcast: podcast)
                        }
                        .buttonStyle(.plain)
                    }

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                    } else if hasMore {
                        Color.clear
                            .frame(height: 1)
                            .task(id: podcasts.count) { await loadMore() }
                    }
                }
                PlayerClearanceSpacer()
            }
            .padding(.horizontal, Theme.Layout.contentInset)
            .padding(.top, Theme.Layout.pageTopPadding)
        }
        .navigationTitle(category.name)
        .task(id: category.id) {
            guard podcasts.isEmpty else { return }
            await load(reset: true)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) {
                Task { await load(reset: true) }
            }
            .frame(minHeight: 300)
        } else {
            EmptyStateView(icon: "mic", title: "暂无播客")
                .frame(minHeight: 300)
        }
    }

    private func load(reset: Bool) async {
        if reset {
            isLoading = true
            errorMessage = nil
        }
        do {
            let offset = reset ? 0 : podcasts.count
            let page = try await MusicAPI.podcasts(categoryID: category.id, offset: offset)
            if reset { podcasts = [] }
            var known = Set(podcasts.map(\.id))
            podcasts += page.podcasts.filter { known.insert($0.id).inserted }
            hasMore = page.hasMore
        } catch {
            if podcasts.isEmpty { errorMessage = error.localizedDescription }
            hasMore = false
        }
        isLoading = false
        isLoadingMore = false
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await load(reset: false)
    }
}
