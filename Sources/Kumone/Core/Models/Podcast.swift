import Foundation

// MARK: - Host

/// A podcast's anchor (the service's `dj` object).
struct PodcastHost: Decodable, Hashable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl
    }

    init(userId: Int = 0, nickname: String = "", avatarUrl: String? = nil) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? ""
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
    }
}

// MARK: - Podcast (show)

/// A podcast show — the service's "radio"/djradio object.
struct Podcast: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let podcastDescription: String?
    let recommendationText: String?
    let categoryId: Int?
    let category: String?
    let secondCategory: String?
    let programCount: Int
    let subscriberCount: Int
    let playCount: Int
    let host: PodcastHost?
    /// Mutated locally after subscribe/unsubscribe; the server value is only
    /// the snapshot at fetch time.
    var isSubscribed: Bool
    /// 0 = free; non-zero marks a paid show.
    let feeType: Int?

    var artworkURL: URL? { picUrl?.resizedImageURL(384) }

    /// The one-line context a card shows: recommendation copy, else the host,
    /// else the category.
    var subtitle: String? {
        if let text = Self.nonEmpty(recommendationText) { return text }
        if let text = Self.nonEmpty(host?.nickname) { return text }
        if let text = Self.nonEmpty(category) { return text }
        return nil
    }

    var isPaid: Bool { (feeType ?? 0) > 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, desc, categoryId, category, secondCategory
        case recommendationText = "rcmdText"
        case legacyRecommendationText = "rcmdtext"
        case programCount, subCount, playCount, dj, subed
        case feeType = "radioFeeType"
    }

    init(id: Int = 0, name: String = "", picUrl: String? = nil,
         podcastDescription: String? = nil, recommendationText: String? = nil,
         categoryId: Int? = nil, category: String? = nil, secondCategory: String? = nil,
         programCount: Int = 0, subscriberCount: Int = 0, playCount: Int = 0,
         host: PodcastHost? = nil, isSubscribed: Bool = false, feeType: Int? = nil) {
        self.id = id
        self.name = name
        self.picUrl = picUrl
        self.podcastDescription = podcastDescription
        self.recommendationText = recommendationText
        self.categoryId = categoryId
        self.category = category
        self.secondCategory = secondCategory
        self.programCount = programCount
        self.subscriberCount = subscriberCount
        self.playCount = playCount
        self.host = host
        self.isSubscribed = isSubscribed
        self.feeType = feeType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = try? c.decode(String.self, forKey: .picUrl)
        podcastDescription = try? c.decode(String.self, forKey: .desc)
        recommendationText = (try? c.decode(String.self, forKey: .recommendationText))
            ?? (try? c.decode(String.self, forKey: .legacyRecommendationText))
        categoryId = try? c.decode(Int.self, forKey: .categoryId)
        category = try? c.decode(String.self, forKey: .category)
        secondCategory = try? c.decode(String.self, forKey: .secondCategory)
        programCount = Self.int(c, .programCount)
        subscriberCount = Self.int(c, .subCount)
        playCount = Self.int(c, .playCount)
        host = try? c.decode(PodcastHost.self, forKey: .dj)
        isSubscribed = (try? c.decode(Bool.self, forKey: .subed)) ?? false
        feeType = try? c.decode(Int.self, forKey: .feeType)
    }

    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int {
        Int((try? c.decode(Double.self, forKey: key)) ?? 0)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Category

struct PodcastCategory: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?

    var artworkURL: URL? { picUrl?.resizedImageURL(192) }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case picUrl = "pic96x96Url"
        case fallbackPicUrl = "pic56x56Url"
    }

    init(id: Int = 0, name: String = "", picUrl: String? = nil) {
        self.id = id
        self.name = name
        self.picUrl = picUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = (try? c.decode(String.self, forKey: .picUrl))
            ?? (try? c.decode(String.self, forKey: .fallbackPicUrl))
    }
}

// MARK: - Program (episode)

/// The show an episode belongs to, as embedded in program payloads.
struct PodcastRadioRef: Decodable, Hashable {
    let id: Int
    let name: String
    let picUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl
    }

    init(id: Int = 0, name: String = "", picUrl: String? = nil) {
        self.id = id
        self.name = name
        self.picUrl = picUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = try? c.decode(String.self, forKey: .picUrl)
    }
}

