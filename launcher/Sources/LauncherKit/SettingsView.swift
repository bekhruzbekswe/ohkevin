import CallViews
import ServiceManagement
import Updating
import SwiftUI
import VoiceCore

/// Settings: one window, one page, in the design system's own pieces (CallViews): paper ground, small labels over full-width
/// choosers, hairline rows, switches in ink. The privacy note ends it. The settings themselves are the launcher's.
struct SettingsView: View {
    @Bindable var launcher: Launcher
    /// A chooser whose list starts open (pictures).
    var openChooser: String?

    var body: some View {
        SettingsSheet(openChooser: openChooser) {
            if launcher.onCall { Fineprint("You’re on a call. Changes apply to the next one.") }
            SectionTitle("Calls")
            Chooser("Claude Code model", selection: $launcher.settings.workerModel, options: Model.forWork.map { ChooserOption($0, $0.title) })
            Chooser("A spoken “yes” approves", selection: $launcher.settings.spokenYes,
                    options: [ChooserOption(SpokenYes.safeSteps, "Safe steps"), ChooserOption(.anyStep, "Any step"), ChooserOption(.nothing, "Nothing")])
            SwitchRow("Open the work in Claude afterwards", isOn: $launcher.settings.openInClaudeApp)
            SectionTitle("This Mac").padding(.top, 8)
            HairlineRow("Speaks with", detail: voiceDetail, wrong: false, topRule: false) { voiceTrailing }
            HairlineRow("Open at login", detail: loginDetail, wrong: launcher.loginError != nil) {
                HStack(spacing: 12) {
                    if launcher.loginItem == .requiresApproval { PillButton("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } }
                    Toggle("Open at login", isOn: $launcher.opensAtLogin).labelsHidden().toggleStyle(InkToggleStyle()).accessibilityLabel("Open at login")
                }
            }
            if launcher.updates.available { // only a build that can update itself offers the switch
                SwitchRow("Update automatically", isOn: Binding(get: { launcher.updates.automatic }, set: { launcher.updates.automatic = $0 }))
            }
            FineprintLink(Disclosure.pointer, link: "Read more") { launcher.openPrivacy() }.padding(.top, 8)
        }
        .onAppear { launcher.refreshLoginItem() }
    }

    private var voiceDetail: String? {
        if launcher.kokoro != nil { return nil }
        return launcher.installingVoice ? "Downloading a voice…" : launcher.voiceFailed ? "That didn’t work." : "Chrome’s voice. A voice on this Mac: 381 MB."
    }

    private var loginDetail: String? {
        launcher.loginError ?? (launcher.loginItem == .requiresApproval ? "Allow it in System Settings to finish." : nil)
    }

    /// The local voice's download: a quiet button (nothing here is marigold).
    @ViewBuilder private var voiceTrailing: some View {
        if launcher.kokoro != nil { SettingsValue("A voice on this Mac") }
        else if launcher.installingVoice { ProgressView().controlSize(.small) }
        else { PillButton(launcher.voiceFailed ? "Try Again" : "Download", style: .quiet) { launcher.installVoice() } }
    }
}
