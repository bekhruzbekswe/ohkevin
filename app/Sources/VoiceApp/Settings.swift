import AppKit
import CallViews
import CallKit
import SwiftUI
import Updating
import VoiceCore

/// The three choices (design/final.html, "Settings"): the project folder, the model the workers use, the voice.
/// Kept as the launcher keeps them (VoiceCore's CallSettings), in this app's own defaults; a change applies to the next call,
/// except the voice, which changes at once on a call.
@Observable final class AppSettings {
    /// false for --check: its made-up project and voices must not land in the owner's settings.
    let persist: Bool
    var call: CallSettings { didSet { if persist { call.save() } } }
    init(persist: Bool = true) { self.persist = persist; call = persist ? CallSettings.load() : CallSettings(); if persist { lookAtFirstCall() } }
    /// Before the first call on this Mac, as the call server remembers it (first-call.json: "greeted" once the first hello was said):
    /// the window opens on the setup screen, at its size. Pictures set it directly.
    var firstCall = false
    /// Pictures only: the download's parts as drawn.
    var downloadPicture: [SetupInput.Part]?
    func lookAtFirstCall() {
        guard persist else { return }
        let file = ProcessInfo.processInfo.environment["FIRST_CALL_FILE"].map { URL(fileURLWithPath: $0) } ?? Server.place.support.appending(path: "first-call.json")
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        firstCall = saved?["greeted"] as? Bool != true
    }
    var voice = UserDefaults.standard.string(forKey: CallModel.voiceKey) ?? CallModel.defaultVoice
    /// The voices the call server offered last time.
    var voices = UserDefaults.standard.stringArray(forKey: "voices") ?? []
    /// The Settings card is open over the window.
    var shown = false
    /// A chooser's list is open in Settings (the shared sheet keeps it; false closes it): Escape closes the list before Settings.
    var listOpen = false
    /// Self-updating (the launcher's Sparkle updater); nil in a build without a feed, and while drawing figures.
    var updates: Updates?
    /// The transient update line (checking, up to date, could not check) has had its four seconds for this state.
    var lineGone: UpdateState?
    /// Moving to Applications: the line's progress.
    var moving = false
    /// Pictures only: the update line drawn in the start window.
    var linePicture: PanelLine?
    /// The start window's update line now (VoiceCore's updateLine, the launcher's own rule), or nil.
    @MainActor var updateLine: PanelLine? {
        if let linePicture { return linePicture }
        guard let u = updates else { return nil }
        var l = UpdateLineInput()
        l.state = u.state; l.automatic = u.automatic; l.moving = moving
        if case .move? = AppMover.decision() { l.moveOffered = true }
        l.transientGone = lineGone == u.state
        return VoiceCore.updateLine(l)
    }
    /// What a call still needs on this Mac (Node, Claude Code, its sign-in), and the fixes.
    var setup = Setup()
    /// Pictures only: the chooser whose list is drawn open.
    var openForPicture: String?
    /// Recent projects worth a list: on disk, other than the current one. With none, the chooser opens the Finder at once.
    var otherRecents: [String] { call.recents.filter { $0 != call.project && FileManager.default.fileExists(atPath: $0) } }

    var projectName: String? { call.project.map { URL(fileURLWithPath: $0).lastPathComponent } }

    // The lists of the three choosers (the app's own, not the system menu).
    /// The project chooser's options: the current project and the other recent ones on disk. With no other, none: a press opens the
    /// Finder at once (the pill still says the project's name: selectionTitle).
    var projectOptions: [ChooserOption<String>] {
        otherRecents.isEmpty ? [] : ((call.project.map { [$0] } ?? []) + otherRecents).map { ChooserOption($0, URL(fileURLWithPath: $0).lastPathComponent) }
    }
    var projectAction: ChooserAction {
        ChooserAction("Choose a Folder…") { [self] in chooseFolder() }
    }
    var projectBinding: Binding<String> { Binding { [self] in call.project ?? "" } set: { [self] in call.choose($0) } }

    func saw(_ names: [String]) { voices = names; if persist { UserDefaults.standard.set(names, forKey: "voices") } }

    /// The system's folder chooser; the folder becomes the project and goes to the top of the recent ones.
    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Choose"; p.message = "The project Claude Code works in on a call"
        if let project = call.project { p.directoryURL = URL(fileURLWithPath: project).deletingLastPathComponent() }
        if p.runModal() == .OK, let url = p.url { call.choose(url.path) }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// The voice is chosen through the call when there is one, so it is heard at once.
    let chooseVoice: (String) -> Void

    var body: some View {
        // the shared Settings (CallViews), the launcher's own; this app gives it the drop-down's rounded surface
        SettingsSheet(openChooser: settings.openForPicture, width: nil, paintsGround: false, listOpen: $settings.listOpen) {
            Chooser("Project folder", selection: settings.projectBinding, options: settings.projectOptions, action: settings.projectAction, selectionTitle: settings.projectName)
            Chooser("Model", selection: Binding { settings.call.workerModel } set: { settings.call.workerModel = $0 },
                    options: Model.forWork.map { ChooserOption($0, $0.title) })
            Chooser("Voice", selection: Binding { settings.voice } set: { settings.voice = $0; chooseVoice($0) },
                    options: voiceGroups(settings.voices.isEmpty ? [settings.voice] : settings.voices).flatMap { g in g.voices.map { ChooserOption($0.name, $0.title, group: g.title) } })
            if MainActor.assumeIsolated({ settings.updates?.available ?? false }) {
                SwitchRow("Update automatically", isOn: Binding { MainActor.assumeIsolated { settings.updates?.automatic ?? true } }
                                                        set: { v in MainActor.assumeIsolated { settings.updates?.automatic = v } })
            }
        }
        .id(settings.openForPicture)
        .background { // ground and hairline under the content, so an open list is drawn over the card's edge
            RoundedRectangle(cornerRadius: CV.radius, style: .continuous).fill(CV.ground)
                .overlay(RoundedRectangle(cornerRadius: CV.radius, style: .continuous).strokeBorder(CV.hair))
        }
        .cvShadow().shadow(color: .black.opacity(0.18), radius: 20, y: 12) // it floats over the window
        .accessibilityElement(children: .contain).accessibilityLabel("Settings")
    }
}
