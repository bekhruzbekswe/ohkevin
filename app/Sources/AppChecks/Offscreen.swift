import AppKit
import CallViews
import SwiftUI
import VoiceCore
@testable import OhKevinKit

/// `AppChecks --offscreen <folder>`: the menu-bar panel in every state this app draws, and the closed Settings card,
/// light and dark at 2×, rendered offscreen (ImageRenderer): no window opens. The same states as `--check`'s "launcher" sheet.
@MainActor
enum Offscreen {
    static func run(folder: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var drawn = 0
        func save<V: View>(_ view: V, _ name: String, dark: Bool) {
            let r = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
            r.scale = 2
            guard let image = r.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { print("could not draw \(name)"); return }
            try? png.write(to: folder.appending(path: "\(name)-\(dark ? "dark" : "light").png")); drawn += 1
        }
        let none = AppSettings(persist: false), settings = AppSettings(persist: false)
        settings.call.choose("/Users/you/Lab/api")
        settings.voices = ["af_heart", "bm_fable", "bm_george"]
        for (cap, build) in Scene.launcher {
            let r = Scene.Rig(); build(r); r.model.update()
            settings.setup = Setup(machine: Scene.machines[cap] ?? Scene.ready)
            let data = PanelData(r.model.panelInput(cap == "First run: no project" ? none : settings))
            let name = "panel-" + cap.lowercased().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "-")
            for dark in [false, true] {
                save(PanelView(data: data, active: true, still: true) { _ in }.frame(width: PanelView.size.width, height: PanelView.size(for: data).height), name, dark: dark)
            }
        }
        for dark in [false, true] { // closed: an open list is a scroll view, which ImageRenderer leaves blank
            save(SettingsView(settings: settings, chooseVoice: { _ in }).frame(width: 360).padding(24).background(Palette(dark ? .dark : .light).ground), "settings", dark: dark)
        }
        print("drew \(drawn) pictures offscreen in \(folder.path)")
        return 0
    }
}
