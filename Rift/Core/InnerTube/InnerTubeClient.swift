// SPDX-License-Identifier: GPL-3.0-only
//
// InnerTubeClient — Swift reimplementation of YouTube Music's private InnerTube
// API (the ytmusicapi / OuterTune protocol). Protocol knowledge only; no code
// ported. Anonymous search works with no auth.
//
// Ref: ytmusicapi `search()` + WEB_REMIX client context
//      (sigma67/ytmusicapi, mixins/search.py, parsers/search.py).

import Foundation
import CryptoKit

/// A browseable card in the dashboard: a song, album, playlist, or artist.
/// `id` is a videoId (song) or a browseId (album/playlist/artist).
struct MusicCard: Identifiable, Hashable {
    enum Kind: Hashable { case song, album, playlist, artist }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let artworkURL: URL?
}

/// One horizontal carousel on the home feed.
struct HomeSection: Identifiable {
    let id = UUID()
    let title: String
    let cards: [MusicCard]
}

struct InnerTubeClient {

    private static let base = "https://music.youtube.com/youtubei/v1"
    // WEB_REMIX = the YouTube Music web client. Version string is periodically
    // bumped by Google; an out-of-date one still works for anonymous browse.
    private static let clientName = "WEB_REMIX"
    private static let clientVersion = "1.20240403.01.00"
    // Search filter: songs only. (base64 of the "Songs" chip params.)
    private static let songsFilterParams = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"

    private static func context(brandId: String? = nil) -> [String: Any] {
        var userDict: [String: Any] = [:]
        if let brandId {
            userDict["onBehalfOfUser"] = brandId
        }
        return [
            "client": [
                "clientName": clientName,
                "clientVersion": clientVersion,
                "hl": "en", "gl": "US",
            ],
            "user": userDict,
        ]
    }

