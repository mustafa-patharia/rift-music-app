// SPDX-License-Identifier: GPL-3.0-only
//
// SettingsPanelView — in-app settings. A horizontal category tab bar (like
// System Settings' own top-level categories) switches between grouped
// sections, each System Settings-style (HIG): UPPERCASE header outside the
// card, rows = label left / control right, ≥44pt row height, inset dividers,
// 8pt grid. Glass cards keep the app's material language. New categories slot
// in as another SettingsTab case — the tab bar and dispatch don't change.

import SwiftUI
import AppKit

private enum SettingsTab: String, CaseIterable, Identifiable {
    case app = "App Settings", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .app:   return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct SettingsPanelView: View {
    @EnvironmentObject var mode: AppModeController
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var auth: AuthController

    @ObservedObject private var ai = AIStore.shared
    @State private var tab: SettingsTab = .app
    @Namespace private var tabNS

    @State private var downloadsBytes: Int64 = 0
    @State private var cacheBytes: Int64 = 0
    @State private var streamCount = 0
    @State private var historyCount = 0
    @State private var confirmClearAudio = false
    @State private var confirmClearHistory = false

    // Ollama panel state
    @State private var ollamaUp = false
    @State private var installedModels: [String] = []
    @State private var pulling: String?
    @State private var pullProgress: Double = 0
    @State private var pullError: String?

    /// Small local models suited to the app's tasks (transliteration etc.).
    private static let curatedModels: [(id: String, name: String, info: String)] = [
        ("llama3.2:3b", "Llama 3.2 3B", "Meta · ~2.0 GB"),
        ("qwen2.5:3b", "Qwen 2.5 3B", "Alibaba · ~1.9 GB"),
        ("gemma3:4b", "Gemma 3 4B", "Google · ~3.3 GB"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.largeTitle.bold())
                Text("Everything is stored only on this Mac.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22).padding(.top, 24)

            tabBar.padding(.horizontal, 22)

            ScrollView {
                tabContent
                    .padding(.vertical, 20).padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .noScrollbar()
        }
        .task { await refreshCounts() }
        .task(id: ai.provider) { if ai.provider == .ollama { await refreshOllama() } }
        .confirmationDialog("Delete all downloads?", isPresented: $confirmClearAudio) {
            Button("Delete Downloads", role: .destructive) {
                Task { await AudioFileCache.shared.clearDownloads(); await refreshCounts() }
            }
        } message: { Text("Your downloaded songs will be removed from this Mac.") }
        .confirmationDialog("Delete all listening history?", isPresented: $confirmClearHistory) {
            Button("Delete History", role: .destructive) {
                Task { await PlayHistoryStore.shared.clear(); await refreshCounts() }
            }
        } message: { Text("Stats and Recently Played start over. This can't be undone.") }
    }

    // MARK: tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { t in
                tabButton(t)
            }
        }
        .padding(4)
        .liquidGlass(in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .fixedSize()   // hug its two tabs — don't stretch/center across the row
    }

