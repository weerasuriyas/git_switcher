import XCTest
@testable import GitSwitcher

final class GitConfigManagerTests: XCTestCase {
    var tempConfigURL: URL!

    override func setUp() {
        super.setUp()
        tempConfigURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("test_gitconfig_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempConfigURL.path, contents: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempConfigURL)
        super.tearDown()
    }

    func test_apply_profile_writes_name_and_email() throws {
        let manager = GitConfigManager(configPath: tempConfigURL.path)
        let profile = GitProfile(name: "Work", gitName: "Test User", gitEmail: "test@example.com")

        try manager.apply(profile)

        let name = try manager.read(key: "user.name")
        let email = try manager.read(key: "user.email")
        XCTAssertEqual(name, "Test User")
        XCTAssertEqual(email, "test@example.com")
    }

    func test_read_current_profile_returns_name_email() throws {
        let manager = GitConfigManager(configPath: tempConfigURL.path)
        let profile = GitProfile(name: "Personal", gitName: "Alice", gitEmail: "alice@home.io")
        try manager.apply(profile)

        let (name, email) = try manager.readCurrentNameEmail()
        XCTAssertEqual(name, "Alice")
        XCTAssertEqual(email, "alice@home.io")
    }

    func test_apply_profile_with_ssh_key_containing_space() throws {
        let manager = GitConfigManager(configPath: tempConfigURL.path)
        let profile = GitProfile(
            name: "Work",
            gitName: "Bob",
            gitEmail: "bob@work.com",
            sshKeyPath: "/Users/bob/my keys/id_work"
        )
        try manager.apply(profile)
        let sshCommand = try manager.read(key: "core.sshCommand")
        XCTAssertTrue(sshCommand.contains("'"), "SSH key path must be shell-quoted")
        XCTAssertTrue(sshCommand.contains("/Users/bob/my keys/id_work"), "Path must be preserved")
    }
}
