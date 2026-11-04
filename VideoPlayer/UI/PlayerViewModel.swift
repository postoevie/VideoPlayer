//
//  PlayerViewModel.swift
//  VideoPlayer
//

import AVFoundation
import RxSwift
import RxCocoa

extension PlayerState {

    /// The player is playing or trying to play, so a tap on the button should pause it.
    var isActive: Bool {
        self == .playing || self == .buffering
    }

    /// The content is loaded, so the controls make sense.
    var isLoaded: Bool {
        switch self {
        case .ready, .buffering, .playing, .paused, .ended: return true
        default: return false
        }
    }
}

/// Turns the engine events into what the player view shows, and the view input into engine calls.
/// Everything runs on the main thread, like the engine.
final class PlayerViewModel {

    struct Input {
        let playPauseTap: Observable<Void>
        /// The slider position, 0...1
        let seek: Observable<Float>
    }

    struct Output {
        let buttonTitle: Driver<String>
        let status: Driver<String>
        let elapsed: Driver<String>
        let total: Driver<String>
        /// 0...1
        let progress: Driver<Float>
        let controlsEnabled: Driver<Bool>
    }

    private let engine: AVPlayerEngine
    private let disposeBag = DisposeBag()

    init(engine: AVPlayerEngine) {
        self.engine = engine
    }

    func load(_ url: URL) {
        engine.loadContent(url)
    }

    /// Subscribes to the engine first, so call it before `load(_:)`.
    func transform(_ input: Input) -> Output {
        let engine = self.engine
        let state = engine.rx.state

        // Button taps toggle by the latest state
        input.playPauseTap
            .withLatestFrom(state)
            .subscribe(onNext: { state in
                if state.isActive {
                    engine.pause()
                } else {
                    engine.play()
                }
            })
            .disposed(by: disposeBag)

        // The slider is a stream of values; a seek per value would flood the player
        input.seek
            .throttle(.milliseconds(100), latest: true, scheduler: MainScheduler.instance)
            .distinctUntilChanged()
            .subscribe(onNext: { position in
                let duration = engine.duration
                guard duration.isNumeric, duration.seconds > 0 else { return }
                engine.seek(to: CMTime(seconds: Double(position) * duration.seconds, preferredTimescale: 600))
            })
            .disposed(by: disposeBag)

        let buttonTitle = state
            .map { $0.isActive ? "Pause" : "Play" }
            .asDriver(onErrorJustReturn: "Play")

        // A failure ends in .idle, then the error arrives, so the error text stays last
        let status = Observable.merge(
            state.map(Self.statusText),
            engine.rx.error.map { "Error: \($0.localizedDescription)" }
        ).asDriver(onErrorJustReturn: "")

        let controlsEnabled = state
            .map { $0.isLoaded }
            .asDriver(onErrorJustReturn: false)

        // The player has no time callback, so the position is polled while it plays
        let ticks = state
            .map { $0.isActive }
            .distinctUntilChanged()
            .flatMapLatest { active -> Observable<Void> in
                active
                    ? Observable<Int>.interval(.milliseconds(250), scheduler: MainScheduler.instance).map { _ in () }
                    : .empty()
            }
        let refresh = Observable.merge(state.map { _ in () }, ticks, input.seek.map { _ in () })

        let times = refresh
            .map { _ -> (current: Double, duration: Double) in
                (Self.seconds(engine.currentTime), Self.seconds(engine.duration))
            }
            .share(replay: 1, scope: .whileConnected)

        return Output(
            buttonTitle: buttonTitle,
            status: status,
            elapsed: times.map { Self.format($0.current) }.asDriver(onErrorJustReturn: "0:00"),
            total: times.map { Self.format($0.duration) }.asDriver(onErrorJustReturn: "0:00"),
            progress: times.map { Self.progress(current: $0.current, duration: $0.duration) }
                .asDriver(onErrorJustReturn: 0),
            controlsEnabled: controlsEnabled
        )
    }

    // MARK: Formatting

    static func statusText(_ state: PlayerState) -> String {
        switch state {
        case .idle: return "Idle"
        case .loading: return "Loading…"
        case .ready: return "Ready"
        case .buffering: return "Buffering…"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .ended: return "Ended"
        @unknown default: return ""
        }
    }

    /// Seconds of a time, 0 when the time is not a number yet (for example the duration before loading)
    static func seconds(_ time: CMTime) -> Double {
        time.isNumeric && time.seconds.isFinite ? max(time.seconds, 0) : 0
    }

    static func progress(current: Double, duration: Double) -> Float {
        guard duration > 0 else { return 0 }
        return Float(min(max(current / duration, 0), 1))
    }

    /// m:ss
    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
