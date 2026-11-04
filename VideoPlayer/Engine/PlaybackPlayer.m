//
//  PlaybackPlayer.m
//  VideoPlayer
//

#import "PlaybackPlayer.h"

@implementation AVPlayerItem (PlaybackItem)
@end

@implementation AVPlayer (PlaybackPlayer)

- (NSObject<PlaybackItem> *)makeItemWithURL:(NSURL *)url {
    return [AVPlayerItem playerItemWithURL:url];
}

- (void)replaceCurrentItem:(NSObject<PlaybackItem> *)item {
    // Only items made by makeItemWithURL: are expected here
    [self replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item];
}

@end
