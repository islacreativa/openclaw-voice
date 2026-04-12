import Foundation
import Network
import Observation

@Observable
final class ConnectionMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ConnectionMonitor")

    var isConnected: Bool = true
    var isWiFi: Bool = false
    var isCellular: Bool = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isWiFi = path.usesInterfaceType(.wifi)
                self?.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
