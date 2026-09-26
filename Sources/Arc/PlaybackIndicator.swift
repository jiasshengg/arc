import AppKit
import QuartzCore
import SwiftUI

/// Animate four tiny layers without asking SwiftUI to lay out every frame.
struct PlaybackIndicator: NSViewRepresentable {
    let playing: Bool
    let animating: Bool

    func makeNSView(context: Context) -> PlaybackBarsView { PlaybackBarsView() }

    func updateNSView(_ view: PlaybackBarsView, context: Context) {
        view.update(playing: playing, animating: animating)
    }

    static func dismantleNSView(_ view: PlaybackBarsView, coordinator: ()) {
        view.update(playing: false, animating: false)
    }
}

final class PlaybackBarsView: NSView {
    private let bars = (0..<4).map { _ in CALayer() }
    private var state: (playing: Bool, animating: Bool)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 16, height: 18))
        wantsLayer = true
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 2, height: 16)
            bar.position = CGPoint(x: 2 + index * 4, y: 9)
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { nil }

    func update(playing: Bool, animating: Bool) {
        guard state?.playing != playing || state?.animating != animating else { return }
        state = (playing, animating)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "playback")
            bar.backgroundColor = (playing ? NSColor.white : NSColor.gray).cgColor
            let height = playing ? 5 + 11 * abs(sin(Double(index) * 1.7)) : 4
            bar.setAffineTransform(CGAffineTransform(scaleX: 1, y: height / 16))
            if playing && animating {
                let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
                animation.values = (0...60).map { step in
                    (5 + 11 * abs(sin(Double(step) / 60 * 2 * .pi + Double(index) * 1.7))) / 16
                }
                animation.duration = 2 * .pi / 5
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                animation.repeatCount = .infinity
                bar.add(animation, forKey: "playback")
            }
        }
        CATransaction.commit()
    }
}
