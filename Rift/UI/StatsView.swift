// SPDX-License-Identifier: GPL-3.0-only
//
// StatsView — your listening, poster-first. Hero cards for the #1 song and
// #1 artist (built from real artwork), an "On Repeat" shelf, artist circles,
// compact stat chips, and two small time charts. All data is local
// (PlayHistoryStore) — nothing leaves the Mac. Cards animate in staggered and
// scale on hover.

import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var player: PlayerController

    private enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", all = "All Time"
        var id: String { rawValue }
        var cutoff: Date? {
            switch self {
            case .week:  return Calendar.current.date(byAdding: .day, value: -7, to: .now)
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: .now)
            case .all:   return nil
            }
        }
    }

    private struct SongAgg: Identifiable {
        let event: PlayEvent; let plays: Int; let secs: TimeInterval
        var id: String { event.trackId }
    }
    private struct ArtistAgg: Identifiable {
        let name: String; let secs: TimeInterval; let plays: Int; let art: URL?
        var id: String { name }
    }

    @State private var events: [PlayEvent] = []
    @State private var range: Range = .month
    @State private var appeared = false
    @State private var artistNav: MusicCard?   // resolved artist page target
    @State private var artistPhotos: [String: URL] = [:]   // real artist photos (search lookup)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No listening yet",
                        systemImage: "chart.bar",
                        description: Text("Play some music — your stats build up right here, stored only on this Mac.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    let songs = topSongs
                    let artists = topArtists
                    chips
                    HStack(alignment: .top, spacing: 16) {
                        if let s = songs.first { heroSong(s).frame(maxWidth: .infinity) }
                        if let a = artists.first { heroArtist(a).frame(maxWidth: .infinity) }
                    }
                    // "On Repeat" means repeat — one play doesn't qualify.
                    let repeats = songs.dropFirst().filter { $0.plays >= 2 }
                    if !repeats.isEmpty { onRepeat(repeats) }
                    if artists.count > 1 { artistRow(Array(artists.dropFirst())) }
                    HStack(alignment: .top, spacing: 16) {
                        hourChart.frame(maxWidth: .infinity)
                        weekdayChart.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(22)
            // One gentle entrance for the whole page — per-row staggered offsets
            // fought the hover springs and made cards jitter.
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: appeared)
        }
        .scrollContentBackground(.hidden)
        .noScrollbar()
        .task {
            events = await PlayHistoryStore.shared.all()
            appeared = true
            // Auto-refresh: stats stay live without relaunching. Ticks every
            // 30 min while the panel is open (task cancels when it closes).
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                events = await PlayHistoryStore.shared.all()
            }
        }
        // …and refresh the moment a track changes (a play just got logged).
        .onChange(of: player.track?.id) { _, _ in
            Task { events = await PlayHistoryStore.shared.all() }
        }
        // Artist cards navigate: history stores only the name, so resolve it
        // to a UC… browseId via artist search, then push the artist page.
        .navigationDestination(item: $artistNav) { ArtistDetailView(card: $0) }
        // Artist circles show the real artist photo (search lookup), not the
        // poster of whichever song was most played.
        .task(id: "\(range.rawValue)-\(events.count)") {
            for a in topArtists where artistPhotos[a.name] == nil {
                if let url = (try? await InnerTubeClient.artistCard(named: a.name))??.artworkURL {
                    artistPhotos[a.name] = url
                }
            }
        }
    }

    private func photo(for a: ArtistAgg) -> URL? { artistPhotos[a.name] ?? a.art }

    private func openArtist(_ name: String) {
        Task {
            if let card = try? await InnerTubeClient.artistCard(named: name) {
                artistNav = card
            }
        }
    }

    // MARK: data
    private var filtered: [PlayEvent] {
        guard let cutoff = range.cutoff else { return events }
        return events.filter { $0.ts >= cutoff }
    }

    private var topSongs: [SongAgg] {
        var agg: [String: SongAgg] = [:]
        for e in filtered {
            let a = agg[e.trackId]
            agg[e.trackId] = SongAgg(event: e, plays: (a?.plays ?? 0) + 1,
                                     secs: (a?.secs ?? 0) + e.cleanSeconds)
        }
        // FULLY deterministic order. Dictionary iteration order varies per call,
        // and body re-runs on every player tick — without total tiebreakers the
        // tied cards reshuffled 4×/sec.
        return agg.values.sorted {
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            if $0.secs != $1.secs { return $0.secs > $1.secs }
            return $0.id < $1.id
        }.prefix(5).map { $0 }
    }

    private var topArtists: [ArtistAgg] {
        var secs: [String: TimeInterval] = [:], plays: [String: Int] = [:]
        var art: [String: (URL?, Int)] = [:]   // best artwork = from most-played song
        var perSong: [String: [String: Int]] = [:]
        for e in filtered {
            let artist = e.cleanArtist
            guard !artist.isEmpty else { continue }
            secs[artist, default: 0] += e.cleanSeconds
            plays[artist, default: 0] += 1
            perSong[artist, default: [:]][e.trackId, default: 0] += 1
            let n = perSong[artist]?[e.trackId] ?? 0
            if n >= (art[artist]?.1 ?? 0) {
                art[artist] = (e.asTrack.artworkURL, n)
            }
        }
        // Same determinism rule as topSongs — name breaks seconds ties.
        return secs.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.prefix(5).map {
            ArtistAgg(name: $0.key, secs: $0.value, plays: plays[$0.key] ?? 0,
                      art: art[$0.key]?.0)
        }
    }

    // MARK: header + chips
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Listening").font(.largeTitle.bold())
                Text("Private — stats never leave this Mac.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 280)
        }
    }

    private var chips: some View {
        let secs = filtered.reduce(0) { $0 + $1.cleanSeconds }
        return HStack(spacing: 10) {
            chip("clock.fill", fmtHours(secs), "Listened")
            chip("play.circle.fill", "\(filtered.count)", "Plays")
            chip("music.note", "\(Set(filtered.map(\.trackId)).count)", "Songs")
            chip("music.mic", "\(Set(filtered.map(\.cleanArtist)).count)", "Artists")
        }
    }

    private func chip(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.tint)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlass(in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.10)))
    }

    // MARK: hero cards
    private func heroSong(_ s: SongAgg) -> some View {
        HoverCard {
            Button { player.play(s.event.asTrack) } label: {
                HStack(spacing: 16) {
                    Artwork(url: s.event.asTrack.artworkURL, size: 120)
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MOST PLAYED SONG").font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                        Text(s.event.title).font(.title3.bold()).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(s.event.artist).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label("\(s.plays) plays · \(fmtHours(s.secs))", systemImage: "repeat")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30)).symbolRenderingMode(.hierarchical)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // Poster ambience inside the card only (background layer —
                    // never a sibling; see memory safe-area-container-clip).
                    ambient(s.event.asTrack.artworkURL)
                }
                .clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func heroArtist(_ a: ArtistAgg) -> some View {
        HoverCard {
            Button { openArtist(a.name) } label: {
                HStack(spacing: 16) {
                    Artwork(url: photo(for: a), size: 120)
                        .clipShape(.circle)
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TOP ARTIST").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                        Text(a.name).font(.title3.bold()).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Label("\(fmtHours(a.secs)) · \(a.plays) plays", systemImage: "waveform")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { ambient(photo(for: a)) }
                .clipShape(.rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func ambient(_ url: URL?) -> some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            if let url {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.clear }
                    .blur(radius: 50).saturation(1.3).opacity(0.35)
                    .overlay(.black.opacity(0.25))
            }
        }
        .clipped()
    }

    // MARK: shelves
    private func onRepeat(_ songs: [SongAgg]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On Repeat").font(.title3.bold())
            HStack(alignment: .top, spacing: 16) {
                ForEach(songs) { s in
                    HoverCard {
                        Button { player.play(s.event.asTrack) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Artwork(url: s.event.asTrack.artworkURL, size: 124)
                                    .clipShape(.rect(cornerRadius: 10))
                                    .overlay(alignment: .topLeading) {
                                        Text("\(s.plays)×")
                                            .font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(.black.opacity(0.55), in: .capsule)
                                            .padding(6)
                                    }
                                Text(s.event.title).font(.caption.weight(.semibold))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                Text(s.event.artist).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 124, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func artistRow(_ artists: [ArtistAgg]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Artists").font(.title3.bold())
            HStack(alignment: .top, spacing: 22) {
                ForEach(artists) { a in
                    HoverCard {
                        Button { openArtist(a.name) } label: {
                            VStack(spacing: 8) {
                                Artwork(url: photo(for: a), size: 84)
                                    .clipShape(.circle)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                                Text(a.name).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(fmtHours(a.secs)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 96)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: charts (small, at the bottom)
    private var hourChart: some View {
        var byHour = [Double](repeating: 0, count: 24)
        let cal = Calendar.current
        for e in filtered { byHour[cal.component(.hour, from: e.ts)] += e.cleanSeconds / 60 }
        return chartCard("When you listen") {
            Chart(0..<24, id: \.self) { h in
                BarMark(x: .value("Hour", h), y: .value("Minutes", byHour[h]))
                    .foregroundStyle(.tint.opacity(0.85)).cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel { if let h = v.as(Int.self) { Text("\(h)h") } }
                }
            }
            .frame(height: 120)
        }
    }

    private var weekdayChart: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        var byDay = [Double](repeating: 0, count: 7)
        let cal = Calendar.current
        for e in filtered { byDay[cal.component(.weekday, from: e.ts) - 1] += e.cleanSeconds / 60 }
        return chartCard("Your week") {
            Chart(0..<7, id: \.self) { d in
                BarMark(x: .value("Day", symbols[d]), y: .value("Minutes", byDay[d]))
                    .foregroundStyle(.tint.opacity(0.85)).cornerRadius(3)
            }
            .frame(height: 120)
        }
    }

    private func chartCard(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlass(in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.10)))
    }

    private func fmtHours(_ secs: TimeInterval) -> String {
        let m = Int(secs) / 60
        return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
    }
}

// MARK: - animation helpers

/// Scales up slightly on hover — makes every card feel touchable. Hover is
/// tracked on the UNSCALED geometry (onHover innermost) so the growing card
/// can't push the cursor in/out of its own hit area and flicker.
private struct HoverCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var hover = false
    var body: some View {
        content()
            .onHover { hover = $0 }
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.easeOut(duration: 0.18), value: hover)
    }
}