    private static func request(_ endpoint: String, body: [String: Any], auth overrideAuth: YTAuth? = nil) async throws -> [String: Any] {
        guard let url = URL(string: "\(base)/\(endpoint)?prettyPrint=false") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")

        // Authenticated? Attach the YTM session so browse/home returns the
        // user's personalized feed, library, and subscriptions. An explicit
        // override is used during login (before the session is saved to Keychain).
        let auth = overrideAuth ?? AuthStore.load()
        if let auth {
            req.setValue(auth.cookie, forHTTPHeaderField: "Cookie")
            req.setValue(sapisidHash(auth.sapisid), forHTTPHeaderField: "Authorization")
            req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }

        var full = body
        full["context"] = context(brandId: auth?.brandId)
        req.httpBody = try JSONSerialization.data(withJSONObject: full)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "InnerTube", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "search HTTP \(code)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "InnerTube", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "malformed response"])
        }
        return json
    }

    /// SAPISIDHASH auth header — the same scheme the YTM website uses:
    /// SHA1("<unixtime> <SAPISID> <origin>"). Ref: Google internal APIs / ytmusicapi.
    private static func sapisidHash(_ sapisid: String) -> String {
        let ts = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) \(origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(ts)_\(hex)"
    }

    /// Search YT Music for songs. Returns playable tracks (id = videoId).
    static func searchSongs(_ query: String) async throws -> [PlayableTrack] {
        let json = try await request("search", body: [
            "query": query,
            "params": songsFilterParams,
        ])
        return parseSongs(json)
    }

    /// Search YT Music for artists. Returns .artist cards (id = UC… browseId).
    /// Ref: ytmusicapi search filter "artists" params. Verified live.
    static func searchArtists(_ query: String) async throws -> [MusicCard] {
        let json = try await request("search", body: [
            "query": query,
            "params": "EgWKAQIgAWoKEAkQBRAKEAMQBA%3D%3D",
        ])
        var items: [[String: Any]] = []
        collect(json, key: "musicResponsiveListItemRenderer", into: &items)
        var seen = Set<String>()
        return items.compactMap { r in
            guard let browseId = firstString(in: r, key: "browseId"),
                  browseId.hasPrefix("UC"), seen.insert(browseId).inserted else { return nil }
            let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
            guard let name = flexText(cols, 0) else { return nil }
            return MusicCard(id: browseId, kind: .artist, title: name,
                             subtitle: "Artist",
                             artworkURL: artworkURL(firstString(in: r, key: "url")))
        }
    }

    /// Best-match artist card for a plain artist name (used by Stats / "your
    /// top artists", where history stores only the name string).
    static func artistCard(named name: String) async throws -> MusicCard? {
        try await searchArtists(name).first
    }

    /// Like / un-like a song on the signed-in account. Ref: ytmusicapi
    /// `rate_song` — `like/like` and `like/removelike` with a videoId target.
    static func rate(videoId: String, liked: Bool) async throws {
        _ = try await request(liked ? "like/like" : "like/removelike",
                              body: ["target": ["videoId": videoId]])
    }

    /// The signed-in user's Liked Songs. Ref: ytmusicapi `get_liked_songs` —
    /// the auto-playlist "LM", browsed like any playlist (VLLM). Empty when
    /// anonymous.
    static func likedSongs() async throws -> [PlayableTrack] {
        try await tracks(forBrowseId: "VLLM")
    }

    // MARK: playlist writes (signed-in only)
    // Ref: ytmusicapi create_playlist / edit_playlist / delete_playlist /
    // add_playlist_items / remove_playlist_items. Edit ops take the plain
    // playlistId (no VL prefix); browse takes VL<id>.

    private static func plainPlaylistId(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    /// Create a private playlist on the signed-in account. Returns its playlistId.
    static func createPlaylist(title: String) async throws -> String {
        let json = try await request("playlist/create", body: [
            "title": title, "privacyStatus": "PRIVATE",
        ])
        guard let id = json["playlistId"] as? String else {
            throw NSError(domain: "InnerTube", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "playlist/create returned no id"])
        }
        return id
    }

    static func addPlaylistItems(playlistId: String, videoIds: [String]) async throws {
        guard !videoIds.isEmpty else { return }
        _ = try await request("browse/edit_playlist", body: [
            "playlistId": plainPlaylistId(playlistId),
            "actions": videoIds.map { ["action": "ACTION_ADD_VIDEO", "addedVideoId": $0] },
        ])
    }

    /// Remove songs from a playlist. ACTION_REMOVE_VIDEO needs each item's
    /// setVideoId (per ytmusicapi remove_playlist_items), which only exists in
    /// the playlist's browse payload — so fetch it and map videoId → setVideoId.
    static func removePlaylistItems(playlistId: String, videoIds: [String]) async throws {
        guard !videoIds.isEmpty else { return }
        let json = try await browse("VL" + plainPlaylistId(playlistId))
        var items: [[String: Any]] = []
        collect(json, key: "playlistItemData", into: &items)
        let wanted = Set(videoIds)
        let actions: [[String: String]] = items.compactMap { d in
            guard let v = d["videoId"] as? String, wanted.contains(v),
                  let s = d["playlistSetVideoId"] as? String else { return nil }
            return ["action": "ACTION_REMOVE_VIDEO", "removedVideoId": v, "setVideoId": s]
        }
        guard !actions.isEmpty else { return }
        _ = try await request("browse/edit_playlist", body: [
            "playlistId": plainPlaylistId(playlistId), "actions": actions,
        ])
    }

    static func renamePlaylist(playlistId: String, title: String) async throws {
        _ = try await request("browse/edit_playlist", body: [
            "playlistId": plainPlaylistId(playlistId),
            "actions": [["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": title]],
        ])
    }

    static func deletePlaylist(playlistId: String) async throws {
        _ = try await request("playlist/delete", body: ["playlistId": plainPlaylistId(playlistId)])
    }

    /// Signed-in account name + photo. Ref: ytmusicapi `get_account_info`
    /// (account/account_menu → activeAccountHeaderRenderer). Needs auth cookies.
    struct Account { let name: String; let photoURL: URL?; let email: String? }

    static func accountInfo() async throws -> Account? {
        let json = try await request("account/account_menu", body: [:])
        var headers: [[String: Any]] = []
        collect(json, key: "activeAccountHeaderRenderer", into: &headers)
        guard let h = headers.first else { return nil }
        let name = runsText(h["accountName"])
        let email = runsText(h["email"])
        let photo = biggestThumb(in: h["accountPhoto"] ?? [:])
        return Account(name: name.isEmpty ? "YouTube Music" : name,
                       photoURL: photo,
                       email: email.isEmpty ? nil : email)
    }

    /// The list of available accounts (primary + brand accounts) for the
    /// authenticated user. Ref: ytmusicapi `account/accounts_list` →
    /// `getMultiPageMenuAction` → `multiPageMenuRenderer` sections. Needs auth
    /// cookies. Used by the login-time account chooser.
    static func fetchAccountsList(auth: YTAuth? = nil) async throws -> AccountsListResponse {
        let json = try await request("account/accounts_list", body: [:], auth: auth)
        let response = AccountsListParser.parse(json)
        return response
    }

    private static func biggestThumb(in node: Any) -> URL? {
        // Find a "thumbnails" array anywhere and take the last (largest) url.
        func search(_ obj: Any) -> [[String: Any]]? {
            if let d = obj as? [String: Any] {
                if let t = d["thumbnails"] as? [[String: Any]] { return t }
                for (_, v) in d { if let r = search(v) { return r } }
            } else if let a = obj as? [Any] {
                for v in a { if let r = search(v) { return r } }
            }
            return nil
        }
        guard let last = search(node)?.last, let s = last["url"] as? String else { return nil }
        return URL(string: s.hasPrefix("//") ? "https:\(s)" : s)
    }

    /// Typeahead suggestions. Ref: ytmusicapi `get_search_suggestions`.
    static func searchSuggestions(_ input: String) async throws -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let json = try await request("music/get_search_suggestions", body: ["input": trimmed])
        var items: [[String: Any]] = []
        collect(json, key: "searchSuggestionRenderer", into: &items)
        var seen = Set<String>()
        return items.compactMap { r in
            let s = runsText(r["suggestion"])
            guard !s.isEmpty, seen.insert(s.lowercased()).inserted else { return nil }
            return s
        }
    }

    // MARK: parsing — walk the variable renderer tree defensively.
    private static func parseSongs(_ json: [String: Any]) -> [PlayableTrack] {
        // Collect every musicResponsiveListItemRenderer anywhere in the tree.
        var items: [[String: Any]] = []
        collect(json, key: "musicResponsiveListItemRenderer", into: &items)
        return items.compactMap(track(from:))
    }

    private static func track(from r: [String: Any]) -> PlayableTrack? {
        guard let videoId = firstString(in: r, key: "videoId") else { return nil }
        let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
        let title = flexText(cols, 0) ?? "Unknown"
        // Column 1 joins ALL byline runs — "Artist • Album • 3:29". Keep only
        // the artist segment or history/stats aggregate garbage strings.
        let artist = (flexText(cols, 1) ?? "").components(separatedBy: " • ").first ?? ""
        let art = artworkURL(firstString(in: r, key: "url"))
        return PlayableTrack(id: videoId, title: title, artist: artist, artworkURL: art, duration: nil)
    }

    /// YTM serves tiny thumbnails (w60/w120…). Rewrite the size params to a
    /// high-res variant — the image server honors any requested size.
    private static func artworkURL(_ s: String?) -> URL? {
        guard var str = s else { return nil }
        str = str.replacingOccurrences(of: "http://", with: "https://")
        if let re = try? Regex(#"w\d+-h\d+"#) { str = str.replacing(re, with: "w544-h544") }
        if let re = try? Regex(#"=s\d+"#) { str = str.replacing(re, with: "=s544") }
        return URL(string: str)
    }

    private static func flexText(_ cols: [[String: Any]], _ i: Int) -> String? {
        guard cols.indices.contains(i),
              let col = cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = col["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return nil }
        let s = runs.compactMap { $0["text"] as? String }.joined()
        return s.isEmpty ? nil : s
    }

    // Recursively find the first String value for `key` under a subtree.
    private static func firstString(in obj: Any, key: String) -> String? {
        if let d = obj as? [String: Any] {
            if let v = d[key] as? String { return v }
            for (_, val) in d { if let f = firstString(in: val, key: key) { return f } }
        } else if let a = obj as? [Any] {
            for val in a { if let f = firstString(in: val, key: key) { return f } }
        }
        return nil
    }

    // Recursively collect every dict stored under `key`.
    private static func collect(_ obj: Any, key: String, into out: inout [[String: Any]]) {
        if let d = obj as? [String: Any] {
            if let hit = d[key] as? [String: Any] { out.append(hit) }
            for (_, val) in d { collect(val, key: key, into: &out) }
        } else if let a = obj as? [Any] {
            for val in a { collect(val, key: key, into: &out) }
        }
    }

    // MARK: browse (home feed, albums, playlists)

    /// Generic InnerTube browse call. Ref: ytmusicapi browse endpoint.
    private static func browse(_ browseId: String) async throws -> [String: Any] {
        try await request("browse", body: ["browseId": browseId])
    }

    /// The YT Music home feed = recommendations. Works anonymously.
    /// Ref: ytmusicapi `get_home()` — browseId FEmusic_home.
    static func home() async throws -> [HomeSection] {
        parseHomeSections(try await browse("FEmusic_home"))
    }

    /// Tracks of an album or playlist by its browseId (MPRE… / VL…).
    static func tracks(forBrowseId browseId: String) async throws -> [PlayableTrack] {
        let json = try await browse(browseId)
        var items: [[String: Any]] = []
        collect(json, key: "musicResponsiveListItemRenderer", into: &items)
        // Album rows usually carry no per-track thumbnail — the cover is in the
        // page header. Use it as fallback so the player shows the album art.
        let albumArt = artworkURL(biggestThumb(in: json)?.absoluteString)
        return items.compactMap(track(from:)).map { t in
            guard t.artworkURL == nil, let albumArt else { return t }
            return PlayableTrack(id: t.id, title: t.title, artist: t.artist,
                                 artworkURL: albumArt, duration: t.duration)
        }
    }

    /// Plain lyrics for a track, or nil if none. Ref: ytmusicapi `get_lyrics`:
    /// `next` → the Lyrics tab's browseId (MPLYt…) → browse → description shelf.
    /// ponytail: YTM returns plain (untimed) text here — synced/timed lyrics would
    /// need a different source (e.g. LRCLIB). Plain is enough for a lyrics panel.
    static func lyrics(videoId: String) async throws -> String? {
        let next = try await request("next", body: ["videoId": videoId])
        var ids: [String] = []
        collectStrings(next, key: "browseId", into: &ids)
        guard let browseId = ids.first(where: { $0.hasPrefix("MPLYt") }) else { return nil }
        let json = try await browse(browseId)
        var shelves: [[String: Any]] = []
        collect(json, key: "musicDescriptionShelfRenderer", into: &shelves)
        let text = shelves.compactMap { runsText($0["description"]) }.first { !$0.isEmpty }
        return (text?.isEmpty == false) ? text : nil
    }

    /// The signed-in user's library playlists. Ref: ytmusicapi
    /// `get_library_playlists` — browseId FEmusic_liked_playlists. Returns []
    /// for anonymous sessions (endpoint yields no playlist tiles).
    static func libraryPlaylists() async throws -> [MusicCard] {
        let json = try await browse("FEmusic_liked_playlists")
        var items: [[String: Any]] = []
        collect(json, key: "musicTwoRowItemRenderer", into: &items)
        return items.compactMap(cardFromTwoRow).filter { $0.kind == .playlist }
    }

    /// Radio / autoplay continuation: tracks that keep playing after a song.
    /// Ref: ytmusicapi `get_watch_playlist` — `next` with the RDAMVM<videoId>
    /// radio playlist; results are playlistPanelVideoRenderer entries.
    static func radio(videoId: String) async throws -> [PlayableTrack] {
        let json = try await request("next", body: [
            "videoId": videoId,
            "playlistId": "RDAMVM" + videoId,
            "isAudioOnly": true,
        ])
        return panelTracks(in: json, excluding: videoId)
    }

    /// Tracks of a watch panel playlist (RDAO… artist shuffle, RDEM… mix, …) —
    /// same `next` + playlistPanelVideoRenderer protocol as radio.
    static func watchPlaylist(_ playlistId: String) async throws -> [PlayableTrack] {
        let json = try await request("next", body: [
            "playlistId": playlistId,
            "isAudioOnly": true,
        ])
        return panelTracks(in: json, excluding: nil)
    }

    private static func panelTracks(in json: [String: Any], excluding: String?) -> [PlayableTrack] {
        var items: [[String: Any]] = []
        collect(json, key: "playlistPanelVideoRenderer", into: &items)
        var seen = Set<String>()
        return items.compactMap { r in
            guard let vid = r["videoId"] as? String, vid != excluding,
                  seen.insert(vid).inserted else { return nil }
            let title = runsText(r["title"])
            // longBylineText runs = "Artist • Album • Views…" — artist is first.
            let artist = runsText(r["longBylineText"])
                .components(separatedBy: " • ").first ?? ""
            let art = artworkURL(firstString(in: r, key: "url"))
            return PlayableTrack(id: vid, title: title.isEmpty ? "Unknown" : title,
                                 artist: artist, artworkURL: art, duration: nil)
        }
    }

    // MARK: artist page

    /// An artist's channel page. Anonymous browse returns NO top-songs shelf —
    /// only the header (with shuffle RDAO… / mix RDEM… playlist ids) plus
    /// carousels (Albums, Singles & EPs, Featured on, Fans might also like).
    /// Top songs come from `watchPlaylist(shufflePlaylistId)`. Verified live.
    /// Ref: ytmusicapi `get_artist` — browse UC… → musicImmersiveHeaderRenderer.
    struct ArtistPage {
        let name: String
        let listeners: String?      // "249M monthly audience"
        let description: String?
        let heroURL: URL?
        let shufflePlaylistId: String?
        let radioPlaylistId: String?
        let sections: [HomeSection]
    }

    static func artist(browseId: String) async throws -> ArtistPage {
        let json = try await browse(browseId)
        var hdrs: [[String: Any]] = []
        collect(json, key: "musicImmersiveHeaderRenderer", into: &hdrs)
        if hdrs.isEmpty { collect(json, key: "musicVisualHeaderRenderer", into: &hdrs) }
        let h = hdrs.first ?? [:]
        let name = runsText(h["title"])
        let listeners = runsText(h["monthlyListenerCount"])
        let desc = runsText(h["description"])
        let hero = artworkURL(biggestThumb(in: h["thumbnail"] ?? [:])?.absoluteString)
        return ArtistPage(
            name: name.isEmpty ? "Artist" : name,
            listeners: listeners.isEmpty ? nil : listeners,
            description: desc.isEmpty ? nil : desc,
            heroURL: hero,
            shufflePlaylistId: firstString(in: h["playButton"] ?? [:], key: "playlistId"),
            radioPlaylistId: firstString(in: h["startRadioButton"] ?? [:], key: "playlistId"),
            sections: parseHomeSections(json))
    }

    // Recursively collect every String stored under `key`.
    private static func collectStrings(_ obj: Any, key: String, into out: inout [String]) {
        if let d = obj as? [String: Any] {
            if let v = d[key] as? String { out.append(v) }
            for (_, val) in d { collectStrings(val, key: key, into: &out) }
        } else if let a = obj as? [Any] {
            for val in a { collectStrings(val, key: key, into: &out) }
        }
    }

    // MARK: home parsing — walk carousel shelves defensively.
    private static func parseHomeSections(_ json: [String: Any]) -> [HomeSection] {
        var carousels: [[String: Any]] = []
        collect(json, key: "musicCarouselShelfRenderer", into: &carousels)

        return carousels.compactMap { shelf in
            // Deterministic title path only: header → basic header → title runs.
            // A blind firstString(key: "text") walk also hits the header's
            // moreContentButton ("More") — dict order is random per call, so
            // every shelf randomly titled itself "More".
            let basicHeader = (shelf["header"] as? [String: Any])?
                .values.compactMap { $0 as? [String: Any] }
                .first { $0["title"] != nil }
            let titleText = runsText(basicHeader?["title"])
            let title = titleText.isEmpty ? "More" : titleText
            let contents = (shelf["contents"] as? [[String: Any]]) ?? []
            let cards: [MusicCard] = contents.compactMap { item in
                if let tr = item["musicTwoRowItemRenderer"] as? [String: Any] {
                    return cardFromTwoRow(tr)
                }
                if let li = item["musicResponsiveListItemRenderer"] as? [String: Any] {
                    if let t = track(from: li) {
                        return MusicCard(id: t.id, kind: .song, title: t.title,
                                         subtitle: t.artist, artworkURL: t.artworkURL)
                    }
                    // No videoId — chart "Top artists" rows are artist entries.
                    if let browseId = firstString(in: li, key: "browseId"), browseId.hasPrefix("UC") {
                        let cols = (li["flexColumns"] as? [[String: Any]]) ?? []
                        guard let name = flexText(cols, 0) else { return nil }
                        return MusicCard(id: browseId, kind: .artist, title: name,
                                         subtitle: flexText(cols, 1) ?? "Artist",
                                         artworkURL: artworkURL(firstString(in: li, key: "url")))
                    }
                }
                return nil
            }
            return cards.isEmpty ? nil : HomeSection(title: title, cards: cards)
        }
    }

    // MARK: charts + moods (Explore)

    /// Charts page (browse FEmusic_charts): "Video charts" playlist tiles +
    /// "Top artists" (40 artist rows). "Languages" shelf is dropped — its tiles
    /// are locale playlists that read like noise on Home. Ref: ytmusicapi
    /// `get_charts`. Anonymous browse has no trending-songs shelf (verified).
    static func charts() async throws -> [HomeSection] {
        parseHomeSections(try await browse("FEmusic_charts"))
            .filter { $0.title != "Languages" }
    }

    /// One mood / genre chip on the Explore grid.
    struct MoodCategory: Identifiable, Hashable {
        let title: String
        let params: String
        var id: String { params }
    }

    /// Mood & genre chips. Ref: ytmusicapi `get_mood_categories` — browse
    /// FEmusic_moods_and_genres → musicNavigationButtonRenderer.
    static func moodCategories() async throws -> [MoodCategory] {
        let json = try await browse("FEmusic_moods_and_genres")
        var btns: [[String: Any]] = []
        collect(json, key: "musicNavigationButtonRenderer", into: &btns)
        var seen = Set<String>()
        return btns.compactMap { b in
            let title = runsText(b["buttonText"])
            guard !title.isEmpty, let params = firstString(in: b, key: "params"),
                  seen.insert(params).inserted else { return nil }
            return MoodCategory(title: title, params: params)
        }
    }

    /// Playlists of one mood/genre. Ref: ytmusicapi `get_mood_playlists` —
    /// FEmusic_moods_and_genres_category + the chip's params. Category pages
    /// use grids rather than carousels, so fall back to a flat section when no
    /// carousel parses.
    static func moodPlaylists(_ category: MoodCategory) async throws -> [HomeSection] {
        let json = try await request("browse", body: [
            "browseId": "FEmusic_moods_and_genres_category",
            "params": category.params,
        ])
        let sections = parseHomeSections(json)
        if !sections.isEmpty { return sections }
        var items: [[String: Any]] = []
        collect(json, key: "musicTwoRowItemRenderer", into: &items)
        let cards = items.compactMap(cardFromTwoRow)
        return cards.isEmpty ? [] : [HomeSection(title: category.title, cards: cards)]
    }

    /// Album/playlist/artist tile → MusicCard. Kind inferred from the nav
    /// endpoint (videoId = song, else browse pageType).
    private static func cardFromTwoRow(_ r: [String: Any]) -> MusicCard? {
        let title = runsText(r["title"])
        guard !title.isEmpty else { return nil }
        let subtitle = runsText(r["subtitle"])
        let art = artworkURL(firstString(in: r, key: "url"))

        if let videoId = firstString(in: r, key: "videoId") {
            return MusicCard(id: videoId, kind: .song, title: title, subtitle: subtitle, artworkURL: art)
        }
        guard let browseId = firstString(in: r, key: "browseId") else { return nil }
        let pageType = firstString(in: r, key: "pageType") ?? ""
        let kind: MusicCard.Kind =
            pageType.contains("ARTIST") ? .artist :
            pageType.contains("PLAYLIST") ? .playlist : .album
        return MusicCard(id: browseId, kind: kind, title: title, subtitle: subtitle, artworkURL: art)
    }

    private static func runsText(_ node: Any?) -> String {
        guard let d = node as? [String: Any], let runs = d["runs"] as? [[String: Any]] else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }
}
