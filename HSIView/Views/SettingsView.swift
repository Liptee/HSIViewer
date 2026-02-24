import SwiftUI
import AppKit

struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case wavelengths
        case python

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general:
                return "gearshape"
            case .wavelengths:
                return "waveform.path.ecg"
            case .python:
                return "terminal"
            }
        }

        var titleKey: String {
            switch self {
            case .general:
                return "settings.group.general"
            case .wavelengths:
                return "settings.group.wavelengths"
            case .python:
                return "settings.group.python"
            }
        }
    }

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSection: SettingsSection = .general
    @State private var draftLanguage: AppLanguage = .english
    @State private var wavelengthStartDraft: String = ""
    @State private var wavelengthEndDraft: String = ""
    @State private var pythonInterpreterPathDraft: String = ""
    @State private var validationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 240)
                Divider()
                content
            }

            Divider()

            HStack {
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Spacer()
                Button(state.localized("common.apply")) {
                    applyChanges()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(SettingsWindowChromeHider())
        .onAppear {
            syncDraftsFromState()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.iconName)
                            .frame(width: 18)
                        Text(state.localized(section.titleKey))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(selectedSection == section ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(16)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch selectedSection {
                case .general:
                    generalSettingsView
                case .wavelengths:
                    wavelengthsSettingsView
                case .python:
                    pythonSettingsView
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.localized("settings.general.title"))
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("settings.general.language"))
                    .font(.headline)

                Picker("", selection: $draftLanguage) {
                    ForEach(state.supportedAppLanguages) { language in
                        Text(state.localized(languageTitleKey(language)))
                            .tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Text(state.localized("settings.general.language.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("settings.general.access_manager"))
                    .font(.headline)

                Text(state.localized("settings.general.access_manager.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                AccessManagerView(mode: .embedded)
                    .frame(minHeight: 280)
            }
        }
    }

    private var wavelengthsSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.localized("settings.wavelengths.title"))
                .font(.title3.weight(.semibold))

            Text(state.localized("settings.wavelengths.description"))
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.localized("settings.wavelengths.start"))
                        .font(.headline)
                    TextField("400", text: $wavelengthStartDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(state.localized("settings.wavelengths.end"))
                        .font(.headline)
                    TextField("1000", text: $wavelengthEndDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            let currentRange = state.resolvedDefaultWavelengthRange()
            Text(
                state.localizedFormat(
                    "settings.wavelengths.saved_range",
                    currentRange.start,
                    currentRange.end
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var pythonSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.localized("settings.python.title"))
                .font(.title3.weight(.semibold))

            Text(state.localized("settings.python.description"))
                .font(.callout)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("settings.python.path"))
                    .font(.headline)

                TextField("/usr/bin/python3", text: $pythonInterpreterPathDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button(state.localized("settings.python.browse")) {
                        choosePythonInterpreter()
                    }
                    .buttonStyle(.bordered)

                    Button(state.localized("settings.python.use_auto")) {
                        pythonInterpreterPathDraft = ""
                    }
                    .buttonStyle(.bordered)
                }
            }

            let resolvedPathPreview: String = {
                let trimmedDraft = pythonInterpreterPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedDraft.isEmpty ? state.resolvedPythonInterpreterPath : trimmedDraft
            }()

            Text(
                state.localizedFormat(
                    "settings.python.resolved_path",
                    resolvedPathPreview
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func languageTitleKey(_ language: AppLanguage) -> String {
        switch language {
        case .english:
            return "menu.language.english"
        case .russian:
            return "menu.language.russian"
        case .system:
            return "menu.language.system"
        }
    }

    private func syncDraftsFromState() {
        draftLanguage = state.preferredLanguage
        wavelengthStartDraft = state.defaultWavelengthStart
        wavelengthEndDraft = state.defaultWavelengthEnd
        pythonInterpreterPathDraft = state.pythonInterpreterPath
        validationMessage = nil
    }

    private func applyChanges() {
        let previousRange = state.resolvedDefaultWavelengthRange()
        let previousStart = parseWavelength(previousRange.start) ?? 400
        let previousEnd = parseWavelength(previousRange.end) ?? 1000

        let draftStart = parseWavelength(wavelengthStartDraft) ?? previousStart
        let draftEnd = parseWavelength(wavelengthEndDraft) ?? previousEnd

        let normalizedStart: String
        let normalizedEnd: String
        if draftEnd > draftStart {
            normalizedStart = String(format: "%.1f", draftStart)
            normalizedEnd = String(format: "%.1f", draftEnd)
        } else {
            normalizedStart = String(format: "%.1f", previousStart)
            normalizedEnd = String(format: "%.1f", previousEnd)
        }

        state.preferredLanguage = draftLanguage
        state.defaultWavelengthStart = normalizedStart
        state.defaultWavelengthEnd = normalizedEnd
        state.pythonInterpreterPath = pythonInterpreterPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        wavelengthStartDraft = normalizedStart
        wavelengthEndDraft = normalizedEnd

        if state.wavelengths == nil {
            state.lambdaStart = normalizedStart
            state.lambdaEnd = normalizedEnd
            state.lambdaStep = ""
        }

        let checkResult = runInterpreterVersionCheck(path: state.resolvedPythonInterpreterPath)
        validationMessage = checkResult.message
        dismiss()
    }

    private func choosePythonInterpreter() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = state.localized("common.open")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        pythonInterpreterPathDraft = url.path
    }

    private func parseWavelength(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func runInterpreterVersionCheck(path: String) -> (success: Bool, message: String?) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (false, state.localized("settings.python.status.missing"))
        }

        let interpreterURL = URL(fileURLWithPath: path)
        let resolvedURL = interpreterURL.resolvingSymlinksInPath()

        _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: interpreterURL)
        if resolvedURL.path != interpreterURL.path {
            _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: resolvedURL)
        }

        let process = Process()
        process.executableURL = interpreterURL
        process.arguments = ["--version"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            if resolvedURL.path != interpreterURL.path {
                return (
                    false,
                    state.localizedFormat("settings.python.status.symlink_hint", resolvedURL.path)
                )
            }
            return (false, state.localized("settings.python.status.missing"))
        }

        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return (true, nil)
        }

        if resolvedURL.path != interpreterURL.path {
            return (
                false,
                state.localizedFormat("settings.python.status.symlink_hint", resolvedURL.path)
            )
        }

        return (false, state.localized("settings.python.status.missing"))
    }
}

private struct SettingsWindowChromeHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}
