#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers

struct AppleConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AppleConfigurationError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
struct AppleBackupSettingsView: View {
    let controller: AppleConfigurationController
    @State private var passphrase = ""
    @State private var syncEnabled = false
    @State private var document: AppleConfigurationDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var signingIn: AppleSource?
    @State private var syncAvailability = AppleICloudSyncAvailability.available

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $syncEnabled) {
                    Text("Sync with iCloud")
                    if let note = syncAvailability.note {
                        Text(note)
                    }
                }
                .tint(.green)
                .disabled(!syncAvailability.allowsChange(from: syncEnabled))
                .accessibilityIdentifier("backup.sync")
            }
            Section {
                SecureField("Export passphrase (optional)", text: $passphrase)
                    .textContentType(.password)
                #if !os(macOS)
                exportButton
                importButton
                #endif
            }
            .disabled(controller.isBusy)
            #if os(macOS)
            AppleFormActionSection {
                importButton
                exportButton
            }
            .disabled(controller.isBusy)
            #endif
            if !controller.sources.sources.filter(\.needsSignIn).isEmpty {
                Section("Needs sign-in") {
                    ForEach(controller.sources.sources.filter(\.needsSignIn)) { source in
                        Button(source.name) { signingIn = source }
                    }
                }
            }
            if let result = controller.result {
                Section { Text(result) }
            }
        }
        .appleSettingsPage(AppleSettingsRootEntry.backup.title)
        .scrollIndicators(.hidden)
        .task {
            syncEnabled = controller.syncEnabled
            syncAvailability = AppleICloudSyncProbe.current()
        }
        .onChange(of: syncEnabled) { _, enabled in
            Task {
                await controller.setSyncEnabled(enabled)
                syncEnabled = controller.syncEnabled
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "openstream-config.json") { result in
            switch result {
            case .success: controller.setResult("Configuration exported")
            case .failure: controller.setResult("Export cancelled or unavailable")
            }
            document = nil
        }
        .appleConfigurationImport(isPresented: $importing, controller: controller)
        .sheet(item: $signingIn) { source in
            if source.kind == .mediaServer {
                NavigationStack { AppleAddMediaServerView(sourceStore: controller.sources) }
            } else {
                AppleBackupSourceSignInView(source: source, store: controller.sources)
            }
        }
    }

    private var exportButton: some View {
        Button {
            Task {
                do {
                    document = try await AppleConfigurationDocument(data: controller.export(passphrase: passphrase))
                    passphrase = ""
                    exporting = true
                } catch { controller.setResult("Could not export configuration") }
            }
        } label: {
            AppleWorkingButtonLabel(title: "Export Configuration…", workingTitle: "Exporting…", isWorking: controller.isBusy && !importing)
        }
        .accessibilityIdentifier("backup.export")
    }

    private var importButton: some View {
        Button { importing = true } label: {
            AppleWorkingButtonLabel(title: "Import Configuration…", workingTitle: "Importing…", isWorking: controller.isBusy && importing)
        }
        .accessibilityIdentifier("backup.import")
    }
}

/// "Import Configuration…": pick a file, then confirm what it restores. Shared
/// by the Backup page and Discover's No Sources page.
@MainActor
private struct AppleConfigurationImport: ViewModifier {
    @Binding var isPresented: Bool
    let controller: AppleConfigurationController
    @State private var pendingImport: PendingImport?

    private struct PendingImport: Identifiable {
        let id = UUID()
        let data: Data
        let file: AppleConfigurationFile
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 10_000_000 else { throw AppleConfigurationError.tooLarge }
                    let data = try Data(contentsOf: url)
                    pendingImport = try PendingImport(data: data, file: AppleConfigurationFile.inspect(data))
                } catch { controller.setResult("Could not open configuration") }
            }
            .sheet(item: $pendingImport) { pending in
                AppleBackupImportView(controller: controller, data: pending.data, file: pending.file)
            }
    }
}

extension View {
    func appleConfigurationImport(isPresented: Binding<Bool>, controller: AppleConfigurationController) -> some View {
        modifier(AppleConfigurationImport(isPresented: isPresented, controller: controller))
    }
}

