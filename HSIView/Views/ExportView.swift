import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PendingExportInfo: Equatable {
    let format: ExportFormat
    let wavelengths: Bool
    let matVariableName: String?
    let matWavelengthsAsVariable: Bool
    let colorSynthesisMode: ColorSynthesisMode?
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case npy = "NumPy (.npy)"
    case mat = "MATLAB (.mat)"
    case tiff = "PNG Channels"
    case quickPNG = "Быстрый PNG"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .npy: return "npy"
        case .mat: return "mat"
        case .tiff: return "png"
        case .quickPNG: return "png"
        }
    }
}

enum ColorSynthesisMode: String, CaseIterable, Identifiable {
    case trueColorRGB = "True Color RGB"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .trueColorRGB:
            return "R=630нм, G=530нм, B=450нм"
        }
    }
    
    var iconName: String {
        switch self {
        case .trueColorRGB:
            return "paintpalette"
        }
    }
}

struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedFormat: ExportFormat = .npy
    @State private var exportWavelengths: Bool = true
    @State private var matVariableName: String = "hypercube"
    @State private var matWavelengthsAsVariable: Bool = true
    @State private var colorSynthesisMode: ColorSynthesisMode = .trueColorRGB
    @State private var isExporting: Bool = false
    @State private var exportError: String?
    
    private var defaultExportBaseName: String {
        state.defaultExportBaseName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    formatSection
                    libraryExportSection
                    
                    if selectedFormat == .mat {
                        matOptionsSection
                    }
                    
                    if selectedFormat == .quickPNG {
                        colorSynthesisSection
                    }
                    
                    if selectedFormat != .quickPNG {
                        wavelengthsSection
                    }
                    
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
    
    private var libraryExportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $state.exportEntireLibrary) {
                HStack(spacing: 6) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 11))
                    Text("Экспортировать всю библиотеку")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .disabled(state.libraryEntries.isEmpty)
            
            if state.libraryEntries.isEmpty {
                infoBox(
                    icon: "exclamationmark.triangle",
                    text: "Библиотека пуста. Добавьте файлы или выключите опцию экспорта библиотеки.",
                    color: .orange
                )
            } else if state.exportEntireLibrary {
                infoBox(
                    icon: "folder",
                    text: "Будет экспортировано \(state.libraryEntries.count) файлов. Для каждого используется сохранённая обработка из библиотеки."
                )
            }
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
        case .mat:
            infoBox(
                icon: "doc.badge.gearshape",
                text: "MATLAB формат. Сохраняет тип данных. Совместим с MATLAB/Octave. Данные в column-major порядке."
            )
        case .tiff:
            infoBox(
                icon: "photo.stack",
                text: "Экспорт каналов как отдельные PNG изображения в выбранную папку. Все типы данных автоматически масштабируются."
            )
        case .quickPNG:
            infoBox(
                icon: "photo",
                text: "Быстрый экспорт RGB изображения с выбранным режимом цветосинтеза."
            )
        }
    }
    
    private var colorSynthesisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Режим цветосинтеза:")
                .font(.system(size: 11, weight: .semibold))
            
            VStack(spacing: 8) {
                ForEach(ColorSynthesisMode.allCases) { mode in
                    Button(action: {
                        colorSynthesisMode = mode
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 16))
                                .foregroundColor(colorSynthesisMode == mode ? .accentColor : .secondary)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(mode.description)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if colorSynthesisMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorSynthesisMode == mode ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colorSynthesisMode == mode ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if state.wavelengths == nil || state.wavelengths?.isEmpty == true {
                infoBox(
                    icon: "exclamationmark.triangle",
                    text: "Для корректного цветосинтеза необходимо задать длины волн.",
                    color: .orange
                )
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var matOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Параметры MAT:")
                .font(.system(size: 11, weight: .semibold))
            
            HStack(spacing: 8) {
                Text("Имя переменной:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                TextField("hypercube", text: $matVariableName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: 200)
            }
            
            infoBox(
                icon: "info.circle",
                text: "Имя переменной в MAT файле (например: 'data', 'cube', 'hypercube')."
            )
            
            if exportWavelengths {
                Toggle(isOn: $matWavelengthsAsVariable) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 11))
                        Text("Сохранить wavelengths в MAT как переменную")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                
                if matWavelengthsAsVariable {
                    infoBox(
                        icon: "doc.badge.gearshape",
                        text: "Wavelengths будут сохранены как переменная '\(matVariableName)_wavelengths' в том же MAT файле."
                    )
                } else {
                    infoBox(
                        icon: "doc.text",
                        text: "Wavelengths будут сохранены в отдельный .txt файл."
                    )
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
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
        if let wavelengths = state.wavelengths, !wavelengths.isEmpty {
            switch selectedFormat {
            case .npy:
                infoBox(
                    icon: "doc.text",
                    text: "Будет создан дополнительный файл '_wavelengths.txt' с \(wavelengths.count) длинами волн (по одному значению на строку)."
                )
            case .mat:
                infoBox(
                    icon: "doc.text",
                    text: "Будет создан дополнительный файл '_wavelengths.txt' с \(wavelengths.count) длинами волн."
                )
            case .tiff:
                infoBox(
                    icon: "doc.text",
                    text: "Будет создан файл '\(defaultExportBaseName)_wavelengths.txt' с \(wavelengths.count) длинами волн."
                )
            case .quickPNG:
                EmptyView()
            }
        } else {
            infoBox(
                icon: "exclamationmark.triangle",
                text: "Длины волн отсутствуют. Сгенерируйте их в панели управления (Start/Step) перед экспортом.",
                color: .orange
            )
        }
    }
    
    private var cubeInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Информация о кубе:")
                .font(.system(size: 11, weight: .semibold))
            
            if state.exportEntireLibrary {
                infoRow(label: "Файлов в библиотеке", value: "\(state.libraryEntries.count)")
                if let current = state.cubeURL {
                    infoRow(label: "Текущий файл", value: current.lastPathComponent)
                }
            } else if let cube = state.cube {
                VStack(spacing: 4) {
                    infoRow(label: "Размер", value: "\(cube.dims.0) × \(cube.dims.1) × \(cube.dims.2)")
                    infoRow(label: "Тип данных", value: cube.originalDataType.rawValue)
                    infoRow(label: "Порядок", value: cube.isFortranOrder ? "Fortran" : "C")
                    infoRow(label: "Память", value: formatMemorySize(bytes: cube.storage.sizeInBytes))
                }
            } else {
                infoBox(
                    icon: "exclamationmark.triangle",
                    text: "Открой гиперкуб или включите экспорт всей библиотеки.",
                    color: .orange
                )
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
            
            let singleCubeMissing = !state.exportEntireLibrary && state.cube == nil
            let libraryUnavailable = state.exportEntireLibrary && state.libraryEntries.isEmpty
            
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
            .disabled(isExporting || singleCubeMissing || libraryUnavailable)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16)
    }
    
    private func performExport() {
        exportError = nil
        
        if state.exportEntireLibrary {
            guard !state.libraryEntries.isEmpty else {
                exportError = "Библиотека пуста"
                return
            }
        } else {
            guard state.cube != nil else {
                exportError = "Открой гиперкуб для экспорта"
                return
            }
        }
        
        state.pendingExport = PendingExportInfo(
            format: selectedFormat,
            wavelengths: exportWavelengths,
            matVariableName: selectedFormat == .mat ? matVariableName : nil,
            matWavelengthsAsVariable: matWavelengthsAsVariable,
            colorSynthesisMode: selectedFormat == .quickPNG ? colorSynthesisMode : nil
        )
        dismiss()
    }
    
    private func formatMemorySize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
