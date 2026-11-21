import AppKit
import AVFoundation
import Speech
import CallKit

/// The app's command line: `--call <link>` uses a running call server instead of starting one; `--log <file>` writes the call's
/// log (every word heard, sent and said); `--permissions` prints what macOS lets this copy do. The checks and measurements live
/// in AppChecks, which never ships.
let args = CommandLine.arguments
func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

/// The app: its window, menus and menu-bar item. AppChecks runs it with a window that draws pictures instead.
public func runApp() { runApp(window: Window()) }

func runApp(window: Window) {
    // What macOS lets this copy of the app do, without asking and without opening anything: the update rehearsal compares it before and
    // after an update (a stable signing identity keeps both; an ad-hoc one loses them).
    if args.contains("--permissions") {
        let mic = ["not asked yet", "restricted", "denied", "allowed"][AVCaptureDevice.authorizationStatus(for: .audio).rawValue]
        let speech = ["not asked yet", "denied", "restricted", "allowed"][SFSpeechRecognizer.authorizationStatus().rawValue]
        print("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") \(Bundle.main.bundleIdentifier ?? "?"): microphone \(mic), speech recognition \(speech)")
        exit(0)
    }

    let app = NSApplication.shared
    app.delegate = window
    func menu(_ title: String, _ items: [(String, Selector, String)]) -> NSMenuItem {
        let item = NSMenuItem(), sub = NSMenu(title: title)
        items.forEach { sub.addItem(withTitle: $0.0, action: $0.1, keyEquivalent: $0.2) }
        item.submenu = sub; return item
    }
    app.mainMenu = NSMenu()
    // The app menu as every Mac app has it: About, (Check for Updates…, added by Window when the app can update), Settings…, Services,
    // Hide, Hide Others, Show All, Quit. Its items aim at the app's delegate (Window) directly, so they work whatever window is in front.
    let appMenu = NSMenu(title: appName)
    func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", target: AnyObject? = nil, mods: NSEvent.ModifierFlags = .command) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = target; item.keyEquivalentModifierMask = mods
    }
    add(appMenu, "About \(appName)", #selector(Window.showAbout), target: window)
    appMenu.addItem(.separator())
    add(appMenu, "Settings…", #selector(Window.openSettings), ",", target: window)
    appMenu.addItem(.separator())
    let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: ""); services.submenu = NSMenu(title: "Services"); app.servicesMenu = services.submenu
    appMenu.addItem(services); appMenu.addItem(.separator())
    add(appMenu, "Hide \(appName)", #selector(NSApplication.hide(_:)), "h")
    add(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option])
    add(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
    appMenu.addItem(.separator())
    add(appMenu, "Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")
    let appItem = NSMenuItem(); appItem.submenu = appMenu
    app.mainMenu?.addItem(appItem)
    for m in [
              menu("File", [("Close", #selector(NSWindow.performClose(_:)), "w")]), // the call goes on
              menu("Edit", [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])] { app.mainMenu?.addItem(m) }
    app.setActivationPolicy(!window.drawing || ProcessInfo.processInfo.environment["REAL_POINTER"] == "1" ? .regular : .prohibited) // drawing figures: no Dock icon
    app.run()
}
