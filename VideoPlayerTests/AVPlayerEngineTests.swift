//
//  AVPlayerEngineTests.swift
//  VideoPlayerTests
//
//  State machine tests of AVPlayerEngine. The engine runs on FakePlayer and FakeItem, which the tests
//  drive by hand, so there is no video, no timing and no network.
//  Tests named ...KnownLimitation_ document behavior that the engine accepts as a limitation.
//

import XCTest
import AVFoundation
import VideoPlayerEngine

// MARK: - Delegate spy

final class SpyDelegate: NSObject, PlayerEngineDelegate {
    enum Event: Equatable {
        case state(PlayerState)
        case error
    }

    private(set) var events: [Event] = []
    private(set) var errors: [Error] = []
    private(set) var bufferedTimes: [CMTime] = []

    var onState: ((PlayerState) -> Void)?
    var onError: ((Error) -> Void)?

    var states: [PlayerState] {
        events.compactMap { event in
            if case .state(let state) = event { return state }
            return nil
        }
    }

    func engine(_ engine: PlayerEngine, didChange state: PlayerState) {
        events.append(.state(state))
        onState?(state)
    }

    func engine(_ engine: PlayerEngine, didFailWithError error: Error) {
        events.append(.error)
        errors.append(error)
        onError?(error)
    }

    func engine(_ engine: PlayerEngine, didUpdateBufferedTime time: CMTime) {
        bufferedTimes.append(time)
    }
}

// MARK: - Test case base

class EngineTestCase: XCTestCase {
    var player: FakePlayer!
    var engine: AVPlayerEngine!
    var spy: SpyDelegate!

    let url = URL(fileURLWithPath: "/fake/video.mp4")
    let otherURL = URL(fileURLWithPath: "/fake/other.mp4")

    override func setUp() {
        super.setUp()
        player = FakePlayer()
        engine = AVPlayerEngine(player: player)
        spy = SpyDelegate()
        engine.delegate = spy
    }

    override func tearDown() {
        engine = nil
        spy = nil
        player = nil
        super.tearDown()
    }

    /// The engine hands player events to the main queue asynchronously. A block queued after them runs
    /// after them, so waiting for it means they were all handled.
    func drain() {
        for _ in 0..<2 {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 2)
        }
    }

    // MARK: Scenario steps

    @discardableResult
    func load(_ url: URL? = nil) -> FakeItem {
        engine.loadContent(url ?? self.url)
        drain()
        return player.madeItems.last!
    }

    @discardableResult
    func loadAndMakeReady() -> FakeItem {
        let item = load()
        item.status = .readyToPlay
        drain()
        return item
    }

    @discardableResult
    func loadAndStartPlaying() -> FakeItem {
        let item = loadAndMakeReady()
        engine.play()
        player.timeControlStatus = .playing
        drain()
        return item
    }

    @discardableResult
    func loadAndFinishPlaying(duration: Double = 10) -> FakeItem {
        let item = loadAndStartPlaying()
        item.duration = CMTime(seconds: duration, preferredTimescale: 600)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        drain()
        return item
    }

    func range(_ start: Double, _ end: Double) -> NSValue {
        NSValue(timeRange: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600)))
    }
}

// MARK: - Loading

final class LoadingTests: EngineTestCase {

    func test_initialState_hasNoEvents() {
        XCTAssertTrue(spy.events.isEmpty)
    }

    func test_loadContent_reportsLoading_andAttachesNewItem() {
        let item = load()

        XCTAssertEqual(spy.states, [.loading])
        XCTAssertEqual(player.madeItems.count, 1)
        XCTAssertEqual(item.url, url)
        XCTAssertTrue(player.currentItem === item)
    }

    func test_itemReady_reportsReady() {
        let item = load()
        item.status = .readyToPlay
        drain()

        XCTAssertEqual(spy.states, [.loading, .ready])
    }

    func test_itemFailed_goesIdleFirst_thenReportsError() {
        let item = load()
        item.error = NSError(domain: "test", code: 42)
        item.status = .failed
        drain()

        XCTAssertEqual(spy.events, [.state(.loading), .state(.idle), .error])
        XCTAssertEqual((spy.errors.first as NSError?)?.code, 42)
    }

