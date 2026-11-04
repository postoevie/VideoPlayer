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

@end

NS_ASSUME_NONNULL_END
