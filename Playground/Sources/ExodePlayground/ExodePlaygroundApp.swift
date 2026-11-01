import SwiftUI
import ExodeUI
import PlaygroundKit

@main
struct ExodePlaygroundApp: App {
    var body: some Scene {
        WindowGroup("ExodeUI Playground") {
            PlaygroundView()
                .frame(minWidth: 960, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capture PNG") {
                    NotificationCenter.default.post(name: .exodePlaygroundCapture, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let exodePlaygroundCapture = Notification.Name("exode.playground.capture")
}
