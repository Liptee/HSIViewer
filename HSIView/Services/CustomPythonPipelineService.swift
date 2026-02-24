import Foundation

struct CustomPythonOperationTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var script: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        script: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.script = script
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func defaultScript(layout: CubeLayout) -> String {
        let layoutTuple: String
        if layout == .auto {
            layoutTuple = "(H, W, C)"
        } else {
            let components = layout.rawValue.map { String($0) }
            layoutTuple = "(" + components.joined(separator: ", ") + ")"
        }

        return """
import numpy as np

def process_hsi(hsi_image: np.ndarray) -> np.ndarray:
    \"\"\"
    hsi_image is 3D numpy array with layout \(layoutTuple).
    Function must return 3D numpy array.
    \"\"\"
    return hsi_image
"""
    }
}

struct CustomPythonOperationConfig: Equatable {
    var templateID: UUID?
    var templateName: String
    var script: String

    static let empty = CustomPythonOperationConfig(
        templateID: nil,
        templateName: "",
        script: CustomPythonOperationTemplate.defaultScript(layout: .hwc)
    )
}

final class CustomPythonOperationStore: ObservableObject {
    static let shared = CustomPythonOperationStore()

    @Published private(set) var templates: [CustomPythonOperationTemplate] = []

    private let storageKey = "custom_python_pipeline_templates.v1"

    private init() {
        load()
    }

    func createTemplate(name: String, script: String) -> CustomPythonOperationTemplate {
        let trimmedName = sanitizedTemplateName(name)
        let now = Date()
        let template = CustomPythonOperationTemplate(
            name: trimmedName,
            script: script,
            createdAt: now,
            updatedAt: now
        )
        templates.append(template)
        sortTemplates()
        save()
        return template
    }

    func updateTemplate(_ template: CustomPythonOperationTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        var updated = template
        updated.name = sanitizedTemplateName(updated.name)
        updated.updatedAt = Date()
        templates[index] = updated
        sortTemplates()
        save()
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }

    func template(for id: UUID) -> CustomPythonOperationTemplate? {
        templates.first(where: { $0.id == id })
    }

