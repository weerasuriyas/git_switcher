import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) var dismiss
    @State private var editingProfile: GitProfile?
    @State private var showingAddSheet = false

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
        }
        .frame(width: 480, height: 360)
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

    init(profile: GitProfile?) {
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _gitName = State(initialValue: profile?.gitName ?? "")
        _gitEmail = State(initialValue: profile?.gitEmail ?? "")
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
    }

    private var isValid: Bool {
        !name.isEmpty && !gitName.isEmpty && !gitEmail.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingProfile == nil ? "Add Profile" : "Edit Profile")
                .font(.title2.bold())

            Form {
                TextField("Profile label (e.g. Work)", text: $name)
                TextField("Full name", text: $gitName)
                TextField("Email", text: $gitEmail)
                TextField("SSH key path (optional)", text: $sshKeyPath)
                    .font(.system(.body, design: .monospaced))
            }

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
        .frame(width: 400)
    }

    private func save() {
        if var existing = existingProfile {
            existing.name = name
            existing.gitName = gitName
            existing.gitEmail = gitEmail
            existing.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
            store.update(existing)
        } else {
            let profile = GitProfile(
                name: name,
                gitName: gitName,
                gitEmail: gitEmail,
                sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath
            )
            store.add(profile)
        }
    }
}
