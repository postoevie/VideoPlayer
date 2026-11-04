//
//  PlayerView.swift
//  VideoPlayer
//

import UIKit
import AVFoundation

/// The player screen: the video, a time slider with the elapsed and total time, a play/pause button and a
/// status label. It has no logic and no animations; a view model drives it.
final class PlayerView: UIView {

    let playButton = UIButton(type: .system)
    let slider = UISlider()
    let elapsedLabel = UILabel()
    let totalLabel = UILabel()
    let statusLabel = UILabel()

    private let videoContainer = UIView()
    private var videoLayer: AVPlayerLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    /// Shows the video of the given layer. A previously attached layer is removed.
    func attach(_ layer: AVPlayerLayer) {
        videoLayer?.removeFromSuperlayer()
        layer.videoGravity = .resizeAspect
        videoContainer.layer.addSublayer(layer)
        videoLayer = layer
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A sublayer animates its frame change by default
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.frame = videoContainer.bounds
        CATransaction.commit()
    }

    // MARK: Layout

    private func setUp() {
        backgroundColor = .systemBackground

        videoContainer.backgroundColor = .black
        videoContainer.translatesAutoresizingMaskIntoConstraints = false

        let timeFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        for label in [elapsedLabel, totalLabel] {
            label.font = timeFont
            label.textColor = .secondaryLabel
            label.text = "0:00"
        }
        totalLabel.textAlignment = .right

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        playButton.setTitle("Play", for: .normal)
        playButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)

        let timesRow = UIStackView(arrangedSubviews: [elapsedLabel, UIView(), totalLabel])
        timesRow.axis = .horizontal

        let controls = UIStackView(arrangedSubviews: [slider, timesRow, playButton, statusLabel])
        controls.axis = .vertical
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false

        addSubview(videoContainer)
        addSubview(controls)

        let guide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoContainer.heightAnchor.constraint(equalTo: videoContainer.widthAnchor, multiplier: 9.0 / 16.0),

            controls.topAnchor.constraint(equalTo: videoContainer.bottomAnchor, constant: 16),
            controls.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
        ])
    }
}
