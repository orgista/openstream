import OpenStreamApple
import SwiftUI

@main
struct OpenStreamPlatformApp: App {
    @State private var showLaunch = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            #if os(tvOS)
            // Mount a focusable hierarchy immediately. Replacing a
            // non-focusable launch overlay after startup can leave the Siri
            // Remote without a default focus candidate.
            OpenStreamRootView()
                .tint(.white)
            #else
            ZStack {
                if showLaunch {
                    AppleOpenStreamLaunchView()
                        .transition(.opacity)
                        .zIndex(20)
                } else {
                    OpenStreamRootView()
                        .transition(.opacity)
                }
            }
            // Brand accent is monochrome — the mark is white bars on black, so
            // controls tint white, not the iOS default blue. Owner feedback:
            // "if there's anything anywhere but OpenStream being blue, remove
            // it." Green toggles stay (system on/off), red stays destructive.
            .tint(.white)
            .task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 220 : 1_300))
                withAnimation(.easeOut(duration: 0.22)) { showLaunch = false }
            }
            #endif
        }
    }
}

private struct AppleOpenStreamLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                OpenStreamThreeBarMark()
                    .frame(width: 74, height: 52)
                // Brand wordmark: straight bold sans with tight tracking,
                // matching the Android launch screen, TV banner, and store
                // assets. Never rounded, never lowercase-first.
                Text("OpenStream")
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
            }
            .opacity(reduceMotion ? 1 : (appeared ? 1 : 0))
            .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.94))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.52)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OpenStream")
    }
}
