import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PendingExportInfo: Equatable {
    let format: ExportFormat
    let wavelengths: Bool
    let matVariableName: String?
    let matWavelengthsAsVariable: Bool
    let colorSynthesisConfig: ColorSynthesisConfig?
    let tiffEnviCompatible: Bool
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case npy = "NumPy (.npy)"
    case mat = "MATLAB (.mat)"
    case tiff = "TIFF (.tiff)"
    case pngChannels = "PNG Channels"
    case quickPNG = "Быстрый PNG"
    case maskPNG = "Маска PNG"
    case maskNpy = "Маска NumPy"
    case maskMat = "Маска MAT"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .npy, .maskNpy: return "npy"
        case .mat, .maskMat: return "mat"
        case .tiff: return "tiff"
        case .pngChannels, .quickPNG, .maskPNG: return "png"
        }
    }
    
    var isMaskExport: Bool {
        switch self {
        case .maskPNG, .maskNpy, .maskMat: return true
        default: return false
        }
    }
    
    static var cubeFormats: [ExportFormat] {
        [.npy, .mat, .tiff, .pngChannels, .quickPNG]
    }
    
    static var maskFormats: [ExportFormat] {
        [.maskPNG, .maskNpy, .maskMat]
    }
}

enum ExportTab: String, CaseIterable, Identifiable {
    case cube = "Гиперкуб"
    case mask = "Маска"
    
    var id: String { rawValue }
}

struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: ExportTab = .cube
    @State private var selectedFormat: ExportFormat = .npy
    @State private var exportWavelengths: Bool = true
    @State private var matVariableName: String = "hypercube"
    @State private var matWavelengthsAsVariable: Bool = true
    @State private var colorSynthesisMode: ColorSynthesisMode = .trueColorRGB
    @State private var isExporting: Bool = false
    @State private var exportError: String?
    @State private var maskExportColored: Bool = false
    @State private var maskVariableName: String = "mask"
    @State private var tiffEnviCompatible: Bool = false
    
    private var defaultExportBaseName: String {
        state.defaultExportBaseName
    }
    
    private var hasMask: Bool {
        !state.maskEditorState.maskLayers.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            Picker("", selection: $selectedTab) {
                ForEach(ExportTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == .cube {
                        cubeExportContent
                    } else {
                        maskExportContent
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 640, height: 500)
        .onAppear {
            colorSynthesisMode = state.colorSynthesisConfig.mode
            if state.viewMode == .mask && hasMask {
                selectedTab = .mask
                selectedFormat = .maskPNG
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .cube && selectedFormat.isMaskExport {
                selectedFormat = .npy
            } else if newTab == .mask && !selectedFormat.isMaskExport {
                selectedFormat = .maskPNG
            }
        }
    }
    
    @ViewBuilder
    private var cubeExportContent: some View {
        formatSection
        libraryExportSection
        
        if selectedFormat == .mat {
            matOptionsSection
        }
        
        if selectedFormat == .tiff {
            tiffOptionsSection
        }
        
        if selectedFormat == .quickPNG {
            colorSynthesisSection
        }
        
        if selectedFormat != .quickPNG {
            wavelengthsSection
        }
        
        cubeInfoSection
    }
    
    private var tiffOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Параметры TIFF:")
                .font(.system(size: 11, weight: .semibold))
            
            Toggle(isOn: $tiffEnviCompatible) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 11))
                    Text("Совместимость с ENVI (многоканальный TIFF)")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            
            infoBox(
                icon: "info.circle",
                text: tiffEnviCompatible
                    ? "Файл будет сохранён как один TIFF с interleaved каналами (Photometric: minisblack, PlanarConfig: contig)."
                    : "По умолчанию каждый канал экспортируется отдельным кадром TIFF."
            )
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var maskExportContent: some View {
        if !hasMask {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("Нет маски для экспорта")
                    .font(.system(size: 13, weight: .medium))
                Text("Переключитесь в режим Mask и создайте маску")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        } else {
            maskFormatSection
            maskOptionsSection
            maskInfoSection
        }
    }
    
    private var maskFormatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Формат экспорта маски:")
                .font(.system(size: 11, weight: .semibold))
            
            Picker("", selection: $selectedFormat) {
                ForEach(ExportFormat.maskFormats) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            
            maskFormatDescription
        }
    }
    
    @ViewBuilder
    private var maskFormatDescription: some View {
        switch selectedFormat {
        case .maskPNG:
            infoBox(
                icon: "photo",
                text: maskExportColored
                    ? "Цветной PNG с цветами классов. Для визуализации."
                    : "Одноканальный PNG (grayscale). Значения пикселей = номера классов."
            )
        case .maskNpy:
            infoBox(
                icon: "doc.badge.gearshape",
                text: "NumPy массив HxW uint8. Значения = номера классов (0 = фон)."
            )
        case .maskMat:
            infoBox(
                icon: "doc.badge.gearshape",
                text: "MATLAB формат с маской и метаданными классов."
            )
        default:
            EmptyView()
        }
    }
    
    private var maskOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedFormat == .maskPNG {
                Toggle(isOn: $maskExportColored) {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 11))
                        Text("Экспорт в цвете")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
            
            if selectedFormat == .maskMat {
                HStack(spacing: 8) {
                    Text("Имя переменной:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    TextField("mask", text: $maskVariableName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: 200)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var maskInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Информация о маске:")
                .font(.system(size: 11, weight: .semibold))
            
            if let firstMask = state.maskEditorState.maskLayers.first {
                infoRow(label: "Размер", value: "\(firstMask.width) × \(firstMask.height)")
                infoRow(label: "Классов", value: "\(state.maskEditorState.maskLayers.count)")
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.maskEditorState.maskLayers, id: \.id) { layer in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(layer.color))
                                .frame(width: 10, height: 10)
                            Text("\(layer.classValue): \(layer.name)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(4)
            }
        }
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
                ForEach(ExportFormat.cubeFormats) { format in
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
                text: "Экспорт всех каналов в один многокадровый TIFF файл."
            )
        case .pngChannels:
            infoBox(
                icon: "photo.stack",
                text: "Экспорт каналов как отдельные PNG изображения в выбранную папку. Все типы данных автоматически масштабируются."
            )
        case .quickPNG:
            infoBox(
                icon: "photo",
                text: "Быстрый экспорт RGB изображения с выбранным режимом цветосинтеза."
            )
        case .maskPNG, .maskNpy, .maskMat:
            EmptyView()
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
                            state.setColorSynthesisMode(mode)
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
            case .pngChannels:
                infoBox(
                    icon: "doc.text",
                    text: "Будет создан файл '\(defaultExportBaseName)_wavelengths.txt' с \(wavelengths.count) длинами волн."
                )
            case .quickPNG, .maskPNG, .maskNpy, .maskMat:
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
                    infoRow(label: "Текущий файл", value: state.displayName(for: current))
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
            
            let canExportCube = selectedTab == .cube && (state.exportEntireLibrary ? !state.libraryEntries.isEmpty : state.cube != nil)
            let canExportMask = selectedTab == .mask && hasMask
            let canExport = canExportCube || canExportMask
            
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
            .disabled(isExporting || !canExport)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16)
    }
    
    private func performExport() {
        exportError = nil
        
        if selectedTab == .mask {
            performMaskExport()
            return
        }
        
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

        let pendingInfo = PendingExportInfo(
            format: selectedFormat,
            wavelengths: exportWavelengths,
            matVariableName: selectedFormat == .mat ? matVariableName : nil,
            matWavelengthsAsVariable: matWavelengthsAsVariable,
            colorSynthesisConfig: selectedFormat == .quickPNG
            ? ColorSynthesisConfig(
                mode: colorSynthesisMode,
                mapping: state.colorSynthesisConfig.mapping,
                pcaConfig: state.colorSynthesisConfig.pcaConfig
            )
            : nil,
            tiffEnviCompatible: selectedFormat == .tiff ? tiffEnviCompatible : false
        )
        dismiss()
        // Даем модальному окну закрыться, прежде чем показывать системную панель выбора пути
        DispatchQueue.main.async {
            state.pendingExport = pendingInfo
        }
    }
    
    private func performMaskExport() {
        guard let firstMask = state.maskEditorState.maskLayers.first else {
            exportError = "Нет маски для экспорта"
            return
        }
        
        let mergedMask = state.maskEditorState.computeMergedMask()
        let width = firstMask.width
        let height = firstMask.height
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(defaultExportBaseName)_mask.\(selectedFormat.fileExtension)"
        
        switch selectedFormat {
        case .maskPNG:
            panel.allowedContentTypes = [.png]
        case .maskNpy:
            panel.allowedContentTypes = [.data]
        case .maskMat:
            panel.allowedContentTypes = [.data]
        default:
            break
        }
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Void, Error>
            
            switch selectedFormat {
            case .maskPNG:
                if maskExportColored {
                    let colors = state.maskEditorState.maskLayers.map { (id: $0.classValue, color: $0.color) }
                    result = MaskExporter.exportAsPNG(mask: mergedMask, width: width, height: height, to: url, classColors: colors)
                } else {
                    result = MaskExporter.exportAsGrayscalePNG(mask: mergedMask, width: width, height: height, to: url)
                }
            case .maskNpy:
                result = MaskExporter.exportAsNumPy(mask: mergedMask, width: width, height: height, to: url)
            case .maskMat:
                let metadata = state.maskEditorState.classMetadata()
                result = MaskExporter.exportAsMAT(
                    mask: mergedMask,
                    width: width,
                    height: height,
                    to: url,
                    maskVariableName: maskVariableName.isEmpty ? "mask" : maskVariableName,
                    metadata: metadata
                )
            default:
                result = .failure(ExportError.invalidData)
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
