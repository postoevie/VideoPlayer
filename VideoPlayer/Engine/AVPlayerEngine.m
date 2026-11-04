//
//  AVPlayerEngine.m
//  VideoPlayer
//
//  Created by Игорь Постоев on 4. 11. 2026..
//

#import <AVFoundation/AVFoundation.h>
#import "AVPlayerEngine.h"

// NOTE: Delegate calls are intentionally not nil-guarded. Messaging nil is a no-op in ObjC,
// and the required delegate methods don't need a respondsToSelector: check.

// THREADING: the engine is main-thread only. Public methods must be called on the main thread, and every
// delegate call is made on the main thread. Player events (KVO, notifications) may arrive on any thread;
// they are always handed over to the main queue asynchronously, so they are handled in order and never
// nested inside the caller (for example inside a delegate callback that retries loadContent).

@interface AVPlayerEngine() // Anonymous category

@property (nonatomic, strong) NSObject<PlaybackPlayer> *player;
@property (nonatomic, assign) PlayerState state;

@end

// Use their own address as unique identifier. These are needed to distinct player and player item events
static void *PlayerCtx = &PlayerCtx;
static void *ItemCtx = &ItemCtx;

@implementation AVPlayerEngine

- (instancetype)init
{
    return [self initWithPlayer:[[AVPlayer alloc] init]];
}

- (instancetype)initWithPlayer:(NSObject<PlaybackPlayer> *)player
{
    self = [super init];
    if (self) {
        _state = PlayerStateIdle;
        self.player = player;
        // No Initial option: a fresh player is already Paused, which must not be reported
        [self.player addObserver:self
                      forKeyPath:@"timeControlStatus"
                         options:NSKeyValueObservingOptionNew
                         context:PlayerCtx];
    }
    return self;
}

- (CMTime)currentTime {
    return [self.player currentTime];
}

- (void)assertMainThread {
    NSAssert([NSThread isMainThread], @"AVPlayerEngine must be used on the main thread");
}

- (void)loadContent:(NSURL *)url {
    [self assertMainThread];
    NSParameterAssert(url);
    NSObject<PlaybackItem> *oldItem = self.player.currentItem;
    if (oldItem) {
        [oldItem removeObserver:self forKeyPath:@"status" context:ItemCtx];
        [oldItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:ItemCtx];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:oldItem];
    }
    NSObject<PlaybackItem> *playerItem = [self.player makeItemWithURL:url];
    [playerItem addObserver:self
                 forKeyPath:@"status"
                    options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                    context:ItemCtx];
    [playerItem addObserver:self
                 forKeyPath:@"loadedTimeRanges"
                    options:NSKeyValueObservingOptionNew
                    context:ItemCtx];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];
    [self.player replaceCurrentItem:playerItem];
    // After the replace, so a delegate that calls back from didChangeState: sees a consistent engine.
    // Player events are handed to the main queue asynchronously, so they are handled after this state is set.
    self.state = PlayerStateLoading;
}

- (void)itemDidFinish:(NSNotification *)note {
    NSObject<PlaybackItem> *item = note.object;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Ignore a stale notification of an item that was replaced while this block was queued
        if (item != self.player.currentItem) {
            return;
        }
        self.state = PlayerStateEnded;
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    // KVO can arrive on any thread; hand it over to the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        if (context == ItemCtx) {
            NSObject<PlaybackItem> *item = object;
            // Ignore a stale event of an item that was replaced while this block was queued
            if (item != self.player.currentItem) {
                return;
            }
            if ([keyPath isEqualToString:@"status"]) {
                AVPlayerItemStatus status = item.status;
                if (self.state == PlayerStateLoading && status == AVPlayerItemStatusReadyToPlay) {
                    self.state = PlayerStateReady;
                    // Events were ignored while loading; if the player is already running (a reload while
                    // playing keeps its rate), catch up so the state does not stay Ready during playback
                    [self handleTimeControlStatus:self.player];
                } else if (status == AVPlayerItemStatusFailed) {
                    // Use it as signal playback is failed instead of AVPlayerItemFailedToPlayToEndTimeNotification
                    // item.error should be set for a failed item, but never pass nil to a required delegate method
                    NSError *error = item.error ?: [NSError errorWithDomain:AVFoundationErrorDomain
                                                                       code:AVErrorUnknown
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"The item failed to load"}];
                    // Idle first, so a delegate that retries from the callback is not overwritten by a late Idle
                    self.state = PlayerStateIdle;
                    [self.delegate engine:self didFailWithError:error];
                }
                // Unknown state is not handled intentionally.
            } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
                [self notifyBufferedTimeForItem:item];
            }
        } else if (context == PlayerCtx) {
            [self handleTimeControlStatus:self.player];
        } else {
            [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        }
    });
}

