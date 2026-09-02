import SwiftUI

enum AppleSettingsRoute: Hashable {
    case sources
    case metadata
    case serverDownloads
    case gateway
    case trakt
    case playbackInfo
    case storage
    case about
}

@MainActor
struct AppleSettingsView: View {
    let settings: AppleSettingsStore
    let sourceStore: AppleSourceStore
    let webManagement: any AppleWebManagementServing

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                NavigationLink(value: AppleSettingsRoute.sources) {
                    Label("Sources", systemImage: "rectangle.stack.badge.plus")
                }
            }

            Section("Services") {
                NavigationLink(value: AppleSettingsRoute.metadata) {
                    Label("Metadata", systemImage: "photo.on.rectangle.angled")
                }
                NavigationLink(value: AppleSettingsRoute.serverDownloads) {
                    Label("Radarr & Sonarr", systemImage: "arrow.down.circle")
                }
                NavigationLink(value: AppleSettingsRoute.gateway) {
                    Label("Gateway", systemImage: "server.rack")
                }
                NavigationLink(value: AppleSettingsRoute.trakt) {
                    Label("Trakt", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section("Playback") {
                Toggle("Captions Auto-On", isOn: $settings.captionsAutoOn)
                Toggle("Delete After Watching", isOn: $settings.deleteAfterWatching)
                NavigationLink(value: AppleSettingsRoute.playbackInfo) {
                    Label("Playback Info", systemImage: "play.square.stack")
                }
            }

            Section {
                NavigationLink(value: AppleSettingsRoute.storage) {
                    Label("Storage", systemImage: "internaldrive")
                }
                NavigationLink(value: AppleSettingsRoute.about) {
                    Label("About", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(for: AppleSettingsRoute.self) { route in
            switch route {
            case .sources:
                AppleSourcesSettingsView(sourceStore: sourceStore, webManagement: webManagement)
            case .metadata:
                AppleMetadataSettingsView(settings: settings)
            case .serverDownloads:
                AppleServerDownloadsSettingsView(settings: settings)
            case .gateway:
                AppleGatewaySettingsView(settings: settings)
            case .trakt:
                AppleTraktSettingsView(settings: settings)
            case .playbackInfo:
                ApplePlaybackInfoView()
            case .storage:
                AppleStorageSettingsView()
            case .about:
                AppleAboutView()
            }
        }
    }
}

@MainActor
private struct AppleMetadataSettingsView: View {
    let settings: AppleSettingsStore

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Use Metadata APIs", isOn: $settings.metadataEnabled)
            }

            Section("TMDB") {
                SecureField("API key or read token", text: $settings.tmdbAPIKey)
                    .disabled(!settings.metadataEnabled)
            }

            Section("OMDb") {
                SecureField("API key", text: $settings.omdbAPIKey)
                    .disabled(!settings.metadataEnabled)
            }

            AppleSettingsPersistenceError(settings: settings)
        }
        .navigationTitle("Metadata")
    }
}

@MainActor
private struct AppleServerDownloadsSettingsView: View {
    let settings: AppleSettingsStore

    var body: some View {
        @Bindable var settings = settings

        Form {
            AppleArrConnectionSection(
                kind: .radarr,
                baseURL: $settings.radarrURL,
                apiKey: $settings.radarrAPIKey
            )

            AppleArrConnectionSection(
                kind: .sonarr,
                baseURL: $settings.sonarrURL,
                apiKey: $settings.sonarrAPIKey
            )

            AppleSettingsPersistenceError(settings: settings)
        }
        .navigationTitle("Radarr & Sonarr")
    }
}

@MainActor
private struct AppleArrConnectionSection: View {
    let kind: AppleArrKind
    @Binding var baseURL: String
    @Binding var apiKey: String

    private let client: AppleArrClient
    @State private var state = AppleConnectionTestState.idle

    init(
        kind: AppleArrKind,
        baseURL: Binding<String>,
        apiKey: Binding<String>,
        client: AppleArrClient = AppleArrClient()
    ) {
        self.kind = kind
        _baseURL = baseURL
        _apiKey = apiKey
        self.client = client
    }

    var body: some View {
        Section(kind.displayName) {
            TextField("Server URL", text: $baseURL)
                .autocorrectionDisabled()
            SecureField("API key", text: $apiKey)

            AppleConnectionStatusView(state: state)

            Button {
                Task { await testConnection() }
            } label: {
                AppleConnectionTestLabel(isTesting: state.isTesting)
            }
            .buttonStyle(.bordered)
            .disabled(!canTest || state.isTesting)
        }
        .onChange(of: baseURL) { _, _ in state = .idle }
        .onChange(of: apiKey) { _, _ in state = .idle }
    }

    private var canTest: Bool {
        AppleArrEndpointPolicy.isAllowed(baseURL) && AppleArrClient.isValidAPIKey(apiKey)
    }

    private func testConnection() async {
        let submittedURL = baseURL
        let submittedAPIKey = apiKey
        state = .testing

        do {
            let status = try await client.test(kind: kind, baseURL: submittedURL, apiKey: submittedAPIKey)
            guard baseURL == submittedURL, apiKey == submittedAPIKey else { return }
            state = .success(connectionLabel(for: status))
        } catch is CancellationError {
            guard baseURL == submittedURL, apiKey == submittedAPIKey else { return }
            state = .idle
        } catch {
            guard baseURL == submittedURL, apiKey == submittedAPIKey else { return }
            state = .failure(error.localizedDescription)
        }
    }

    private func connectionLabel(for status: AppleArrStatus) -> String {
        var parts = ["Connected", status.appName]
        if !status.version.isEmpty { parts.append(status.version) }
        if !status.instanceName.isEmpty { parts.append(status.instanceName) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
private struct AppleGatewaySettingsView: View {
    let settings: AppleSettingsStore

    private let client: AppleTranscodeGatewayClient
    @State private var state = AppleConnectionTestState.idle

    init(
        settings: AppleSettingsStore,
        client: AppleTranscodeGatewayClient = AppleTranscodeGatewayClient()
    ) {
        self.settings = settings
        self.client = client
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Enabled", isOn: $settings.gatewayEnabled)
            }

            Section("Connection") {
                TextField("Gateway URL", text: $settings.gatewayURL)
                    .autocorrectionDisabled()
                SecureField("Gateway token", text: $settings.gatewayToken)

                AppleConnectionStatusView(state: state)

                Button {
                    Task { await testConnection() }
                } label: {
                    AppleConnectionTestLabel(isTesting: state.isTesting)
                }
                .buttonStyle(.bordered)
                .disabled(!canTest || state.isTesting)
            }

            AppleSettingsPersistenceError(settings: settings)
        }
        .navigationTitle("Gateway")
        .onChange(of: settings.gatewayURL) { _, _ in state = .idle }
        .onChange(of: settings.gatewayToken) { _, _ in state = .idle }
    }

    private var canTest: Bool {
        (try? configuration()) != nil
    }

    private func configuration() throws -> AppleTranscodeGatewayConfig {
        try AppleTranscodeGatewayConfig(
            baseURL: settings.gatewayURL,
            sessionToken: settings.gatewayToken,
            isEnabled: settings.gatewayEnabled
        )
    }

    private func testConnection() async {
        let submittedURL = settings.gatewayURL
        let submittedToken = settings.gatewayToken
        state = .testing

        do {
            let capabilities = try await client.capabilities(config: configuration())
            guard settings.gatewayURL == submittedURL, settings.gatewayToken == submittedToken else { return }
            state = .success(connectionLabel(for: capabilities))
        } catch is CancellationError {
            guard settings.gatewayURL == submittedURL, settings.gatewayToken == submittedToken else { return }
            state = .idle
        } catch {
            guard settings.gatewayURL == submittedURL, settings.gatewayToken == submittedToken else { return }
            state = .failure(error.localizedDescription)
        }
    }

    private func connectionLabel(for capabilities: AppleTranscodeGatewayCapabilities) -> String {
        guard capabilities.available else { return "Connected · FFmpeg unavailable" }
        var parts = ["Connected", "FFmpeg"]
        if let version = capabilities.version?.trimmingCharacters(in: .whitespacesAndNewlines),
           !version.isEmpty {
            parts.append(String(version.prefix(40)))
        }
        if capabilities.hardwareAccelerated { parts.append("Hardware acceleration") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
private struct AppleTraktSettingsView: View {
    let settings: AppleSettingsStore

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Client Credentials") {
                SecureField("Client ID", text: $settings.traktClientID)
                SecureField("Client secret", text: $settings.traktClientSecret)
            }

            AppleSettingsPersistenceError(settings: settings)
        }
        .navigationTitle("Trakt")
    }
}

private enum AppleConnectionTestState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)

    var isTesting: Bool {
        if case .testing = self { return true }
        return false
    }
}

private struct AppleConnectionStatusView: View {
    let state: AppleConnectionTestState

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .testing:
            EmptyView()
        case .success(let message):
            Text(message)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }
}

private struct AppleConnectionTestLabel: View {
    let isTesting: Bool

    var body: some View {
        if isTesting {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Testing")
            }
        } else {
            Text("Test Connection")
        }
    }
}

@MainActor
private struct AppleSettingsPersistenceError: View {
    let settings: AppleSettingsStore

    var body: some View {
        if let error = settings.persistenceError {
            Section {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct AppleAboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("App", value: "OpenStream")
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }

            Section {
                Link(destination: URL(string: "https://github.com/cyberbanksy")!) {
                    Label("GitHub", systemImage: "link")
                }
            }
        }
        .navigationTitle("About")
    }
}
