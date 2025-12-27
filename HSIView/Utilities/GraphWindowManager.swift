import SwiftUI
import AppKit

final class GraphWindowManager: NSObject, NSWindowDelegate {
    static let shared = GraphWindowManager()
    
    private var window: NSWindow?
    
    func show(appState: AppState) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let content = GraphWindowView()
            .environmentObject(appState)
        
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "График"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
