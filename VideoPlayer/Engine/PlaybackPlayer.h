//
//  PlaybackPlayer.h
//  VideoPlayer
//
//  Seam between AVPlayerEngine and AVFoundation. The engine talks to these protocols only, so a test can
//  replace AVPlayer and AVPlayerItem with fakes. AVPlayer and AVPlayerItem conform through categories.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The part of AVPlayerItem that the engine reads. All properties must be KVO compliant.
@protocol PlaybackItem <NSObject>

@property (nonatomic, readonly) AVPlayerItemStatus status;
@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly) CMTime duration;
@property (nonatomic, readonly) NSArray<NSValue *> *loadedTimeRanges;

@end

/// The part of AVPlayer that the engine uses. timeControlStatus and currentItem must be KVO compliant.
@protocol PlaybackPlayer <NSObject>

@property (nonatomic, readonly) AVPlayerTimeControlStatus timeControlStatus;
@property (nonatomic, readonly, nullable) AVPlayerWaitingReason reasonForWaitingToPlay;
@property (nonatomic, readonly, nullable) NSObject<PlaybackItem> *currentItem;

- (CMTime)currentTime;
- (void)play;
- (void)pause;
- (void)seekToTime:(CMTime)time completionHandler:(void (^)(BOOL finished))completionHandler;
- (void)seekToTime:(CMTime)time toleranceBefore:(CMTime)toleranceBefore toleranceAfter:(CMTime)toleranceAfter;

/// Creates an item for the content at the URL. The item is not attached to the player yet.
- (NSObject<PlaybackItem> *)makeItemWithURL:(NSURL *)url;
/// Makes the item (or nil) the current one.
- (void)replaceCurrentItem:(nullable NSObject<PlaybackItem> *)item;

@end

@interface AVPlayerItem (PlaybackItem) <PlaybackItem>
@end

@interface AVPlayer (PlaybackPlayer) <PlaybackPlayer>
@end

NS_ASSUME_NONNULL_END
