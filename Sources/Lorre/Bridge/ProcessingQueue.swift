import Foundation

/// Processes conversations one at a time, in the order they were queued.
///
/// The speech services keep their loaded models and configuration as shared state, so two jobs
/// at once would compete for the Neural Engine and could mix up their settings.
actor ProcessingQueue {
    enum Event: Equatable, Sendable {
        case started(UUID)
        case finished(UUID, error: String?)
    }

    private let work: @Sendable (UUID) async throws -> Void
    private var pending: [UUID] = []
    private(set) var current: UUID?
    private var isDraining = false
    private var observers: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(work: @escaping @Sendable (UUID) async throws -> Void) {
        self.work = work
    }

    var waiting: [UUID] { pending }

    func isQueued(_ id: UUID) -> Bool {
        current == id || pending.contains(id)
    }

    /// Adds the conversation to the queue. Queuing one that is already waiting or running does nothing.
    func enqueue(_ id: UUID) {
        guard !isQueued(id) else { return }
        pending.append(id)
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    func events() -> AsyncStream<Event> {
        let key = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        observers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(key) }
        }
        return stream
    }

    /// Returns when nothing is running or waiting.
    func waitUntilIdle() async {
        guard isDraining else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func removeObserver(_ key: UUID) {
        observers[key] = nil
    }

    private func emit(_ event: Event) {
        for observer in observers.values { observer.yield(event) }
    }

    private func drain() async {
        while !pending.isEmpty {
            let id = pending.removeFirst()
            current = id
            emit(.started(id))
            var failure: String?
            do {
                try await work(id)
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            current = nil
            emit(.finished(id, error: failure))
        }
        isDraining = false
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
