import XCTest
@testable import Tidy

final class CleanupTests: XCTestCase {
    private var root: URL!
    private var library: URL { root.appending(path: "Library") }
    private var downloads: URL { root.appending(path: "Downloads") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "CleanupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func file(_ url: URL, _ path: String) throws -> URL {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: file)
        return file
    }

    private func scan(running: Set<String> = []) -> [CleanupTarget] {
        CleanupScanner.scan(library: library, installerFolders: [downloads], running: running)
    }

    func testCleaningCachesKeepsAppleAndOpenAppsCaches() throws {
        let unused = try file(library, "Caches/com.example.unused/data")
        let apple = try file(library, "Caches/com.apple.Safari/data")
        let open = try file(library, "Caches/com.example.open/data")
        let companyFolder = try file(library, "Caches/Google/Chrome/data")

        let caches = try XCTUnwrap(scan(running: ["com.example.open", "google"]).first { $0.id == "caches" })
        XCTAssertEqual(caches.method, .delete)
        let result = CleanupScanner.clean(caches)

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: unused.path))
        XCTAssertTrue(fm.fileExists(atPath: apple.path))
        XCTAssertTrue(fm.fileExists(atPath: open.path))
        XCTAssertTrue(fm.fileExists(atPath: companyFolder.path))
        XCTAssertTrue(fm.fileExists(atPath: library.appending(path: "Caches").path), "The Caches folder itself must stay")
        XCTAssertGreaterThan(result.bytes, 0)
        XCTAssertEqual(result.failures, 0)
    }

    func testInstallersAreOptionalAndOnlyInstallers() throws {
        let dmg = try file(downloads, "App.dmg")
        let sorted = try file(downloads, "Installers/Other.pkg")
        try file(downloads, "Contract.pdf")
        try file(downloads, "Documents/Invoice.pdf")

        let installers = try XCTUnwrap(scan().first { $0.id == "installers" })
        XCTAssertEqual(installers.method, .trash)
        XCTAssertFalse(installers.isRecommended, "Installers must never be ticked by default")
        XCTAssertEqual(Set(installers.entries.map { $0.resolvingSymlinksInPath() }),
                       Set([dmg, sorted].map { $0.resolvingSymlinksInPath() }))
    }

    func testXcodeFilesAreSkippedWhileXcodeIsOpen() throws {
        try file(library, "Developer/Xcode/DerivedData/Project/build")
        XCTAssertNotNil(scan().first { $0.id == "derivedData" })
        XCTAssertNil(scan(running: ["com.apple.dt.xcode"]).first { $0.id == "derivedData" })
    }

    func testNothingFoundMeansNothingOffered() {
        XCTAssertTrue(scan().isEmpty)
    }
}

final class AppsScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "AppsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func app(_ path: String, category: String?) throws -> URL {
        let url = root.appending(path: path)
        let contents = url.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": "com.example.\(UUID().uuidString)", "CFBundleName": "Test"]
        if let category { plist["LSApplicationCategoryType"] = category }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        return url
    }

    func testCategoryNames() {
        XCTAssertEqual(AppsScanner.categoryName(for: "public.app-category.developer-tools"), "Developer Tools")
        XCTAssertEqual(AppsScanner.categoryName(for: "public.app-category.action-games"), "Games")
        XCTAssertEqual(AppsScanner.categoryName(for: "public.app-category.something-new"), "Other")
        XCTAssertEqual(AppsScanner.categoryName(for: nil), "Other")
    }

    func testFindsAppsOneFolderDownAndIgnoresOtherFiles() throws {
        _ = try app("Beta.app", category: "public.app-category.utilities")
        _ = try app("Tools/Alpha.app", category: nil)
        _ = try app("Tools/Deep/TooDeep.app", category: nil)
        try Data().write(to: root.appending(path: "readme.txt"))

        let apps = AppsScanner.apps(in: [root])
        XCTAssertEqual(apps.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(apps.map(\.category), ["Other", "Utilities"])
    }

    func testMoveNeverReplacesAnExistingApp() throws {
        let stray = try app("Downloads/Foo.app", category: nil)
        let applications = root.appending(path: "Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let moved = try AppsScanner.move(stray, into: applications)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path))

        let second = try app("Desktop/Foo.app", category: nil)
        XCTAssertThrowsError(try AppsScanner.move(second, into: applications))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path), "The app must stay put if it can't move")
    }

    func testUnusedNeedsAKnownOldDate() {
        let url = URL(filePath: "/Applications/Foo.app")
        func app(_ date: Date?) -> AppInfo { AppInfo(url: url, name: "Foo", category: "Other", lastUsed: date) }
        XCTAssertTrue(app(.now.addingTimeInterval(-86_400 * 365)).isUnused)
        XCTAssertFalse(app(.now).isUnused)
        XCTAssertFalse(app(nil).isUnused, "An unknown date must not look unused")
    }
}
