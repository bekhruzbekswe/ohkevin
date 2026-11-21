import AppKit
import SwiftUI
import CallKit
@testable import OhKevinKit

/// The owner's app icon (the AppIcon.icns build.sh puts in the app) in light and dark Docks at 128, 64 and 32 px, for the status
/// page. Drawn by `--check`.
enum IconBoard {
    /// The app's own icon, from the app build.sh made (AppChecks has no bundle of its own); the plain app icon before a build.
    @MainActor static var icon: NSImage {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../build/\(appName).app/Contents/Resources/AppIcon.icns").standardized
        return NSImage(contentsOf: file) ?? NSApp.applicationIconImage
    }

    @MainActor static func draw(to folder: URL) {
        let image = icon
        for dark in [false, true] {
            let desk = dark ? Color(red: 0.11, green: 0.12, blue: 0.16) : Color(red: 0.80, green: 0.84, blue: 0.90), text: Color = dark ? .white : .black
            let board = VStack(alignment: .leading, spacing: 18) {
                ForEach([128, 64, 32] as [CGFloat], id: \.self) { px in
                    HStack(spacing: 16) {
                        Text("\(Int(px)) px").font(.system(size: 13)).foregroundStyle(text.opacity(0.7)).frame(width: 60, alignment: .leading)
                        HStack { Image(nsImage: image).resizable().interpolation(.high).frame(width: px / 2, height: px / 2) } // points at 2x
                            .padding(8).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45)))
                    }
                }
            }
            .padding(28).background(desk)
            let r = ImageRenderer(content: board); r.scale = 2
            if let cg = r.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: folder.appending(path: "icons-\(dark ? "dark" : "light").png")) }
        }
    }
}
