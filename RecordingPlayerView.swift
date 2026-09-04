import SwiftUI
import AVFoundation

/// Reproductor de las exportaciones de audio de Logic, para poder escuchar una toma sin salir a
/// Finder y sobre todo para comparar la de hoy con la del mes pasado sin cambiar de app.
///
/// Mantiene el acceso con alcance de seguridad abierto mientras suena (no se puede usar
/// `SecurityScopedFile.withAccess`, que lo cierra al volver) y lo libera al soltar el archivo.
@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    @Published var rate: Float = 1.0
    @Published private(set) var errorMessage = ""

    private var player: AVAudioPlayer?
    private var scopedURL: URL?
    private var ticker: Timer?

    deinit {
        ticker?.invalidate()
        player?.stop()
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
    }

    func load(bookmark: Data) {
        release()

        guard let url = SecurityScopedFile.resolve(bookmark) else {
            errorMessage = "No se pudo acceder al archivo. Revisa que el disco esté conectado."
            return
        }
        let granted = url.startAccessingSecurityScopedResource()
        scopedURL = granted ? url : nil

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            currentTime = 0
            errorMessage = ""
        } catch {
            errorMessage = "No se pudo reproducir este archivo: \(error.localizedDescription)"
            releaseScope()
        }
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.invalidate()
        } else {
            player.rate = rate
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    func skip(_ seconds: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + seconds)
    }

    func applyRate(_ newRate: Float) {
        rate = newRate
        player?.rate = newRate
    }

    func release() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        releaseScope()
    }

    private func releaseScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.ticker?.invalidate()
            self.currentTime = 0
        }
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Controles compactos para el detalle de una grabación.
struct RecordingPlayerView: View {
    let bookmark: Data
    @StateObject private var controller = AudioPlaybackController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button("Atrás 5 s", systemImage: "gobackward.5") { controller.skip(-5) }
                    .labelStyle(.iconOnly)
                    .disabled(controller.duration == 0)

                Button(
                    controller.isPlaying ? "Pausar" : "Reproducir",
                    systemImage: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                ) {
                    controller.togglePlay()
                }
                .labelStyle(.iconOnly)
                .font(.title)
                .buttonStyle(.plain)
                .disabled(controller.duration == 0)

                Button("Adelante 5 s", systemImage: "goforward.5") { controller.skip(5) }
                    .labelStyle(.iconOnly)
                    .disabled(controller.duration == 0)

                Text("\(AudioPlaybackController.timeLabel(controller.currentTime)) / \(AudioPlaybackController.timeLabel(controller.duration))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Velocidad", selection: Binding(
                    get: { controller.rate },
                    set: { controller.applyRate($0) }
                )) {
                    Text("0,5×").tag(Float(0.5))
                    Text("0,75×").tag(Float(0.75))
                    Text("1×").tag(Float(1.0))
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Slider(
                value: Binding(
                    get: { controller.currentTime },
                    set: { controller.seek(to: $0) }
                ),
                in: 0...max(controller.duration, 0.1)
            )
            .disabled(controller.duration == 0)

            if !controller.errorMessage.isEmpty {
                Text(controller.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Bajar la velocidad no cambia el tono: sirve para sacar un pasaje rápido de tu propia toma.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { controller.load(bookmark: bookmark) }
        .onDisappear { controller.release() }
    }
}
