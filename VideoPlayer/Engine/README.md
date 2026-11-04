# Engine

The playback layer of the app. It hides the video backend behind the `PlayerEngine` protocol and reports what happens to a `PlayerEngineDelegate`.

## What it does

- Loads a video and prepares it for playback (`loadContent:`), then plays, pauses and seeks it.
- Turns the low-level events of `AVPlayer` (item status, time control status, loaded time ranges, end of playback) into one simple `PlayerState`.
- Reports every state change, every failure with its `NSError`, and how far the video is buffered.
- Reuses one `AVPlayer` for all loads. Only the `AVPlayerItem` is replaced.

## Files

| File | Role |
| --- | --- |
| `PlayerEngine.h` | `PlayerState` enum, `PlayerEngine` and `PlayerEngineDelegate` protocols |
| `AVPlayerEngine.h/.m` | `PlayerEngine` implementation built on `AVPlayer` |

## State machine

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle --> Loading: loadContent
    Loading --> Ready: item ready to play
    Loading --> Idle: item failed (Idle, then didFailWithError:)

    Ready --> Playing: play (enough data)
    Ready --> Buffering: play (waiting for data)

    Buffering --> Playing: enough data
    Playing --> Buffering: buffer ran out
    Playing --> Paused: pause
    Buffering --> Paused: pause
    Paused --> Playing: play (enough data)
    Paused --> Buffering: play (waiting for data)

    Playing --> Ended: item finished
    Buffering --> Ended: item finished

    Ended --> Playing: play (restarts from the beginning)
    Ended --> Buffering: play (waiting for data)
    Ended --> Paused: seekToTime:

    Ready --> Loading: loadContent
    Playing --> Loading: loadContent
    Buffering --> Loading: loadContent
    Paused --> Loading: loadContent
    Ended --> Loading: loadContent
```

`loadContent` from any state other than `Idle` starts a reload, so all of them lead back to `Loading`. They are listed separately above only to keep the diagram readable.

### Transitions

| From | To | Trigger |
| --- | --- | --- |
| `Idle` | `Loading` | `loadContent` |
| `Loading` | `Ready` | The item becomes ready to play |
| `Loading` | `Idle` | The item fails. The state goes to `Idle` first, then `engine:didFailWithError:` is called, so the delegate may retry from the callback |
| `Ready` | `Playing` / `Buffering` | `play`, depending on whether enough data is buffered |
| `Buffering` | `Playing` | Enough data is buffered |
| `Playing` | `Buffering` | The buffer runs out |
| `Playing`, `Buffering` | `Paused` | `pause` |
| `Paused` | `Playing` / `Buffering` | `play` |
| `Playing`, `Buffering` | `Ended` | The item plays to its end. The end is detected by the end notification, or by a paused event while the playhead is at the end of the item |
| `Ended` | `Playing` / `Buffering` | `play`: seeks to the beginning and plays |
| `Ended` | `Paused` | `seekToTime:`. The item is loaded and sits at the new position |
| any except `Idle` | `Loading` | `loadContent` (reload) |

### Paused guard

`AVPlayer` also drops to "paused" when an item ends, fails, or is replaced. The engine accepts a paused event only while the state is `Playing` or `Buffering`, so none of these cases is reported as a user pause.

### Known limits

- The end check compares `currentTime` with the item duration exactly. If the paused event arrives a few ticks before the playhead reaches the end, `Paused` is reported first and `Ended` follows from the end notification.
- `play` is ignored in `Idle` and `Loading`. In the other states it is forwarded to the player, so a `play` right after a `pause` is not dropped, even though the state has not changed yet.
- After a reload while playing, the player keeps its rate, so the new item starts by itself once it is ready. The state goes `Loading`, `Ready`, then `Playing` or `Buffering`, because the engine re-syncs with the player when the item becomes ready.
- The engine is main-thread only. Its methods must be called on the main thread, and delegate calls are made on the main thread. Player events can arrive on any thread; the engine always hands them to the main queue asynchronously, so they are handled in order and never nested inside a delegate callback (for example a retry from `didFailWithError:`). Because of that hop, the state changes slightly after the player does.
