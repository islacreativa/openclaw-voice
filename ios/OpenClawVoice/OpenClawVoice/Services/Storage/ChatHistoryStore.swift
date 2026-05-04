import Foundation

/// Loads and saves the chat transcript to a JSON file in the app's Documents
/// directory. Writes are debounced — frequent in-flight chunks don't thrash
/// the disk, but the file always settles to current state within ~500ms.
@MainActor
final class ChatHistoryStore {
    static let shared = ChatHistoryStore()
    private init() {}

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("chat-history.json")
    }()

    private let limit = 200
    private var debounceTask: Task<Void, Never>?

    func load() -> [ChatMessage] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ChatMessage].self, from: data)
        } catch {
            print("[ChatHistoryStore] load failed: \(error)")
            return []
        }
    }

    /// Queues a save. The actual write happens after a short debounce so we
    /// don't write on every streaming chunk.
    func saveDebounced(_ messages: [ChatMessage]) {
        debounceTask?.cancel()
        let snapshot = Array(messages.suffix(limit))
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self.write(snapshot)
        }
    }

    /// Forces an immediate write. Use on app background / scene disconnect.
    func saveNow(_ messages: [ChatMessage]) async {
        debounceTask?.cancel()
        await write(Array(messages.suffix(limit)))
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ messages: [ChatMessage]) async {
        let url = fileURL
        await Task.detached {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(messages)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[ChatHistoryStore] write failed: \(error)")
            }
        }.value
    }
}
