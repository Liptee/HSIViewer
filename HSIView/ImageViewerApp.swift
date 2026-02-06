import SwiftUI
import AppKit
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedState: AppState?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureSingleMainWindow()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        activateMainWindow()
        Self.sharedState?.open(url: url)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            activateMainWindow()
            Self.sharedState?.open(url: url)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            activateMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.sharedState?.cleanupTemporaryWorkspace()
    }
    
    private func activateMainWindow() {
        if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main-window" }) {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func ensureSingleMainWindow() {
        let mainWindows = NSApp.windows.filter { $0.identifier?.rawValue == "main-window" }
        if mainWindows.count > 1 {
            for window in mainWindows.dropFirst() {
                window.close()
            }
        }
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "main-window" else {
            return
        }
        AppDelegate.sharedState?.cleanupTemporaryWorkspace()
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
        Window("HSIView", id: "main-window") {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    appState.open(url: url)
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Создать из текущего") {
                    appState.createDerivedCubeFromCurrent()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState.cube == nil || appState.isBusy)

                Divider()

                Button("Экспорт...") {
                    appState.showExportView = true
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(appState.cube == nil)
            }
            
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Распространить обработку") {
                    appState.propagateProcessingToLibrary()
                }
                .disabled(!appState.canPropagateProcessing)
            }
            
            CommandGroup(after: .sidebar) {
                Divider()
                Button("График") {
                    GraphWindowManager.shared.show(appState: appState)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                
                Divider()
                Button("Управление доступами…") {
                    appState.showAccessManager = true
                }
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