/// Ride-along identity for a playing episode, persisted with the queue
/// snapshot so a restored session can still link back to the show.
struct PodcastPlaybackMetadata: Codable, Hashable {
    let programID: Int
    let radioID: Int
    let radioName: String
    let coverURLString: String?
    let hostName: String
    let programDescription: String?
}

/// One episode of a podcast. Its playable audio is the `mainSong`'s; the
/// program itself supplies the show identity the song record lacks.
struct PodcastProgram: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let coverUrl: String?
    let programDescription: String?
    /// Publish time, milliseconds since 1970.
    let createTime: Int64?
    let durationMS: Int
    let listenerCount: Int
    let likedCount: Int
    let commentCount: Int
    let serialNum: Int?
    let feeScope: Int?
    let radio: PodcastRadioRef
    let host: PodcastHost?
    let mainSong: Track?

    var artworkURL: URL? { (coverUrl ?? radio.picUrl)?.resizedImageURL(384) }
    var isPaid: Bool { (feeScope ?? 0) > 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, coverUrl, description, createTime, duration
        case listenerCount, likedCount, commentCount, serialNum, feeScope
        case radio
        case host = "dj"
        case mainSong
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        coverUrl = try? c.decode(String.self, forKey: .coverUrl)
        programDescription = try? c.decode(String.self, forKey: .description)
        createTime = Self.flexibleInt64(c, .createTime)
        durationMS = (try? c.decode(Int.self, forKey: .duration)) ?? 0
        listenerCount = (try? c.decode(Int.self, forKey: .listenerCount)) ?? 0
        likedCount = (try? c.decode(Int.self, forKey: .likedCount)) ?? 0
        commentCount = (try? c.decode(Int.self, forKey: .commentCount)) ?? 0
        serialNum = try? c.decode(Int.self, forKey: .serialNum)
        feeScope = try? c.decode(Int.self, forKey: .feeScope)
        radio = (try? c.decode(PodcastRadioRef.self, forKey: .radio)) ?? PodcastRadioRef()
        host = try? c.decode(PodcastHost.self, forKey: .host)
        mainSong = try? c.decode(Track.self, forKey: .mainSong)
    }

    /// The playable form: the episode rendered as a `Track`, with the show in
    /// the album position and the host as the artist so existing views render
    /// it sensibly. Nil when the episode has no playable song (paid shows).
    var playbackTrack: Track? {
        guard let mainSong, mainSong.id > 0 else { return nil }
        let cover = coverUrl ?? radio.picUrl
        let hostName = Self.nonEmpty(host?.nickname)
            ?? Self.nonEmpty(mainSong.artists.first?.name)
            ?? radio.name
        return Track(
            id: mainSong.id,
            name: name,
            artists: [ArtistRef(id: host?.userId ?? 0, name: hostName)],
            album: AlbumRef(id: 0, name: radio.name, picUrl: cover),
            durationMS: durationMS > 0 ? durationMS : mainSong.durationMS,
            alias: mainSong.alias,
            transNames: mainSong.transNames,
            fee: mainSong.fee,
            trackNo: serialNum ?? 0,
            embeddedPrivilege: mainSong.embeddedPrivilege,
            podcastMetadata: PodcastPlaybackMetadata(
                programID: id,
                radioID: radio.id,
                radioName: radio.name,
                coverURLString: cover,
                hostName: hostName,
                programDescription: programDescription))
    }

    private static func flexibleInt64(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> Int64? {
        if let value = try? c.decode(Int64.self, forKey: key) { return value }
        if let value = try? c.decode(Double.self, forKey: key) { return Int64(value) }
        if let value = try? c.decode(String.self, forKey: key) { return Int64(value) }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Pages

struct PodcastPage {
    let podcasts: [Podcast]
    let hasMore: Bool
    let totalCount: Int?
}

struct PodcastProgramPage {
    let programs: [PodcastProgram]
    let hasMore: Bool
    let totalCount: Int
}

enum PodcastProgramOrder: CaseIterable, Identifiable {
    case newest, oldest

    var id: Self { self }

    var ascending: Bool { self == .oldest }
}
