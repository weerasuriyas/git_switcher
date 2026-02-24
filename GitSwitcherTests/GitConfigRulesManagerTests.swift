import XCTest
@testable import GitSwitcher

final class GitConfigRulesManagerTests: XCTestCase {
    var tempDir: URL!
    var globalConfigURL: URL!
    var storageDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        globalConfigURL = tempDir.appendingPathComponent("gitconfig")
        storageDir = tempDir.appendingPathComponent("storage")
        try! FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: globalConfigURL.path, contents: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func makeManager() -> GitConfigRulesManager {
        GitConfigRulesManager(globalConfigPath: globalConfigURL.path, storageDirectory: storageDir.path)
    }

    func test_write_companion_config_creates_file_with_name_and_email() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.writeCompanionConfig(for: profile)
        let companionURL = storageDir.appendingPathComponent("\(profile.id.uuidString).gitconfig")
        XCTAssertTrue(FileManager.default.fileExists(atPath: companionURL.path))
        let content = try String(contentsOf: companionURL)
        XCTAssertTrue(content.contains("name = Bob"))
        XCTAssertTrue(content.contains("email = bob@work.com"))
    }

    func test_remove_companion_config_deletes_file() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.writeCompanionConfig(for: profile)
        try manager.removeCompanionConfig(for: profile)
        let companionURL = storageDir.appendingPathComponent("\(profile.id.uuidString).gitconfig")
        XCTAssertFalse(FileManager.default.fileExists(atPath: companionURL.path))
    }

    func test_apply_writes_includif_block_for_directory_rule() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.apply(profiles: [profile])
        let content = try String(contentsOf: globalConfigURL)
        XCTAssertTrue(content.contains("includeIf"))
        XCTAssertTrue(content.contains("/Users/bob/work/"))
        XCTAssertTrue(content.contains("\(profile.id.uuidString).gitconfig"))
    }

    func test_apply_with_no_rules_adds_no_includif() throws {
        let manager = makeManager()
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        try manager.apply(profiles: [profile])
        let content = try String(contentsOf: globalConfigURL)
        XCTAssertFalse(content.contains("includeIf"))
    }

    func test_apply_replaces_existing_managed_section() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.apply(profiles: [profile])
        profile.directoryRules = ["/Users/bob/newwork"]
        try manager.apply(profiles: [profile])
        let content = try String(contentsOf: globalConfigURL)
        XCTAssertTrue(content.contains("/Users/bob/newwork/"))
        XCTAssertFalse(content.contains("/Users/bob/work/"))
    }

    func test_apply_preserves_existing_non_managed_content() throws {
        let existing = "[user]\n\tname = Alice\n\temail = alice@example.com\n"
        try existing.write(to: globalConfigURL, atomically: true, encoding: .utf8)
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.apply(profiles: [profile])
        let content = try String(contentsOf: globalConfigURL)
        XCTAssertTrue(content.contains("name = Alice"))
        XCTAssertTrue(content.contains("includeIf"))
    }

    func test_write_repo_override_writes_to_git_config() throws {
        let repoDir = tempDir.appendingPathComponent("myrepo")
        let gitDir = repoDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let gitConfigFile = gitDir.appendingPathComponent("config")
        FileManager.default.createFile(atPath: gitConfigFile.path, contents: nil)
        let manager = makeManager()
        let profile = GitProfile(name: "Personal", gitName: "Alice", gitEmail: "alice@home.io")
        try manager.writeRepoOverride(repoPath: repoDir.path, profile: profile)
        let content = try String(contentsOf: gitConfigFile)
        XCTAssertTrue(content.contains("name = Alice"))
        XCTAssertTrue(content.contains("email = alice@home.io"))
    }

    func test_write_repo_override_throws_if_not_a_git_repo() {
        let notARepo = tempDir.appendingPathComponent("notarepo")
        try! FileManager.default.createDirectory(at: notARepo, withIntermediateDirectories: true)
        let manager = makeManager()
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        XCTAssertThrowsError(try manager.writeRepoOverride(repoPath: notARepo.path, profile: profile))
    }
}