    func test_itemFailedWithoutError_stillReportsAnError() {
        let item = load()
        item.error = nil
        item.status = .failed
        drain()

        XCTAssertEqual(spy.errors.count, 1)
    }

    func test_retryFromErrorCallback_isNotNested_andKeepsLoadingState() {
        spy.onError = { [unowned self] _ in
            // The engine is already Idle here, so a retry must be allowed and must not be overwritten
            self.engine.loadContent(self.otherURL)
        }
        let item = load()
        item.status = .failed
        drain()

        XCTAssertEqual(player.madeItems.count, 2)
        XCTAssertEqual(player.madeItems.last?.url, otherURL)
        XCTAssertEqual(spy.states.last, .loading)
    }

    func test_unknownItemStatus_reportsNothing() {
        let item = load()
        item.status = .unknown
        drain()

        XCTAssertEqual(spy.states, [.loading])
    }
}

// MARK: - Play

final class PlayTests: EngineTestCase {

    func test_play_inIdle_isIgnored() {
        engine.play()
        drain()

        XCTAssertEqual(player.playCount, 0)
    }

    func test_play_inLoading_isIgnored() {
        load()
        engine.play()
        drain()

        XCTAssertEqual(player.playCount, 0)
    }

    func test_play_inReady_playsThePlayer() {
        loadAndMakeReady()
        engine.play()

        XCTAssertEqual(player.playCount, 1)
    }

    func test_playerPlaying_reportsPlaying() {
        loadAndStartPlaying()

        XCTAssertEqual(spy.states, [.loading, .ready, .playing])
    }

    func test_playRightAfterPause_isNotDropped() {
        loadAndStartPlaying()
        engine.pause()
        engine.play() // the state is still Playing here, the pause event has not been handled yet

        XCTAssertEqual(player.pauseCount, 1)
        XCTAssertEqual(player.playCount, 2)
    }
}

// MARK: - Buffering

final class BufferingTests: EngineTestCase {

    func test_waitingToPlay_reportsBuffering_thenPlaying() {
        loadAndMakeReady()
        engine.play()
        player.reasonForWaitingToPlay = .toMinimizeStalls
        player.timeControlStatus = .waitingToPlayAtSpecifiedRate
        drain()
        player.reasonForWaitingToPlay = nil
        player.timeControlStatus = .playing
        drain()

        XCTAssertEqual(spy.states, [.loading, .ready, .buffering, .playing])
    }

    func test_stallWhilePlaying_reportsBuffering() {
        loadAndStartPlaying()
        player.reasonForWaitingToPlay = .toMinimizeStalls
        player.timeControlStatus = .waitingToPlayAtSpecifiedRate
        drain()

        XCTAssertEqual(spy.states.last, .buffering)
    }

    func test_waitingWithNoItem_isIgnored() {
        loadAndMakeReady()
        player.reasonForWaitingToPlay = .noItemToPlay
        player.timeControlStatus = .waitingToPlayAtSpecifiedRate
        drain()

        XCTAssertEqual(spy.states, [.loading, .ready])
    }
}

// MARK: - Pause

final class PauseTests: EngineTestCase {

    func test_pauseWhilePlaying_reportsPaused() {
        loadAndStartPlaying()
        engine.pause()
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states.last, .paused)
    }

    func test_pauseWhileBuffering_reportsPaused() {
        loadAndStartPlaying()
        player.timeControlStatus = .waitingToPlayAtSpecifiedRate
        drain()
        engine.pause()
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(Array(spy.states.suffix(2)), [.buffering, .paused])
    }

    func test_pausedEvent_isIgnoredInIdle() {
        player.timeControlStatus = .paused
        drain()

        XCTAssertTrue(spy.events.isEmpty)
    }

    func test_pausedEvent_isIgnoredInLoading() {
        load()
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states, [.loading])
    }

    func test_pausedEvent_isIgnoredInReady() {
        loadAndMakeReady()
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states, [.loading, .ready])
    }

    func test_pausedEvent_afterFailure_isIgnored() {
        let item = loadAndStartPlaying()
        item.status = .failed
        drain()
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states.last, .idle)
    }
}