    private func sanitizedTemplateName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("custom.python.unnamed") : trimmed
    }

    private func sortTemplates() {
        templates.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([CustomPythonOperationTemplate].self, from: data) {
            templates = decoded
            sortTemplates()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum CustomPythonPipelineRuntimeError: LocalizedError {
    case emptyScript
    case pythonInterpreterUnavailable(String)
    case tempDirectoryCreateFailed
    case inputExportFailed(String)
    case runtimeScriptWriteFailed(String)
    case pythonExecutionFailed(String)
    case outputReadFailed(String)
    case outputValidationFailed

    var errorDescription: String? {
        switch self {
        case .emptyScript:
            return L("custom.python.error.empty_script")
        case .pythonInterpreterUnavailable(let path):
            return LF("custom.python.error.interpreter_unavailable", path)
        case .tempDirectoryCreateFailed:
            return L("custom.python.error.temp_dir")
        case .inputExportFailed(let message):
            return LF("custom.python.error.input_export", message)
        case .runtimeScriptWriteFailed(let message):
            return LF("custom.python.error.script_write", message)
        case .pythonExecutionFailed(let message):
            return LF("custom.python.error.execution", message)
        case .outputReadFailed(let message):
            return LF("custom.python.error.output_read", message)
        case .outputValidationFailed:
            return L("custom.python.error.output_validation")
        }
    }
}

enum CustomPythonPipelineService {
    static func apply(
        cube: HyperCube,
        layout: CubeLayout,
        config: CustomPythonOperationConfig,
        interpreterPath: String
    ) -> Result<HyperCube, Error> {
        let script = config.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            return .failure(CustomPythonPipelineRuntimeError.emptyScript)
        }

        let interpreterURL = URL(fileURLWithPath: interpreterPath)
        let resolvedInterpreterURL = interpreterURL.resolvingSymlinksInPath()
        _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: interpreterURL)
        if resolvedInterpreterURL.path != interpreterURL.path {
            _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: resolvedInterpreterURL)
        }

        let executablePath: String
        if FileManager.default.isExecutableFile(atPath: interpreterURL.path) {
            executablePath = interpreterURL.path
        } else if FileManager.default.isExecutableFile(atPath: resolvedInterpreterURL.path) {
            executablePath = resolvedInterpreterURL.path
        } else {
            return .failure(CustomPythonPipelineRuntimeError.pythonInterpreterUnavailable(interpreterPath))
        }

        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HSIViewCustomPython", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        } catch {
            return .failure(CustomPythonPipelineRuntimeError.tempDirectoryCreateFailed)
        }

        let runtimeID = UUID().uuidString
        let inputURL = runtimeRoot.appendingPathComponent("\(runtimeID)_input.npy")
        let outputURL = runtimeRoot.appendingPathComponent("\(runtimeID)_output.npy")
        let scriptURL = runtimeRoot.appendingPathComponent("\(runtimeID)_runner.py")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: scriptURL)
        }

        switch NpyExporter.export(cube: cube, to: inputURL, wavelengths: nil) {
        case .success:
            break
        case .failure(let error):
            return .failure(CustomPythonPipelineRuntimeError.inputExportFailed(error.localizedDescription))
        }

        do {
            let runtimeScript = buildRuntimeScript(userScript: script)
            try runtimeScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure(CustomPythonPipelineRuntimeError.runtimeScriptWriteFailed(error.localizedDescription))
        }

        let execution = runPython(
            interpreterPath: executablePath,
            scriptURL: scriptURL,
            inputURL: inputURL,
            outputURL: outputURL
        )
        if !execution.success {
            return .failure(CustomPythonPipelineRuntimeError.pythonExecutionFailed(execution.output))
        }

        let loadedResult = ImageLoaderFactory.load(from: outputURL)
        guard case .success(let outputCube) = loadedResult else {
            if case .failure(let error) = loadedResult {
                return .failure(CustomPythonPipelineRuntimeError.outputReadFailed(error.localizedDescription))
            }
            return .failure(CustomPythonPipelineRuntimeError.outputReadFailed("Unknown error"))
        }

        guard outputCube.totalElements > 0 else {
            return .failure(CustomPythonPipelineRuntimeError.outputValidationFailed)
        }

        let sourceChannels = cube.channelCount(for: layout)
        let outputChannels = outputCube.channelCount(for: layout)

        let wavelengthsToUse: [Double]?
        if let explicit = outputCube.wavelengths, explicit.count == outputChannels {
            wavelengthsToUse = explicit
        } else if let sourceWavelengths = cube.wavelengths, sourceWavelengths.count == sourceChannels, sourceChannels == outputChannels {
            wavelengthsToUse = sourceWavelengths
        } else {
            wavelengthsToUse = nil
        }

        let geoReferenceToUse = outputCube.dims == cube.dims ? cube.geoReference : nil

        let wrappedOutput = HyperCube(
            dims: outputCube.dims,
            storage: outputCube.storage,
            sourceFormat: cube.sourceFormat + " [Python]",
            isFortranOrder: outputCube.isFortranOrder,
            wavelengths: wavelengthsToUse,
            geoReference: geoReferenceToUse
        )

        return .success(wrappedOutput)
    }

    private static func buildRuntimeScript(userScript: String) -> String {
        """
import numpy as np
import sys
import traceback

\(userScript)

if 'process_hsi' not in globals():
    raise RuntimeError('Function process_hsi is not defined')

if __name__ == '__main__':
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    try:
        source = np.load(input_path, allow_pickle=False)
        result = process_hsi(source)
        if not isinstance(result, np.ndarray):
            raise TypeError('process_hsi must return numpy.ndarray')
        if result.ndim != 3:
            raise ValueError('process_hsi must return 3D numpy.ndarray')
        np.save(output_path, result)
    except Exception:
        traceback.print_exc()
        raise
"""
    }

    private static func runPython(
        interpreterPath: String,
        scriptURL: URL,
        inputURL: URL,
        outputURL: URL
    ) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: interpreterPath)
        process.arguments = [scriptURL.path, inputURL.path, outputURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return (false, error.localizedDescription)
        }

        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (process.terminationStatus == 0, outputText)
    }
}