    private func tabButton(_ t: SettingsTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { tab = t }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: t.icon).font(.system(size: 12, weight: .medium))
                Text(t.rawValue).font(.system(size: 12, weight: tab == t ? .semibold : .regular))
            }
            .foregroundStyle(tab == t ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background {
                if tab == t {
                    RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.14)))
                        .matchedGeometryEffect(id: "settings.tab", in: tabNS)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: tab content dispatch

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .app:
            VStack(alignment: .leading, spacing: 24) {
                accountSection
                displaySection
                playbackSection
                aiSection
                dataSection
            }
        case .about: aboutSection
        }
    }

    private var displaySection: some View {
        Group {
            if NotchDetector.hasNotch {
                section("Player Display",
                        footer: "Menu bar shows a mini player in the status bar. Notch turns the camera housing into a dynamic island.") {
                    row("Show player in") {
                        Picker("", selection: $mode.mode) {
                            ForEach(AppModeController.Mode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .frame(width: 340)
                    }
                }
            } else {
                section("Player Display",
                        footer: "No notch on this Mac. Playback controls are always in the main window; " +
                                "this adds a quick mini player in the status bar too.") {
                    row("Show menu bar icon") {
                        Toggle("", isOn: $mode.menuBarIconVisible)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
            }
        }
    }

    private var playbackSection: some View {
        section("Playback") {
            row("Volume") {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { player.volume },
                                          set: { player.setVolume($0) }), in: 0...1)
                        .controlSize(.small).frame(width: 180)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            divider
            row("Autoplay", subtitle: "When the queue ends, keep playing similar songs") {
                Toggle("", isOn: $player.autoplay)
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
        }
    }

    private var accountSection: some View {
        section("Account") {
            if auth.isAuthenticated {
                HStack(spacing: 12) {
                    if let url = auth.photoURL {
                        AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                            placeholder: { Circle().fill(.tint.opacity(0.9)) }
                            .frame(width: 36, height: 36).clipShape(.circle)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 32)).foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(auth.name ?? "Signed in").font(.body)
                        if let email = auth.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 16)
                    Button("Sign Out…", role: .destructive) { auth.signOut() }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            } else {
                row("Not signed in", subtitle: "Browsing anonymously") {
                    Button("Sign In…") { auth.signIn() }
                }
            }
        }
    }

    private var aiSection: some View {
        section("AI", footer: aiFooter) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("AI features").font(.body)
                    Text("BETA")
                        .font(.caption2.weight(.bold)).kerning(0.5)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.orange.opacity(0.18), in: .capsule)
                        .overlay(Capsule().strokeBorder(.orange.opacity(0.35)))
                }
                Spacer(minLength: 16)
                Picker("", selection: $ai.provider) {
                    ForEach(AIStore.Provider.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 340)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            if ai.provider == .apple { appleRow }
            if ai.provider == .ollama { ollamaRows }
        }
    }

    private var dataSection: some View {
        section("Data", footer: "Playback cache expires automatically. Downloads stay until you remove them.") {
            row("Downloads", subtitle: "Songs you downloaded · \(fmtBytes(downloadsBytes))") {
                Button("Clear…", role: .destructive) { confirmClearAudio = true }
                    .disabled(downloadsBytes == 0)
            }
            divider
            row("Playback cache", subtitle: "\(fmtBytes(cacheBytes)) audio · \(streamCount) resolved links") {
                Button("Clear") {
                    Task {
                        await AudioFileCache.shared.clearCache()
                        await StreamCache.shared.clear()
                        await refreshCounts()
                    }
                }
                .disabled(cacheBytes == 0 && streamCount == 0)
            }
            divider
            row("Listening history", subtitle: "\(historyCount) plays · powers Stats and Recently Played") {
                Button("Clear…", role: .destructive) { confirmClearHistory = true }
                    .disabled(historyCount == 0)
            }
        }
    }

    // MARK: About — full write-up, not just a one-line card

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rift Music App").font(.title2.bold())
                        Text("Native macOS YouTube Music player").font(.subheadline).foregroundStyle(.secondary)
                        Text("Version \(Self.marketingVersion) (\(Self.buildVersion))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Text("A native player over YouTube Music's own catalog and recommendations — "
                     + "streamed or downloaded, with local files alongside, in one Liquid Glass window "
                     + "and a notch-native dynamic island. Free, fully open source.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://rift-music-app.vercel.app/")!) {
                        Label("Website", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://github.com/MustafaPatharia/rift-music-app")!) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/MustafaPatharia/rift-music-app/issues")!) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                }
                .font(.caption).buttonStyle(.plain)
            }
            .padding(16)
            .liquidGlass(in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))

            section("Developer") {
                row("Mustafa Patharia", subtitle: "Built and maintained by one developer") {
                    Link(destination: URL(string: "https://mustafapatharia.vercel.app")!) {
                        Label("Meet the Developer", systemImage: "person.crop.circle")
                    }
                    .font(.caption)
                }
                divider
                row("Enjoying Rift?", subtitle: "No ads, no subscriptions — support keeps it going") {
                    Link(destination: URL(string: "https://buymeachai.in/mustafapatharia")!) {
                        Label("Buy me a chai", systemImage: "cup.and.saucer.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .background(.orange.opacity(0.18), in: .capsule)
                    .overlay(Capsule().strokeBorder(.orange.opacity(0.35)))
                    .foregroundStyle(.orange)
                }
            }

            section("License", footer: "GPL-3.0 — free to use, study, share, and modify; changes you " +
                    "distribute must stay open under the same license.") {
                row("GNU General Public License v3.0") {
                    Link("View License", destination: URL(string: "https://github.com/MustafaPatharia/rift-music-app/blob/main/LICENSE")!)
                        .font(.caption)
                }
                divider
                row("Terms of Service") {
                    Link("View Terms", destination: URL(string: "https://rift-music-app.vercel.app/terms")!)
                        .font(.caption)
                }
                divider
                row("Privacy Policy") {
                    Link("View Policy", destination: URL(string: "https://rift-music-app.vercel.app/privacy")!)
                        .font(.caption)
                }
            }

            section("Credits", footer: "Protocol shapes and design patterns are learned, not copied — "
                    + "Kotlin/TypeScript source was never ported into this Swift codebase.") {
                row("Atoll", subtitle: "Design reference for the notch dynamic island") { EmptyView() }
                divider
                row("ytmusicapi · OuterTune", subtitle: "InnerTube protocol reference") { EmptyView() }
                divider
                row("pear-desktop", subtitle: "WebView-playback pattern & disclaimer wording") { EmptyView() }
            }

            Text("Not affiliated with, endorsed by, or connected to Google LLC / YouTube.")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
        }
    }

    private static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private static var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // MARK: AI section pieces

    private var aiFooter: String {
        switch ai.provider {
        case .off:
            return "AI is off. Nothing is downloaded or run until you pick a provider — everything stays on this Mac either way."
        case .apple:
            return "Uses the Apple Intelligence system model built into macOS — on-device, no download, no data leaves this Mac."
        case .ollama:
            return "Uses your local Ollama server (localhost only). Models are downloaded and run by Ollama on this Mac."
        }
    }

    private var appleRow: some View {
        Group {
            divider
            row("Apple Intelligence",
                subtitle: AppleAI.isAvailable
                    ? "Ready · built-in on-device system model"
                    : "Not available — enable Apple Intelligence in System Settings") {
                Image(systemName: AppleAI.isAvailable
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(AppleAI.isAvailable ? .green : .orange)
            }
        }
    }

    @ViewBuilder private var ollamaRows: some View {
        divider
        if !ollamaUp {
            row("Ollama not detected",
                subtitle: "Install and start Ollama, then refresh") {
                HStack(spacing: 10) {
                    Link("Get Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                    Button("Refresh") { Task { await refreshOllama() } }
                }
            }
        } else {
            row("Model", subtitle: installedModels.isEmpty
                    ? "No models installed — download one below"
                    : "Runs locally via Ollama") {
                Picker("", selection: $ai.ollamaModel) {
                    Text("None").tag("")
                    ForEach(installedModels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 220)
            }
            ForEach(Self.curatedModels.filter { m in !installedModels.contains(m.id) }, id: \.id) { m in
                divider
                row(m.name, subtitle: m.info) {
                    if pulling == m.id {
                        HStack(spacing: 8) {
                            ProgressView(value: pullProgress).frame(width: 110)
                            Text("\(Int(pullProgress * 100))%")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Download") { pull(m.id) }
                            .disabled(pulling != nil)
                    }
                }
            }
            if let pullError {
                divider
                Text(pullError).font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
    }

    private func refreshOllama() async {
        ollamaUp = await OllamaClient.running()
        installedModels = ollamaUp ? ((try? await OllamaClient.models()) ?? []) : []
        // Selected model vanished from Ollama → deselect so isReady is honest.
        if !ai.ollamaModel.isEmpty && ollamaUp && !installedModels.contains(ai.ollamaModel) {
            ai.ollamaModel = ""
        }
    }

    private func pull(_ model: String) {
        pulling = model; pullProgress = 0; pullError = nil
        Task {
            do {
                try await OllamaClient.pull(model) { p in
                    Task { @MainActor in pullProgress = p }
                }
                await refreshOllama()
                if ai.ollamaModel.isEmpty { ai.ollamaModel = model }   // auto-select first model
            } catch {
                pullError = error.localizedDescription
            }
            pulling = nil
        }
    }

    // MARK: grouped-section scaffolding (HIG: header outside, footer caption)
    private func section(_ header: String, footer: String? = nil,
                         @ViewBuilder _ rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header.uppercased())
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .kerning(0.3)
                .padding(.horizontal, 16)
            VStack(spacing: 0) { rows() }
                .padding(.vertical, 4)
                .liquidGlass(in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
            if let footer {
                Text(footer)
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// One settings row: label (+optional subtitle) leading, control trailing.
    private func row(_ title: String, subtitle: String? = nil,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    /// Inset divider (starts at the text column, like grouped lists).
    private var divider: some View {
        Divider().padding(.leading, 16)
    }

    private func refreshCounts() async {
        downloadsBytes = await AudioFileCache.shared.downloadsBytes()
        cacheBytes = await AudioFileCache.shared.cacheBytes()
        streamCount = await StreamCache.shared.count
        historyCount = await PlayHistoryStore.shared.all().count
    }

    private func fmtBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
