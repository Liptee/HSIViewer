import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedState: AppState?

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Self.sharedState?.open(url: url)
        return true
    }

    func application(_ application: NSApplication,
                     open urls: [URL]) {
        if let url = urls.first {
            Self.sharedState?.open(url: url)
        }
    }
}

@main
struct HSIViewApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppDelegate.sharedState = appState
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    appState.open(url: url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Открыть"
        panel.allowedFileTypes = ["mat", "tif", "tiff", "npy"]
        
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        
        appState.open(url: url)
    }
}
