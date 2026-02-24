import Foundation

struct GitProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gitName: String
    var gitEmail: String
    var sshKeyPath: String?
    var signingKey: String?
    var signingFormat: String?
    var githubLogin: String?
    var directoryRules: [String]
    var repoOverrides: [String]

    init(
        id: UUID = UUID(),
        name: String,
        gitName: String,
        gitEmail: String,
        sshKeyPath: String? = nil,
        signingKey: String? = nil,
        signingFormat: String? = nil,
        githubLogin: String? = nil,
        directoryRules: [String] = [],
        repoOverrides: [String] = []
    ) {
        self.id = id
        self.name = name
        self.gitName = gitName
        self.gitEmail = gitEmail
        self.sshKeyPath = sshKeyPath
        self.signingKey = signingKey
        self.signingFormat = signingFormat
        self.githubLogin = githubLogin
        self.directoryRules = directoryRules
        self.repoOverrides = repoOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, gitName, gitEmail
        case sshKeyPath, signingKey, signingFormat
        case githubLogin, directoryRules, repoOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gitName = try container.decode(String.self, forKey: .gitName)
        gitEmail = try container.decode(String.self, forKey: .gitEmail)
        sshKeyPath = try container.decodeIfPresent(String.self, forKey: .sshKeyPath)
        signingKey = try container.decodeIfPresent(String.self, forKey: .signingKey)
        signingFormat = try container.decodeIfPresent(String.self, forKey: .signingFormat)
        githubLogin = try container.decodeIfPresent(String.self, forKey: .githubLogin)
        directoryRules = try container.decodeIfPresent([String].self, forKey: .directoryRules) ?? []
        repoOverrides = try container.decodeIfPresent([String].self, forKey: .repoOverrides) ?? []
    }
}
