import SwiftUI
import AppKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case npy = "NumPy (.npy)"
    case tiff = "PNG Channels"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .npy: return "npy"
        case .tiff: return "png"
        }
    }
}

struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedFormat: ExportFormat = .npy
    @State private var exportWavelengths: Bool = true
    @State private var isExporting: Bool = false
    @State private var exportError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    formatSection
                    wavelengthsSection
                    cubeInfoSection
                }
                .padding(20)
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 500, height: 450)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16))
            Text("Экспорт гиперкуба")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Формат экспорта:")
                .font(.system(size: 11, weight: .semibold))
            
            Picker("", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            
            formatDescription
        }
    }
    
    @ViewBuilder
    private var formatDescription: some View {
        switch selectedFormat {
        case .npy:
            infoBox(
                icon: "doc.badge.gearshape",
                text: "NumPy формат. Сохраняет тип данных и порядок (C/Fortran). Совместим с Python/NumPy."
            )
        case .tiff:
            infoBox(
                icon: "photo.stack",
                text: "Экспорт каналов как отдельные PNG изображения. Поддержка только UInt8/UInt16."
            )
        }
    }
    
    private var wavelengthsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $exportWavelengths) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 11))
                    Text("Экспортировать длины волн")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            
            if exportWavelengths {
                wavelengthsDescription
            }
        }
    }
    
    @ViewBuilder
    private var wavelengthsDescription: some View {
        if let wavelengths = state.cube?.wavelengths, !wavelengths.isEmpty {
            switch selectedFormat {
            case .npy:
                infoBox(
                    icon: "doc.text",
                    text: "Будет создан дополнительный файл '_wavelengths.txt' с длинами волн (по одному значению на строку)."
                )
            case .tiff:
                infoBox(
                    icon: "doc.text",
                    text: "Будет создан файл 'hypercube_wavelengths.txt' с длинами волн."
                )
            }
        } else {
            infoBox(
                icon: "exclamationmark.triangle",
                text: "Длины волн отсутствуют в текущем кубе.",
                color: .orange
            )
        }
    }
    
    private var cubeInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Информация о кубе:")
                .font(.system(size: 11, weight: .semibold))
            
            if let cube = state.cube {
                VStack(spacing: 4) {
                    infoRow(label: "Размер", value: "\(cube.dims.0) × \(cube.dims.1) × \(cube.dims.2)")
                    infoRow(label: "Тип данных", value: cube.originalDataType.rawValue)
                    infoRow(label: "Порядок", value: cube.isFortranOrder ? "Fortran" : "C")
                    infoRow(label: "Память", value: formatMemorySize(bytes: cube.storage.sizeInBytes))
                }
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(4)
    }
    
    private func infoBox(icon: String, text: String, color: Color = .blue) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }
    
    private var footerView: some View {
        HStack(spacing: 12) {
            if let error = exportError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            Button("Отмена") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.escape, modifiers: [])
            
            Button(action: performExport) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text("Экспорт")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExporting || state.cube == nil)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16)
    }
    
    private func performExport() {
        guard let cube = state.cube else { return }
        
        let panel = NSSavePanel()
        
        if selectedFormat == .tiff {
            panel.nameFieldStringValue = "hypercube"
            panel.allowedFileTypes = nil
            panel.message = "Выберите базовое имя файла (будет создано много PNG)"
        } else {
            panel.nameFieldStringValue = "hypercube.\(selectedFormat.fileExtension)"
            panel.allowedFileTypes = [selectedFormat.fileExtension]
            panel.message = "Выберите путь для сохранения"
        }
        
        panel.canCreateDirectories = true
        
        guard panel.runModal() == .OK, let saveURL = panel.url else {
            return
        }
        
        isExporting = true
        exportError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Void, Error>
            
            switch selectedFormat {
            case .npy:
                result = NpyExporter.export(cube: cube, to: saveURL, exportWavelengths: exportWavelengths)
            case .tiff:
                result = TiffExporter.export(cube: cube, to: saveURL, exportWavelengths: exportWavelengths)
            }
            
            DispatchQueue.main.async {
                isExporting = false
                
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
        }
    }
    
    private func formatMemorySize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

