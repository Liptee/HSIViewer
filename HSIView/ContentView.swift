import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var tempZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var showWavelengthPopover: Bool = false
    @State private var currentImageSize: CGSize = .zero
    @State private var currentGeoSize: CGSize = .zero
    @State private var roiDragStartPixel: PixelCoordinate?
    @State private var roiPreviewRect: SpectrumROIRect?
    @FocusState private var isImageFocused: Bool
    
    private let imageCoordinateSpaceName = "image-canvas"
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                mainContent
                    .disabled(state.isBusy)
                
                if state.isBusy {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                        BusyOverlayView(message: state.busyMessage ?? "Выполнение…")
                    }
                    .transition(.opacity)
                }
                
                if let exportInfo = state.libraryExportProgressState {
                    VStack {
                        HStack {
                            Spacer()
                            LibraryExportToastView(state: exportInfo)
                                .frame(maxWidth: 280)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            
            HStack(spacing: 0) {
                if state.cube != nil {
                    PipelinePanel()
                        .environmentObject(state)
                        .padding(.leading, 12)
                    
                    Divider()
                }
                
                GeometryReader { geo in
                    ZStack {
                        if let cube = state.cube {
                            cubeView(cube: cube, geoSize: geo.size)
                                .scaleEffect(state.zoomScale * tempZoomScale)
                                .offset(
                                    x: state.imageOffset.width + dragOffset.width,
                                    y: state.imageOffset.height + dragOffset.height
                                )
                        } else {
                            VStack(spacing: 8) {
                                Text("Открой гиперспектральный куб")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Поддерживаются форматы: .mat, .tiff, .npy")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("2D и 3D изображения")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                tempZoomScale = value
                            }
                            .onEnded { value in
                                state.zoomScale *= value
                                state.zoomScale = max(0.5, min(state.zoomScale, 10.0))
                                tempZoomScale = 1.0
                            }
                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if state.activeAnalysisTool == .spectrumGraphROI {
                                    handleROIDrag(value: value, geoSize: geo.size)
                                } else {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if state.activeAnalysisTool == .spectrumGraphROI {
                                    handleROIDragEnd(value: value, geoSize: geo.size)
                                } else {
                                    state.imageOffset.width += value.translation.width
                                    state.imageOffset.height += value.translation.height
                                }
                                dragOffset = .zero
                            }
                    )
                    .onTapGesture { location in
                        if state.activeAnalysisTool == .spectrumGraph {
                            handleImageClick(at: location, geoSize: geo.size)
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($isImageFocused)
                    .onAppear {
                        isImageFocused = true
                    }
                    .onKeyPress(.leftArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: 20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: -20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: 0, height: 20))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: 0, height: -20))
                        return .handled
                    }
                    .onChange(of: geo.size) { newSize in
                        currentGeoSize = newSize
                    }
                    .onHover { isHovering in
                        if (state.activeAnalysisTool == .spectrumGraph || state.activeAnalysisTool == .spectrumGraphROI),
                           state.cube != nil {
                            if isHovering {
                                NSCursor.crosshair.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .onChange(of: state.activeAnalysisTool) { _ in
                        NSCursor.pop()
                        roiPreviewRect = nil
                        roiDragStartPixel = nil
                    }
                    .onChange(of: state.cubeURL) { _ in
                        roiPreviewRect = nil
                        roiDragStartPixel = nil
                    }
                }
                .coordinateSpace(name: imageCoordinateSpaceName)
                
                if let cube = state.cube {
                    Divider()
                    
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            VStack(spacing: 12) {
                                ImageInfoPanel(cube: cube, layout: state.activeLayout)
                                    .id(cube.id)
                                
                                LibraryPanel()
                            }
                            .padding(12)
                        }
                        .frame(width: 260)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        
                        GraphPanel()
                            .environmentObject(state)
                    }
                    .padding(.trailing, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            if let cube = state.cube {
                bottomControls(cube: cube)
                    .padding(8)
                    .border(Color(NSColor.separatorColor), width: 0.5)
            }
        }
        .frame(minWidth: 960, minHeight: 500)
        .sheet(item: $state.pendingMatSelection) { request in
            MatVariableSelectionView(request: request)
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showExportView) {
            ExportView()
                .environmentObject(state)
        }
        .onChange(of: state.pendingExport) { newValue in
            if let exportInfo = newValue {
                performActualExport(
                    format: exportInfo.format,
                    wavelengths: exportInfo.wavelengths,
                    matVariableName: exportInfo.matVariableName,
                    matWavelengthsAsVariable: exportInfo.matWavelengthsAsVariable,
                    colorSynthesisConfig: exportInfo.colorSynthesisConfig
                )
                state.pendingExport = nil
            }
        }
    }
    
    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    if let cube = state.cube {
                        ImageInfoPanel(cube: cube, layout: state.activeLayout)
                            .id(cube.id)
                    }
                    
                    LibraryPanel()
                }
                .padding(12)
            }
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
    }
    
    private func performActualExport(format: ExportFormat, wavelengths: Bool, matVariableName: String?, matWavelengthsAsVariable: Bool, colorSynthesisConfig: ColorSynthesisConfig?) {
        if state.exportEntireLibrary {
            guard !state.libraryEntries.isEmpty else { return }
            
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Выбрать папку"
            panel.message = "Выберите папку для сохранения экспортированных файлов библиотеки"
            
            let response = panel.runModal()
            guard response == .OK, let folderURL = panel.url else {
                return
            }
            
            exportLibraryEntries(
                to: folderURL,
                format: format,
                wavelengths: wavelengths,
                matVariableName: matVariableName,
                matWavelengthsAsVariable: matWavelengthsAsVariable,
                colorSynthesisConfig: colorSynthesisConfig
            )
            return
        }
        
        guard let cube = state.cube else { return }
        
        let defaultBaseName = state.defaultExportBaseName
        
        // PNG Channels требует выбора директории, так как создаётся много файлов
        if format == .tiff {
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = true
            openPanel.canChooseFiles = false
            openPanel.canCreateDirectories = true
            openPanel.allowsMultipleSelection = false
            openPanel.prompt = "Выбрать папку"
            openPanel.message = "Выберите папку для сохранения PNG каналов (\(defaultBaseName)_channel_XXX.png)"
            
            openPanel.begin { response in
                print("ContentView: Open panel response: \(response == .OK ? "OK" : "Cancel")")
                guard response == .OK, let folderURL = openPanel.url else {
                    print("ContentView: Export cancelled or no URL")
                    return
                }
                
                print("ContentView: Exporting PNG Channels to folder: \(folderURL.path)")
                
                let wavelengthsToExport = wavelengths ? self.state.wavelengths : nil
                let currentLayout = self.state.activeLayout
                // Создаём URL с базовым именем внутри выбранной папки
                let baseURL = folderURL.appendingPathComponent(defaultBaseName)
                
                DispatchQueue.global(qos: .userInitiated).async {
                    print("ContentView: Calling TiffExporter with layout: \(currentLayout)")
                    let result = TiffExporter.export(cube: cube, to: baseURL, wavelengths: wavelengthsToExport, layout: currentLayout)
                    
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            print("ContentView: PNG Channels export successful")
                        case .failure(let error):
                            print("ContentView: PNG Channels export error: \(error.localizedDescription)")
                        }
                    }
                }
            }
            return
        }
        
        // Для остальных форматов используем NSSavePanel
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        
        switch format {
        case .tiff:
            break // Обработано выше
        case .quickPNG:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType.png]
            panel.message = "Выберите путь для сохранения PNG изображения"
        case .npy:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType(filenameExtension: "npy") ?? .data]
            panel.message = "Выберите путь для сохранения"
        case .mat:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType(filenameExtension: "mat") ?? .data]
            panel.message = "Выберите путь для сохранения"
        }
        
        panel.begin { response in
            print("ContentView: Save panel response: \(response == .OK ? "OK" : "Cancel")")
            guard response == .OK, let saveURL = panel.url else {
                print("ContentView: Export cancelled or no URL")
                return
            }
            
            print("ContentView: Exporting to: \(saveURL.path)")
            print("ContentView: Format: \(format.rawValue)")
            
            let wavelengthsToExport = wavelengths ? self.state.wavelengths : nil
            let currentLayout = self.state.activeLayout
            let currentWavelengths = self.state.wavelengths
            
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Void, Error>
                
                switch format {
                case .npy:
                    result = NpyExporter.export(cube: cube, to: saveURL, wavelengths: wavelengthsToExport)
                case .mat:
                    result = MatExporter.export(
                        cube: cube,
                        to: saveURL,
                        variableName: matVariableName ?? "hypercube",
                        wavelengths: wavelengthsToExport,
                        wavelengthsAsVariable: matWavelengthsAsVariable
                    )
                case .tiff:
                    result = .failure(ExportError.writeError("Unexpected tiff format"))
                case .quickPNG:
                    result = QuickPNGExporter.export(
                        cube: cube,
                        to: saveURL,
                        layout: currentLayout,
                        wavelengths: currentWavelengths,
                        config: colorSynthesisConfig ?? state.colorSynthesisConfig
                    )
                }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("ContentView: Export successful")
                    case .failure(let error):
                        print("ContentView: Export error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func exportLibraryEntries(to destinationFolder: URL, format: ExportFormat, wavelengths: Bool, matVariableName: String?, matWavelengthsAsVariable: Bool, colorSynthesisConfig: ColorSynthesisConfig?) {
        let entries = state.libraryEntries
        guard !entries.isEmpty else { return }
        let includeWavelengths = wavelengths
        state.beginLibraryExportProgress(total: entries.count)
        
        DispatchQueue.global(qos: .userInitiated).async {
            var completed = 0
            var allSuccess = true
            
            for entry in entries {
                autoreleasepool {
                    guard let payload = state.exportPayload(for: entry) else {
                        allSuccess = false
                        completed += 1
                        state.updateLibraryExportProgress(completed: completed, total: entries.count)
                        print("Пропуск \(entry.fileName) — нет данных для экспорта")
                        return
                    }
                    
                    let baseName = payload.baseName
                    let wavelengthsToExport = includeWavelengths ? payload.wavelengths : nil
                    let result: Result<Void, Error>
                    
                    switch format {
                    case .npy:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("npy")
                        result = NpyExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport)
                    case .mat:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("mat")
                        let varName = (matVariableName?.isEmpty == false ? matVariableName! : "hypercube")
                        result = MatExporter.export(
                            cube: payload.cube,
                            to: target,
                            variableName: varName,
                            wavelengths: wavelengthsToExport,
                            wavelengthsAsVariable: matWavelengthsAsVariable && includeWavelengths
                        )
                    case .tiff:
                        let target = destinationFolder.appendingPathComponent(baseName)
                        result = TiffExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport, layout: payload.layout)
                    case .quickPNG:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("png")
                        let config = colorSynthesisConfig ?? payload.colorSynthesisConfig
                        result = QuickPNGExporter.export(
                            cube: payload.cube,
                            to: target,
                            layout: payload.layout,
                            wavelengths: payload.wavelengths,
                            config: config
                        )
                    }
                    
                    switch result {
                    case .success:
                        print("Экспортирован \(entry.fileName)")
                    case .failure(let error):
                        print("Ошибка экспорта \(entry.fileName): \(error.localizedDescription)")
                        allSuccess = false
                    }
                    
                    completed += 1
                    state.updateLibraryExportProgress(completed: completed, total: entries.count)
                }
            }
            
            let message = allSuccess
                ? "Экспорт библиотеки завершён"
                : "Экспорт выполнен с ошибками"
            state.finishLibraryExportProgress(success: allSuccess, total: entries.count, message: message)
        }
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
    
    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                if let url = state.cubeURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Файл не выбран")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                if let error = state.loadError {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            
            Spacer()
            
            if state.cube != nil {
                ToolbarDockView()
                    .environmentObject(state)
            }
            
            Spacer()
            
            Text(appVersion)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: 300, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Color(NSColor.windowBackgroundColor)
                .opacity(0.9)
        )
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
    
    private func cubeView(cube: HyperCube, geoSize: CGSize) -> some View {
        Group {
            switch state.viewMode {
            case .gray:
                let chIdx = Int(state.currentChannel)
                if let nsImage = ImageRenderer.renderGrayscale(
                    cube: cube,
                    layout: state.activeLayout,
                    channelIndex: chIdx
                ) {
                    spectrumImageView(nsImage: nsImage, geoSize: geoSize)
                } else {
                    Text("Не удалось построить изображение")
                        .foregroundColor(.red)
                }
                
            case .rgb:
                let config = state.colorSynthesisConfig
                if let nsImage = ImageRenderer.renderRGB(
                    cube: cube,
                    layout: state.activeLayout,
                    wavelengths: state.wavelengths,
                    mapping: config.mapping
                ) {
                    spectrumImageView(nsImage: nsImage, geoSize: geoSize)
                } else {
                    Text("Не удалось построить RGB изображение")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func spectrumImageView(nsImage: NSImage, geoSize: CGSize) -> some View {
        let fittedSize = fittingSize(imageSize: nsImage.size, in: geoSize)
        
        return ZStack(alignment: .topLeading) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: fittedSize.width,
                       height: fittedSize.height,
                       alignment: .center)
            
            if state.activeAnalysisTool == .spectrumGraph {
                SpectrumPointsOverlay(
                    samples: state.activeSpectrumSamples,
                    originalSize: nsImage.size,
                    displaySize: fittedSize
                )
            } else if state.activeAnalysisTool == .spectrumGraphROI {
                SpectrumROIsOverlay(
                    samples: state.activeROISamples,
                    temporaryRect: roiPreviewRect,
                    originalSize: nsImage.size,
                    displaySize: fittedSize
                )
            }
        }
        .frame(width: fittedSize.width,
               height: fittedSize.height,
               alignment: .center)
        .background(Color.black.opacity(0.02))
        .onAppear {
            currentImageSize = nsImage.size
            currentGeoSize = geoSize
        }
        .onChange(of: nsImage.size) { newSize in
            currentImageSize = newSize
        }
    }
    
    private func bottomControls(cube: HyperCube) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if cube.is2D {
                    Text("Режим: 2D изображение")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("Layout:")
                        .font(.system(size: 11))
                    Picker("", selection: $state.layout) {
                        ForEach(CubeLayout.allCases) { layout in
                            Text(layout.rawValue).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    
                    Divider()
                        .frame(height: 18)
                    
                    Text("Mode:")
                        .font(.system(size: 11))
                    
                    Picker("", selection: $state.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 160)
                    
                    if state.viewMode == .rgb {
                        Divider()
                            .frame(height: 18)
                        
                        Text("Цветосинтез:")
                            .font(.system(size: 11))
                        
                        Picker("", selection: Binding(
                            get: { state.colorSynthesisConfig.mode },
                            set: { state.setColorSynthesisMode($0) }
                        )) {
                            ForEach(ColorSynthesisMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 170)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        state.resetZoom()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Центрировать")
                                .font(.system(size: 11))
                        }
                    }
                    .disabled(state.zoomScale == 1.0 && state.imageOffset == .zero)
                    
                    Text("Zoom: \(String(format: "%.1f", state.zoomScale))x")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if cube.is2D, let dims2D = cube.dims2D {
                        Divider()
                            .frame(height: 18)
                        Text("размер: \(dims2D.width) × \(dims2D.height)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Divider()
                            .frame(height: 18)
                        Text("dims: \(cube.dims.0) × \(cube.dims.1) × \(cube.dims.2)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !cube.is2D {
                if state.viewMode == .gray {
                    grayscaleChannelControls(cube: cube)
                } else {
                    colorSynthesisControls(cube: cube)
                }
                
                HStack(spacing: 12) {
                    Button {
                        showWavelengthPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wave.3.right")
                                .font(.system(size: 10))
                            Text("Длины волн")
                                .font(.system(size: 11))
                        }
                    }
                    .popover(isPresented: $showWavelengthPopover, arrowEdge: .top) {
                        wavelengthPopoverContent
                    }
                    
                    if let lambda = state.wavelengths {
                        Text("λ: \(lambda.count) каналов")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if let first = lambda.first, let last = lambda.last {
                            Text("(\(String(format: "%.0f", first)) – \(String(format: "%.0f", last)) нм)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("λ не заданы")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            state.updateChannelCount()
        }
        .onChange(of: state.cube?.dims.0) { _ in
            state.updateChannelCount()
        }
    }
    
    private func grayscaleChannelControls(cube: HyperCube) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let channelIdx = Int(state.currentChannel)
            let wavelengthText: String = {
                if let wavelengths = state.wavelengths,
                   channelIdx < wavelengths.count {
                    return String(format: " (%.2f нм)", wavelengths[channelIdx])
                }
                return ""
            }()
            
            HStack {
                Text("Канал: \(channelIdx) / \(max(state.channelCount - 1, 0))\(wavelengthText)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                
                Spacer()
                
                if state.isTrimMode {
                    trimInfoView
                }
            }
            
            HStack(spacing: 8) {
                ChannelSliderView(
                    currentChannel: $state.currentChannel,
                    channelCount: state.channelCount,
                    cube: cube,
                    layout: state.activeLayout,
                    isTrimMode: state.isTrimMode,
                    trimStart: $state.trimStart,
                    trimEnd: $state.trimEnd
                )
                
                trimControlButtons
            }
        }
    }
    
    private func colorSynthesisControls(cube: HyperCube) -> some View {
        let mapping = state.colorSynthesisConfig.mapping.clamped(maxChannelCount: max(state.channelCount, 0))
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Каналы цветосинтеза")
                        .font(.system(size: 11, weight: .medium))
                    Text(colorMappingDescription(mapping: mapping))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            ColorSynthesisSliderView(
                channelCount: state.channelCount,
                cube: cube,
                layout: state.activeLayout,
                mapping: mapping
            ) { newMapping in
                state.updateColorSynthesisMapping(newMapping, userInitiated: true)
            }
        }
    }
    
    private func colorMappingDescription(mapping: RGBChannelMapping) -> String {
        func channelInfo(label: String, index: Int) -> String {
            if let wavelengths = state.wavelengths, index < wavelengths.count {
                return "\(label): ch \(index) (\(String(format: "%.1f", wavelengths[index])) нм)"
            }
            return "\(label): ch \(index)"
        }
        
        let red = channelInfo(label: "R", index: mapping.red)
        let green = channelInfo(label: "G", index: mapping.green)
        let blue = channelInfo(label: "B", index: mapping.blue)
        return "\(red) • \(green) • \(blue)"
    }
    
    private var trimControlButtons: some View {
        VStack(spacing: 4) {
            if state.isTrimMode {
                TrimActionButton(
                    icon: "checkmark",
                    color: .green,
                    tooltip: "Применить обрезку"
                ) {
                    state.applyTrim()
                }
                
                TrimActionButton(
                    icon: "xmark",
                    color: .red,
                    tooltip: "Отменить"
                ) {
                    state.exitTrimMode()
                }
            } else {
                Button {
                    state.enterTrimMode()
                } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .help("Обрезать каналы")
            }
        }
    }
    
    private var trimInfoView: some View {
        HStack(spacing: 4) {
            let startCh = Int(state.trimStart)
            let endCh = Int(state.trimEnd)
            let trimCount = endCh - startCh + 1
            
            if let wavelengths = state.wavelengths,
               startCh < wavelengths.count,
               endCh < wavelengths.count {
                Text("Обрезка: \(String(format: "%.0f", wavelengths[startCh])) – \(String(format: "%.0f", wavelengths[endCh])) нм")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("(\(trimCount) кан.)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("Обрезка: канал \(startCh) – \(endCh)")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("(\(trimCount) кан.)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.15))
        .cornerRadius(4)
    }
    
    private var wavelengthPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройка длин волн")
                .font(.system(size: 12, weight: .semibold))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Диапазон (нм):")
                    .font(.system(size: 11))
                
                HStack(spacing: 8) {
                    Text("от")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("400", text: $state.lambdaStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    
                    Text("до")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("1000", text: $state.lambdaEnd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                
                if state.channelCount > 1 {
                    let step = calculateDisplayStep()
                    Text("Шаг: \(String(format: "%.2f", step)) нм")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Button("Применить диапазон") {
                    state.generateWavelengthsFromParams()
                    showWavelengthPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Или загрузить из файла:")
                    .font(.system(size: 11))
                
                Button("Выбрать .txt файл…") {
                    openWavelengthTXT()
                    showWavelengthPopover = false
                }
                .controlSize(.small)
            }
            
            if let lambda = state.wavelengths {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Текущие значения:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(lambda.count) каналов")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let first = lambda.first, let last = lambda.last {
                        Text("\(String(format: "%.1f", first)) – \(String(format: "%.1f", last)) нм")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
    
    private func calculateDisplayStep() -> Double {
        guard let start = Double(state.lambdaStart.replacingOccurrences(of: ",", with: ".")),
              let end = Double(state.lambdaEnd.replacingOccurrences(of: ",", with: ".")),
              state.channelCount > 1 else {
            return 0
        }
        return (end - start) / Double(state.channelCount - 1)
    }
    
    private func openWavelengthTXT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать txt"
        panel.allowedContentTypes = [.plainText]
        
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        
        state.loadWavelengthsFromTXT(url: url)
    }
    
    private func fittingSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return containerSize
        }
        
        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = min(widthScale, heightScale, 1.0)
        
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
    
    private func handleImageClick(at location: CGPoint, geoSize: CGSize) {
        guard state.activeAnalysisTool == .spectrumGraph else { return }
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        state.extractSpectrum(at: pixel.x, pixelY: pixel.y)
    }
    
    private func pixelCoordinate(for location: CGPoint, geoSize: CGSize) -> PixelCoordinate? {
        guard currentImageSize.width > 0, currentImageSize.height > 0 else { return nil }
        
        let fittedSize = fittingSize(imageSize: currentImageSize, in: geoSize)
        let totalZoom = state.zoomScale * tempZoomScale
        let scaledImageSize = CGSize(
            width: fittedSize.width * totalZoom,
            height: fittedSize.height * totalZoom
        )
        
        let centerX = geoSize.width / 2
        let centerY = geoSize.height / 2
        
        let imageOriginX = centerX - scaledImageSize.width / 2 + state.imageOffset.width + dragOffset.width
        let imageOriginY = centerY - scaledImageSize.height / 2 + state.imageOffset.height + dragOffset.height
        
        let relativeX = location.x - imageOriginX
        let relativeY = location.y - imageOriginY
        
        guard relativeX >= 0, relativeX < scaledImageSize.width,
              relativeY >= 0, relativeY < scaledImageSize.height else {
            return nil
        }
        
        let maxX = max(Int(currentImageSize.width) - 1, 0)
        let maxY = max(Int(currentImageSize.height) - 1, 0)
        let rawX = Int((relativeX / scaledImageSize.width) * currentImageSize.width)
        let rawY = Int((relativeY / scaledImageSize.height) * currentImageSize.height)
        let pixelX = max(0, min(rawX, maxX))
        let pixelY = max(0, min(rawY, maxY))
        
        return PixelCoordinate(x: pixelX, y: pixelY)
    }
    
    private func roiRect(from start: PixelCoordinate, to end: PixelCoordinate) -> SpectrumROIRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x) + 1
        let height = abs(end.y - start.y) + 1
        return SpectrumROIRect(minX: minX, minY: minY, width: width, height: height)
    }
    
    private func handleROIDrag(value: DragGesture.Value, geoSize: CGSize) {
        guard let startPixel = roiDragStartPixel ?? pixelCoordinate(for: value.startLocation, geoSize: geoSize) else { return }
        guard let currentPixel = pixelCoordinate(for: value.location, geoSize: geoSize) else { return }
        roiDragStartPixel = startPixel
        roiPreviewRect = roiRect(from: startPixel, to: currentPixel)
    }
    
    private func handleROIDragEnd(value: DragGesture.Value, geoSize: CGSize) {
        defer {
            roiDragStartPixel = nil
            roiPreviewRect = nil
        }
        guard
            let startPixel = roiDragStartPixel ?? pixelCoordinate(for: value.startLocation, geoSize: geoSize),
            let endPixel = pixelCoordinate(for: value.location, geoSize: geoSize)
        else { return }
        let rect = roiRect(from: startPixel, to: endPixel)
        state.extractROISpectrum(for: rect)
    }
    
    private func roiSelectionGesture(in geoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(imageCoordinateSpaceName))
            .onChanged { value in
                guard state.activeAnalysisTool == .spectrumGraphROI else { return }
                handleROIDrag(value: value, geoSize: geoSize)
            }
            .onEnded { value in
                guard state.activeAnalysisTool == .spectrumGraphROI else { return }
                handleROIDragEnd(value: value, geoSize: geoSize)
            }
    }
}

private struct LibraryExportToastView: View {
    let state: LibraryExportProgressState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(titleText)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            
            switch state.phase {
            case .running:
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                Text("\(state.completed) / \(state.total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            case .success, .failure:
                Text(state.message ?? defaultMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
    
    private var titleText: String {
        switch state.phase {
        case .running:
            return "Экспорт библиотеки"
        case .success:
            return "Готово"
        case .failure:
            return "Ошибка экспорта"
        }
    }
    
    private var iconName: String {
        switch state.phase {
        case .running:
            return "tray.full"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch state.phase {
        case .running:
            return .accentColor
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
    
    private var defaultMessage: String {
        switch state.phase {
        case .success:
            return "Все файлы успешно экспортированы"
        case .failure:
            return "При экспорте возникли ошибки"
        case .running:
            return ""
        }
    }
}

private struct SpectrumPointsOverlay: View {
    let samples: [SpectrumSample]
    let originalSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                let position = position(for: sample)
                Circle()
                    .fill(sample.displayColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .frame(width: 10, height: 10)
                    .position(x: position.x, y: position.y)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    
    private func position(for sample: SpectrumSample) -> CGPoint {
        let width = max(originalSize.width - 1, 1)
        let height = max(originalSize.height - 1, 1)
        let xRatio = CGFloat(sample.pixelX) / width
        let yRatio = CGFloat(sample.pixelY) / height
        let x = xRatio * displaySize.width
        let y = yRatio * displaySize.height
        return CGPoint(x: x, y: y)
    }
}

private struct SpectrumROIsOverlay: View {
    let samples: [SpectrumROISample]
    let temporaryRect: SpectrumROIRect?
    let originalSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                roiPath(for: sample.rect)
                    .stroke(sample.displayColor, lineWidth: 1.5)
                    .background(
                        roiPath(for: sample.rect)
                            .fill(sample.displayColor.opacity(0.08))
                    )
            }
            
            if let temp = temporaryRect {
                roiPath(for: temp)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .background(
                        roiPath(for: temp)
                            .fill(Color.accentColor.opacity(0.05))
                    )
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    
    private func roiPath(for rect: SpectrumROIRect) -> Path {
        Path { path in
            path.addRoundedRect(in: frame(for: rect), cornerSize: CGSize(width: 4, height: 4))
        }
    }
    
    private func frame(for rect: SpectrumROIRect) -> CGRect {
        guard originalSize.width > 0, originalSize.height > 0 else { return .zero }
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height
        let x = CGFloat(rect.minX) * scaleX
        let y = CGFloat(rect.minY) * scaleY
        let width = CGFloat(rect.width) * scaleX
        let height = CGFloat(rect.height) * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct PixelCoordinate: Equatable {
    let x: Int
    let y: Int
}

struct TrimActionButton: View {
    let icon: String
    let color: Color
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .shadow(color: isHovered ? color.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(isHovered ? 0.8 : 0.4), lineWidth: isHovered ? 2 : 1)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isHovered ? .white : color)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 30, height: 30)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .help(tooltip)
    }
    
    private var backgroundColor: Color {
        if isPressed {
            return color.opacity(0.9)
        } else if isHovered {
            return color.opacity(0.75)
        } else {
            return color.opacity(0.15)
        }
    }
}

struct BusyOverlayView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.1)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
        )
    }
}
