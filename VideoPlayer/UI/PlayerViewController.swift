//
//  PlayerViewController.swift
//  VideoPlayer
//

import UIKit
import RxSwift
import RxCocoa

/// Wires the engine, the view model and the view together.
@objc(PlayerViewController)
final class PlayerViewController: UIViewController {

    private let engine = AVPlayerEngine()
    private lazy var viewModel = PlayerViewModel(engine: engine)
    private let playerView = PlayerView()
    private let disposeBag = DisposeBag()

    override func loadView() {
        view = playerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let layer = engine.makePlayerLayer() {
            playerView.attach(layer)
        }
        bind()

        guard let url = contentURL() else {
            playerView.statusLabel.text = "sample.mp4 is missing from the bundle"
            return
        }
        // After bind(): the view model must subscribe to the engine before the first load
        viewModel.load(url)
    }

    /// The demo plays a network stream, so buffering can be seen (with a throttled network).
    /// Switch to `.local` to play the bundled sample.mp4 instead.
    private enum Source {
        case local
        case remote
    }

    private let source: Source = .remote

    // HLS example stream by Apple. It is served over https, so App Transport Security needs no exception.
    private static let remoteURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")

    private func contentURL() -> URL? {
        switch source {
        case .local:
            return Bundle.main.url(forResource: "sample", withExtension: "mp4")
        case .remote:
            return Self.remoteURL
        }
    }

    private func bind() {
        let slider = playerView.slider
        let output = viewModel.transform(
            PlayerViewModel.Input(
                playPauseTap: playerView.playButton.rx.tap.asObservable(),
                seek: slider.rx.value.asObservable()
            )
        )

        output.buttonTitle.drive(playerView.playButton.rx.title(for: .normal)).disposed(by: disposeBag)
        output.status.drive(playerView.statusLabel.rx.text).disposed(by: disposeBag)
        output.elapsed.drive(playerView.elapsedLabel.rx.text).disposed(by: disposeBag)
        output.total.drive(playerView.totalLabel.rx.text).disposed(by: disposeBag)
        output.controlsEnabled.drive(playerView.playButton.rx.isEnabled).disposed(by: disposeBag)
        output.controlsEnabled.drive(slider.rx.isEnabled).disposed(by: disposeBag)
        // The position must not jump under the finger while the user drags the slider
        output.progress
            .drive(onNext: { progress in
                if !slider.isTracking {
                    slider.value = progress
                }
            })
            .disposed(by: disposeBag)
    }
}
