import Foundation

struct GitConfigManager {
    let configPath: String

    init(configPath: String = "\(NSHomeDirectory())/.gitconfig") {
        self.configPath = configPath
    }

    func apply(_ profile: GitProfile) throws {
        try run("git", "config", "--file", configPath, "user.name", profile.gitName)
        try run("git", "config", "--file", configPath, "user.email", profile.gitEmail)

        if let sshKey = profile.sshKeyPath, !sshKey.isEmpty {
            let sshCommand = "ssh -i \(sshKey) -o IdentitiesOnly=yes"
            try run("git", "config", "--file", configPath, "core.sshCommand", sshCommand)
        }

        if let signingKey = profile.signingKey, !signingKey.isEmpty {
            try run("git", "config", "--file", configPath, "user.signingkey", signingKey)
            if let format = profile.signingFormat, !format.isEmpty {
                try run("git", "config", "--file", configPath, "gpg.format", format)
            }
        }
    }

    func read(key: String) throws -> String {
        let output = try runOutput("git", "config", "--file", configPath, key)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func readCurrentNameEmail() throws -> (String, String) {
        let name = try read(key: "user.name")
        let email = try read(key: "user.email")
        return (name, email)
    }

    @discardableResult
    private func run(_ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitConfigError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        return process.terminationStatus
    }

    private func runOutput(_ args: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitConfigError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum GitConfigError: LocalizedError {
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code):
            return "Command `\(cmd)` failed with exit code \(code)"
        }
    }
}
