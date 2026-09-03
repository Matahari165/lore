import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct PodcastLibraryView: View {
    @State private var model: PodcastLibraryModel
    @State private var presentsImporter = false
    @State private var selectedPodcast: PodcastRecord?

    init(model: PodcastLibraryModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                pageHeader
                if model.podcasts.isEmpty {
                    emptyState
                } else {
                    podcastList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .loreCanvas()
        .task { model.reload() }
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [.mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            Task { await model.importSelection(result.mapError { $0 as Error }) }
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastPlayerView(
                podcast: podcast,
                repository: model.repository,
                fileStore: model.fileStore
            )
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if model.isImporting {
                ZStack {
                    LoreTheme.canvas.opacity(0.88)
                    ProgressView("Importation en cours…")
                        .font(.callout.weight(.medium))
                }
                .ignoresSafeArea()
                .accessibilityElement(children: .combine)
            }
        }
        .alert("Importation terminée", isPresented: Binding(
            get: { model.importSummary != nil },
            set: { if !$0 { model.importSummary = nil } }
        )) {
            Button("OK", role: .cancel) { model.importSummary = nil }
        } message: {
            Text(model.importSummary?.message ?? "")
        }
        .alert("Impossible de continuer", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 10) {
            Text("Podcasts")
                .font(.title.weight(.bold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Importer des MP4", systemImage: "plus") {
                presentsImporter = true
            }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .disabled(model.isImporting)
        }
        .foregroundStyle(LoreTheme.ink)
        .padding(.leading, LoreTheme.pageMargin)
        .padding(.trailing, max(8, LoreTheme.pageMargin - 6))
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(LoreTheme.canvas)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun podcast", systemImage: "waveform")
        } description: {
            Text("Importez un fichier MP4 depuis Fichiers pour l’écouter et reprendre sa lecture plus tard.")
        } actions: {
            Button("Importer un MP4") { presentsImporter = true }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(LoreTheme.canvas)
                .controlSize(.large)
        }
    }

    private var podcastList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.podcasts) { podcast in
                    Button {
                        selectedPodcast = podcast
                    } label: {
                        podcastRow(podcast)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: podcast))
                    .accessibilityHint("Ouvre le lecteur")
                    Divider().overlay(LoreTheme.hairline)
                }
            }
            .padding(.horizontal, LoreTheme.pageMargin)
            .padding(.bottom, 32)
        }
    }

    private func podcastRow(_ podcast: PodcastRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(LoreTheme.ink)
                .frame(width: 44, height: 44)
                .background(LoreTheme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(podcast.lastPositionSeconds > 0
                         ? "Reprendre à \(PodcastTimeFormatter.string(from: podcast.lastPositionSeconds))"
                         : "Pas encore écouté")
                    if let duration = podcast.durationSeconds {
                        Text("·")
                        Text(PodcastTimeFormatter.string(from: duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(LoreTheme.secondaryInk)
                LoreProgressBar(value: podcast.progression, height: 5)
            }
            Image(systemName: podcast.lastPositionSeconds > 0 ? "play.fill" : "play")
                .font(.body.weight(.semibold))
                .foregroundStyle(LoreTheme.ink)
                .frame(width: 44, height: 44)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(for podcast: PodcastRecord) -> String {
        let position = podcast.lastPositionSeconds > 0
            ? "Reprendre à \(PodcastTimeFormatter.string(from: podcast.lastPositionSeconds))"
            : "Pas encore écouté"
        return "\(podcast.title). \(position)"
    }
}

struct PodcastPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let podcast: PodcastRecord
    let repository: PodcastRepository
    let fileStore: PodcastFileStore
    @State private var playerModel: PodcastPlayerModel?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let playerModel {
                    playerContent(playerModel)
                } else if let loadError {
                    ContentUnavailableView("Lecture impossible", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView("Préparation du podcast…")
                }
            }
            .padding(.horizontal, LoreTheme.pageMargin)
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .loreCanvas()
        .task { await loadPlayer() }
        .task(id: playerModel?.podcast.id) {
            guard let playerModel else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                playerModel.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            playerModel?.pauseAndSave()
        }
        .onDisappear {
            playerModel?.pauseAndSave()
        }
    }

    @ViewBuilder
    private func playerContent(_ playerModel: PodcastPlayerModel) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VideoPlayer(player: playerModel.player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 10) {
                    Text(podcast.title)
                        .font(.title2.weight(.bold))
                    Text(podcast.originalFilename)
                        .font(.subheadline)
                        .foregroundStyle(LoreTheme.secondaryInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playerModel.currentTime },
                        set: { playerModel.seek(to: $0) }
                    ),
                    in: 0...max(playerModel.duration, 1),
                    onEditingChanged: { editing in
                        if !editing { playerModel.persist() }
                    }
                )
                .disabled(!playerModel.isReady)
                HStack {
                    Text(PodcastTimeFormatter.string(from: playerModel.currentTime))
                    Spacer()
                    Text(PodcastTimeFormatter.string(from: playerModel.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(LoreTheme.secondaryInk)

                Button {
                    playerModel.togglePlayback()
                } label: {
                    Label(
                        playerModel.isPlaying ? "Pause" : (playerModel.currentTime > 0 ? "Reprendre" : "Écouter"),
                        systemImage: playerModel.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!playerModel.isReady)
                .accessibilityHint("La position est enregistrée automatiquement")

                if let error = playerModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 18)
        }
    }

    private func loadPlayer() async {
        guard playerModel == nil else { return }
        do {
            let fileURL = try fileStore.fileURL(for: podcast.relativeFilePath)
            let model = PodcastPlayerModel(podcast: podcast, repository: repository)
            playerModel = model
            await model.load(fileURL: fileURL)
            if let error = model.errorMessage { loadError = error }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private enum PodcastTimeFormatter {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        }
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }
}
