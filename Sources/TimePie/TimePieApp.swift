import SwiftUI

@main
struct TimePieApp: App {
    @State private var store = Store()
    @State private var friends = Friends()
    @State private var updates = Updates()

    var body: some Scene {
        WindowGroup("TimePie") {
            ContentView()
                .environment(store)
                .environment(friends)
                .environment(updates)
                .task { await updates.watch() }
                .background(FullScreenBlocker())
        }
        .defaultSize(width: 460, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }

            // SwiftData would have supplied undo; with a plain store it is ours to provide.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
            }

            CommandGroup(after: .saveItem) {
                Button("Export JSON…") { Export.run(store: store) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Reveal Data File in Finder") { Export.revealStoreFile(store: store) }
            }
        }
    }
}

/// Opts the hosting window out of full screen: the green button zooms instead, and
/// View › Enter Full Screen (and ⌃⌘F) go inert. SwiftUI has no scene modifier for this
/// on macOS 14, so we reach the NSWindow once it exists.
private struct FullScreenBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowHook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
        }
    }
}
