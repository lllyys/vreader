import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader
@Suite("ThemeBackgroundStore") struct ThemeBackgroundTests {
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("TBT-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true); return tmp
    }
    #if canImport(UIKit)
    private func makeTestImage(width: Int = 100, height: Int = 100) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    @Test func saveBackground_savesImageToDisk() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "light", baseDirectory: d)
        #expect(FileManager.default.fileExists(atPath: ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d).path))
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_resizesLargeImage() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(width: 2048, height: 3072), for: "light", baseDirectory: d)
        let p = ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d)
        if let data = try? Data(contentsOf: p), let img = UIImage(data: data) { #expect(max(img.size.width, img.size.height) <= 1024) }
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_doesNotResizeSmallImage() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(width: 512, height: 512), for: "dark", baseDirectory: d)
        let p = ThemeBackgroundStore.backgroundPath(for: "dark", baseDirectory: d)
        if let data = try? Data(contentsOf: p), let img = UIImage(data: data) { #expect(img.size.width <= 1024); #expect(img.size.height <= 1024) }
        try? FileManager.default.removeItem(at: d)
    }
    @Test func loadBackground_returnsNil_whenNone() throws {
        let d = try makeTempDir(); #expect(ThemeBackgroundStore.loadBackground(for: "light", baseDirectory: d) == nil)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func loadBackground_returnsImage_whenSet() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "light", baseDirectory: d)
        #expect(ThemeBackgroundStore.loadBackground(for: "light", baseDirectory: d) != nil)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func removeBackground_deletesFile() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "s", baseDirectory: d)
        try ThemeBackgroundStore.removeBackground(for: "s", baseDirectory: d)
        #expect(!FileManager.default.fileExists(atPath: ThemeBackgroundStore.backgroundPath(for: "s", baseDirectory: d).path))
        try? FileManager.default.removeItem(at: d)
    }
    @Test func removeBackground_doesNotThrow_whenNoFile() throws {
        let d = try makeTempDir(); try ThemeBackgroundStore.removeBackground(for: "x", baseDirectory: d)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_resizesHighScaleImage() throws {
        // A 3000x3000px image at scale 3 reports as 1000x1000pt.
        // resizeIfNeeded must check pixel dimensions, not points.
        let d = try makeTempDir()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        // Render at scale 3 → 1000x1000pt but 3000x3000px
        let highScaleImage = UIGraphicsImageRenderer(
            size: CGSize(width: 1000, height: 1000), format: format
        ).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        }
        // Verify precondition: point size is within cap but pixels exceed it
        #expect(highScaleImage.size.width <= 1024)
        #expect(highScaleImage.size.height <= 1024)
        #expect(highScaleImage.scale == 3.0)
        // Save should trigger resize because pixel dimensions exceed 1024
        try ThemeBackgroundStore.saveBackground(highScaleImage, for: "light", baseDirectory: d)
        let p = ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d)
        let data = try Data(contentsOf: p)
        let loaded = UIImage(data: data)!
        // The saved image (rendered at scale 1.0) must have dimensions <= 1024
        #expect(max(loaded.size.width, loaded.size.height) <= 1024)
        // Pixels must also be <= 1024 (scale 1.0 → pixels == points)
        let pixelW = loaded.size.width * loaded.scale
        let pixelH = loaded.size.height * loaded.scale
        #expect(max(pixelW, pixelH) <= 1024)
        try? FileManager.default.removeItem(at: d)
    }
    @Test func saveBackground_overwritesExisting() throws {
        let d = try makeTempDir()
        try ThemeBackgroundStore.saveBackground(makeTestImage(width: 100, height: 100), for: "light", baseDirectory: d)
        try ThemeBackgroundStore.saveBackground(makeTestImage(width: 200, height: 200), for: "light", baseDirectory: d)
        let loaded = ThemeBackgroundStore.loadBackground(for: "light", baseDirectory: d)
        #expect(loaded != nil); #expect(loaded!.size.width == 200)
        try? FileManager.default.removeItem(at: d)
    }

    // MARK: - backgroundImageDataURL (feature #60 WI-12 / GH #795)
    //
    // The EPUB reader can't load the Photo theme's background image via a
    // `file://` URL — the WKWebView's `allowingReadAccessTo` scope covers
    // only the EPUB extraction directory, not Application Support. So the
    // image is injected into the EPUB CSS as an inline base64 `data:` URL.

    @Test func backgroundImageDataURL_returnsNil_whenNoBackground() throws {
        let d = try makeTempDir()
        #expect(ThemeBackgroundStore.backgroundImageDataURL(for: "photo", baseDirectory: d) == nil)
        try? FileManager.default.removeItem(at: d)
    }

    @Test func backgroundImageDataURL_returnsBase64JPEGDataURL_whenSet() throws {
        let d = try makeTempDir()
        try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "photo", baseDirectory: d)
        let url = try #require(ThemeBackgroundStore.backgroundImageDataURL(for: "photo", baseDirectory: d))
        #expect(url.absoluteString.hasPrefix("data:image/jpeg;base64,"),
                "EPUB Photo background is injected as an inline base64 data URL")
        try? FileManager.default.removeItem(at: d)
    }

    @Test func backgroundImageDataURL_payloadRoundTripsStoredJPEG() throws {
        let d = try makeTempDir()
        try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "photo", baseDirectory: d)
        let stored = try Data(contentsOf: ThemeBackgroundStore.backgroundPath(for: "photo", baseDirectory: d))
        let url = try #require(ThemeBackgroundStore.backgroundImageDataURL(for: "photo", baseDirectory: d))
        let base64 = String(url.absoluteString.dropFirst("data:image/jpeg;base64,".count))
        let decoded = try #require(Data(base64Encoded: base64))
        #expect(decoded == stored, "data URL payload must be the exact stored JPEG bytes")
        #expect(UIImage(data: decoded) != nil, "decoded payload is a valid image")
        try? FileManager.default.removeItem(at: d)
    }

    @Test func backgroundImageDataURL_isThemeScoped() throws {
        // A background saved for one theme key must not leak into another.
        let d = try makeTempDir()
        try ThemeBackgroundStore.saveBackground(makeTestImage(), for: "photo", baseDirectory: d)
        #expect(ThemeBackgroundStore.backgroundImageDataURL(for: "photo", baseDirectory: d) != nil)
        #expect(ThemeBackgroundStore.backgroundImageDataURL(for: "sepia", baseDirectory: d) == nil)
        try? FileManager.default.removeItem(at: d)
    }

    @Test func backgroundImageDataURL_reflectsLatestFileAfterOverwrite() throws {
        // The WI-12 `customBackgroundRevision` invalidation relies on
        // `backgroundImageDataURL` always reading the CURRENT file — it
        // must never cache internally, so a re-pick produces a new URL.
        let d = try makeTempDir()
        try ThemeBackgroundStore.saveBackground(makeTestImage(width: 60, height: 60), for: "photo", baseDirectory: d)
        let first = try #require(ThemeBackgroundStore.backgroundImageDataURL(for: "photo", baseDirectory: d))
        try ThemeBackgroundStore.saveBackground(makeTestImage(width: 240, height: 240), for: "photo", baseDirectory: d)
        let second = try #require(ThemeBackgroundStore.backgroundImageDataURL(for: "photo", baseDirectory: d))
        #expect(first != second, "data URL must reflect the overwritten file, not a stale read")
        try? FileManager.default.removeItem(at: d)
    }
    #endif
    @Test func backgroundPath_uniquePerTheme() throws {
        let d = try makeTempDir()
        #expect(ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d) != ThemeBackgroundStore.backgroundPath(for: "dark", baseDirectory: d))
        try? FileManager.default.removeItem(at: d)
    }
    @Test func backgroundPath_usesJPEGExtension() throws {
        let d = try makeTempDir()
        #expect(ThemeBackgroundStore.backgroundPath(for: "light", baseDirectory: d).pathExtension == "jpg")
        try? FileManager.default.removeItem(at: d)
    }
}
