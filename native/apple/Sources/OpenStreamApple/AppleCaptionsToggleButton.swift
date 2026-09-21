import SwiftUI

/// The player's CC key: one tap turns the preferred-language subtitle track on,
/// the next turns it off.
///
/// It says which state it is in the way a real key does — with depth, not
/// colour (owner 2026-09-20: "when pressed is on and when pressed is off …
/// think of a button when pressed is 'pressed down' that's one and when pressed
/// up it's pressed off"). `cap` below is where that drawing lives.
///
/// The state is persistent, not the momentary tap: `isOn` is the model's, and
/// the tap's own feedback is the small scale in `Style` below.
@MainActor
struct AppleCaptionsToggleButton: View {
    let isOn: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sized against the cap of a key on the system keyboard rather than the
    /// glyph buttons beside it: "CC" is two letters, and a circle around them
    /// would be the boxed icon the owner's rules rule out.
    private let capSize = CGSize(width: 38, height: 28)
    private let capRadius: CGFloat = 7

    var body: some View {
        Button(action: action) {
            Text(verbatim: "CC")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: isOn ? 1 : 0)
                .frame(width: capSize.width, height: capSize.height)
                .background(cap)
                .frame(
                    width: AppleDesignTokens.minimumActionSize,
                    height: AppleDesignTokens.minimumActionSize
                )
                .contentShape(.rect)
        }
        .buttonStyle(Style())
        .appleHoverAffordance()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isOn)
        .accessibilityLabel("Closed Captions")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("player.captions.toggle")
    }

    /// The housing.
    ///
    /// Three cues, all of them about depth and none of them about hue. Raised:
    /// a light bevel along the top inside edge, a shadow cast onto the surface
    /// below, and a face turned towards the light. Pressed: the bevel light
    /// moves to the bottom edge and a hard shade takes the top, the cast shadow
    /// goes, the face sits in the recess and so takes less light, and the cap
    /// travels a point down. Grey levels only, so a viewer who cannot tell red
    /// from green reads it exactly the same — and VoiceOver gets the state as a
    /// value rather than having to infer it from the drawing at all.
    ///
    /// The bevels are drawn rather than left to `.shadow(.inner:)`, which is a
    /// render-server effect: `ImageRenderer` drops it, so the difference could
    /// not be photographed, and a control whose state cannot be seen in a still
    /// is one nobody can check.
    private var cap: some View {
        ZStack {
            shape.fill(Color.white.opacity(isOn ? 0.07 : 0.22))
            bevel(color: .white.opacity(isOn ? 0 : 0.55), from: .top)
            bevel(color: .black.opacity(isOn ? 0.9 : 0), from: .top)
            bevel(color: .white.opacity(isOn ? 0.38 : 0), from: .bottom)
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isOn ? 0 : 0.7), radius: 3, y: 3)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: capRadius, style: .continuous)
    }

    /// One inside edge, lit or shaded: a soft stroke pushed off centre and
    /// clipped back to the cap, which is what an inner shadow is.
    private func bevel(color: Color, from edge: VerticalEdge) -> some View {
        shape
            .stroke(color, lineWidth: 3)
            .blur(radius: 2)
            .offset(y: edge == .top ? 2.5 : -2.5)
            .mask { shape.fill(.black) }
    }

    /// Only the momentary tap lives here. The on/off appearance is `isOn`'s,
    /// because the key stays down after the finger leaves.
    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
