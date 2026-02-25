import XCTest
@testable import GitSwitcher

@MainActor
final class ProfileStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_add_profile_persists_to_disk() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")

        store.add(profile)

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertEqual(store2.profiles.count, 1)
        XCTAssertEqual(store2.profiles[0].gitEmail, "bob@work.com")
    }

    func test_delete_profile_removes_from_disk() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        store.add(profile)

        store.delete(profile)

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertTrue(store2.profiles.isEmpty)
    }

    func test_active_profile_id_persists() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Personal", gitName: "Alice", gitEmail: "alice@home.io")
        store.add(profile)
        store.activeProfileId = profile.id

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertEqual(store2.activeProfileId, profile.id)
    }

    func test_update_profile_replaces_in_place() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        store.add(profile)

        profile.gitEmail = "bob@newwork.com"
        store.update(profile)

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertEqual(store2.profiles[0].gitEmail, "bob@newwork.com")
    }

    func test_delete_active_profile_clears_activeProfileId() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        store.add(profile)
        store.activeProfileId = profile.id

        store.delete(profile)

        XCTAssertNil(store.activeProfileId)
        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertNil(store2.activeProfileId)
    }
}
