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

        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp4") else {
            playerView.statusLabel.text = "sample.mp4 is missing from the bundle"
            return
        }
        // After bind(): the view model must subscribe to the engine before the first load
        viewModel.load(url)
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
