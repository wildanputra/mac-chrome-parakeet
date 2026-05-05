import XCTest
@testable import MacParakeetCore

final class ThumbnailCacheServiceTests: XCTestCase {
    var service: ThumbnailCacheService!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbnail-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ThumbnailCacheService(cacheDir: tempDir.path)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCachedThumbnailReturnsNilWhenNotCached() {
        let result = service.cachedThumbnail(for: UUID())
        XCTAssertNil(result)
    }

    func testCachedThumbnailReturnsCachedFile() throws {
        let id = UUID()
        let filePath = tempDir.appendingPathComponent("\(id.uuidString).jpg")
        try Data([0xFF, 0xD8]).write(to: filePath)

        let result = service.cachedThumbnail(for: id)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lastPathComponent, "\(id.uuidString).jpg")
    }

    func testCacheThumbnailDataWritesEmbeddedArtwork() throws {
        let id = UUID()
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let url = try service.cacheThumbnailData(artwork, for: id)

        XCTAssertEqual(url.lastPathComponent, "\(id.uuidString).jpg")
        XCTAssertEqual(try Data(contentsOf: url), artwork)
        XCTAssertEqual(service.cachedThumbnail(for: id), url)
    }

    func testDeleteThumbnail() throws {
        let id = UUID()
        let filePath = tempDir.appendingPathComponent("\(id.uuidString).jpg")
        try Data([0xFF, 0xD8]).write(to: filePath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
        service.deleteThumbnail(for: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
    }

    func testDeleteNonexistentThumbnailDoesNotThrow() {
        service.deleteThumbnail(for: UUID())
    }
}
