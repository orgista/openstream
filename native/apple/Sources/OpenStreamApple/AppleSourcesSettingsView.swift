import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public protocol AppleWebManagementServing: AnyObject {
    var session: AppleWebManagementSession? { get }

    func start(sourceStore: AppleSourceStore) async throws -> AppleWebManagementSession
    func stop() async
}

public struct AppleWebManagementUnavailableError: LocalizedError, Sendable {
    public init() {}

    public var errorDescription: String? {
        "Web Management is unavailable in this build."
    }
}

@MainActor
public final class AppleUnavailableWebManagementService: AppleWebManagementServing {
    public var session: AppleWebManagementSession? { nil }

    public init() {}

    public func start(sourceStore: AppleSourceStore) async throws -> AppleWebManagementSession {
        throw AppleWebManagementUnavailableError()
    }

    public func stop() async {}
}

@MainActor
struct AppleSourcesSettingsView: View {
    @State private var showingLibraryImporter = false
    @State private var importError: String?

    let sourceStore: AppleSourceStore
    let webManagement: any AppleWebManagementServing

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppleSourceRoute.addManifest) {
                    Label("Add Manifest URL", systemImage: "plus")
                }

                NavigationLink(value: AppleSourceRoute.addLiveTV) {
                    Label("Add Live TV", systemImage: "dot.radiowaves.left.and.right")
                }

                #if !os(tvOS)
                Button {
                    showingLibraryImporter = true
                } label: {
                    Label("Add Files or SMB Folder", systemImage: "folder.badge.plus")
                }
                #endif

                NavigationLink(value: AppleSourceRoute.webManagement) {
                    Label("Web Management", systemImage: "network")
                }
            }

            Section("Sources") {
                if sourceStore.sources.isEmpty {
                    Text("No sources")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sourceStore.sources) { source in
                        NavigationLink(value: AppleSourceRoute.detail(source.id)) {
                            AppleSourceRow(source: source)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sources")
        .navigationDestination(for: AppleSourceRoute.self) { route in
            switch route {
            case .addManifest:
                AppleAddManifestSourceView(sourceStore: sourceStore)
            case .addLiveTV:
                AppleAddLiveTVSourceView(sourceStore: sourceStore)
            case .webManagement:
                AppleWebManagementView(sourceStore: sourceStore, service: webManagement)
            case .detail(let sourceID):
                AppleSourceDetailView(sourceID: sourceID, sourceStore: sourceStore)
            }
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showingLibraryImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            importFolder(result)
        }
        #endif
        .alert("Couldn’t Add Folder", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "The folder could not be added.")
        }
    }

    #if !os(tvOS)
    private func importFolder(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { throw AppleLibrarySourceError.invalidFolder }
            let access = AppleSecurityScopedAccess(url: url)
            _ = access
            let bookmark = try AppleLibraryBookmark.make(for: url)
            try sourceStore.addLibraryFolder(name: url.lastPathComponent, url: url, bookmarkData: bookmark)
        } catch {
            importError = error.localizedDescription
        }
    }
    #endif
}

private enum AppleSourceRoute: Hashable {
    case addManifest
    case addLiveTV
    case webManagement
    case detail(AppleSource.ID)
}

private struct AppleSourceRow: View {
    let source: AppleSource

    var body: some View {
        HStack(spacing: 12) {
            sourceIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                Text(source.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(source.isEnabled ? "On" : "Off")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let logoURL = source.logoURL {
            AsyncImage(url: logoURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: source.kind.systemImage)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(.rect(cornerRadius: 6))
        } else {
            Image(systemName: source.kind.systemImage)
                .frame(width: 28, height: 28)
        }
    }
}

private extension AppleSourceKind {
    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .stremio: "puzzlepiece.extension"
        case .youtube: "play.rectangle"
        case .liveTV: "dot.radiowaves.left.and.right"
        case .nas: "externaldrive.connected.to.line.below"
        }
    }
}