- (void)handleTimeControlStatus:(NSObject<PlaybackPlayer> *)player {
    // While the item is loading, the player events belong to the previous playback (e.g. a reload while
    // playing) and must not overwrite Loading. The state is re-synced with the player once the item is ready.
    // In Idle (nothing loaded, or loading failed) no playback was requested, so the events are ignored too.
    if (self.state == PlayerStateLoading || self.state == PlayerStateIdle) {
        return;
    }
    switch (player.timeControlStatus) {
        case AVPlayerTimeControlStatusPlaying:
            self.state = PlayerStatePlaying;
            break;
        case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
            // Waiting with no item is a usage error, not buffering
            if (![player.reasonForWaitingToPlay isEqualToString:AVPlayerWaitingWithNoItemToPlayReason]) {
                self.state = PlayerStateBuffering;
            }
            break;
        case AVPlayerTimeControlStatusPaused:
            // Paused guard (see PlayerEngineDelegate docs): only a playing or buffering player can be paused.
            // Ignores the drop to Paused after a failure (Idle), the end, or a reload (Loading)
            if (self.state == PlayerStatePlaying || self.state == PlayerStateBuffering) {
                // The drop to Paused at the end of the item can arrive before the end notification,
                // so a pause at the end of the item is the end, not a user pause
                self.state = [self isAtEndOfItem:player.currentItem] ? PlayerStateEnded : PlayerStatePaused;
            }
            break;
    }
}

- (BOOL)isAtEndOfItem:(NSObject<PlaybackItem> *)item {
    CMTime duration = item.duration;
    // Duration is not numeric until the item is loaded (or for live streams)
    if (!item || !CMTIME_IS_NUMERIC(duration)) {
        return NO;
    }
    // Accepted limitation: this is an exact comparison. At a natural end the paused event can arrive
    // a few ticks before currentTime reaches duration; then Paused is reported and the end notification
    // is expected to follow with Ended.
    return CMTimeCompare(self.player.currentTime, duration) >= 0;
}

// Single point where state changes are published to the delegate
- (void)setState:(PlayerState)state {
    if (_state == state) {
        return;
    }
    _state = state;
    [self.delegate engine:self didChangeState:state];
}

- (void)notifyBufferedTimeForItem:(NSObject<PlaybackItem> *)item {
    if (![self.delegate respondsToSelector:@selector(engine:didUpdateBufferedTime:)]) {
        return;
    }
    CMTime current = self.player.currentTime;
    for (NSValue *value in item.loadedTimeRanges) {
        CMTimeRange range = value.CMTimeRangeValue;
        if (CMTimeRangeContainsTime(range, current) || CMTimeCompare(range.start, current) > 0) {
            [self.delegate engine:self didUpdateBufferedTime:CMTimeRangeGetEnd(range)];
            return;
        }
    }
}

- (void)pause {
    [self assertMainThread];
    [self.player pause];
}

- (void)play {
    [self assertMainThread];
    // Attempt to play after loading is ignored intentionally
    if (self.state == PlayerStateIdle || self.state == PlayerStateLoading) {
        return;
    }
    // The state changes when the player event is handled, which is one hop to the main queue after the
    // player changed, so a play right after a pause can still see Playing. Playing a player that is
    // already playing is a no-op, so the remaining states are not filtered and the request is never dropped.
    if (self.state == PlayerStateEnded) {
        // Play only after the seek to the beginning is done, otherwise play races with the seek.
        // finished is NO when another seek interrupted this one; that seek wins and no play is started.
        // Accepted limitation: this play cannot be cancelled. A pause or loadContent: called before the seek
        // finishes is not honored, because the player is already paused and the play still fires afterwards.
        [self.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
            // The completion handler can be called on any queue
            dispatch_async(dispatch_get_main_queue(), ^{
                if (finished) {
                    [self.player play];
                }
            });
        }];
        return;
    }
    [self.player play];
}

- (void)seekToTime:(CMTime)time {
    [self assertMainThread];
    [self.player seekToTime:time];
    // After the end the player is paused and sends no event on a seek, so leave Ended manually.
    // Other states are updated by the player events (e.g. a seek while playing may start buffering).
    // Accepted limitation: if the seek target is the end of the item, the state becomes Paused
    // but the player is still at the end, so a following play does nothing.
    if (self.state == PlayerStateEnded) {
        self.state = PlayerStatePaused;
    }
}

- (void)dealloc {
    [self.player removeObserver:self forKeyPath:@"timeControlStatus" context:PlayerCtx];
    NSObject<PlaybackItem> *item = self.player.currentItem;
    if (item) {
        [item removeObserver:self forKeyPath:@"status" context:ItemCtx];
        [item removeObserver:self forKeyPath:@"loadedTimeRanges" context:ItemCtx];
    }
}

@end
