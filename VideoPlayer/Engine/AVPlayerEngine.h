//
//  AVPlayerEngine.h
//  VideoPlayer
//
//  Created by Игорь Постоев on 4. 11. 2026..
//

#import <Foundation/Foundation.h>
#import "PlayerEngine.h"
#import "PlaybackPlayer.h"

NS_ASSUME_NONNULL_BEGIN

@interface AVPlayerEngine: NSObject <PlayerEngine>

@property (nonatomic, weak) id <PlayerEngineDelegate> delegate;

/// Creates an engine on top of the given player. Used to replace AVPlayer with a fake in tests.
/// init uses a real AVPlayer.
- (instancetype)initWithPlayer:(NSObject<PlaybackPlayer> *)player NS_DESIGNATED_INITIALIZER;

/// Creates a layer that shows the video of this engine. Add it to a view; each call returns a new layer.
/// Returns nil when the engine does not run on a real AVPlayer (for example in tests).
/// Must be called on the main thread.
- (nullable AVPlayerLayer *)makePlayerLayer;

@end

NS_ASSUME_NONNULL_END
