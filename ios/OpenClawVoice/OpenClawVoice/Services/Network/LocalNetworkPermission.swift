import Foundation
import Network

/// Forces iOS to show the Local Network permission prompt by starting a
/// Bonjour browser. This is a known workaround because WebSocket requests
/// alone don't reliably trigger the prompt on iOS 14+.
///
/// Usage:
///   await LocalNetworkPermission.request()
final class LocalNetworkPermission {
    private static var browser: NWBrowser?

    static func request() async {
        await withCheckedContinuation { continuation in
            let parameters = NWParameters()
            parameters.includePeerToPeer = true

            // Browse for any Bonjour service — iOS shows the permission
            // prompt as soon as the browser starts. Service doesn't need
            // to exist; just starting the browser is enough.
            let browser = NWBrowser(for: .bonjour(type: "_openclaw._tcp", domain: nil), using: parameters)

            var resumed = false
            let resume = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    // After any terminal state, we've either got permission
                    // or the user denied. Either way, proceed.
                    resume()
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { _, _ in
                // Received at least one result — permission is granted
                resume()
            }

            browser.start(queue: .main)
            self.browser = browser

            // Fallback: resolve after 2s even if nothing happens
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resume()
            }
        }
    }

    static func stop() {
        browser?.cancel()
        browser = nil
    }
}
