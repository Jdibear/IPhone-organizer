import XCTest
@testable import Tidy

@MainActor
final class AutoTidyTests: XCTestCase {
    private var folder: URL!
    private var controller: AutoTidyController?

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TidyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: AutoTidyController.enabledKey)
    }

    override func tearDown() async throws {
        controller?.isEnabled = false
        controller = nil
        chmod(folder.path, 0o755)
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removeObject(forKey: AutoTidyController.enabledKey)
    }

    private func write(_ name: String) throws {
        try Data("test".utf8).write(to: folder.appending(path: name))
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: path).path)
    }

    func testSortsNewFilesButLeavesExistingOnesAlone() async throws {
        try write("already-here.pdf")
        let controller = AutoTidyController(folder: folder)
        self.controller = controller
        controller.isEnabled = true

        try await Task.sleep(for: .seconds(1.5))
        try write("new-download.pdf")
        try await Task.sleep(for: .seconds(7))

        XCTAssertTrue(exists("already-here.pdf"), "a file that was there before watching started was moved")
        XCTAssertTrue(exists("Documents/new-download.pdf"), "the new file wasn't sorted")
    }

    /// Regression: when the folder couldn't be read at startup (no permission yet), every existing
    /// file was treated as new and got sorted once access came through.
    func testExistingFilesSurviveStartingBeforeAccessIsGranted() async throws {
        try write("old-statement.docx")
        try write("old-photo.png")
        chmod(folder.path, 0o000)

        let controller = AutoTidyController(folder: folder)
        self.controller = controller
        controller.isEnabled = true
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotNil(controller.status, "should report that it's waiting for access")

        chmod(folder.path, 0o755)
        try await Task.sleep(for: .seconds(8))  // retry happens after 5 s

        XCTAssertNil(controller.status)
        XCTAssertTrue(exists("old-statement.docx"))
        XCTAssertTrue(exists("old-photo.png"))
        XCTAssertFalse(exists("Documents"))
        XCTAssertFalse(exists("Images"))

        try write("fresh.png")
        try await Task.sleep(for: .seconds(7))
        XCTAssertTrue(exists("Images/fresh.png"), "new files should still be sorted after access is granted")
        XCTAssertTrue(exists("old-photo.png"))
    }
}
