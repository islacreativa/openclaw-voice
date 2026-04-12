import Foundation
import Network

/// Forces iOS to show the Local Network permission prompt.
/// iOS 14+ requires explicit permission to access devices on the local
/// network. WebSocket connections alone don't trigger the prompt reliably,
/// so we both publish AND browse a Bonjour service, which guarantees the
/// system dialog appears on first run.
final class LocalNetworkPermission {
    private static var listener: NWListener?
    private static var browser: NWBrowser?

    static func request() async {
        print("[LocalNetwork] Requesting permission...")

        await withCheckedContinuation { continuation in
            var resumed = false
            let resume: () -> Void = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }

            // 1) PUBLISH a Bonjour service — this is the most reliable
            //    way to trigger the system prompt.
            let listenerParameters = NWParameters.tcp
            do {
                let listener = try NWListener(using: listenerParameters)
                listener.service = NWListener.Service(
                    name: "OpenClawVoice-\(UIDevice.current.name)",
                    type: "_openclaw._tcp"
                )
                listener.newConnectionHandler = { connection in
                    connection.cancel()
                }
                listener.stateUpdateHandler = { state in
                    print("[LocalNetwork] Listener state: \(state)")
                    switch state {
                    case .ready:
                        print("[LocalNetwork] Listener ready, permission likely granted")
                        resume()
                    case .failed(let err):
                        print("[LocalNetwork] Listener failed: \(err)")
                        resume()
                    case .cancelled:
                        resume()
                    default:
                        break
                    }
                }
                listener.start(queue: .main)
                self.listener = listener
            } catch {
                print("[LocalNetwork] Could not create listener: \(error)")
            }

            // 2) BROWSE Bonjour services — belt & suspenders
            let browserParameters = NWParameters()
            browserParameters.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjour(type: "_openclaw._tcp", domain: nil),
                using: browserParameters
            )
            browser.stateUpdateHandler = { state in
                print("[LocalNetwork] Browser state: \(state)")
                switch state {
                case .ready, .failed, .cancelled:
                    resume()
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { _, _ in
                print("[LocalNetwork] Browser found services")
                resume()
            }
            browser.start(queue: .main)
            self.browser = browser

            // 3) Fallback timeout: 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("[LocalNetwork] Timeout reached")
                resume()
            }
        }

        print("[LocalNetwork] Request complete")
    }

    static func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }
}

import UIKit
