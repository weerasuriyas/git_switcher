import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) var dismiss
    @State private var editingProfile: GitProfile?
    @State private var showingAddSheet = false
    @StateObject private var launchManager = LaunchAtLoginManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Git Profiles")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            List {
                ForEach(store.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name).bold()
                            Text("\(profile.gitName) <\(profile.gitEmail)>")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingProfile = profile }
                            .buttonStyle(.borderless)
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { store.delete(store.profiles[$0]) }
                }
            }

            Divider()

            HStack {
                Button("+ Add Profile") { showingAddSheet = true }
                    .padding()
                Spacer()
            }

            Divider()

            Toggle("Launch at login", isOn: Binding(
                get: { launchManager.isEnabled },
                set: { newValue in
                    if newValue != launchManager.isEnabled {
                        launchManager.toggle()
                    }
                }
            ))
            .padding([.horizontal, .bottom])
            .onAppear { launchManager.refresh() }
        }
        .frame(width: 480, height: 380)
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .sheet(isPresented: $showingAddSheet) {
            ProfileFormView(profile: nil)
                .environmentObject(store)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileFormView(profile: profile)
                .environmentObject(store)
        }
    }
}

struct ProfileFormView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) var dismiss

    let existingProfile: GitProfile?

    @State private var name: String
    @State private var gitName: String
    @State private var gitEmail: String
    @State private var sshKeyPath: String
    @State private var directoryRules: [String]
    @State private var repoOverrides: [String]
    @State private var githubLogin: String

    // GitHub import state
    @State private var isImporting = false
    @State private var importStatus: ImportStatus = .idle
    @State private var usernameInput = ""
    @State private var showUsernameField = false

    enum ImportStatus: Equatable {
        case idle
        case success(String)  // login
        case error(String)
    }

    init(profile: GitProfile?) {
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _gitName = State(initialValue: profile?.gitName ?? "")
        _gitEmail = State(initialValue: profile?.gitEmail ?? "")
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
        _directoryRules = State(initialValue: profile?.directoryRules ?? [])
        _repoOverrides = State(initialValue: profile?.repoOverrides ?? [])
        _githubLogin = State(initialValue: profile?.githubLogin ?? "")
    }

    private var isValid: Bool {
        !name.isEmpty && !gitName.isEmpty && !gitEmail.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(existingProfile == nil ? "Add Profile" : "Edit Profile")
                    .font(.title2.bold())

                // GitHub import
                githubImportSection

                Divider()

                // Core fields
                Form {
                    TextField("Profile label (e.g. Work)", text: $name)
                    TextField("Full name", text: $gitName)
                    TextField("Email", text: $gitEmail)
                    TextField("SSH key path (optional)", text: $sshKeyPath)
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                // Directory rules
                folderRulesSection

                Divider()

                // Repo overrides
                repoOverridesSection

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.escape)
                    Button(existingProfile == nil ? "Add" : "Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                    .keyboardShortcut(.return)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 560)
    }

    // MARK: - GitHub import section

    private var githubImportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: startGitHubImport) {
                    HStack(spacing: 6) {
                        if isImporting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "person.badge.plus")
                        }
                        Text("Connect via GitHub")
                    }
                }
                .disabled(isImporting)

                if case .success(let login) = importStatus {
                    Label("Connected as @\(login)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if showUsernameField {
                HStack {
                    TextField("GitHub username", text: $usernameInput)
                        .frame(width: 200)
                    Button("Fetch") {
                        Task { await fetchByUsername() }
                    }
                    .disabled(usernameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if case .error(let msg) = importStatus {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Folder rules section

    private var folderRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Folders (applies to all repos inside)")
                .font(.headline)

            ForEach(directoryRules, id: \.self) { path in
                HStack {
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        directoryRules.removeAll { $0 == path }
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }
            }

            Button("+ Add Folder") {
                pickFolder { url in
                    let path = url.path
                    if !directoryRules.contains(path) {
                        directoryRules.append(path)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Repo overrides section

    private var repoOverridesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Specific Repos (override for one repo)")
                .font(.headline)

            ForEach(repoOverrides, id: \.self) { path in
                HStack {
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        repoOverrides.removeAll { $0 == path }
                        try? GitConfigRulesManager().removeRepoOverride(repoPath: path)
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }
            }

            Button("+ Add Repo") {
                pickFolder { url in
                    let path = url.path
                    guard !repoOverrides.contains(path) else { return }
                    guard FileManager.default.fileExists(atPath: "\(path)/.git") else { return }
                    repoOverrides.append(path)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Actions

    private func startGitHubImport() {
        isImporting = true
        importStatus = .idle
        let importer = GitHubImporter()

        if importer.isGHAvailable() {
            Task {
                do {
                    let info = try await importer.importViaGHCLI()
                    applyImport(info)
                } catch {
                    showUsernameField = true
                    importStatus = .error("gh CLI failed. Enter your GitHub username below.")
                }
                isImporting = false
            }
        } else {
            showUsernameField = true
            importStatus = .error("GitHub CLI not found. Enter your GitHub username below.")
            isImporting = false
        }
    }

    private func fetchByUsername() async {
        isImporting = true
        importStatus = .idle
        let importer = GitHubImporter()
        do {
            let info = try await importer.importViaUsername(usernameInput)
            applyImport(info)
            showUsernameField = false
        } catch {
            importStatus = .error(error.localizedDescription)
        }
        isImporting = false
    }

    private func applyImport(_ info: GitHubUserInfo) {
        if gitName.isEmpty { gitName = info.name }
        if gitEmail.isEmpty { gitEmail = info.email ?? "" }
        if name.isEmpty { name = info.login }
        githubLogin = info.login
        importStatus = .success(info.login)
    }

    private func pickFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func save() {
        let rulesManager = GitConfigRulesManager()
        if var existing = existingProfile {
            existing.name = name
            existing.gitName = gitName
            existing.gitEmail = gitEmail
            existing.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
            existing.githubLogin = githubLogin.isEmpty ? nil : githubLogin
            existing.directoryRules = directoryRules
            existing.repoOverrides = repoOverrides
            for path in repoOverrides {
                try? rulesManager.writeRepoOverride(repoPath: path, profile: existing)
            }
            store.update(existing)
        } else {
            let profile = GitProfile(
                name: name,
                gitName: gitName,
                gitEmail: gitEmail,
                sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
                githubLogin: githubLogin.isEmpty ? nil : githubLogin,
                directoryRules: directoryRules,
                repoOverrides: repoOverrides
            )
            for path in repoOverrides {
                try? rulesManager.writeRepoOverride(repoPath: path, profile: profile)
            }
            store.add(profile)
        }
    }
}
