import AVKit
import MediaPlayer
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
            .presentationDetents([.medium, .large])
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
    @State private var sheetHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let playerModel {
                    playerContent(playerModel)
                } else if let loadError {
                    ContentUnavailableView("Lecture impossible", systemImage: "exclamationmark.triangle", description: Text(loadError))
                        .padding(.top, 24)
                } else {
                    ProgressView("Préparation du podcast…")
                        .font(.callout)
                        .foregroundStyle(LoreTheme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }
            }
            .padding(.horizontal, LoreTheme.pageMargin)
        }
        .background(LoreTheme.canvas.ignoresSafeArea())
        .tint(LoreTheme.ink)
        .foregroundStyle(LoreTheme.ink)
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
            // Verrouillage ou arrière-plan : on enregistre la position sans couper le son.
            playerModel?.savePositionOnly()
        }
        .onDisappear {
            playerModel?.teardown()
        }
    }

    private var isFilenameRedundant: Bool {
        let titleNorm = podcast.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var name = podcast.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = name.lastIndex(of: ".") {
            name = String(name[..<dot])
        }
        name = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !titleNorm.isEmpty, !name.isEmpty else { return true }
        if name == titleNorm { return true }
        if titleNorm.contains(name) || name.contains(titleNorm) { return true }
        return false
    }

    @ViewBuilder
    private func playerContent(_ playerModel: PodcastPlayerModel) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                VideoPlayer(player: playerModel.player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 28)
                    .accessibilityLabel("Vidéo du podcast")
                    .overlay(alignment: .topTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.glass)
                        .padding(10)
                        .accessibilityLabel("Fermer le lecteur")
                        .accessibilityHint("Met en pause et enregistre la position")
                    }

                VStack(spacing: 6) {
                    PodcastScrubber(
                        currentTime: playerModel.currentTime,
                        duration: playerModel.duration,
                        isEnabled: playerModel.isReady,
                        onSeek: { playerModel.seek(to: $0) },
                        onScrubEnded: { playerModel.persist() }
                    )
                    HStack {
                        Text(PodcastTimeFormatter.string(from: playerModel.currentTime))
                        Spacer()
                        Text(PodcastTimeFormatter.remaining(from: playerModel.currentTime, total: playerModel.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Position \(PodcastTimeFormatter.string(from: playerModel.currentTime)), reste \(PodcastTimeFormatter.remaining(from: playerModel.currentTime, total: playerModel.duration)) sur \(PodcastTimeFormatter.string(from: playerModel.duration)) au total"
                    )
                }

                transportRow(playerModel)

                VStack(alignment: .leading, spacing: 6) {
                    Text(podcast.title)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isFilenameRedundant {
                        Text(podcast.originalFilename)
                            .font(.caption)
                            .foregroundStyle(LoreTheme.secondaryInk)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(podcast.title)

                if sheetHeight > 600 {
                    volumeRow
                        .padding(.top, 10)
                }

                if let error = playerModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
            sheetHeight = newHeight
        }
    }

    private func transportRow(_ playerModel: PodcastPlayerModel) -> some View {
        HStack(spacing: 0) {
            Button {
                playerModel.cyclePlaybackRate()
            } label: {
                Text(playerModel.playbackRateLabel)
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!playerModel.isReady)
            .accessibilityLabel("Vitesse de lecture")
            .accessibilityValue(playerModel.playbackRateLabel)
            .accessibilityHint("Toucher pour changer de vitesse")

            Spacer(minLength: 0)

            Button {
                playerModel.seek(to: playerModel.currentTime - 15)
                playerModel.persist()
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!playerModel.isReady)
            .accessibilityLabel("Reculer de 15 secondes")
            .accessibilityHint("Reprend 15 secondes plus tôt")

            Button {
                playerModel.togglePlayback()
            } label: {
                Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(LoreTheme.canvas)
                    .frame(width: 64, height: 64)
                    .background(LoreTheme.ink, in: Circle())
                    .offset(x: playerModel.isPlaying ? 0 : 2)
            }
            .buttonStyle(.plain)
            .disabled(!playerModel.isReady)
            .accessibilityLabel(playerModel.isPlaying ? "Pause" : (playerModel.currentTime > 1 ? "Reprendre" : "Écouter"))
            .accessibilityHint("La position est enregistrée automatiquement")

            Button {
                playerModel.seek(to: playerModel.currentTime + 15)
                playerModel.persist()
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!playerModel.isReady)
            .accessibilityLabel("Avancer de 15 secondes")
            .accessibilityHint("Saute 15 secondes")

            Spacer(minLength: 0)

            PodcastRouteButton()
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
                .accessibilityLabel("Sortie audio")
                .accessibilityHint("Choisir un appareil de diffusion, par exemple AirPlay")
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(LoreTheme.secondaryInk)
                .accessibilityHidden(true)
            PodcastVolumeSlider()
                .frame(height: 44)
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(LoreTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .glassEffect(.regular, in: Capsule())
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

private struct PodcastScrubber: View {
    let currentTime: Double
    let duration: Double
    let isEnabled: Bool
    var onSeek: (Double) -> Void
    var onScrubEnded: () -> Void

    @State private var dragValue: Double?

    private var displayed: Double {
        dragValue ?? currentTime
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(displayed / duration, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let trackHeight: CGFloat = 4
            let thumbDiameter: CGFloat = 18
            let width = max(geometry.size.width - thumbDiameter, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(height: trackHeight)
                    .glassEffect(.regular, in: Capsule())
                    .opacity(isEnabled ? 1 : 0.5)
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(isEnabled ? LoreTheme.ink : LoreTheme.secondaryInk)
                    .frame(width: width * progress + thumbDiameter / 2, height: trackHeight)
                Circle()
                    .fill(isEnabled ? LoreTheme.ink : LoreTheme.secondaryInk)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: width * progress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, duration > 0 else { return }
                        let x = min(max(value.location.x - thumbDiameter / 2, 0), width)
                        dragValue = (x / width) * duration
                        if let dragValue { onSeek(dragValue) }
                    }
                    .onEnded { _ in
                        dragValue = nil
                        onScrubEnded()
                    }
            )
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Curseur de lecture")
        .accessibilityValue("\(PodcastTimeFormatter.string(from: displayed)) sur \(PodcastTimeFormatter.string(from: duration))")
        .accessibilityHint("Glisser pour changer de position")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onSeek(min(displayed + 15, max(duration, 0))); onScrubEnded()
            case .decrement: onSeek(max(displayed - 15, 0)); onScrubEnded()
            @unknown default: break
            }
        }
    }
}

private struct PodcastVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsRouteButton = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct PodcastRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
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

    /// Temps restant affiché en négatif, comme dans l'application Podcasts d'Apple.
    static func remaining(from current: Double, total: Double) -> String {
        guard current.isFinite, total.isFinite, total > 0 else { return "-0:00" }
        return "-" + string(from: max(total - current, 0))
    }
}
