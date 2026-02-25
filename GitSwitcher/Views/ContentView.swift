import SwiftUI

struct ContentView: View {
    @EnvironmentObject var service: GHCLIService

    var body: some View {
        if let error = service.ghError {
            Text(error.localizedDescription)
                .foregroundStyle(.red)
                .font(.caption)
            Divider()
        } else if service.accounts.isEmpty {
            Text("No accounts — add one below")
                .foregroundStyle(.secondary)
            Divider()
        } else {
            ForEach(service.accounts) { account in
                Button {
                    service.switchTo(account)
                } label: {
                    HStack {
                        Text(account.displayName)
                        Spacer()
                        if account.active {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            let removable = service.accounts.filter { !$0.active }
            if !removable.isEmpty {
                Menu("Remove Account") {
                    ForEach(removable) { account in
                        Button(account.displayName) {
                            service.remove(account)
                        }
                    }
                }
            }
        }

        Button("Add Account…") {
            service.addAccount()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
