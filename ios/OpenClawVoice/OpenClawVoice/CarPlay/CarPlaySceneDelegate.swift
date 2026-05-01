import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var templateManager: CarPlayTemplateManager?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            let manager = CarPlayTemplateManager(interfaceController: interfaceController)
            self.templateManager = manager
            manager.setupRootTemplate()
            CarPlayCoordinator.shared.appState?.isCarPlayConnected = true
            NotificationCenter.default.post(name: .carPlayDidConnect, object: nil)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.templateManager = nil
        Task { @MainActor in
            CarPlayCoordinator.shared.appState?.isCarPlayConnected = false
            NotificationCenter.default.post(name: .carPlayDidDisconnect, object: nil)
        }
    }
}

extension Notification.Name {
    static let carPlayDidConnect = Notification.Name("carPlayDidConnect")
    static let carPlayDidDisconnect = Notification.Name("carPlayDidDisconnect")
}
