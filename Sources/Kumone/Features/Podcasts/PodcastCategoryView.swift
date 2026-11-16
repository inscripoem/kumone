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

                    if hasMore || isLoadingMore || errorMessage != nil {
                        VStack(spacing: 6) {
                            if isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else if let errorMessage {
                                HStack(spacing: 8) {
                                    Text(errorMessage)
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
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isLoadingMore || errorMessage != nil ? 16 : 0)
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
        } catch is CancellationError {
            isLoading = false
            isLoadingMore = false
            return
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
