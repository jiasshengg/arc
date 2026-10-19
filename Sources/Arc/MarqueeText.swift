import SwiftUI

/// One line of text that scrolls when it doesn't fit, pausing at the start of each pass.
/// Frames are only drawn while a pass is moving; it stays still when `animating` is false.
struct MarqueeText: View {
    let text: String
    let font: Font
    var alignment: Alignment = .leading
    let animating: Bool

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let gap: CGFloat = 32
    private let fade: CGFloat = 10
    private let speed: CGFloat = 30
    private let pause: Duration = .seconds(2)
    private var overflows: Bool { textWidth > containerWidth + 1 }

    private struct Pass: Equatable {
        let text: String
        let distance: CGFloat
        let active: Bool
    }

    var body: some View {
        let label = Text(text).font(font).lineLimit(1).fixedSize()
        // The plain line sets the size; the scrolling copies live in an overlay so they never widen the layout.
        Text(text).font(font).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
            .opacity(overflows ? 0 : 1)
            .overlay(alignment: .leading) {
                if overflows {
                    HStack(spacing: gap) { label; label }.offset(x: offset)
                }
            }
            .clipped()
            .mask { if overflows { edgeFade } else { Color.black } }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { containerWidth = $0 }
        .background(label.hidden().onGeometryChange(for: CGFloat.self, of: \.size.width) { textWidth = $0 })
        .task(id: Pass(text: text, distance: textWidth + gap, active: overflows && animating)) {
            withTransaction(Transaction(animation: nil)) { offset = 0 }
            guard overflows && animating else { return }
            let distance = textWidth + gap
            let duration = Double(distance / speed)
            while true {
                do { try await Task.sleep(for: pause) } catch { return }
                withAnimation(.linear(duration: duration)) { offset = -distance }
                do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                // The second copy now sits where the first began, so the jump back is invisible.
                withTransaction(Transaction(animation: nil)) { offset = 0 }
            }
        }
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            // Only fade the leading edge while scrolling, so the first letter stays crisp at rest.
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: offset == 0 ? 0 : fade)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: fade)
        }
    }
}
