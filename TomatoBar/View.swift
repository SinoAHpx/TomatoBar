import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
    static let pauseTimer = Self("pauseTimer")
}

struct TBPopoverView: View {
    @ObservedObject var timer = TBTimer()
    @State private var buttonHovered = false

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")
    private var pauseLabel = NSLocalizedString("TBPopoverView.pause.label", comment: "Pause label")
    private var resumeLabel = NSLocalizedString("TBPopoverView.resume.label", comment: "Resume label")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    timer.startStop()
                    TBStatusItem.shared.closePopover(nil)
                } label: {
                    Text(timer.timer != nil || timer.isPaused ?
                         (buttonHovered ? stopLabel : timer.timeLeftString) :
                            startLabel)
                        .foregroundColor(Color.white)
                        .font(.system(.body).monospacedDigit())
                        .frame(maxWidth: .infinity)
                }
                .onHover { over in
                    buttonHovered = over
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if timer.enablePauseFeature && (timer.timer != nil || timer.isPaused) {
                    Button {
                        timer.pause()
                    } label: {
                        Text(timer.isPaused ? resumeLabel : pauseLabel)
                            .frame(width: 60)
                    }
                    .controlSize(.large)
                }
            }

            Group {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    TBStatusItem.shared.showSettingsWindow()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.settings.label",
                                           comment: "Settings label"))
                    Spacer()
                    Text("⌘ S").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s")

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    TBStatusItem.shared.showProductivityWindow()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.productivity.label",
                                           comment: "Productivity label"))
                    Spacer()
                    Text("⌘ P").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("p")

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.about.label",
                                           comment: "About label"))
                    Spacer()
                    Text("⌘ A").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Text(NSLocalizedString("TBPopoverView.quit.label",
                                           comment: "Quit label"))
                    Spacer()
                    Text("⌘ Q").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
