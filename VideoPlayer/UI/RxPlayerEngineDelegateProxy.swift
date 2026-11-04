//
//  RxPlayerEngineDelegateProxy.swift
//  VideoPlayer
//

import AVFoundation
import RxSwift
import RxCocoa

/// Exposes the Objective-C `PlayerEngineDelegate` of an `AVPlayerEngine` as Rx streams.
///
/// The engine keeps its delegate weakly. RxCocoa installs this proxy as the delegate and retains it for the
/// lifetime of the engine. A delegate that was set before is kept and still receives every call.
final class RxPlayerEngineDelegateProxy: DelegateProxy<AVPlayerEngine, PlayerEngineDelegate>,
                                         DelegateProxyType,
                                         PlayerEngineDelegate {

    /// Replays the last state to a late subscriber. The engine has no state getter, so the proxy must be
    /// created before the first `loadContent:`, otherwise state changes that already happened are missed.
    let stateSubject = BehaviorSubject<PlayerState>(value: .idle)
    let errorSubject = PublishSubject<Error>()
    let bufferedTimeSubject = PublishSubject<CMTime>()

    init(engine: AVPlayerEngine) {
        super.init(parentObject: engine, delegateProxy: RxPlayerEngineDelegateProxy.self)
    }

    static func registerKnownImplementations() {
        register { RxPlayerEngineDelegateProxy(engine: $0) }
    }

    static func currentDelegate(for object: AVPlayerEngine) -> PlayerEngineDelegate? {
        object.delegate
    }

    static func setCurrentDelegate(_ delegate: PlayerEngineDelegate?, to object: AVPlayerEngine) {
        object.delegate = delegate
    }

    // MARK: PlayerEngineDelegate

    func engine(_ engine: PlayerEngine, didChange state: PlayerState) {
        stateSubject.onNext(state)
        _forwardToDelegate?.engine(engine, didChange: state)
    }

    func engine(_ engine: PlayerEngine, didFailWithError error: Error) {
        errorSubject.onNext(error)
        _forwardToDelegate?.engine(engine, didFailWithError: error)
    }

    func engine(_ engine: PlayerEngine, didUpdateBufferedTime time: CMTime) {
        bufferedTimeSubject.onNext(time)
        _forwardToDelegate?.engine?(engine, didUpdateBufferedTime: time)
    }
}
