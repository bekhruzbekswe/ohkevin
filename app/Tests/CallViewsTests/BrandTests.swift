import Foundation
import Testing
@testable import CallViews

/// The brand mark's SVGs are copied into Brand.swift; the owner's files in design/logo stay the one source.
@Test func theBrandMarkIsTheLogoSetsOwn() throws {
    let logo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../design/logo")
    for (embedded, file) in [(Logo.full, "mark-full-ink.svg"), (Logo.compact, "mark-compact-ink.svg")] {
        #expect(LogoArt(svg: try String(contentsOf: logo.appending(path: file), encoding: .utf8)) == embedded, "update CallViews/Brand.swift from design/logo/\(file)")
    }
}
