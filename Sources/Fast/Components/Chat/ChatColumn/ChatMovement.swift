/// The latest requested chat state owns every deferred write. The model
/// can still show the old state while the next frame is waiting to run.
struct ChatMovement {
    enum Request: Equatable { case unchanged, cancelled, move(Int) }
    private(set) var target: Bool?
    private(set) var generation = 0

    mutating func request(open: Bool, current: Bool, moving: Bool) -> Request {
        if open == (target ?? current) {
            // An idempotent close also releases an orphaned movement hold.
            guard !open, moving, target == nil else { return .unchanged }
            generation += 1
            return .cancelled
        }
        generation += 1
        if open == current {
            target = nil
            return .cancelled
        }
        target = open
        return .move(generation)
    }

    func isCurrent(_ move: Int) -> Bool { target != nil && generation == move }

    @discardableResult
    mutating func complete(_ move: Int) -> Bool {
        guard isCurrent(move) else { return false }
        target = nil
        return true
    }
}
