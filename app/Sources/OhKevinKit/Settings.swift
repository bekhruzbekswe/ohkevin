import AppKit
import ServiceManagement
import CallViews
import CallKit
import SwiftUI
import Updating
import VoiceCore

/// Settings (the owner's grouped card): the calls' choices (the project folder, the model the workers use, the
/// voice, what a spoken yes approves, opening the work in Claude afterwards), this Mac's (opening at login, updating by itself) and
/// the privacy note. Kept in VoiceCore's CallSettings, in this app's own defaults; a change applies to the next call, except the
/// voice, which changes at once on a call.
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
    /// Self-updating (Sparkle, Sources/Updating); nil in a build without a feed, and while drawing figures.
    var updates: Updates?
    /// The transient update line (checking, up to date, could not check) has had its four seconds for this state.
    var lineGone: UpdateState?
    /// Moving to Applications: the line's progress.
    var moving = false
    /// Pictures only: Settings draws "Update automatically" as a build with a feed has it.
    var updatesPicture = false
    /// Pictures only: the update line drawn in the start window.
    var linePicture: PanelLine?
    /// The start window's update line now (VoiceCore's updateLine), or nil.
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

    // Open at login: the app itself as a login item (SMAppService).
    private(set) var loginItem = SMAppService.mainApp.status
    private(set) var loginError: String?
    var opensAtLogin: Bool {
        get { loginItem == .enabled || loginItem == .requiresApproval }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch { loginError = error.localizedDescription }
            loginItem = SMAppService.mainApp.status
        }
    }
    func refreshLoginItem() { loginItem = SMAppService.mainApp.status }

    /// "Read more": what leaves this Mac and what Claude Code may do, as a page in the browser, made now from the Disclosure strings
    /// with today's spoken-yes choice marked.
    func openPrivacy() {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(Product.name) privacy.html")
        guard (try? Disclosure.page(current: call.spokenYes).write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        NSWorkspace.shared.open(file)
    }

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
    /// A call is on: the card says what waits for the next call.
    var onCall = false
    @Environment(\.colorScheme) private var scheme

    /// The grouped card the owner approved (ohkevin-notes/settings-design/approved.png): small grey headers, two inset groups on the
    /// paper, rows 52 high with hairlines between them only, pickers as rows (their lists drop under the row), the ink switch.
    var body: some View {
        let c = Palette(scheme)
        let canUpdate = settings.updatesPicture || MainActor.assumeIsolated({ settings.updates?.available ?? false })
        SettingsSheet(openChooser: settings.openForPicture, width: nil, paintsGround: false, listOpen: $settings.listOpen, inset: 16, spacing: 0) {
            header("Calls").padding(.top, 12)
            if onCall { // only the voice changes on a call; everything else waits for the next one
                Text("Changes apply to the next call. The voice, now.").font(.system(size: 14)).foregroundStyle(c.ink2)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            VStack(spacing: 0) {
                Chooser("Project folder", selection: settings.projectBinding, options: settings.projectOptions, action: settings.projectAction,
                        selectionTitle: settings.projectName, look: .row)
                Chooser("Worker model", selection: Binding { settings.call.workerModel } set: { settings.call.workerModel = $0 },
                        options: Model.forWork.map { ChooserOption($0, $0.title) }, look: .row).ruled(c)
                Chooser("Voice model", selection: Binding { settings.voice } set: { settings.voice = $0; chooseVoice($0) },
                        options: voiceGroups(settings.voices.isEmpty ? [settings.voice] : settings.voices).flatMap { g in g.voices.map { ChooserOption($0.name, $0.title, group: g.title) } },
                        look: .row).ruled(c)
                Chooser("A spoken “yes” approves", selection: Binding { settings.call.spokenYes } set: { settings.call.spokenYes = $0 },
                        options: [ChooserOption(SpokenYes.safeSteps, "Safe steps"), ChooserOption(.anyStep, "Any step"), ChooserOption(.nothing, "Nothing")], look: .row).ruled(c)
                switchRow("Open in Claude afterwards", Binding { settings.call.openInClaudeApp } set: { settings.call.openInClaudeApp = $0 }).ruled(c)
            }
            .group(c, scheme)
            header("This Mac").padding(.top, 19)
            VStack(spacing: 0) {
                switchRow("Open at login", Binding { settings.opensAtLogin } set: { settings.opensAtLogin = $0 }, detail: loginDetail) {
                    if settings.loginItem == .requiresApproval { PillButton("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } }
                }
                if canUpdate {
                    switchRow("Update automatically", Binding { MainActor.assumeIsolated { settings.updates?.automatic ?? true } }
                                                      set: { v in MainActor.assumeIsolated { settings.updates?.automatic = v } }).ruled(c)
                }
                privacyRow(c).ruled(c)
            }
            .group(c, scheme)
            .padding(.bottom, 4)
        }
        .id(settings.openForPicture)
        .background { // the card: paper, a hairline edge, and one shadow for the whole of it (none on the controls inside)
            RoundedRectangle(cornerRadius: CV.radius, style: .continuous).fill(CV.ground)
                .overlay(RoundedRectangle(cornerRadius: CV.radius, style: .continuous).strokeBorder(CV.hair))
                .compositingGroup().cvShadow().shadow(color: .black.opacity(0.18), radius: 20, y: 12)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Settings")
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette(scheme).ink2)
            .padding(.horizontal, 16).frame(height: 20).padding(.bottom, 8).accessibilityAddTraits(.isHeader)
    }

    private func switchRow<Extra: View>(_ title: String, _ isOn: Binding<Bool>, detail: String? = nil, @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        let c = Palette(scheme)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17)).foregroundStyle(c.ink)
                if let detail { Text(detail).font(.system(size: 15)).foregroundStyle(settings.loginError != nil ? c.wrong : c.ink2).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            extra()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(InkToggleStyle()).accessibilityLabel(title)
        }
        .padding(.horizontal, 16).padding(.vertical, detail == nil ? 0 : 12).frame(minHeight: 52)
    }

    /// "Privacy": what leaves this Mac and what Claude Code may do, on a page in the browser.
    private func privacyRow(_ c: Palette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Privacy").font(.system(size: 17)).foregroundStyle(c.ink)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(c.ink2)
            }
            Text(Disclosure.pointer).font(.system(size: 15)).foregroundStyle(c.ink2).lineSpacing(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle()).onTapGesture { settings.openPrivacy() }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isLink).accessibilityAction { settings.openPrivacy() }
    }

    private var loginDetail: String? {
        settings.loginError ?? (settings.loginItem == .requiresApproval ? "Allow it in System Settings to finish." : nil)
    }
}

private extension View {
    /// A hairline above this row, from the row's text to the group's right edge: between rows only.
    func ruled(_ c: Palette) -> some View { overlay(alignment: .top) { Rectangle().fill(c.hair).frame(height: 1).padding(.leading, 16) } }
    /// One of the card's two groups: white on the paper in light, a lifted grey in dark, its rows clipped to its corners.
    func group(_ c: Palette, _ scheme: ColorScheme) -> some View {
        background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(scheme == .dark ? Color(red: 0x2F / 255, green: 0x2D / 255, blue: 0x2A / 255) : .white))
    }
}
