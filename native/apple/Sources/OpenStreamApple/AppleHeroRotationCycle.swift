import Foundation

extension AppleHeroRotation {
    /// The iPhone hero's rotation, held as state rather than read off the clock.
    ///
    /// The clock-derived `index(at:)` cannot be swiped, jumped or held still,
    /// and the owner asked for the Apple TV app's hero on the iPhone: swipe to
    /// change page, tap a dot to jump, and a timer that stops while you touch it
    /// (2026-09-22, "match apple tv hero buttons trailers and 'cycle'"). Same
    /// interval and candidates as the clock; only the iPhone portrait hero uses
    /// this, every other hero still follows `index(at:)`.
    public struct Cycle: Equatable, Sendable {
        public let count: Int
        public let interval: TimeInterval
        public private(set) var index: Int
        /// Time already spent on this page before the current run began.
        private var elapsedBeforeRun: TimeInterval = 0
        /// When the current run began; nil while paused.
        private var runningSince: Date?

        public init(count: Int, index: Int = 0, interval: TimeInterval = AppleHeroRotation.interval, now: Date = .now) {
            self.count = max(count, 0)
            self.interval = interval
            self.index = self.count > 0 ? min(max(index, 0), self.count - 1) : 0
            self.runningSince = now
        }

        public var isPaused: Bool { runningSince == nil }

        /// How far the active page's timer has run, 0...1 — the fill of the
        /// active dot.
        public func progress(at now: Date) -> Double {
            guard interval > 0 else { return 0 }
            let running = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
            return min(max((elapsedBeforeRun + running) / interval, 0), 1)
        }

        /// When the page changes on its own, or nil when it will not (paused, or
        /// nothing to move to).
        public var dueDate: Date? {
            guard count > 1, interval > 0, let runningSince else { return nil }
            return runningSince.addingTimeInterval(max(interval - elapsedBeforeRun, 0))
        }

        public mutating func pause(at now: Date) {
            guard runningSince != nil else { return }
            elapsedBeforeRun = progress(at: now) * interval
            runningSince = nil
        }

        public mutating func resume(at now: Date) {
            guard runningSince == nil else { return }
            runningSince = now
        }

        /// Shows `target` (wrapping) with a fresh timer, keeping the paused or
        /// running state as it was.
        public mutating func show(_ target: Int, at now: Date) {
            guard count > 0 else { return }
            index = ((target % count) + count) % count
            elapsedBeforeRun = 0
            if runningSince != nil { runningSince = now }
        }

        public mutating func step(by offset: Int, at now: Date) {
            show(index + offset, at: now)
        }

        /// Moves to the next page when its timer has run out. True when it moved.
        @discardableResult
        public mutating func advanceIfDue(at now: Date) -> Bool {
            guard let dueDate, now >= dueDate else { return false }
            step(by: 1, at: now)
            return true
        }
    }

    /// Whether the iPhone hero's timer holds still: while a finger is on the
    /// hero, while its trailer is playing with the sound on — nobody wants
    /// a trailer they chose to listen to swapped out from under them — and
    /// while a trailer asked for with Play Trailer loads or plays: it loads
    /// behind the art with nothing on screen (art-first), and moving on
    /// before it can fade in would drop what was asked for.
    public static func cycleIsPaused(isTouching: Bool, trailerIsPlaying: Bool, trailerIsMuted: Bool,
                                     trailerWasRequested: Bool = false) -> Bool {
        isTouching || (trailerIsPlaying && (!trailerIsMuted || trailerWasRequested))
    }
}
