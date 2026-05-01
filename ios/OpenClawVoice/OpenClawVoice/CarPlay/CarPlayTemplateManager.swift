import CarPlay
import UIKit

@MainActor
final class CarPlayTemplateManager {
    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?
    private var listTemplate: CPListTemplate?
    private var historyTemplate: CPListTemplate?
    private var statusTemplate: CPListTemplate?
    private var tabBar: CPTabBarTemplate?

    private var voiceController: CarPlayVoiceController?
    private var voicePresented = false

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        CarPlayCoordinator.shared.templateManager = self
    }

    deinit {
        Task { @MainActor in
            if CarPlayCoordinator.shared.templateManager === self {
                CarPlayCoordinator.shared.templateManager = nil
            }
        }
    }

    // MARK: - Root

    func setupRootTemplate() {
        let voiceTab = createVoiceListTab()
        let historyTab = createHistoryTab()
        let statusTab = createStatusTab()

        let bar = CPTabBarTemplate(templates: [voiceTab, historyTab, statusTab])
        self.tabBar = bar
        interfaceController.setRootTemplate(bar, animated: true, completion: nil)

        // If services were registered before the scene attached, hydrate now.
        servicesAvailable()
    }

    /// Called by the coordinator when services become available — refresh items
    /// that depend on connection state.
    func servicesAvailable() {
        updateConnectionStatus()
    }

    // MARK: - Voice tab (entry list with a "Talk" button)

    private func createVoiceListTab() -> CPTemplate {
        let talkItem = CPListItem(text: "Hablar con OpenClaw", detailText: "Pulsa para iniciar")
        talkItem.setImage(UIImage(systemName: "mic.circle.fill"))
        talkItem.handler = { [weak self] _, completion in
            self?.startVoiceFlow()
            completion()
        }

        let section = CPListSection(items: [talkItem])
        let template = CPListTemplate(title: "OpenClaw", sections: [section])
        template.tabTitle = "Voz"
        template.tabImage = UIImage(systemName: "mic.circle.fill")
        self.listTemplate = template
        return template
    }

    private func voiceControlTemplate() -> CPVoiceControlTemplate {
        if let existing = voiceTemplate { return existing }
        let template = CPVoiceControlTemplate(voiceControlStates: [
            createState("idle", title: "Listo", icon: "mic.circle", repeats: false),
            createState("listening", title: "Escuchando…", icon: "waveform", repeats: true),
            createState("processing", title: "Procesando…", icon: "brain", repeats: true),
            createState("speaking", title: "Respondiendo…", icon: "speaker.wave.3", repeats: true)
        ])
        self.voiceTemplate = template
        return template
    }

    private func createState(_ identifier: String, title: String, icon: String, repeats: Bool) -> CPVoiceControlState {
        CPVoiceControlState(
            identifier: identifier,
            titleVariants: [title],
            image: UIImage(systemName: icon),
            repeats: repeats
        )
    }

    private func startVoiceFlow() {
        guard let controller = CarPlayCoordinator.shared.voiceController
            ?? CarPlayCoordinator.shared.makeVoiceController() else {
            presentAlert(title: "Servicios no listos",
                        message: "Abre la app en el iPhone para conectar antes de usar CarPlay.")
            return
        }
        controller.templateManager = self
        self.voiceController = controller

        let voiceTpl = voiceControlTemplate()
        if voicePresented {
            // Already presented — just activate idle state and let the controller drive.
        } else {
            voicePresented = true
            interfaceController.presentTemplate(voiceTpl, animated: true) { [weak self] _, _ in
                self?.activateState("idle")
            }
        }

        Task {
            await controller.startVoiceInteraction()
            await self.dismissVoiceControl()
        }
    }

    private func dismissVoiceControl() async {
        guard voicePresented else { return }
        voicePresented = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            interfaceController.dismissTemplate(animated: true) { _, _ in
                continuation.resume()
            }
        }
    }

    // MARK: - History tab

    private func createHistoryTab() -> CPTemplate {
        let placeholder = CPListItem(text: "Sin historial", detailText: "Tu conversación aparecerá aquí")
        let section = CPListSection(items: [placeholder])
        let template = CPListTemplate(title: "Historial", sections: [section])
        template.tabTitle = "Historial"
        template.tabImage = UIImage(systemName: "clock")
        self.historyTemplate = template
        return template
    }

    func updateHistory(messages: [(role: String, text: String)]) {
        let recent = Array(messages.suffix(20))
        let items: [CPListItem] = recent.isEmpty
            ? [CPListItem(text: "Sin historial", detailText: "Tu conversación aparecerá aquí")]
            : recent.map { msg in
                CPListItem(
                    text: msg.role == "user" ? "Tú" : "OpenClaw",
                    detailText: String(msg.text.prefix(120))
                )
            }
        let section = CPListSection(items: items)
        historyTemplate?.updateSections([section])
    }

    // MARK: - Status tab

    private func createStatusTab() -> CPTemplate {
        let connection = CPListItem(text: "Conexión", detailText: "Comprobando…")
        connection.setImage(UIImage(systemName: "wifi"))

        let openclaw = CPListItem(text: "OpenClaw", detailText: "—")
        openclaw.setImage(UIImage(systemName: "brain"))

        let section = CPListSection(items: [connection, openclaw])
        let template = CPListTemplate(title: "Estado", sections: [section])
        template.tabTitle = "Estado"
        template.tabImage = UIImage(systemName: "info.circle")
        self.statusTemplate = template
        return template
    }

    func updateConnectionStatus() {
        let connected = CarPlayCoordinator.shared.webSocket?.connectionStatus.isConnected ?? false
        let serverHost = CarPlayCoordinator.shared.appState?.serverURL ?? "Mac"

        let connectionItem = CPListItem(
            text: "Conexión",
            detailText: connected ? "Conectado a \(prettyHost(serverHost))" : "Desconectado"
        )
        connectionItem.setImage(UIImage(systemName: connected ? "wifi" : "wifi.slash"))

        let agentName = CarPlayCoordinator.shared.appState?.currentAgent?.name ?? "—"
        let openclawItem = CPListItem(text: "Agente", detailText: agentName)
        openclawItem.setImage(UIImage(systemName: "brain"))

        let section = CPListSection(items: [connectionItem, openclawItem])
        statusTemplate?.updateSections([section])
    }

    private func prettyHost(_ urlString: String) -> String {
        if let u = URL(string: urlString), let host = u.host { return host }
        return urlString
    }

    // MARK: - State sync from voice controller

    func activateState(_ identifier: String) {
        voiceTemplate?.activateVoiceControlState(withIdentifier: identifier)
    }

    private func presentAlert(title: String, message: String) {
        let action = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.interfaceController.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [title, message], actions: [action])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }
}

// Safe array subscript (kept for backwards compatibility with old call sites)
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
