import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                
                Divider()
                
                Button("Экспорт...") {
                    appState.showExportView = true
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(appState.cube == nil)
            }
        }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Открыть"
        
        let matType = UTType(filenameExtension: "mat") ?? .data
        let tiffType = UTType.tiff
        let npyType = UTType(filenameExtension: "npy") ?? .data
        let datType = UTType(filenameExtension: "dat") ?? .data
        let hdrType = UTType(filenameExtension: "hdr") ?? .data
        let imgType = UTType(filenameExtension: "img") ?? .data
        let bsqType = UTType(filenameExtension: "bsq") ?? .data
        let bilType = UTType(filenameExtension: "bil") ?? .data
        let bipType = UTType(filenameExtension: "bip") ?? .data
        let rawType = UTType(filenameExtension: "raw") ?? .data
        
        panel.allowedContentTypes = [matType, tiffType, npyType, datType, hdrType, imgType, bsqType, bilType, bipType, rawType]
        
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        
        appState.open(url: url)
    }
}
