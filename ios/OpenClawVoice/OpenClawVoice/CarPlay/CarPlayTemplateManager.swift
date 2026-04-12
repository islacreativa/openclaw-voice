import CarPlay
import UIKit

final class CarPlayTemplateManager {
    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    // MARK: - Root Template

    func setupRootTemplate() {
        let tabBar = CPTabBarTemplate(templates: [
            createVoiceTab(),
            createHistoryTab(),
            createStatusTab()
        ])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    // MARK: - Voice Tab

    private func createVoiceTab() -> CPTemplate {
        let template = CPVoiceControlTemplate(voiceControlStates: [
            createState("idle", title: "Tap to talk to OpenClaw", icon: "mic.circle", repeats: false),
            createState("listening", title: "Listening...", icon: "waveform", repeats: true),
            createState("processing", title: "Processing...", icon: "brain", repeats: true),
            createState("speaking", title: "OpenClaw responds...", icon: "speaker.wave.3", repeats: true)
        ])

        template.tabTitle = "OpenClaw"
        template.tabImage = UIImage(systemName: "mic.circle.fill")
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

    // MARK: - History Tab

    private func createHistoryTab() -> CPTemplate {
        let section = CPListSection(items: [
            CPListItem(text: "No commands yet", detailText: "Your voice history will appear here")
        ])
        let template = CPListTemplate(title: "History", sections: [section])
        template.tabTitle = "History"
        template.tabImage = UIImage(systemName: "clock")
        return template
    }

    // MARK: - Status Tab

    private func createStatusTab() -> CPTemplate {
        let connectionItem = CPListItem(text: "Connection", detailText: "Checking...")
        connectionItem.setImage(UIImage(systemName: "wifi"))

        let openclawItem = CPListItem(text: "OpenClaw", detailText: "Checking...")
        openclawItem.setImage(UIImage(systemName: "brain"))

        let section = CPListSection(items: [connectionItem, openclawItem])
        let template = CPListTemplate(title: "Status", sections: [section])
        template.tabTitle = "Status"
        template.tabImage = UIImage(systemName: "gear")
        return template
    }

    // MARK: - State Updates

    func activateState(_ identifier: String) {
        voiceTemplate?.activateVoiceControlState(withIdentifier: identifier)
    }

    func updateHistory(messages: [(role: String, text: String)]) {
        // Update the history tab with recent messages
        let items = messages.suffix(20).map { msg in
            CPListItem(
                text: msg.role == "user" ? "You" : "OpenClaw",
                detailText: String(msg.text.prefix(100))
            )
        }

        if let tabBar = interfaceController.rootTemplate as? CPTabBarTemplate,
           let historyTemplate = tabBar.templates[safe: 1] as? CPListTemplate {
            let section = CPListSection(items: items.isEmpty ? [
                CPListItem(text: "No commands yet", detailText: "Your voice history will appear here")
            ] : items)
            historyTemplate.updateSections([section])
        }
    }

    func updateConnectionStatus(connected: Bool, serverName: String?) {
        if let tabBar = interfaceController.rootTemplate as? CPTabBarTemplate,
           let statusTemplate = tabBar.templates[safe: 2] as? CPListTemplate {
            let connectionItem = CPListItem(
                text: "Connection",
                detailText: connected ? "Connected to \(serverName ?? "Mac")" : "Disconnected"
            )
            connectionItem.setImage(UIImage(systemName: connected ? "wifi" : "wifi.slash"))

            let section = CPListSection(items: [connectionItem])
            statusTemplate.updateSections([section])
        }
    }
}

// Safe array subscript
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
