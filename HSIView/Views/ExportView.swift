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
    let enviOptions: EnviExportOptions?
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case npy
    case mat
    case tiff
    case enviDat
    case enviRaw
    case pngChannels
    case quickPNG
    case maskPNG
    case maskNpy
    case maskMat
    
    var id: String { rawValue }

    var title: String {
        switch self {
        case .npy: return L("export.format.npy")
        case .mat: return L("export.format.mat")
        case .tiff: return L("export.format.tiff")
        case .enviDat: return L("export.format.envi_dat")
        case .enviRaw: return L("export.format.envi_raw")
        case .pngChannels: return L("export.format.png_channels")
        case .quickPNG: return L("export.format.quick_png")
        case .maskPNG: return L("export.format.mask_png")
        case .maskNpy: return L("export.format.mask_npy")
        case .maskMat: return L("export.format.mask_mat")
        }
    }
    
    var fileExtension: String {
        switch self {
        case .npy, .maskNpy: return "npy"
        case .mat, .maskMat: return "mat"
        case .tiff: return "tiff"
        case .enviDat: return "dat"
        case .enviRaw: return "raw"
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
        [.npy, .mat, .tiff, .enviDat, .enviRaw, .pngChannels, .quickPNG]
    }
    
    static var maskFormats: [ExportFormat] {
        [.maskPNG, .maskNpy, .maskMat]
    }
}

