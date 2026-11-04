//
//  PlayerEngine.h
//  VideoPlayer
//
//  Created by Игорь Постоев on 4. 11. 2026..
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Playback state of an engine.
typedef NS_ENUM(NSInteger, PlayerState) {
    /// Nothing is loaded yet, or loading failed (there is no separate failed state; the reason is
    /// delivered by engine:didFailWithError:, and the state is already Idle when it is called).
    PlayerStateIdle,
    /// Content is being loaded for the first time, until it is ready to play.
    PlayerStateLoading,
    /// Content is loaded and ready to play, but has not been played yet.
    PlayerStateReady,
    /// Playback is waiting for more data (buffering) after it was requested or started.
    PlayerStateBuffering,
    /// Content is playing.
    PlayerStatePlaying,
    /// Content is loaded and playback is paused.
    PlayerStatePaused,
    /// Playback reached the end of the content.
    PlayerStateEnded
};

/// Playback backend. Concrete engines (e.g. AVPlayerEngine, a mock for tests) conform to it.
/// THREADING: all methods must be called on the main thread. The engine is not thread safe.
@protocol PlayerEngine <NSObject>

/// Current playback position.
@property (nonatomic, readonly) CMTime currentTime;

/// Duration of the loaded content. It is not numeric (kCMTimeIndefinite) until the content is loaded.
@property (nonatomic, readonly) CMTime duration;

/// Loads the content at the given URL and prepares it for playback. Does not start playing.
/// Exception: when called while the content is playing, the player keeps playing, so the new content
/// starts by itself once it is ready (the state goes Loading, Ready, then Playing or Buffering).
/// A file or network URL that cannot be loaded is reported with engine:didFailWithError:.
/// @param url The location of the content. Must not be nil.
- (void) loadContent:(NSURL *)url;

/// Starts or resumes playback.
/// Ignored without any signal while nothing is loaded (Idle) or while the content is loading (Loading).
/// Call it after the engine reports PlayerStateReady.
/// Called in PlayerStateEnded, it seeks to the beginning and plays. This restart cannot be cancelled:
/// a pause or loadContent: called before the seek finishes is not honored, and playback still starts.
- (void) play;

/// Pauses playback.
- (void) pause;

/// Moves the playback position exactly to the given time, not to the nearest key frame.
/// Called in PlayerStateEnded, it moves the state to PlayerStatePaused. If the target is the end of the
/// content, the playhead stays at the end and a following play does nothing.
- (void) seekToTime:(CMTime)time;

@end

/// Receives events from a PlayerEngine.
/// THREADING: delegate methods are always called on the main thread, so a delegate can update UI directly.
/// NOTE: Events are delivered through a delegate protocol (required and optional methods) on purpose,
/// so every event is an explicit, documented call. Exposing KVO-observable properties instead would
/// also work.
@protocol PlayerEngineDelegate <NSObject>

/// Called when loading or playback fails. The engine is already in PlayerStateIdle when this is called,
/// so the delegate may start a new load from here.
///
/// RETRY: some errors are permanent (for example a missing file) and will fail again on every attempt.
/// The engine does not retry or limit retries; a client that retries from this callback must limit the
/// number of attempts (for example a retry limit with a backoff) and should not retry permanent errors.
///
/// Paused guard: AVPlayer drops to "paused" after an item ends or fails. The engine must not report
/// that as PlayerStatePaused, so a paused event is accepted only while the state is Playing or
/// Buffering. It is ignored in Idle (after a failure), Ended, Loading (e.g. a reload) and Ready.
/// Otherwise a broken, finished or reloading item would look like one the user paused.
/// @param engine The engine that failed.
/// @param error The reason of the failure.
- (void) engine:(id<PlayerEngine>)engine didFailWithError:(NSError *)error;

/// Called when the engine's playback state changes.
///
/// End of content: the end is detected from the end notification, or from a paused event while the
/// playhead is at the end. The check is an exact comparison, so at a natural end the delegate may see
/// PlayerStatePaused first and PlayerStateEnded right after it.
///
/// @param engine The engine whose state changed.
/// @param state The new state.
- (void) engine:(id<PlayerEngine>)engine didChangeState:(PlayerState)state;

@optional

/// Called when the buffered range changes.
/// Reports how far the buffer reaches: the end of the loaded range that contains the playhead
/// (or of the next loaded range ahead of it if the playhead is not buffered).
/// @param engine The engine that is buffering.
/// @param time The time up to which content is buffered.
- (void) engine:(id<PlayerEngine>)engine didUpdateBufferedTime:(CMTime)time;

@end

NS_ASSUME_NONNULL_END
