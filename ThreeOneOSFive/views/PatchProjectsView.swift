import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Extensiones de Estética Neón para 3105 (Basado en tu interfaz)
struct AppTheme {
    static let background = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let cardBackground = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let secondaryCard = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let accent = Color(red: 1.0, green: 0.85, blue: 0.15) // Amarillo Neón por defecto
    static let emptyIconSize: CGFloat = 50
}

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

// MARK: - PatchProjectsView con Estética Neón
struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @StateObject private var store = PatchProjectStore()
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var searchText = ""

    private var filteredItems: [PatchLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            if item.packageURL.lastPathComponent.localizedCaseInsensitiveContains(query) {
                return true
            }
            guard let project = item.project else { return false }
            return project.name.localizedCaseInsensitiveContains(query)
                || project.allBundleIdentifiers.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
                || project.directories.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                }
                || project.rules.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                        || $0.replacementFilename.localizedCaseInsensitiveContains(query)
                }
        }
    }

    init() {
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            NavigationStack {
                VStack(spacing: 0) {
                    // Barra de búsqueda con estética integrada
                    AppSearchField(
                        text: $searchText,
                        prompt: language.text("patch.search"),
                        clearLabel: language.text("common.clear")
                    )
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    
                    List {
                        if store.items.isEmpty && !store.isBusy {
                            emptyState
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else if filteredItems.isEmpty && !store.isBusy {
                            searchEmptyState
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredItems) { item in
                                itemRow(item)
                                    .listRowBackground(AppTheme.cardBackground)
                            }
                            .onDelete { offsets in
                                offsets.map { filteredItems[$0] }.forEach(store.delete)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
                .background(AppTheme.background)
                .navigationTitle(language.text("patch.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showCreate = true
                            } label: {
                                Label(language.text("patch.new"), systemImage: "doc.badge.plus")
                            }
                            Button {
                                showImporter = true
                            } label: {
                                Label(language.text("patch.import"), systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            if store.isBusy {
                                ProgressView()
                                    .tint(AppTheme.accent)
                            } else {
                                Image(systemName: "plus")
                                    .foregroundColor(AppTheme.accent)
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(8)
                                    .background(AppTheme.secondaryCard)
                                    .clipShape(Circle())
                            }
                        }
                        .disabled(store.isBusy)
                        .accessibilityLabel(language.text("patch.add"))
                    }
                }
                .sheet(isPresented: $showImporter) {
                    FileDocumentPicker(
                        allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                        copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                        allowsMultipleSelection: false,
                        onSelection: { result in
                            showImporter = false
                            if case .success(let urls) = result, let url = urls.first {
                                store.importPackage(at: url)
                            }
                        },
                        onCancel: {
                            showImporter = false
                        }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showCreate) {
                    PatchProjectEditorView(
                        existingProject: nil,
                        passwordIsProtected: false
                    ) { project, password in
                        store.create(project: project, password: password)
                    }
                }
                .sheet(item: $draftCoordinator.request) { request in
                    PatchProjectEditorView(
                        existingProject: nil,
                        passwordIsProtected: false,
                        initialDraft: request.draft
                    ) { project, password in
                        store.create(project: project, password: password)
                        draftCoordinator.clear()
                    }
                }
                .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { _ in
                    PatchUnlockView(store: store)
                }
                .alert(item: $store.alert) { alert in
                    Alert(
                        title: Text(language.text(alert.titleKey)),
                        message: Text(alert.message(language: language)),
                        dismissButton: .default(Text(language.text("common.ok")))
                    )
                }
                .onAppear(perform: consumeExternalImport)
                .onChange(of: draftCoordinator.importRequest?.id) { _ in
                    consumeExternalImport()
                }
            }
        }
    }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                PatchProjectRow(item: item, language: language)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundColor(AppTheme.accent)
                .shadow(color: AppTheme.accent.opacity(0.5), radius: 10, x: 0, y: 0)
            Text(language.text("patch.empty_title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text(language.text("patch.empty_message"))
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .frame(height: 44)
                .padding(.horizontal, 24)
                .background(AppTheme.accent)
                .cornerRadius(14)
                .shadow(color: AppTheme.accent.opacity(0.5), radius: 8, x: 0, y: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundColor(.gray)
            Text(language.text("patch.search_empty"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text(language.text("patch.search_empty_message"))
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

// MARK: - Fila Estilizada con Tarjeta Neón
private struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 42, height: 42)
                
                Image(systemName: item.isLocked ? "lock.doc.fill" : "shippingbox.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.accent)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text(item.isLocked
                     ? language.text("patch.tap_to_unlock")
                     : language.text(
                        item.summary.schemaVersion >= 2 ? "patch.workspace_items_count" : "patch.rules_count",
                        Int64((item.project?.rules.count ?? 0) + (item.project?.directories.count ?? 0))
                     ))
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if item.summary.isPasswordProtected {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - PatchUnlockView con Estética Neón
private struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            NavigationStack {
                Form {
                    Section {
                        SecureField(language.text("patch.password"), text: $password)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .onSubmit(unlock)
                            .foregroundColor(.white)
                    } footer: {
                        Text(language.text("patch.password_once_message"))
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .navigationTitle(language.text("patch.unlock"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.text("common.cancel")) { dismiss() }
                            .foregroundColor(.gray)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.text("patch.unlock"), action: unlock)
                            .disabled(password.isEmpty || store.isBusy)
                            .foregroundColor(AppTheme.accent)
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}