/// Discover's No Sources on a device with Backup & Sync: "Restore from iCloud"
/// where iCloud can be reached, "Import Backup", then Settings to add one.
@MainActor
struct AppleDiscoverRestoreEmptyState: View {
    let title: String
    let controller: AppleConfigurationController
    let offersICloud: Bool
    let openSettings: () -> Void
    @State private var importing = false

    var body: some View {
        Group {
            if offersICloud {
                AppleSourceEmptyState(
                    title: title, systemImage: OpenStreamTab.home.systemImage,
                    actionTitle: "Restore from iCloud", action: restoreFromICloud,
                    secondaryActionTitle: "Import Backup", secondaryAction: importBackup,
                    tertiaryActionTitle: "Open Settings", tertiaryAction: openSettings)
            } else {
                AppleSourceEmptyState(
                    title: title, systemImage: OpenStreamTab.home.systemImage,
                    actionTitle: "Open Settings", action: openSettings,
                    secondaryActionTitle: "Import Backup", secondaryAction: importBackup)
            }
        }
        .appleConfigurationImport(isPresented: $importing, controller: controller)
    }

    private func restoreFromICloud() {
        appleTrace("discover: restore from iCloud")
        Task { await controller.restoreFromCloud() }
    }

    private func importBackup() { importing = true }
}

@MainActor
private struct AppleBackupImportView: View {
    let controller: AppleConfigurationController
    let data: Data
    let file: AppleConfigurationFile
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Merge") {
                    LabeledContent("Sources", value: file.snapshot.sources.count.formatted())
                    LabeledContent("Watched", value: file.snapshot.watchedHistory.count.formatted())
                }
                Section("Replace") {
                    Text("Settings and channel selections")
                    LabeledContent("Playback progress", value: file.snapshot.playbackProgress.count.formatted())
                    LabeledContent("My List", value: file.snapshot.watchlist.count.formatted())
                    LabeledContent("Ratings", value: file.snapshot.ratings.count.formatted())
                }
                if file.isEncrypted {
                    Section { SecureField("Passphrase", text: $passphrase).textContentType(.password) }
                }
                if let error { Section { Text(error) } }
            }
            .navigationTitle("Import Configuration")
            .scrollIndicators(.hidden)
            .appleMacFormFields()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            do {
                                try await controller.restore(data, passphrase: passphrase)
                                passphrase = ""
                                dismiss()
                            } catch { self.error = (error as? AppleConfigurationError)?.localizedDescription ?? "Could not import configuration" }
                        }
                    }
                    .disabled(controller.isBusy || (file.isEncrypted && passphrase.isEmpty))
                }
            }
            .interactiveDismissDisabled(controller.isBusy)
        }
    }
}

@MainActor
private struct AppleBackupSourceSignInView: View {
    let source: AppleSource
    let store: AppleSourceStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if source.kind != .library {
                    TextField("Source address", text: $address)
                        .textContentType(.URL)
                }
                if source.iptvType == .xtream || source.kind == .nas {
                    TextField("Username", text: $username).textContentType(.username)
                    SecureField("Password", text: $password).textContentType(.password)
                }
                #if os(macOS)
                if let error { Text(error) }
                AppleFormActionSection { signInButton }
                #else
                signInButton
                if let error { Text(error) }
                #endif
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    #if os(macOS)
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    #else
                    let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    #endif
                    store.reconnectConfigurationFolder(id: source.id, url: url, bookmark: bookmark)
                    dismiss()
                } catch { self.error = "Could not open folder" }
            }
            .navigationTitle(source.name)
            .scrollIndicators(.hidden)
            .appleMacFormFields()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    @ViewBuilder
    private var signInButton: some View {
        if source.kind == .library {
            Button("Choose Folder…") { choosingFolder = true }
        } else {
            Button("Sign In") {
                do {
                    guard let url = URL(string: address),
                          ["http", "https", "smb"].contains(url.scheme?.lowercased() ?? ""),
                          url.host != nil else { throw AppleConfigurationError.invalidFile }
                    try store.restoreSourceSignIn(id: source.id, address: url, username: username, password: password)
                    dismiss()
                } catch { self.error = "Could not restore source" }
            }
            .appleMacFormPrimaryAction()
        }
    }
}
#endif
