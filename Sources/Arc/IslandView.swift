import SwiftUI
import ArcCore

struct IslandView: View {
    let coordinator: IslandCoordinator
    var onSizeChange: (CGSize) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var model: IslandModel { coordinator.model }
    private let accent = Color.white
    private let chargingGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)

    private var attached: Bool { model.notchSize.height > 0 }
    private var activityTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
    private var size: CGSize {
        if model.showsPocket {
            return IslandLayout.pocketSize(expanded: model.expanded, count: model.pocket.islandItems.count,
                                           receiving: model.receivingFiles, notch: model.notchSize)
        }
        if model.screenshotCopied {
            return IslandLayout.activitySize(expanded: model.expanded, notch: model.notchSize)
        }
        if model.activity != nil {
            return IslandLayout.activitySize(expanded: model.expanded, notch: model.notchSize)
        }
        return IslandLayout.size(expanded: model.expanded, hasMedia: model.media.snapshot != nil, notch: model.notchSize)
    }
    private var outline: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: attached ? 0 : (model.expanded ? 24 : 20),
            bottomLeadingRadius: model.expanded ? 24 : (attached ? 12 : 20),
            bottomTrailingRadius: model.expanded ? 24 : (attached ? 12 : 20),
            topTrailingRadius: attached ? 0 : (model.expanded ? 24 : 20), style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if model.showsPocket {
                if model.expanded {
                    Group {
                        if model.receivingFiles {
                            VStack(spacing: 8) {
                                Image(systemName: "tray.and.arrow.down").font(.system(size: 24))
                                Text(model.dropMessage).font(.system(size: 13, weight: .medium))
                                Text("Files and folders · References only").font(.system(size: 10)).foregroundStyle(.gray)
                            }.frame(height: 100)
                        } else { PocketView(model: model, onOpenPocket: coordinator.showPocket) }
                    }
                    .frame(width: max(380, model.notchSize.width + 88))
                    .padding(.top, model.notchSize.height)
                    .transition(.opacity)
                } else {
                    HStack(spacing: 0) {
                        Image(systemName: "doc.on.doc.fill").frame(width: 44)
                        if attached { Color.clear.frame(width: model.notchSize.width) }
                        else { Text("Pocket").font(.system(size: 12, weight: .medium)); Spacer() }
                        Text("\(model.pocket.items.count)").font(.system(size: 12, weight: .semibold)).frame(width: 44)
                    }.frame(width: size.width, height: size.height)
                    .accessibilityLabel("Pocket, \(model.pocket.items.count) held items")
                }
            } else if model.screenshotCopied {
                if model.expanded {
                    screenshotView
                        .padding(.top, model.notchSize.height)
                        .transition(activityTransition)
                } else {
                    compactScreenshotView
                        .frame(width: size.width, height: size.height)
                        .transition(activityTransition)
                }
            } else if let activity = model.activity {
                if model.expanded {
                    activityView(activity)
                        .padding(.top, model.notchSize.height)
                        .transition(activityTransition)
                } else {
                    compactActivityView(activity)
                        .frame(width: size.width, height: size.height)
                        .transition(activityTransition)
                }
            } else if model.expanded {
                Group {
                    if let track = model.media.snapshot { expanded(track) }
                    else { empty.frame(height: 100) }
                }
                // Keep full-size content stable while the surrounding shape opens.
                .frame(width: max(380, model.notchSize.width + 88))
                .padding(.top, model.notchSize.height)
                .transition(.opacity)
            } else {
                compact.frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: model.activity)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: model.screenshotCopied)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black, in: outline)
        .foregroundStyle(.white)
        .clipShape(outline)
        .overlay { outline.strokeBorder(.white.opacity(attached ? 0 : 0.10), lineWidth: 0.5) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: model.expanded ? 0.42 : 0.28, dampingFraction: 0.88), value: size)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arc island")
        .accessibilityAction(named: "Expand island") { model.hover(true) }
        .accessibilityAction(named: "Collapse island") { model.collapse() }
        .preferredColorScheme(.dark)
    }

    private var screenshotView: some View {
        HStack(spacing: 12) {
            screenshotThumbnail(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshot copied").font(.system(size: 13, weight: .semibold))
                Text("Ready to paste").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(chargingGreen)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screenshot copied, ready to paste")
    }

    private var compactScreenshotView: some View {
        Group {
            if attached {
                HStack(spacing: 0) {
                    screenshotThumbnail(size: 24).frame(width: 44)
                    Color.clear.frame(width: model.notchSize.width)
                    Image(systemName: "checkmark")
                        .foregroundStyle(chargingGreen)
                        .frame(width: 44)
                }
            } else {
                HStack(spacing: 10) {
                    screenshotThumbnail(size: 24)
                    Text("Screenshot copied").font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark").foregroundStyle(chargingGreen)
                }.padding(.horizontal, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screenshot copied")
    }

    private func screenshotThumbnail(size: CGFloat) -> some View {
        Group {
            if let screenshot = coordinator.screenshot {
                Image(nsImage: screenshot).resizable().scaledToFill()
            } else {
                Image(systemName: "rectangle.dashed").font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 8 : 5))
        .accessibilityHidden(true)
    }

    private func activityView(_ activity: SystemActivity) -> some View {
        let level = activity.level
        return VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: activity.symbol)
                    .foregroundStyle(activityColor(activity))
                    .frame(width: 22)
                Text(activity.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int((level * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white)
                            .frame(width: geometry.size.width * level)
                    }
            }.frame(height: 3)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: activity.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.title), \(Int((level * 100).rounded())) percent")
    }

    private func compactActivityView(_ activity: SystemActivity) -> some View {
        let percentage = "\(Int((activity.level * 100).rounded()))%"
        return Group {
            if attached {
                HStack(spacing: 0) {
                    Image(systemName: activity.symbol)
                        .foregroundStyle(activityColor(activity))
                        .frame(width: 44)
                    Color.clear.frame(width: model.notchSize.width)
                    Text(percentage).frame(width: 44)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: activity.symbol)
                        .foregroundStyle(activityColor(activity))
                    Spacer(minLength: 0)
                    Text(percentage)
                }
                .padding(.horizontal, 12)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.title), \(percentage)")
    }

    private func activityColor(_ activity: SystemActivity) -> Color {
        switch activity.kind {
        case .charging: chargingGreen
        default: .white
        }
    }

    @ViewBuilder private var compact: some View {
        if let track = model.media.snapshot {
            if attached {
                HStack(spacing: 0) {
                    artwork(size: min(24, model.notchSize.height - 6)).frame(width: 44)
                    Color.clear.frame(width: model.notchSize.width)
                    playbackIndicator(track.isPlaying).frame(width: 44)
                }
                .accessibilityLabel(track.title)
            } else {
                HStack(spacing: 10) {
                    artwork(size: 28)
                    Text(track.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    playbackIndicator(track.isPlaying)
                }.padding(.horizontal, 8)
            }
        } else if !attached {
            Capsule().fill(.white.opacity(0.25)).frame(width: 24, height: 3)
        }
    }

    private func expanded(_ track: NowPlayingSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                artwork(size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
                playbackIndicator(track.isPlaying)
            }
            TimelineView(.animation(minimumInterval: 1, paused: !model.shouldTick)) { context in
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.16))
                            .overlay(alignment: .leading) {
                                Capsule().fill(accent.opacity(0.9))
                                    .frame(width: geometry.size.width * track.progress(at: context.date))
                            }
                    }.frame(height: 3)
                    HStack {
                        Text(time(track.position(at: context.date)))
                        Spacer()
                        Text(track.duration.map(time) ?? "LIVE")
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playback progress")
                .accessibilityValue("\(time(track.position(at: context.date))) of \(track.duration.map(time) ?? "live media")")
            }
            HStack(spacing: 18) {
                control("backward.end.fill", label: "Previous track", command: .previous)
                control(track.isPlaying ? "pause.fill" : "play.fill", label: track.isPlaying ? "Pause" : "Play", command: .togglePlayback, prominent: true)
                control("forward.end.fill", label: "Next track", command: .next)
            }.frame(height: 36)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    private var empty: some View {
        HStack(spacing: 14) {
            Image(systemName: model.media == .unavailable ? "antenna.radiowaves.left.and.right.slash" : "music.note")
                .font(.system(size: 24)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.media == .unavailable ? "Media connection unavailable" : "A little space for your music.")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.media == .unavailable ? "Retry from Arc in the menu bar." : "Play something to get started.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }.padding(20)
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1))
            if let artwork = coordinator.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.36)).foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 10 : 6))
        .accessibilityHidden(true)
    }

    private func playbackIndicator(_ playing: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion || !model.enabled)) { context in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let phase = context.date.timeIntervalSinceReferenceDate * 5 + Double(index) * 1.7
                    Capsule().fill(playing ? accent : .gray)
                        .frame(width: 2, height: playing ? 5 + 11 * abs(sin(phase)) : 4)
                }
            }.frame(width: 16, height: 18)
        }.accessibilityLabel(playing ? "Playing" : "Paused")
    }

    private func control(_ symbol: String, label: String, command: MediaCommand, prominent: Bool = false) -> some View {
        Button { coordinator.send(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func time(_ value: Double) -> String {
        let seconds = Int(min(359_999, max(0, value.isFinite ? value : 0)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
