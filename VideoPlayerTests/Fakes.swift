//
//  Fakes.swift
//  VideoPlayerTests
//
//  Fakes of AVPlayer and AVPlayerItem for AVPlayerEngine tests. The tests drive them by setting the
//  properties. The properties the engine observes are `@objc dynamic`, so they are KVO compliant,
//  like the real ones.
//

import AVFoundation
import VideoPlayerEngine

final class FakeItem: NSObject, PlaybackItem {
    @objc dynamic var status: AVPlayerItem.Status = .unknown
    @objc dynamic var loadedTimeRanges: [NSValue] = []
    @objc var duration: CMTime = .indefinite
    @objc var error: Error?

    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }
}

final class FakePlayer: NSObject, PlaybackPlayer {
    // Driven by the test
    @objc dynamic var timeControlStatus: AVPlayer.TimeControlStatus = .paused
    @objc dynamic var currentItem: PlaybackItem?
    @objc var reasonForWaitingToPlay: AVPlayer.WaitingReason?
    var fakeCurrentTime: CMTime = .zero

    // Recorded calls
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var seekTimes: [CMTime] = []
    private(set) var madeItems: [FakeItem] = []

    /// Completion handler of the last seek with a completion handler, to finish the seek from the test
    var pendingSeekCompletion: ((Bool) -> Void)?

    func currentTime() -> CMTime {
        fakeCurrentTime
    }

    func play() {
        playCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        seekTimes.append(time)
    }

    func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        seekTimes.append(time)
        pendingSeekCompletion = completionHandler
    }

    func makeItem(with url: URL) -> PlaybackItem {
        let item = FakeItem(url: url)
        madeItems.append(item)
        return item
    }

    func replaceCurrentItem(_ item: PlaybackItem?) {
        // Like the real player, this changes currentItem through KVO
        currentItem = item
    }
}
