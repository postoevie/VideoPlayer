//
//  PlayerEngine+Rx.swift
//  VideoPlayer
//

import AVFoundation
import RxSwift
import RxCocoa

extension Reactive where Base: AVPlayerEngine {

    /// Must be accessed on the main thread, before the first `loadContent:` (see the proxy).
    var delegate: RxPlayerEngineDelegateProxy {
        RxPlayerEngineDelegateProxy.proxy(for: base)
    }

    /// The playback state. Replays the last state to a new subscriber.
    var state: Observable<PlayerState> {
        delegate.stateSubject.asObservable().distinctUntilChanged()
    }

    /// Loading or playback failures. The engine is already in `.idle` when an error is emitted.
    var error: Observable<Error> {
        delegate.errorSubject.asObservable()
    }

    /// How far the buffer reaches from the playhead.
    var bufferedTime: Observable<CMTime> {
        delegate.bufferedTimeSubject.asObservable()
    }
}
