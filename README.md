# VideoPlayer

A small iOS video playback engine written in Objective-C. It plays a video through an `AVPlayer`-based engine that is hidden behind a protocol, turns the low-level `AVPlayer` events into one simple playback state, and reports state changes, errors and buffering to a delegate.

## Status

The engine covers loading, playback control, state tracking and error reporting, and it is covered by unit tests. The app is a small demo player built on it: a Swift and UIKit screen with a view model on RxSwift (`PlayerViewModel`), which plays a bundled 8 second test clip.

## Requirements

- iOS 13 or later
- Xcode (the project is built and tested with Xcode 26)
- Content to play: a file or network URL passed to `loadContent:`
- The demo screen uses [RxSwift](https://github.com/ReactiveX/RxSwift) 6, added through Swift Package Manager. The engine itself does not depend on it.

## Installation

There is no package yet. Copy the files from `VideoPlayer/Engine/` into your project:

- `PlayerEngine.h`
- `AVPlayerEngine.h`, `AVPlayerEngine.m`
- `PlaybackPlayer.h`, `PlaybackPlayer.m`

`module.modulemap` is only needed to import the headers from Swift as a module.

## Usage

```objc
#import "AVPlayerEngine.h"

@interface Controller () <PlayerEngineDelegate>
@property (nonatomic, strong) AVPlayerEngine *engine;
@end

@implementation Controller

- (void)start:(NSURL *)url {
    self.engine = [[AVPlayerEngine alloc] init];
    self.engine.delegate = self;
    [self.engine loadContent:url];
}

- (void)engine:(id<PlayerEngine>)engine didChangeState:(PlayerState)state {
    if (state == PlayerStateReady) {
        [engine play];
    }
}

- (void)engine:(id<PlayerEngine>)engine didFailWithError:(NSError *)error {
    NSLog(@"Playback failed: %@", error);
}

@end
```

All engine methods must be called on the main thread, and all delegate methods are called on the main thread.

## Engine

`PlayerEngine` is the playback backend protocol:

| Member | Purpose |
| --- | --- |
| `currentTime` | Current playback position |
| `duration` | Duration of the loaded content, indefinite until it is loaded |
| `loadContent:` | Loads the content at a URL and prepares it for playback. Does not start playing |
| `play` / `pause` | Start or resume, and pause playback |
| `seekToTime:` | Move the playback position |

`AVPlayerEngine` implements it with a single `AVPlayer` that is reused across loads. It watches the player and the current item with KVO and notifications, and turns what it sees into state changes. `makePlayerLayer` on `AVPlayerEngine` returns an `AVPlayerLayer` that shows the video. See [`VideoPlayer/Engine/README.md`](VideoPlayer/Engine/README.md) for the state machine, the transitions and the known limits.

## Delegate

`PlayerEngineDelegate` receives events from the engine:

- `engine:didChangeState:` (required): the playback state changed.
- `engine:didFailWithError:` (required): loading or playback failed. The engine is already in `Idle` when it is called.
- `engine:didUpdateBufferedTime:` (optional): how far the buffer reaches from the playhead.

## States

| State | Meaning |
| --- | --- |
| `Idle` | Nothing is loaded, or loading failed |
| `Loading` | Content is loading for the first time |
| `Ready` | Loaded and ready to play, not played yet |
| `Buffering` | Waiting for more data |
| `Playing` | Playing |
| `Paused` | Paused after playing or buffering |
| `Ended` | Playback reached the end |

There is no separate failed state. A failure puts the engine in `Idle` and is then reported once through `engine:didFailWithError:`.

## Demo app

`PlayerViewController` wires an `AVPlayerEngine`, a `PlayerViewModel` and a `PlayerView` together.

- `RxPlayerEngineDelegateProxy` is a RxCocoa `DelegateProxy` over the Objective-C delegate. `engine.rx.state`, `engine.rx.error` and `engine.rx.bufferedTime` are streams built on it.
- `PlayerViewModel` turns the input (button taps, slider values) into engine calls and the engine events into what the view shows: the button title and the status text come from the state, the slider and the time labels from the state, the position and the duration (`combineLatest` of the streams), a seek goes through `throttle` and `distinctUntilChanged`, and a tap uses `withLatestFrom(state)` to toggle.
- `PlayerView` is a plain UIKit view with no logic and no animations.

## Testing

`AVPlayerEngine` talks to AVFoundation only through the `PlaybackPlayer` and `PlaybackItem` protocols. The tests replace `AVPlayer` and `AVPlayerItem` with fakes (`VideoPlayerTests/Fakes.swift`), so the state machine is tested without video, timing or network. `AVPlayerEngine` has a second initializer, `initWithPlayer:`, for this.

Run the tests on a simulator:

```sh
xcrun simctl list devices available   # pick a simulator
xcodebuild -project VideoPlayer.xcodeproj -scheme VideoPlayer \
  -destination 'platform=iOS Simulator,name=<simulator name>' test
```

Tests that document accepted limitations have `knownLimitation` in their names.

## Project structure

```
VideoPlayer/
  Engine/
    PlayerEngine.h        PlayerState enum, PlayerEngine and PlayerEngineDelegate protocols
    AVPlayerEngine.h/.m   PlayerEngine implementation built on AVPlayer
    PlaybackPlayer.h/.m   Protocols over AVPlayer and AVPlayerItem (the test seam)
    module.modulemap      Module for importing the headers from Swift
  UI/
    RxPlayerEngineDelegateProxy.swift   Delegate proxy over PlayerEngineDelegate
    PlayerEngine+Rx.swift               engine.rx.state, .error, .bufferedTime
    PlayerViewModel.swift               View model (RxSwift)
    PlayerView.swift                    Player view (UIKit)
    PlayerViewController.swift          Wires the engine, the view model and the view
  Resources/sample.mp4    8 second generated test clip
VideoPlayerTests/
  AVPlayerEngineTests.swift   State machine tests
  Fakes.swift                 Fake player and item
```

## License

MIT. See [`LICENSE`](LICENSE).
