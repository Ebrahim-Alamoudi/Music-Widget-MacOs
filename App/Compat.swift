import AppKit
import SwiftUI

// Liquid Glass and some window APIs need macOS 15 or 26. These helpers use them when available
// and fall back to the closest system material on macOS 14 and 15.

enum GlassKind {
    case regular, clear
}

extension View {
    @ViewBuilder
    func glass<S: Shape>(_ kind: GlassKind = .regular, tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Self.makeGlass(kind, tint: tint, interactive: interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(kind == .clear ? Material.ultraThinMaterial : Material.regularMaterial)
                    if let tint { shape.fill(tint.opacity(0.35)) }
                }
                .overlay { shape.stroke(.white.opacity(0.18), lineWidth: 0.5) }
            }
        }
    }

    @available(macOS 26.0, *)
    private static func makeGlass(_ kind: GlassKind, tint: Color?, interactive: Bool) -> Glass {
        var glass: Glass = kind == .clear ? .clear : .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Lets empty areas drag the window (macOS 15+). On macOS 14 the panel is movable by its background instead.
    @ViewBuilder
    func windowDraggable() -> some View {
        if #available(macOS 15.0, *) {
            gesture(WindowDragGesture())
        } else {
            self
        }
    }

    /// Transparent toolbar over a translucent window (macOS 15+).
    @ViewBuilder
    func translucentWindowChrome() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .containerBackground(.thickMaterial, for: .window)
        } else {
            self
        }
    }
}

/// `GlassEffectContainer` on macOS 26+, a plain container before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

enum GlassBackdropView {
    /// Real Liquid Glass on macOS 26+, a behind-window blur before that.
    @MainActor
    static func make(frame: NSRect, cornerRadius: CGFloat, content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView(frame: frame)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        content.frame = blur.bounds
        blur.addSubview(content)
        return blur
    }

    @MainActor
    static func setTint(_ color: NSColor, on view: NSView) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.tintColor = color
        }
    }
}

// MARK: - Press effect

private struct BurstValues {
    var scale = 1.0
    var opacity = 0.0
}

/// A soft ripple that blooms out of a button and fades, plus a light trackpad tap.
private struct TapBurst: ViewModifier {
    let trigger: Int
    var color: Color

    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(color.opacity(0.28))
                    .keyframeAnimator(initialValue: BurstValues(), trigger: trigger) { circle, value in
                        circle
                            .scaleEffect(value.scale)
                            .opacity(value.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(0.55, duration: 0.01)
                            SpringKeyframe(1.45, duration: 0.5, spring: .snappy)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.04)
                            CubicKeyframe(0, duration: 0.46)
                        }
                    }
                    .allowsHitTesting(false)
            }
            .sensoryFeedback(.alignment, trigger: trigger)
    }
}

extension View {
    /// Bouncing symbol + ripple + haptic whenever `trigger` changes.
    func pressEffect(_ trigger: Int, color: Color = .primary) -> some View {
        self
            .symbolEffect(.bounce, value: trigger)
            .modifier(TapBurst(trigger: trigger, color: color))
    }
}
