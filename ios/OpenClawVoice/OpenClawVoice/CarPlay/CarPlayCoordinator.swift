import Foundation

/// Singleton bridge so the CarPlay scene can find services the phone scene
/// already wired up. The phone scene populates this when services are ready.
@MainActor
final class CarPlayCoordinator {
    static let shared = CarPlayCoordinator()
    private init() {}

    private(set) var appState: AppState?
    private(set) var webSocket: WebSocketManager?
    private(set) var speechRecognizer: SpeechRecognizer?
    private(set) var elevenLabs: ElevenLabsService?
    private(set) var audioPlayer: AudioPlayerService?

    weak var voiceController: CarPlayVoiceController?
    weak var templateManager: CarPlayTemplateManager?

    func register(
        appState: AppState,
        webSocket: WebSocketManager,
        speechRecognizer: SpeechRecognizer,
        elevenLabs: ElevenLabsService,
        audioPlayer: AudioPlayerService
    ) {
        self.appState = appState
        self.webSocket = webSocket
        self.speechRecognizer = speechRecognizer
        self.elevenLabs = elevenLabs
        self.audioPlayer = audioPlayer

        // If the CarPlay scene was already attached when registration happens,
        // refresh templates that depend on these services.
        templateManager?.servicesAvailable()
    }

    func makeVoiceController() -> CarPlayVoiceController? {
        guard let appState, let webSocket, let speechRecognizer, let elevenLabs, let audioPlayer else {
            return nil
        }
        let controller = CarPlayVoiceController(
            appState: appState,
            webSocket: webSocket,
            speechRecognizer: speechRecognizer,
            elevenLabs: elevenLabs,
            audioPlayer: audioPlayer
        )
        self.voiceController = controller
        return controller
    }
}
