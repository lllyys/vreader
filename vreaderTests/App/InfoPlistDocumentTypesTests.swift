import Testing
import Foundation

/// Feature #59 WI-1: regression guard for the Info.plist document-type
/// registration that makes vreader appear in iOS Share Sheet / "Open in…"
/// for the 5 supported book formats.
///
/// These assertions catch accidental removal of `CFBundleDocumentTypes`,
/// `UTImportedTypeDeclarations`, or `LSSupportsOpeningDocumentsInPlace`
/// from `project.yml`. They do NOT test iOS LaunchServices behavior
/// (which is the OS's job); the Share Sheet appearance is verified
/// manually in WI-1's Gate 5a slice verification.
@Suite("Feature #59 — Info.plist document-type registration")
struct InfoPlistDocumentTypesTests {

    /// Helper: the main bundle's parsed Info.plist. Tests assert against
    /// this snapshot rather than the source `project.yml` so we catch
    /// xcodegen / plist-processing-phase regressions, not just YAML edits.
    private func mainInfoPlist() throws -> [String: Any] {
        try #require(Bundle.main.infoDictionary)
    }

    @Test func lsSupportsOpeningDocumentsInPlaceIsTrue() throws {
        let info = try mainInfoPlist()
        #expect(info["LSSupportsOpeningDocumentsInPlace"] as? Bool == true,
                "LSSupportsOpeningDocumentsInPlace must be true so iOS hands incoming URLs to vreader in-place rather than copying first")
    }

    @Test func cfBundleDocumentTypesContainsAllFiveFamilies() throws {
        let info = try mainInfoPlist()
        let types = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]],
                                  "CFBundleDocumentTypes must be an array of dicts")
        // Flatten every declared LSItemContentTypes into one set for membership checks.
        let allUTIs = Set(types.flatMap { entry -> [String] in
            (entry["LSItemContentTypes"] as? [String]) ?? []
        })
        #expect(allUTIs.contains("org.idpf.epub-container"), "EPUB UTI missing")
        #expect(allUTIs.contains("com.adobe.pdf"), "PDF UTI missing")
        #expect(allUTIs.contains("public.plain-text"), "TXT UTI missing")
        #expect(allUTIs.contains("net.daringfireball.markdown"), "Markdown UTI missing")
        #expect(allUTIs.contains("com.amazon.azw3"), "AZW3 imported UTI missing")
        #expect(allUTIs.contains("com.amazon.mobi-pocket"), "MOBI imported UTI missing")
    }

    @Test func everyCFBundleDocumentTypeIsAlternateRank() throws {
        let info = try mainInfoPlist()
        let types = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        for entry in types {
            let rank = entry["LSHandlerRank"] as? String
            #expect(rank == "Alternate",
                    "Every CFBundleDocumentTypes entry must declare LSHandlerRank=Alternate so vreader is a polite alternative, not the default opener. Found: \(rank ?? "nil") for \(entry["CFBundleTypeName"] ?? "<unnamed>")")
        }
    }

    @Test func utImportedTypeDeclarationsCoverKindleFamily() throws {
        let info = try mainInfoPlist()
        let imports = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]],
                                    "UTImportedTypeDeclarations required for the Kindle family — Apple does not ship public UTIs for .azw3/.mobi")
        let identifiers = Set(imports.compactMap { $0["UTTypeIdentifier"] as? String })
        #expect(identifiers.contains("com.amazon.azw3"), "AZW3 imported type missing")
        #expect(identifiers.contains("com.amazon.mobi-pocket"), "MOBI imported type missing")

        // Each imported type must conform to public.data (canonical for opaque binary).
        for entry in imports {
            let conforms = entry["UTTypeConformsTo"] as? [String]
            #expect(conforms?.contains("public.data") == true,
                    "\(entry["UTTypeIdentifier"] ?? "<unknown>") must conform to public.data")
        }
    }

    @Test func azw3ImportedTypeCoversAzw3AndAzwExtensions() throws {
        let info = try mainInfoPlist()
        let imports = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let azw3 = try #require(imports.first { ($0["UTTypeIdentifier"] as? String) == "com.amazon.azw3" })
        let tagSpec = try #require(azw3["UTTypeTagSpecification"] as? [String: Any])
        let extensions = (tagSpec["public.filename-extension"] as? [String]) ?? []
        #expect(extensions.contains("azw3"), ".azw3 extension missing from com.amazon.azw3 tag spec")
        #expect(extensions.contains("azw"), ".azw extension missing from com.amazon.azw3 tag spec")
    }

    @Test func mobiImportedTypeCoversMobiAndPrcExtensions() throws {
        let info = try mainInfoPlist()
        let imports = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let mobi = try #require(imports.first { ($0["UTTypeIdentifier"] as? String) == "com.amazon.mobi-pocket" })
        let tagSpec = try #require(mobi["UTTypeTagSpecification"] as? [String: Any])
        let extensions = (tagSpec["public.filename-extension"] as? [String]) ?? []
        #expect(extensions.contains("mobi"), ".mobi extension missing from com.amazon.mobi-pocket tag spec")
        #expect(extensions.contains("prc"), ".prc extension missing from com.amazon.mobi-pocket tag spec")
    }
}
