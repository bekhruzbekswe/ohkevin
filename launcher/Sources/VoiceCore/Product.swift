import Foundation

/// The product's name, in one place: the app, its menu and the build script read it from here.
public enum Product {
    public static let name = "Oh Kevin"
    /// The app's file name (without .app). Not `name`: the Mac app is "Oh Kevin.app", and dragging one over the other in /Applications
    /// replaced it. The name people see (menu bar, menus, Dock: CFBundleName) stays `name`. build.sh and release.sh read this too.
    public static let fileName = "Oh Kevin Launcher"
    /// Where a short name fits: the voice speaking of itself, the menu-bar item's description.
    public static let shortName = "Kevin"
    /// The app's folders in Application Support and Logs.
    public static let folder = "Oh Kevin"
    /// Their name before the product had one: moved to `folder` once (FolderMove).
    public static let oldFolder = "Claude Voice"
}

/// Moves the app's folders from their first name to Product.folder, once, at launch, before anything uses them: each folder is
/// renamed in one step (nothing copied), only when the old one is there and the new one is not, and the saved voice folder that
/// pointed into it is rewritten. Both there: the old one is left alone, and said so.
public enum FolderMove {
    /// What it did, one line per folder, for the log. Empty when there was nothing to do.
    @discardableResult public static func run(home: URL, defaults: UserDefaults = .standard) -> [String] {
        let fm = FileManager.default
        var said: [String] = []
        for place in ["Library/Application Support", "Library/Logs"] {
            let old = home.appending(path: "\(place)/\(Product.oldFolder)"), new = home.appending(path: "\(place)/\(Product.folder)")
            guard fm.fileExists(atPath: old.path) else { continue }
            if fm.fileExists(atPath: new.path) { said.append("Both \(old.path) and \(new.path) exist: the old one is left as it is."); continue }
            do { try fm.moveItem(at: old, to: new); said.append("Moved \(old.path) to \(new.path).") }
            catch { said.append("Could not move \(old.path): \(error.localizedDescription)") }
        }
        let support = home.appending(path: "Library/Application Support")
        let before = support.appending(path: Product.oldFolder).path + "/", after = support.appending(path: Product.folder).path + "/"
        var settings = CallSettings.load(from: defaults)
        if let voice = settings.kokoroFolder, (voice + "/").hasPrefix(before), fm.fileExists(atPath: after) {
            settings.kokoroFolder = String((after + (voice + "/").dropFirst(before.count)).dropLast())
            settings.save(to: defaults)
        }
        return said
    }
}
