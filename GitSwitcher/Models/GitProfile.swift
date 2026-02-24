import Foundation

struct GitProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gitName: String
    var gitEmail: String
    var sshKeyPath: String?
    var signingKey: String?
    var signingFormat: String?

    init(
        id: UUID = UUID(),
        name: String,
        gitName: String,
        gitEmail: String,
        sshKeyPath: String? = nil,
        signingKey: String? = nil,
        signingFormat: String? = nil
    ) {
        self.id = id
        self.name = name
        self.gitName = gitName
        self.gitEmail = gitEmail
        self.sshKeyPath = sshKeyPath
        self.signingKey = signingKey
        self.signingFormat = signingFormat
    }
}
