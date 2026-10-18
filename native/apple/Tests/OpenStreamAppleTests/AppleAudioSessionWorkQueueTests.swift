import Foundation
import Testing
@testable import OpenStreamApple

@MainActor @Test func audioSessionWorkRunsOffMainAndPreservesActivationOrder() async throws {
    let queue = AppleAudioSessionWorkQueue()
    let recorder = AudioWorkRecorder()
    queue.enqueue { recorder.append("activate") }
    queue.enqueue { recorder.append("deactivate") }
    try await queue.perform { recorder.append("reactivate") }
    #expect(recorder.values == ["activate", "deactivate", "reactivate"])
    #expect(!recorder.usedMainThread)
}

@MainActor @Test func trailerAudioPreparationReturnsBeforePendingAudioWorkCompletes() async throws {
    let queue = AppleAudioSessionWorkQueue()
    let recorder = AudioWorkRecorder()
    let blocked = DispatchSemaphore(value: 0)
    queue.enqueue {
        // Model a two-second mediaserverd wait already occupying the audio queue.
        _ = blocked.wait(timeout: .now() + 2)
        recorder.append("pending playback")
    }

    let clock = ContinuousClock()
    let start = clock.now
    ApplePlaybackSessionPolicy.prepareTrailerAudio(workQueue: queue) {
        recorder.append("trailer")
    }
    let elapsed = start.duration(to: clock.now)
    #expect(elapsed < .milliseconds(50))
    #expect(recorder.values.isEmpty)

    try await queue.perform { recorder.append("subsequent playback") }
    #expect(recorder.values == ["pending playback", "trailer", "subsequent playback"])
    #expect(recorder.usedMainThread == false)
}

private final class AudioWorkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var main = false
    var values: [String] { lock.withLock { storage } }
    var usedMainThread: Bool { lock.withLock { main } }
    func append(_ value: String) { lock.withLock { storage.append(value); main = main || Thread.isMainThread } }
}