@MainActor
private struct AppleSourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    let sourceID: AppleSource.ID
    let sourceStore: AppleSourceStore

    private var source: AppleSource? {
        sourceStore.sources.first { $0.id == sourceID }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { source?.isEnabled ?? false },
            set: { sourceStore.setEnabled($0, id: sourceID) }
        )
    }

    var body: some View {
        Group {
            if let source {
                Form {
                    Section {
                        LabeledContent("Type", value: source.kind.title)
                        LabeledContent(locationLabel(source), value: sourceLocation(source))
                        Toggle("Enabled", isOn: enabled)
                    }

                    Section {
                        Button("Delete Source", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
                .navigationTitle(source.name)
            } else {
                ContentUnavailableView("Source Not Found", systemImage: "questionmark.folder")
            }
        }
        .alert("Delete Source?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                sourceStore.remove(id: sourceID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func locationLabel(_ source: AppleSource) -> String {
        switch source.kind {
        case .stremio: "Manifest Host"
        case .library: "Folder"
        case .liveTV: "Server"
        default: "Location"
        }
    }

    private func sourceLocation(_ source: AppleSource) -> String {
        if source.url.isFileURL { return source.url.lastPathComponent }
        let url = source.url
        guard let host = url.host else { return "Private source" }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

@MainActor
private struct AppleAddManifestSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manifestURL = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    let sourceStore: AppleSourceStore

    var body: some View {
        Form {
            Section("Manifest URL") {
                TextField(
                    "Manifest URL",
                    text: $manifestURL,
                    prompt: Text("https://example.io/manifest.json").foregroundStyle(.secondary)
                )
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    addManifest()
                } label: {
                    if isAdding {
                        ProgressView()
                    } else {
                        Text("Add Source")
                    }
                }
                .disabled(isAdding || manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Add Source")
    }

    private func addManifest() {
        isAdding = true
        errorMessage = nil

        Task { @MainActor in
            defer { isAdding = false }
            do {
                try await sourceStore.addStremio(manifestValue: manifestURL)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
private struct AppleAddLiveTVSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type = AppleIPTVSourceType.xtream
    @State private var name = ""
    @State private var endpoint = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    let sourceStore: AppleSourceStore
    private let client = AppleIPTVClient()

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $type) {
                    ForEach(AppleIPTVSourceType.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
            }

            Section("Connection") {
                TextField("Name", text: $name, prompt: Text("My TV").foregroundStyle(.secondary))
                TextField(
                    type == .xtream ? "Server URL" : "M3U/M3U8 URL",
                    text: $endpoint,
                    prompt: Text(type == .xtream ? "https://tv.example" : "https://tv.example/playlist.m3u")
                        .foregroundStyle(.secondary)
                )
                .textContentType(.URL)
                .autocorrectionDisabled()

                if type == .xtream {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(isError ? .red : .green)
                }
            }

            Section {
                HStack {
                    Button("Save") { save() }
                        .buttonStyle(.brandPrimary)
                        .disabled(!canSubmit || isWorking)
                    Button {
                        test()
                    } label: {
                        if isWorking { ProgressView() } else { Text("Test Connection") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSubmit || isWorking)
                }
            }
        }
        .navigationTitle("Add Live TV")
    }

    private var canSubmit: Bool {
        guard (try? AppleIPTVEndpointPolicy.normalize(endpoint)) != nil else { return false }
        return type == .m3u || (!username.isEmpty && !password.isEmpty)
    }

    private func save() {
        do {
            try sourceStore.addIPTV(
                name: name,
                type: type,
                endpoint: endpoint,
                username: username,
                password: password
            )
            dismiss()
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }

    private func test() {
        isWorking = true
        message = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let source = AppleSource(
                    kind: .liveTV,
                    name: name.isEmpty ? "My TV" : name,
                    url: try AppleIPTVEndpointPolicy.normalize(endpoint),
                    iptvType: type,
                    username: username,
                    password: password
                )
                let channels = try await client.channels(source: source)
                try sourceStore.addIPTV(
                    name: name,
                    type: type,
                    endpoint: endpoint,
                    username: username,
                    password: password
                )
                isError = false
                message = "Connected · \(channels.count) channels"
            } catch {
                isError = true
                message = error.localizedDescription
            }
        }
    }
}

@MainActor
private struct AppleWebManagementView: View {
    @State private var session: AppleWebManagementSession?
    @State private var isWorking = false
    @State private var errorMessage: String?

    let sourceStore: AppleSourceStore
    let service: any AppleWebManagementServing

    private var activeSession: AppleWebManagementSession? {
        guard let session, !session.isExpired else { return nil }
        return session
    }

    var body: some View {
        Form {
            if let activeSession {
                Section {
                    AppleWebManagementQRCode(url: activeSession.url)
                        .frame(maxWidth: .infinity)
                }

                Section("Session") {
                    LabeledContent("Address", value: activeSession.friendlyURL.absoluteString)
                    LabeledContent("Expires", value: activeSession.expiresAt.formatted(date: .omitted, time: .shortened))
                }

                #if os(iOS) || os(macOS)
                Section {
                    Button("Copy Address") {
                        copy(activeSession.friendlyURL)
                    }
                }
                #endif
            }

            Section {
                Button(role: activeSession == nil ? nil : .destructive) {
                    guard !isWorking else { return }
                    if activeSession == nil {
                        start()
                    } else {
                        stop()
                    }
                } label: {
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text(activeSession == nil ? "Starting" : "Stopping")
                        }
                    } else {
                        Text(activeSession == nil ? "Start Web Management" : "Stop Web Management")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Web Management")
        .task {
            while !Task.isCancelled {
                session = service.session
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear {
            Task { @MainActor in
                await service.stop()
                session = nil
            }
        }
    }

    private func start() {
        isWorking = true
        errorMessage = nil

        Task { @MainActor in
            defer { isWorking = false }
            do {
                session = try await service.start(sourceStore: sourceStore)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stop() {
        isWorking = true
        errorMessage = nil

        Task { @MainActor in
            await service.stop()
            session = nil
            isWorking = false
        }
    }

    private func copy(_ url: URL) {
        #if os(iOS)
        UIPasteboard.general.url = url
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        #endif
    }
}

private struct AppleWebManagementQRCode: View {
    let url: URL

    var body: some View {
        if let image = Self.image(for: url) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .padding()
                .background(.white, in: .rect(cornerRadius: 16))
                .accessibilityLabel("Web Management QR code")
        }
    }

    private static func image(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 12, y: 12)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}
