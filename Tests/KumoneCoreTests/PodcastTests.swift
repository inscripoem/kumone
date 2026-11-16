import Foundation
import Testing
@testable import KumoneCore

private final class PodcastProtocol: URLProtocol, @unchecked Sendable {
    struct RecordedRequest {
        let path: String
        let body: [String: String]
    }

    nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var requests: [RecordedRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(RecordedRequest(path: request.url?.path ?? "?", body: Self.formBody(request)))
        let (status, body) = Self.responder?(request) ?? (200, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func formBody(_ request: URLRequest) -> [String: String] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                collected.append(buffer, count: count)
            }
            data = collected
        } else {
            return [:]
        }
        guard let raw = String(data: data, encoding: .utf8) else { return [:] }
        var form: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { continue }
            form[String(key).removingPercentEncoding ?? String(key)] =
                parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
        }
        return form
    }
}

@Suite("Podcasts", .serialized)
struct PodcastTests {
    init() { TestUpstream.configure() }

    private func client() -> MusicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PodcastProtocol.self]
        let client = MusicClient(configuration: configuration, persistsCookies: false)
        client.setCookies(["MUSIC_U": "podcast-test-session", "__csrf": "csrf-token-1"])
        return client
    }

    private func reset(_ responder: @escaping (URLRequest) -> (Int, String)) {
        PodcastProtocol.responder = responder
        PodcastProtocol.requests = []
    }

    private let recommendBody = """
    {"code":200,"djRadios":[{"id":1230174483,"name":"你，静不下来","picUrl":"http://p1.music.126.net/cover.jpg",
      "desc":"关于节目的介绍","rcmdtext":"李静的播客","categoryId":3,"category":"情感","secondCategory":"成长励志",
      "programCount":76,"subCount":12415,"playCount":1927296,"subed":true,"radioFeeType":0,
      "dj":{"userId":13994083929,"nickname":"李静-LIJING","avatarUrl":"http://p1.music.126.net/dj.jpg"}}]}
    """

    private let programBody = """
    {"code":200,"count":76,"more":true,"programs":[{"id":3731927295,"name":"北京听友会",
      "coverUrl":"https://p2.music.126.net/ep.jpg","description":"本期内容","createTime":1793808378646,
      "duration":3651657,"listenerCount":8743,"likedCount":5,"commentCount":4,"serialNum":76,"feeScope":0,
      "radio":{"id":1230174483,"name":"你，静不下来","picUrl":"https://p2.music.126.net/show.jpg"},
      "dj":{"userId":13994083929,"nickname":"李静-LIJING"},
      "mainSong":{"id":3457616466,"name":"song-title","duration":3651657,"fee":0,
        "artists":[{"id":0,"name":"李静-LIJING"}],
        "album":{"id":0,"name":"[DJ节目]李静-LIJING的DJ节目 第76期","picUrl":"http://p1.music.126.net/album.jpg"}}}]}
    """

    // MARK: - Transport

    @Test func plainWebAPICarriesCSRFAndPath() async throws {
        reset { _ in (200, #"{"code":200,"categories":[{"id":3,"name":"情感"}]}"#) }

        let categories = try await MusicAPI.podcastCategories(using: client())

        #expect(PodcastProtocol.requests.map(\.path) == ["/api/djradio/category/get"])
        #expect(PodcastProtocol.requests[0].body["csrf_token"] == "csrf-token-1")
        #expect(categories.map(\.name) == ["情感"])
    }

    @Test func transportFailureFallsBackToEapiWithSameRoute() async throws {
        reset { request in
            request.url?.path.hasPrefix("/api/") == true ? (500, "") : (200, self.recommendBody)
        }

        let podcasts = try await MusicAPI.recommendedPodcasts(using: client())

        #expect(podcasts.map(\.id) == [1_230_174_483])
        #expect(PodcastProtocol.requests.map(\.path) ==
                ["/api/djradio/recommend/v1", "/eapi/djradio/recommend/v1"])
    }

    @Test func businessAnswerIsNotRetried() async throws {
        reset { _ in (200, #"{"code":301}"#) }

        do {
            _ = try await MusicAPI.recommendedPodcasts(using: client())
            Issue.record("expected a business error")
        } catch let error as MusicAPIError {
            guard case .needLogin = error else {
                Issue.record("expected .needLogin, got \(error)")
                return
            }
        }
        #expect(PodcastProtocol.requests.map(\.path) == ["/api/djradio/recommend/v1"])
    }

    @Test func riskControlAnswerFallsBackToEapi() async throws {
        reset { request in
            request.url?.path.hasPrefix("/api/") == true
                ? (200, #"{"code":-460,"message":"risk control"}"#)
                : (200, self.recommendBody)
        }

        let podcasts = try await MusicAPI.recommendedPodcasts(using: client())

        #expect(podcasts.map(\.id) == [1_230_174_483])
        #expect(PodcastProtocol.requests.map(\.path) ==
                ["/api/djradio/recommend/v1", "/eapi/djradio/recommend/v1"])
    }

    @Test func frequencyAnswerIsNotRetried() async throws {
        reset { _ in (200, #"{"code":-447,"message":"操作频繁，请稍后再试"}"#) }

        do {
            _ = try await MusicAPI.recommendedPodcasts(using: client())
            Issue.record("expected a business error")
        } catch let error as MusicAPIError {
            guard case .business(let code, _) = error, code == -447 else {
                Issue.record("expected .business(-447), got \(error)")
                return
            }
        }
        // Asking again immediately would only extend the cooldown.
        #expect(PodcastProtocol.requests.map(\.path) == ["/api/djradio/recommend/v1"])
    }

    // MARK: - Decoding

    @Test func podcastDecodesRecommendationCopyAndHost() async throws {
        reset { _ in (200, recommendBody) }

        let podcasts = try await MusicAPI.recommendedPodcasts(using: client())
        let podcast = try #require(podcasts.first)

        #expect(podcast.name == "你，静不下来")
        #expect(podcast.recommendationText == "李静的播客")
        #expect(podcast.subtitle == "李静的播客")
        #expect(podcast.host?.nickname == "李静-LIJING")
        #expect(podcast.programCount == 76 && podcast.subscriberCount == 12415)
        #expect(podcast.isSubscribed && !podcast.isPaid)
        #expect(podcast.secondCategory == "成长励志")
        #expect(podcast.artworkURL?.absoluteString.hasPrefix("https://") == true)
    }

    @Test func podcastPageDerivesPaginationWhenMoreIsMissing() async throws {
        let body = """
        {"code":200,"count":100,"djRadios":[{"id":1,"name":"a"},{"id":2,"name":"b"},{"id":3,"name":"c"}]}
        """
        reset { request in
            (200, request.url?.path == "/api/djradio/hot" ? body : "{}")
        }

        let page = try await MusicAPI.podcasts(categoryID: 3, offset: 0, using: client())

        #expect(PodcastProtocol.requests[0].body["cateId"] == "3")
        #expect(page.podcasts.count == 3 && page.hasMore && page.totalCount == 100)

        let last = try await MusicAPI.podcasts(categoryID: 3, offset: 98, using: client())
        #expect(last.hasMore == false)
    }

    @Test func programsDecodePaginationAndShape() async throws {
        reset { request in
            (200, request.url?.path == "/api/dj/program/byradio" ? programBody : "{}")
        }

        let page = try await MusicAPI.podcastPrograms(radioID: 1_230_174_483, ascending: false,
                                                      using: client())

        #expect(PodcastProtocol.requests[0].body["radioId"] == "1230174483")
        #expect(PodcastProtocol.requests[0].body["asc"] == "false")
        #expect(page.totalCount == 76 && page.hasMore)
        let program = try #require(page.programs.first)
        #expect(program.serialNum == 76)
        #expect(program.createTime == 1_793_808_378_646)
        #expect(program.radio.name == "你，静不下来")
    }

    @Test func podcastDetailWithoutDataThrows() async throws {
        reset { _ in (200, #"{"code":200,"data":null}"#) }

        do {
            _ = try await MusicAPI.podcast(id: 1, using: client())
            Issue.record("expected a decoding error")
        } catch let error as MusicAPIError {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    // MARK: - Playback bridge

    @Test func playbackTrackCarriesShowIdentity() async throws {
        let data = Data(programBody.utf8)
        let resp = try JSONDecoder().decode(MusicAPI.PodcastProgramsResponse.self, from: data)
        let program = try #require(resp.programs.first)

        let track = try #require(program.playbackTrack)

        #expect(track.id == 3_457_616_466)
        #expect(track.name == "北京听友会")
        #expect(track.artists == [ArtistRef(id: 1_399_408_3929, name: "李静-LIJING")])
        #expect(track.album.id == 0 && track.album.name == "你，静不下来")
        #expect(track.durationMS == 3_651_657)
        #expect(track.trackNo == 76)
        #expect(track.isPodcastProgram && !track.supportsSongActions)
        let metadata = try #require(track.podcastMetadata)
        #expect(metadata.programID == 3_731_927_295)
        #expect(metadata.radioID == 1_230_174_483)
        #expect(metadata.radioName == "你，静不下来")
        #expect(metadata.coverURLString == "https://p2.music.126.net/ep.jpg")
        #expect(metadata.programDescription == "本期内容")
    }

    @Test func aProgramWithoutMainSongIsNotPlayable() throws {
        let body = """
        {"id":1,"name":"付费节目","duration":1000,"radio":{"id":2,"name":"show"},"dj":null,"mainSong":null}
        """
        let program = try JSONDecoder().decode(PodcastProgram.self, from: Data(body.utf8))

        #expect(program.playbackTrack == nil)
    }

    @Test func trackPodcastMetadataSurvivesCodableRoundTrip() throws {
        let metadata = PodcastPlaybackMetadata(
            programID: 11, radioID: 22, radioName: "show", coverURLString: "https://c/1.jpg",
            hostName: "host", programDescription: "notes")
        let track = Track(id: 9, name: "episode", durationMS: 60_000, podcastMetadata: metadata)

        let roundTripped = try JSONDecoder().decode(
            Track.self, from: JSONEncoder().encode(track))

        #expect(roundTripped == track)
        #expect(roundTripped.podcastMetadata == metadata)

        // A legacy snapshot without the private key decodes as a plain song.
        let legacy = try JSONDecoder().decode(
            Track.self, from: Data(#"{"id":1,"name":"song","dt":1000,"ar":[],"al":{}}"#.utf8))
        #expect(legacy.podcastMetadata == nil && !legacy.isPodcastProgram)
    }

    @Test func podcastEpisodesNeverUseThirdPartySources() async {
        let metadata = PodcastPlaybackMetadata(
            programID: 1, radioID: 2, radioName: "show", coverURLString: nil,
            hostName: "host", programDescription: nil)
        let episode = Track(id: 3, name: "episode", podcastMetadata: metadata)

        let resolution = await UnblockService.resolve(
            episode,
            enabledSources: [.pyncmd, .kugou, .kuwo],
            excluding: [])

        #expect(resolution.source == nil)
        #expect(resolution.attemptedSources.isEmpty)
    }

    // MARK: - Subscription

    @Test func subscribeWriteCarriesIDAndCSRF() async throws {
        reset { _ in (200, #"{"code":200}"#) }

        try await MusicAPI.setPodcastSubscribed(id: 5, subscribed: true, using: client())
        try await MusicAPI.setPodcastSubscribed(id: 5, subscribed: false, using: client())

        #expect(PodcastProtocol.requests.map(\.path) == ["/api/djradio/sub", "/api/djradio/unsub"])
        #expect(PodcastProtocol.requests[0].body["id"] == "5")
        #expect(PodcastProtocol.requests[1].body["csrf_token"] == "csrf-token-1")
    }
}
