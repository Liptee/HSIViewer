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
        
        let content = GraphWindowView(spectrumCache: appState.librarySpectrumCache)
            .environmentObject(appState)
            .environment(\.locale, appState.appLocale)
        
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = appState.localized("window.graph.title")
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

final class ROICursorPreviewWindowManager: NSObject, NSWindowDelegate {
    static let shared = ROICursorPreviewWindowManager()

    private var window: NSWindow?

    private func targetScreenFrame() -> NSRect {
        if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main-window" }),
           let screen = mainWindow.screen {
            return screen.frame
        }
        if let keyScreen = NSApp.keyWindow?.screen {
            return keyScreen.frame
        }
        if let main = NSScreen.main {
            return main.frame
        }
        return NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    private func previewSideLength() -> CGFloat {
        let frame = targetScreenFrame()
        return floor(min(frame.width, frame.height) / 3.0)
    }

    private func configure(window: NSWindow, side: CGFloat) {
        let contentSize = NSSize(width: side, height: side)
        window.setContentSize(contentSize)
        window.minSize = contentSize
        window.maxSize = contentSize
        window.contentAspectRatio = contentSize
    }

    func show(appState: AppState) {
        let side = previewSideLength()
        if let window {
            window.title = appState.localized("window.roi_cursor.title")
            configure(window: window, side: side)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = ROICursorPreviewWindowView()
            .environmentObject(appState)
            .environment(\.locale, appState.appLocale)

        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = appState.localized("window.roi_cursor.title")
        window.delegate = self
        window.isReleasedWhenClosed = false
        configure(window: window, side: side)
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct ROICursorPreviewWindowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.85))

            if let roiImage = state.roiCursorPreviewImage {
                Image(nsImage: roiImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Text(L("roi.cursor.window.empty"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
        )
        .padding(8)
    }
}