enum ExportTab: String, CaseIterable, Identifiable {
    case cube
    case mask
    
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cube: return L("export.tab.cube")
        case .mask: return L("export.tab.mask")
        }
    }
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
    @State private var maskExportMetadata: Bool = true
    @State private var maskMATMetadataKeyPrefix: String = MaskMATMetadataKeySet.defaultPrefix
    @State private var tiffEnviCompatible: Bool = false
    @State private var enviOptions: EnviExportOptions = .default()
    @State private var hoveredCubeFormat: ExportFormat?
    
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
                    Text(tab.title).tag(tab)
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
            let dataType = state.cube?.originalDataType ?? .float32
            enviOptions = .default(binaryFileType: .dat, sourceDataType: dataType)
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
        .onChange(of: selectedFormat) { newFormat in
            if newFormat == .enviDat {
                enviOptions.binaryFileType = .dat
            } else if newFormat == .enviRaw {
                enviOptions.binaryFileType = .raw
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

        if selectedFormat == .enviDat || selectedFormat == .enviRaw {
            enviOptionsSection
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
                    ? L("export.tiff.envi_info")
                    : L("export.tiff.default_info")
            )
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var enviOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("export.envi.options.title"))
                .font(.system(size: 11, weight: .semibold))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("export.envi.interleave"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $enviOptions.interleave) {
                        ForEach(EnviInterleave.allCases) { interleave in
                            Text(interleave.title).tag(interleave)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("export.envi.data_type"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $enviOptions.dataType) {
                        ForEach(EnviExportDataType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("export.envi.byte_order"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $enviOptions.byteOrder) {
                        ForEach(EnviByteOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }

            HStack(spacing: 8) {
                Text(L("export.envi.file_type"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("ENVI", text: $enviOptions.fileType)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: 180)

                Text(L("export.envi.sensor_type"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("Unknown", text: $enviOptions.sensorType)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: 180)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L("export.envi.description"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("Export via HSIView by Liptee", text: $enviOptions.description)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
            }

            Toggle(isOn: $enviOptions.includeDefaultBands) {
                Text(L("export.envi.default_bands.include"))
                    .font(.system(size: 10, weight: .medium))
            }

            if enviOptions.includeDefaultBands {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $enviOptions.defaultBandsMode) {
                        ForEach(EnviDefaultBandsMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if enviOptions.defaultBandsMode == .custom {
                        HStack(spacing: 8) {
                            Text("R")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField(
                                "70",
                                value: $enviOptions.customDefaultBands.red,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)

                            Text("G")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField(
                                "53",
                                value: $enviOptions.customDefaultBands.green,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)

                            Text("B")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField(
                                "19",
                                value: $enviOptions.customDefaultBands.blue,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Toggle(isOn: $enviOptions.includeAcquisitionDate) {
                    Text(L("export.envi.acquisition_date.include"))
                        .font(.system(size: 10, weight: .medium))
                }

                if enviOptions.includeAcquisitionDate {
                    DatePicker(
                        "",
                        selection: $enviOptions.acquisitionDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
            }

            Toggle(isOn: $enviOptions.includeCoordinates) {
                Text(L("export.envi.coordinates.include"))
                    .font(.system(size: 10, weight: .medium))
            }

            if enviOptions.includeCoordinates {
                HStack(spacing: 8) {
                    Text(L("export.envi.latitude"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("0.0", value: $enviOptions.latitude, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Text(L("export.envi.longitude"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("0.0", value: $enviOptions.longitude, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            Toggle(isOn: $enviOptions.includeGeoReference) {
                Text(L("export.envi.georef.include"))
                    .font(.system(size: 10, weight: .medium))
            }

            if enviOptions.includeGeoReference {
                infoBox(
                    icon: "globe",
                    text: L("export.envi.georef.info")
                )
            }

            HStack(spacing: 8) {
                Text(L("export.envi.wavelength_units"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("nm", text: $enviOptions.wavelengthUnits)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("export.envi.additional_fields"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextEditor(text: $enviOptions.additionalHeaderFields)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 90)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                Text(L("export.envi.additional_fields.hint"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            infoBox(
                icon: "info.circle",
                text: L("export.envi.options.info")
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
                    Text(format.title).tag(format)
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
                    ? L("export.mask.format.png_color_info")
                    : L("export.mask.format.png_grayscale_info")
            )
        case .maskNpy:
            infoBox(
                icon: "doc.badge.gearshape",
                text: L("export.mask.format.npy_info")
            )
        case .maskMat:
            infoBox(
                icon: "doc.badge.gearshape",
                text: L("export.mask.format.mat_info")
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

            Toggle(isOn: $maskExportMetadata) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                    Text(L("export.mask.metadata.toggle"))
                        .font(.system(size: 11, weight: .medium))
                }
            }

            if maskExportMetadata {
                switch selectedFormat {
                case .maskPNG, .maskNpy:
                    infoBox(
                        icon: "doc.text",
                        text: L("export.mask.metadata.sidecar_info")
                    )
                case .maskMat:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(L("export.mask.metadata.mat.prefix"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            TextField(MaskMATMetadataKeySet.defaultPrefix, text: $maskMATMetadataKeyPrefix)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: 240)
                        }

                        let keys = MaskMATMetadataKeySet(prefix: maskMATMetadataKeyPrefix)
                        infoBox(
                            icon: "info.circle",
                            text: LF("export.mask.metadata.mat.keys_info", keys.prefix, keys.idsKey, keys.namesKey, keys.colorsKey)
                        )
                    }
                default:
                    EmptyView()
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

            let columns = Array(repeating: GridItem(.flexible(minimum: 120), spacing: 8), count: 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ExportFormat.cubeFormats) { format in
                    cubeFormatButton(format)
                }
            }

            formatDescription
        }
    }

    private func cubeFormatButton(_ format: ExportFormat) -> some View {
        let isSelected = selectedFormat == format
        let isHovered = hoveredCubeFormat == format

        return Button {
            selectedFormat = format
        } label: {
            Text(format.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 8)
                .foregroundColor(isSelected ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected
                                ? Color.accentColor
                                : Color(NSColor.separatorColor).opacity(0.7),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            if hovering {
                hoveredCubeFormat = format
            } else if hoveredCubeFormat == format {
                hoveredCubeFormat = nil
            }
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
                    text: L("export.library.empty_hint"),
                    color: .orange
                )
            } else if state.exportEntireLibrary {
                infoBox(
                    icon: "folder",
                    text: LF("export.library.will_export_files", state.libraryEntries.count)
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
                text: L("export.format.npy_info")
            )
        case .mat:
            infoBox(
                icon: "doc.badge.gearshape",
                text: L("export.format.mat_info")
            )
        case .tiff:
            infoBox(
                icon: "photo.stack",
                text: L("export.format.tiff_info")
            )
        case .enviDat:
            infoBox(
                icon: "doc.text",
                text: L("export.format.envi_dat_info")
            )
        case .enviRaw:
            infoBox(
                icon: "doc.text",
                text: L("export.format.envi_raw_info")
            )
        case .pngChannels:
            infoBox(
                icon: "photo.stack",
                text: L("export.format.png_channels_info")
            )
        case .quickPNG:
            infoBox(
                icon: "photo",
                text: L("export.format.quick_png_info")
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
                    text: L("export.color_synthesis.needs_wavelengths"),
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
                text: L("export.mat.variable_name_info")
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
                        text: LF("export.mat.wavelengths_as_variable_info", matVariableName)
                    )
                } else {
                    infoBox(
                        icon: "doc.text",
                        text: L("export.mat.wavelengths_separate_txt_info")
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
                    text: LF("export.wavelengths.extra_file_per_line", wavelengths.count)
                )
            case .mat:
                infoBox(
                    icon: "doc.text",
                    text: LF("export.wavelengths.extra_file", wavelengths.count)
                )
            case .tiff:
                infoBox(
                    icon: "doc.text",
                    text: LF("export.wavelengths.base_file", defaultExportBaseName, wavelengths.count)
                )
            case .enviDat, .enviRaw:
                infoBox(
                    icon: "doc.text",
                    text: L("export.wavelengths.envi_hdr")
                )
            case .pngChannels:
                infoBox(
                    icon: "doc.text",
                    text: LF("export.wavelengths.base_file", defaultExportBaseName, wavelengths.count)
                )
            case .quickPNG, .maskPNG, .maskNpy, .maskMat:
                EmptyView()
            }
        } else {
            infoBox(
                icon: "exclamationmark.triangle",
                text: L("export.wavelengths.missing_hint"),
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
                    text: L("export.cube.open_or_enable_library"),
                    color: .orange
                )
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text("\(state.localized(label)):")
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
            
            Text(state.localized(text))
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
                exportError = L("export.error.library_empty")
                return
            }
        } else {
            guard state.cube != nil else {
                exportError = L("export.error.open_cube")
                return
            }
        }

        let shouldPersistColorConfig = selectedFormat == .quickPNG || selectedFormat == .enviDat || selectedFormat == .enviRaw
        var resolvedEnviOptions = enviOptions
        if selectedFormat == .enviDat {
            resolvedEnviOptions.binaryFileType = .dat
        } else if selectedFormat == .enviRaw {
            resolvedEnviOptions.binaryFileType = .raw
        }

        let pendingInfo = PendingExportInfo(
            format: selectedFormat,
            wavelengths: exportWavelengths,
            matVariableName: selectedFormat == .mat ? matVariableName : nil,
            matWavelengthsAsVariable: matWavelengthsAsVariable,
            colorSynthesisConfig: shouldPersistColorConfig
            ? ColorSynthesisConfig(
                mode: colorSynthesisMode,
                mapping: state.colorSynthesisConfig.mapping,
                rangeMapping: state.colorSynthesisConfig.rangeMapping,
                pcaConfig: state.colorSynthesisConfig.pcaConfig
            )
            : nil,
            tiffEnviCompatible: selectedFormat == .tiff ? tiffEnviCompatible : false,
            enviOptions: (selectedFormat == .enviDat || selectedFormat == .enviRaw) ? resolvedEnviOptions : nil
        )
        dismiss()
        // Даем модальному окну закрыться, прежде чем показывать системную панель выбора пути
        DispatchQueue.main.async {
            state.pendingExport = pendingInfo
        }
    }
    
    private func performMaskExport() {
        guard let firstMask = state.maskEditorState.maskLayers.first else {
            exportError = L("export.error.no_mask")
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
            var result: Result<Void, Error>
            let metadata = state.maskEditorState.classMetadata()
            
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
                result = MaskExporter.exportAsMAT(
                    mask: mergedMask,
                    width: width,
                    height: height,
                    to: url,
                    maskVariableName: maskVariableName.isEmpty ? "mask" : maskVariableName,
                    metadata: maskExportMetadata ? metadata : nil,
                    metadataKeys: MaskMATMetadataKeySet(prefix: maskMATMetadataKeyPrefix)
                )
            default:
                result = .failure(ExportError.invalidData)
            }

            if maskExportMetadata, (selectedFormat == .maskPNG || selectedFormat == .maskNpy),
               case .success = result {
                result = MaskExporter.exportMetadataAsJSON(
                    metadata: metadata,
                    to: metadataSidecarURL(forMaskURL: url)
                )
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

    private func metadataSidecarURL(forMaskURL maskURL: URL) -> URL {
        let baseName = maskURL.deletingPathExtension().lastPathComponent
        return maskURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_metadata.json")
    }
    
    private func formatMemorySize(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