// MARK: - End of content

final class EndTests: EngineTestCase {

    func test_endNotification_reportsEnded() {
        loadAndFinishPlaying()

        XCTAssertEqual(spy.states.last, .ended)
    }

    func test_endNotification_ofReplacedItem_isIgnored() {
        let first = load()
        load(otherURL)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: first)
        drain()

        XCTAssertEqual(spy.states, [.loading])
    }

    func test_pausedAtEndOfItem_reportsEnded_notPaused() {
        let item = loadAndStartPlaying()
        item.duration = CMTime(seconds: 10, preferredTimescale: 600)
        player.fakeCurrentTime = CMTime(seconds: 10, preferredTimescale: 600)
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states.last, .ended)
        XCTAssertFalse(spy.states.contains(.paused))
    }

    func test_pausedBeforeEnd_reportsPaused() {
        let item = loadAndStartPlaying()
        item.duration = CMTime(seconds: 10, preferredTimescale: 600)
        player.fakeCurrentTime = CMTime(seconds: 3, preferredTimescale: 600)
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states.last, .paused)
    }

    func test_pausedEvent_afterEnded_isIgnored() {
        loadAndFinishPlaying()
        player.timeControlStatus = .paused
        drain()

        XCTAssertEqual(spy.states.last, .ended)
    }

    func test_pausedJustBeforeEnd_reportsPausedThenEnded_knownLimitation() {
        // The end check is an exact comparison: a pause a few ticks before the duration is a Paused
        let item = loadAndStartPlaying()
        item.duration = CMTime(seconds: 10, preferredTimescale: 600)
        player.fakeCurrentTime = CMTime(value: 5999, timescale: 600) // one tick short of 10 s
        player.timeControlStatus = .paused
        drain()
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        drain()

        XCTAssertEqual(Array(spy.states.suffix(2)), [.paused, .ended])
    }
}

// MARK: - Play and seek from Ended

final class EndedTransitionTests: EngineTestCase {

    func test_playFromEnded_seeksToStart_andPlaysOnlyAfterTheSeekFinished() {
        loadAndFinishPlaying()
        let playsBefore = player.playCount

        engine.play()

        XCTAssertEqual(player.seekTimes.last, CMTime.zero)
        XCTAssertEqual(player.playCount, playsBefore, "must wait for the seek")

        player.pendingSeekCompletion?(true)
        drain()

        XCTAssertEqual(player.playCount, playsBefore + 1)
    }

    func test_playFromEnded_withInterruptedSeek_doesNotPlay() {
        loadAndFinishPlaying()
        let playsBefore = player.playCount

        engine.play()
        player.pendingSeekCompletion?(false)
        drain()

        XCTAssertEqual(player.playCount, playsBefore)
    }

    func test_playFromEnded_thenPlayerPlays_leavesEnded() {
        loadAndFinishPlaying()

        engine.play()
        player.pendingSeekCompletion?(true)
        player.timeControlStatus = .waitingToPlayAtSpecifiedRate
        drain()
        player.timeControlStatus = .playing
        drain()

        XCTAssertEqual(Array(spy.states.suffix(3)), [.ended, .buffering, .playing])
    }

    func test_playFromEnded_pauseBeforeSeekFinishes_stillPlays_knownLimitation() {
        loadAndFinishPlaying()
        let playsBefore = player.playCount

        engine.play()
        engine.pause() // the player is already paused, so this does not cancel anything
        player.pendingSeekCompletion?(true)
        drain()

        XCTAssertEqual(player.playCount, playsBefore + 1)
    }

    func test_seekFromEnded_movesToPaused() {
        loadAndFinishPlaying()

        engine.seek(to: CMTime(seconds: 2, preferredTimescale: 600))

        XCTAssertEqual(spy.states.last, .paused)
        XCTAssertEqual(player.seekTimes.last, CMTime(seconds: 2, preferredTimescale: 600))
    }

