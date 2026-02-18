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
    @Environment(\.openWindow) private var openWindow

    init() {
        AppDelegate.sharedState = appState
    }

    var body: some Scene {
        Window("HSIView", id: "main-window") {
            ContentView()
                .environmentObject(appState)
                .environment(\.locale, appState.appLocale)
                .onOpenURL { url in
                    appState.open(url: url)
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(appState.localized("menu.open")) {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button(appState.localized("menu.assemble_hsi")) {
                    HSIAssemblerWindowManager.shared.show(appState: appState)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(appState.isBusy)

                Divider()

                Button(appState.localized("menu.create_from_current")) {
                    appState.createDerivedCubeFromCurrent()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState.cube == nil || appState.isBusy)

                Divider()

                Button(appState.localized("menu.export")) {
                    appState.showExportView = true
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(appState.cube == nil)
            }
            
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button(appState.localized("menu.propagate_processing")) {
                    appState.propagateProcessingToLibrary()
                }
                .disabled(!appState.canPropagateProcessing)

                Button(appState.localized("menu.propagate_wavelengths")) {
                    appState.propagateWavelengthsToLibrary()
                }
                .disabled(!appState.canPropagateWavelengths)
            }
            
            CommandGroup(after: .sidebar) {
                Divider()

                Toggle(isOn: Binding(
                    get: { appState.isLeftPanelVisible },
                    set: { appState.isLeftPanelVisible = $0 }
                )) {
                    Text(appState.localized("menu.show_left_panel"))
                }
                .keyboardShortcut("[", modifiers: [.command, .option])

                Toggle(isOn: Binding(
                    get: { appState.isRightPanelVisible },
                    set: { appState.isRightPanelVisible = $0 }
                )) {
                    Text(appState.localized("menu.show_right_panel"))
                }
                .keyboardShortcut("]", modifiers: [.command, .option])

                Divider()

                Button(appState.localized("menu.main_window")) {
                    openWindow(id: "main-window")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(appState.localized("menu.graph")) {
                    GraphWindowManager.shared.show(appState: appState)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button(appState.localized("menu.grid_library")) {
                    GridLibraryWindowManager.shared.show(appState: appState)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()
                Button(appState.localized("menu.access_manager")) {
                    appState.showAccessManager = true
                }

                Divider()
                Menu(appState.localized("menu.language")) {
                    languageMenuButton(.english, titleKey: "menu.language.english")
                    languageMenuButton(.russian, titleKey: "menu.language.russian")
                    languageMenuButton(.system, titleKey: "menu.language.system")
                }
            }
        }
    }

    @ViewBuilder
    private func languageMenuButton(_ language: AppLanguage, titleKey: String) -> some View {
        Button {
            appState.preferredLanguage = language
        } label: {
            if appState.preferredLanguage == language {
                Label(appState.localized(titleKey), systemImage: "checkmark")
            } else {
                Text(appState.localized(titleKey))
            }
        }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = appState.localized("common.open")
        
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
