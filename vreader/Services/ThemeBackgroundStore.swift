import Foundation
#if canImport(UIKit)
import UIKit
#endif
enum ThemeBackgroundStore {
    static let maxDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.8
    static func backgroundPath(for themeName: String, baseDirectory: URL? = nil) -> URL {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ThemeBackgrounds", isDirectory: true).appendingPathComponent(themeName).appendingPathExtension("jpg")
    }
    #if canImport(UIKit)
    static func saveBackground(_ image: UIImage, for themeName: String, baseDirectory: URL? = nil) throws {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let resized = resizeIfNeeded(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { throw ThemeBackgroundError.compressionFailed }
        try data.write(to: path, options: .atomic)
    }
    static func loadBackground(for themeName: String, baseDirectory: URL? = nil) -> UIImage? {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path), let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }
    #endif
    static func removeBackground(for themeName: String, baseDirectory: URL? = nil) throws {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
    /// Photo-theme EPUB support (feature #60 WI-12 / GH #795). Returns the
    /// stored background image as an inline `data:image/jpeg;base64,…` URL.
    ///
    /// EPUB rendering injects the Photo theme's background image through
    /// `ReaderThemeV2.epubOverrideCSS(backgroundImageURL:)`. A `file://`
    /// URL can't be used there: `EPUBWebViewBridge` scopes the WKWebView's
    /// `allowingReadAccessTo` to the EPUB extraction directory, so a URL
    /// into Application Support is refused. A `data:` URL carries the
    /// bytes inline and needs no read-access grant. The stored file is
    /// already capped at `maxDimension`px / `jpegQuality`, so the encoded
    /// string stays bounded. Returns nil when no background is stored.
    static func backgroundImageDataURL(for themeName: String, baseDirectory: URL? = nil) -> URL? {
        let path = backgroundPath(for: themeName, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              !data.isEmpty else { return nil }
        return URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
    }
    #if canImport(UIKit)
    private static func resizeIfNeeded(_ image: UIImage, maxDimension maxDim: CGFloat) -> UIImage {
        // Use pixel dimensions to avoid scale mismatch.
        // image.size is in points; a 3000x3000px image at scale 3 reports 1000x1000pt.
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > maxDim || pixelHeight > maxDim else { return image }
        let scale = pixelWidth > pixelHeight ? maxDim / pixelWidth : maxDim / pixelHeight
        let newSize = CGSize(width: (pixelWidth * scale).rounded(), height: (pixelHeight * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
enum ThemeBackgroundError: Error { case compressionFailed }
