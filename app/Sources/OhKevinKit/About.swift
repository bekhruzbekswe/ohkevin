import AppKit
import CallKit
import CallViews
import SwiftUI

/// About Oh Kevin: the app icon above the wordmark ("Oh Kevin", New York regular, letter-spacing -2%, the logo set's section 4),
/// and the licence.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text(appName).font(DisplaySerif.font(size: 34)).tracking(-0.68).foregroundStyle(CV.ink).padding(.top, CV.s1)
            Text("A voice call with Claude Code.").font(CV.small).foregroundStyle(CV.ink2).padding(.top, CV.s0)
            Text("Licensed under the Apache License 2.0.").font(CV.small).foregroundStyle(CV.ink3).fixedSize().padding(.top, CV.s3)
        }
        .padding(.horizontal, CV.s4).padding(.top, CV.s4).padding(.bottom, CV.s4)
        .frame(width: 360)
        .background(CV.ground)
    }
}
