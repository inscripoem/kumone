import Foundation

extension MusicAPI {
    // MARK: - Transport

    /// Plain web API first: the podcast route family answers it, and no weapi
    /// crypto is needed. On a transport-level failure the same route and
    /// parameters are retried once through the eapi. Business answers (login,
    /// risk control) are thrown, not retried.
    private static func podcastRequest<Response: Decodable>(
        _ type: Response.Type, _ path: String, _ form: [String: String] = [:],
        using client: MusicClient = .shared
    ) async throws -> Response {
        let data: Data
        do {
            data = try await client.api(path, podcastForm(form, client: client))
        } catch {
            guard isTransportFailure(error) else { throw error }
            data = try await client.eapi(path, anyForm(podcastForm(form, client: client)))
        }
        return try client.decoded(Response.self, from: data)
    }

    /// The web client carries its CSRF token on every podcast call, reads
    /// included; an empty cookie omits the field.
    private static func podcastForm(_ form: [String: String], client: MusicClient) -> [String: String] {
        var form = form
        if let csrf = client.cookie(named: "__csrf"), !csrf.isEmpty {
            form["csrf_token"] = csrf
        }
        return form
    }

    private static func anyForm(_ form: [String: String]) -> [String: Any] {
        form.mapValues { $0 as Any }
    }

    private static func isTransportFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let apiError = error as? MusicAPIError else { return false }
        switch apiError {
        case .http, .decoding: return true
        case .business, .needLogin, .notConfigured: return false
        }
    }

    // MARK: - Responses

    struct PodcastCategoriesResponse: Decodable {
        let categories: [PodcastCategory]

        private enum CodingKeys: String, CodingKey {
            case categories
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            categories = (try? c.decode([PodcastCategory].self, forKey: .categories)) ?? []
        }
    }

    struct PodcastCollectionResponse: Decodable {
        let podcasts: [Podcast]
        let hasMore: Bool?
        let count: Int?

        private enum CodingKeys: String, CodingKey {
            case podcasts = "djRadios"
            case hasMore, count
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            podcasts = (try? c.decode([Podcast].self, forKey: .podcasts)) ?? []
            hasMore = try? c.decode(Bool.self, forKey: .hasMore)
            count = try? c.decode(Int.self, forKey: .count)
        }
    }

    struct PodcastPersonalizedResponse: Decodable {
        let podcasts: [Podcast]

        private enum CodingKeys: String, CodingKey {
            case podcasts = "data"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            podcasts = (try? c.decode([Podcast].self, forKey: .podcasts)) ?? []
        }
    }

    struct PodcastDetailResponse: Decodable {
        let podcast: Podcast?

        private enum CodingKeys: String, CodingKey {
            case podcast = "data"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            podcast = try? c.decode(Podcast.self, forKey: .podcast)
        }
    }

    struct PodcastProgramsResponse: Decodable {
        let programs: [PodcastProgram]
        let count: Int?
        let more: Bool?

        private enum CodingKeys: String, CodingKey {
            case programs, count, more
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            programs = (try? c.decode([PodcastProgram].self, forKey: .programs)) ?? []
            count = try? c.decode(Int.self, forKey: .count)
            more = try? c.decode(Bool.self, forKey: .more)
        }
    }

    // MARK: - Browse

    static func podcastCategories(using client: MusicClient = .shared) async throws -> [PodcastCategory] {
        let resp = try await podcastRequest(PodcastCategoriesResponse.self,
                                            "/djradio/category/get", [:], using: client)
        return resp.categories.filter { $0.id > 0 }
    }

    static func recommendedPodcasts(using client: MusicClient = .shared) async throws -> [Podcast] {
        try await podcastRequest(PodcastCollectionResponse.self,
                                 "/djradio/recommend/v1", [:], using: client).podcasts
    }

    /// Personalized recommendations require a login; the caller decides.
    static func personalizedPodcasts(limit: Int = 12,
                                     using client: MusicClient = .shared) async throws -> [Podcast] {
        try await podcastRequest(PodcastPersonalizedResponse.self,
                                 "/djradio/personalize/rcmd",
                                 ["limit": String(max(limit, 1))], using: client).podcasts
    }

    static func podcasts(categoryID: Int, offset: Int = 0, limit: Int = 30,
                         using client: MusicClient = .shared) async throws -> PodcastPage {
        let resp = try await podcastRequest(PodcastCollectionResponse.self, "/djradio/hot",
                                            ["cateId": String(categoryID),
                                             "limit": String(min(max(limit, 1), 50)),
                                             "offset": String(max(offset, 0))], using: client)
        return PodcastPage(
            podcasts: resp.podcasts,
            hasMore: resp.hasMore ?? (max(offset, 0) + resp.podcasts.count < (resp.count ?? 0)),
            totalCount: resp.count)
    }

    static func podcast(id: Int, using client: MusicClient = .shared) async throws -> Podcast {
        let resp = try await podcastRequest(PodcastDetailResponse.self, "/djradio/v2/get",
                                            ["id": String(id)], using: client)
        guard let podcast = resp.podcast else {
            throw MusicAPIError.decoding("djradio/v2/get: no data")
        }
        return podcast
    }

    // MARK: - Programs

    static func podcastPrograms(radioID: Int, offset: Int = 0, limit: Int = 30,
                                ascending: Bool = false,
                                using client: MusicClient = .shared) async throws -> PodcastProgramPage {
        let resp = try await podcastRequest(PodcastProgramsResponse.self, "/dj/program/byradio",
                                            ["radioId": String(radioID),
                                             "limit": String(min(max(limit, 1), 50)),
                                             "offset": String(max(offset, 0)),
                                             "asc": ascending ? "true" : "false"], using: client)
        let nextOffset = max(offset, 0) + resp.programs.count
        return PodcastProgramPage(
            programs: resp.programs,
            hasMore: resp.more ?? (!resp.programs.isEmpty && nextOffset < (resp.count ?? 0)),
            totalCount: resp.count ?? resp.programs.count)
    }

    static func podcastProgramDetail(id: Int,
                                     using client: MusicClient = .shared) async throws -> PodcastProgram {
        struct Response: Decodable {
            let program: PodcastProgram?
        }
        let resp = try await podcastRequest(Response.self, "/dj/program/detail",
                                            ["id": String(id)], using: client)
        guard let program = resp.program else {
            throw MusicAPIError.decoding("dj/program/detail: no program")
        }
        return program
    }

    // MARK: - Subscription

    static func subscribedPodcasts(offset: Int = 0, limit: Int = 50,
                                   using client: MusicClient = .shared) async throws -> PodcastPage {
        let resp = try await podcastRequest(PodcastCollectionResponse.self, "/djradio/get/subed",
                                            ["limit": String(min(max(limit, 1), 100)),
                                             "offset": String(max(offset, 0)),
                                             "total": "true"], using: client)
        return PodcastPage(
            podcasts: resp.podcasts,
            hasMore: resp.hasMore ?? (max(offset, 0) + resp.podcasts.count < (resp.count ?? 0)),
            totalCount: resp.count)
    }

    /// Follow/unfollow a show, through the web API like artist following.
    static func setPodcastSubscribed(id: Int, subscribed: Bool,
                                     using client: MusicClient = .shared) async throws {
        _ = try await podcastRequest(CodeOnly.self, subscribed ? "/djradio/sub" : "/djradio/unsub",
                                     ["id": String(id)], using: client)
    }
}
