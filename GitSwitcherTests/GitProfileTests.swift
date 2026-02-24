import XCTest
@testable import GitSwitcher

final class GitProfileTests: XCTestCase {
    func test_encode_decode_roundtrip() throws {
        let profile = GitProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Work",
            gitName: "Jane Doe",
            gitEmail: "jane@corp.com",
            sshKeyPath: "/Users/jane/.ssh/id_work",
            signingKey: nil,
            signingFormat: nil
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.gitName, profile.gitName)
        XCTAssertEqual(decoded.gitEmail, profile.gitEmail)
        XCTAssertEqual(decoded.sshKeyPath, profile.sshKeyPath)
        XCTAssertNil(decoded.signingKey)
    }

    func test_default_values() {
        let profile = GitProfile(name: "Personal", gitName: "Jane", gitEmail: "jane@home.com")
        XCTAssertNotNil(profile.id)
        XCTAssertNil(profile.sshKeyPath)
        XCTAssertNil(profile.signingKey)
        XCTAssertNil(profile.signingFormat)
    }
}