    func test_seekFromEnded_toTheEnd_isPausedAtTheEnd_knownLimitation() {
        loadAndFinishPlaying(duration: 10)

        engine.seek(to: CMTime(seconds: 10, preferredTimescale: 600))

        XCTAssertEqual(spy.states.last, .paused)
    }

    func test_seekWhilePlaying_doesNotChangeState() {
        loadAndStartPlaying()
        let before = spy.states

        engine.seek(to: CMTime(seconds: 4, preferredTimescale: 600))
        drain()

        XCTAssertEqual(spy.states, before)
    }
}

// MARK: - Reload

final class ReloadTests: EngineTestCase {

    func test_reloadWhilePlaying_ignoresStalePlayerEventsWhileLoading() {
        loadAndStartPlaying()
        load(otherURL)

        // The previous playback is still running and reports events while the new item loads
        player.timeControlStatus = .playing
        drain()
        player.timeControlStatus = .waitingToPlayAtSpecifiedRate
        drain()

        XCTAssertEqual(spy.states.last, .loading)
    }

    func test_reloadWhilePlaying_catchesUpWithThePlayerWhenReady() {
        loadAndStartPlaying()
        let second = load(otherURL)
        player.timeControlStatus = .playing // the player kept its rate
        drain()

        second.status = .readyToPlay
        drain()

        XCTAssertEqual(Array(spy.states.suffix(3)), [.loading, .ready, .playing])
    }

    func test_reloadWhilePaused_staysReady() {
        loadAndMakeReady()
        let second = load(otherURL)
        second.status = .readyToPlay
        drain()

        XCTAssertEqual(Array(spy.states.suffix(2)), [.loading, .ready])
    }

    func test_queuedEventOfReplacedItem_isIgnored() {
        let first = load()
        first.status = .readyToPlay // queued by the engine, not handled yet
        load(otherURL)              // replaces the item before that event is handled
        drain()

        XCTAssertEqual(spy.states, [.loading])
    }

    func test_oldItemEvents_afterReload_doNotReachTheDelegate() {
        let first = load()
        load(otherURL)
        first.status = .failed
        drain()

        XCTAssertTrue(spy.errors.isEmpty)
    }
}

// MARK: - Buffered time

final class BufferedTimeTests: EngineTestCase {

    func test_loadedRange_withPlayhead_reportsItsEnd() {
        let item = loadAndMakeReady()
        player.fakeCurrentTime = CMTime(seconds: 2, preferredTimescale: 600)
        item.loadedTimeRanges = [range(0, 5)]
        drain()

        XCTAssertEqual(spy.bufferedTimes.count, 1)
        XCTAssertEqual(spy.bufferedTimes.first.map { CMTimeGetSeconds($0) }, 5)
    }

    func test_loadedRange_aheadOfPlayhead_reportsItsEnd() {
        let item = loadAndMakeReady()
        player.fakeCurrentTime = CMTime(seconds: 1, preferredTimescale: 600)
        item.loadedTimeRanges = [range(8, 12)]
        drain()

        XCTAssertEqual(spy.bufferedTimes.first.map { CMTimeGetSeconds($0) }, 12)
    }

    func test_playheadBeyondAllRanges_reportsNothing() {
        let item = loadAndMakeReady()
        player.fakeCurrentTime = CMTime(seconds: 20, preferredTimescale: 600)
        item.loadedTimeRanges = [range(0, 5)]
        drain()

        XCTAssertTrue(spy.bufferedTimes.isEmpty)
    }
}

// MARK: - Real AVPlayer

/// A smoke test with the real AVPlayer, to check that the fake behaves like it.
final class RealPlayerSmokeTests: XCTestCase {

    func test_realPlayer_missingFile_goesIdle_andReportsError() {
        let engine = AVPlayerEngine()
        let spy = SpyDelegate()
        engine.delegate = spy
        let failed = expectation(description: "failed")
        spy.onError = { _ in failed.fulfill() }

        engine.loadContent(URL(fileURLWithPath: "/definitely/not/here.mp4"))

        wait(for: [failed], timeout: 10)
        XCTAssertEqual(spy.events, [.state(.loading), .state(.idle), .error])
    }
}
