/// The product's name, in one place: the app, its menu and the build script read it from here.
public enum Product {
    public static let name = "Oh Kevin"
    /// The app's file name (without .app). Not `name`: the Mac app is "Oh Kevin.app", and dragging one over the other in /Applications
    /// replaced it. The name people see (menu bar, menus, Dock: CFBundleName) stays `name`. build.sh and release.sh read this too.
    public static let fileName = "Oh Kevin Launcher"
    /// Where a short name fits: the voice speaking of itself, the menu-bar item's description.
    public static let shortName = "Kevin"
    /// The folders a user already has (Application Support, Logs) keep the first name, so nothing is lost or moved.
    public static let folder = "Claude Voice"
}
