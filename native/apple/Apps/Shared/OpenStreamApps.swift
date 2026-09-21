import OpenStreamApple
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct OpenStreamPlatformApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(OpenStreamAppDelegate.self) private var appDelegate
    #endif
    @State private var showLaunch = true
    @State private var router = AppleAppRouter()
    @State private var webManagement = AppleWebManagementController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            #if DEBUG && !os(tvOS)
            if ProcessInfo.processInfo.arguments.contains("-OpenStreamLibraryTitlesFixture") {
                AppleLibraryTitlesDebugView()
            } else if ProcessInfo.processInfo.arguments.contains("-OpenStreamDownloadFixture") {
                AppleOfflineDownloadDebugView()
            } else {
                platformRoot
            }
            #else
            platformRoot
            #endif
        }
        #if os(visionOS)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        #endif
        #if os(macOS)
        // Without this the Mac window opens at AppKit's 900 x 450 default,
        // which is smaller than any shape this app's Discover billboard and
        // poster rows were designed for. The Settings pages that read as blank
        // at that size were a separate fault and are fixed at the source now
        // (`AppleSettingsContentModifier`, macOS branch); this is just a
        // sensible opening size for a media app.
        .defaultSize(width: 1280, height: 860)
        .commands { AppleMacMenuCommands() }
        #endif

        #if os(visionOS)
        AppleVisionPlaybackScene()
        #endif
    }

    @ViewBuilder
    private var platformRoot: some View {
        #if os(tvOS)
            // Mount a focusable hierarchy immediately. Replacing a
            // non-focusable launch overlay after startup can leave the Siri
            // Remote without a default focus candidate.
            OpenStreamRootView(webManagement: webManagement, router: router)
                .tint(.white)
                .onOpenURL { router.open($0) }
        #else
            ZStack {
                OpenStreamRootView(webManagement: webManagement, router: router)
                    .transition(.opacity)
                if showLaunch {
                    AppleOpenStreamLaunchView()
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            // Brand accent is monochrome — the mark is white bars on black, so
            // controls tint white, not the iOS default blue. Owner feedback:
            // "if there's anything anywhere but OpenStream being blue, remove
            // it." Green toggles stay (system on/off), red stays destructive.
            .tint(.white)
            .onOpenURL { router.open($0) }
            .task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 220 : 1_300))
                withAnimation(.easeOut(duration: 0.22)) { showLaunch = false }
            }
            #if DEBUG
            .task {
                guard AppleAppGroupDiagnostics.isEnabled() else { return }
                AppleAppGroupDiagnostics.emit(AppleAppGroupDiagnostics.run())
            }
            #endif
            #if DEBUG && os(macOS)
            // Renders this window to a PNG and dumps the menu bar, so a macOS
            // screen can be reviewed from a headless session. See
            // `AppleMacWindowShot` for why nothing else works here.
            .task {
                guard let request = AppleMacWindowShot.request() else { return }
                await AppleMacWindowShot.run(request)
            }
            #endif
            #if DEBUG
            .task {
                guard AppleSavedSourceDiagnosticsLaunch.isEnabled() else { return }
                let operations = AppleSavedSourceDiagnosticsProductionOperations(
                    sourceStore: AppleSourceStore(),
                    settings: AppleSettingsStore()
                )
                let results = await AppleSavedSourceDiagnosticsRunner(operations: operations).run()
                print(AppleSavedSourceDiagnosticsConsole.summary(results))
            }
            #endif
        #endif
    }
}

private struct AppleOpenStreamLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            OpenStreamThreeBarMark()
                .frame(width: 74, height: 52)
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

#if os(iOS)
@MainActor
private final class OpenStreamAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppleOrientationLock.shared.supportedOrientations(
            for: UIDevice.current.userInterfaceIdiom
        )
    }
}
#endif
