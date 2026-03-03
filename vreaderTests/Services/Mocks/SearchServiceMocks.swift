import Foundation

@testable import vreader

// MARK: - Mock Content Provider

struct MockContentProvider: ContentProviderProtocol {
    var chapters: [String: String] = [:]

    func textContent(forChapter index: Int) -> String? {
        chapters[String(index)]
    }

    func chapterCount() -> Int {
        chapters.count
    }
}
