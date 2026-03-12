import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    private final class ROICursorHoverBuffer {
        var pixel: PixelCoordinate?
    }

    @EnvironmentObject var state: AppState
    @State private var tempZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var showWavelengthPopover: Bool = false
    @State private var currentImageSize: CGSize = .zero
    @State private var currentGeoSize: CGSize = .zero
    @State private var roiDragStartPixel: PixelCoordinate?
    @State private var roiPreviewRect: SpectrumROIRect?
    @State private var roiCursorHoverPixel: PixelCoordinate?
    @State private var roiCursorPreviewRect: SpectrumROIRect?
    @State private var roiCursorHoverBuffer = ROICursorHoverBuffer()
    @State private var cachedROICursorSourceImageID: ObjectIdentifier?
    @State private var lastCursorGeoPixel: PixelCoordinate?
    @State private var rulerHoverPixel: PixelCoordinate?
    @State private var showWDVIAutoSheet: Bool = false
    @State private var showAdaptiveNDSheet: Bool = false
    @State private var wdviAutoConfig = WDVIAutoEstimationConfig(
        selectedROIIDs: [],
        lowerPercentile: 0.02,
        upperPercentile: 0.98,
        zScoreThreshold: 3.0,
        method: .ols
    )
    @State private var adaptiveNDConfig = AdaptiveNDEstimationConfig(
        positiveROIIDs: [],
        negativeROIIDs: []
    )
    @State private var leftPanelDragStartWidth: CGFloat?
    @State private var rightPanelDragStartWidth: CGFloat?
    @FocusState private var isImageFocused: Bool
    
    private let imageCoordinateSpaceName = "image-canvas"
    
    var body: some View {
        GeometryReader { proxy in
            let isRightPanelVisible = state.cube != nil && state.isRightPanelVisible
            let uncoveredRightWidth = isRightPanelVisible ? (state.rightPanelWidth + 12) : 0
            let dimmedWidth = max(0, proxy.size.width - uncoveredRightWidth)
            GlassEffectContainerWrapper {
                ZStack {
                    mainContent
                        .disabled(state.isBusy)

                    if state.isCubeMetricsSelectionMode {
                        Color.black.opacity(0.3)
                            .frame(width: dimmedWidth, height: proxy.size.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    
                    if state.isBusy {
                        ZStack {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                            BusyOverlayView(
                                message: state.localized(state.busyMessage ?? "Выполнение…"),
                                progress: state.busyProgress
                            )
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
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(isPresented: $showWDVIAutoSheet) {
            wdviAutoSheet
        }
        .sheet(isPresented: $showAdaptiveNDSheet) {
            adaptiveNDSheet
        }
        .sheet(isPresented: $state.showFastImportSheet) {
            FastImportSheetView()
                .environmentObject(state)
        }
        .onAppear {
            ROICursorPreviewWindowManager.shared.hide()
        }
        .onDisappear {
            ROICursorPreviewWindowManager.shared.hide()
        }
        .onChange(of: state.cube?.id) { _, cubeID in
            if cubeID == nil {
                clearROICursorHoverState()
            }
            ROICursorPreviewWindowManager.shared.hide()
        }
        .task(id: roiCursorSchedulerID) {
            await runROICursorSchedulerLoop()
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            
            HStack(spacing: 0) {
                let canShowLeftPanel = state.cube != nil && state.isLeftPanelVisible
                let canShowRightPanel = state.cube != nil && state.isRightPanelVisible
                let graphToggleWidth: CGFloat = 20
                let graphPanelWidth = max(220, state.rightPanelWidth - graphToggleWidth)
                let showsROICursorPreviewInLeftPanel = state.activeAnalysisTool == .roiCursor && state.cube != nil

                if canShowLeftPanel {
                    if showsROICursorPreviewInLeftPanel {
                        roiCursorPreviewPanel
                            .frame(width: state.leftPanelWidth)
                            .padding(.leading, 12)
                            .allowsHitTesting(!state.isCubeMetricsSelectionMode)
                    } else if state.viewMode == .mask {
                        MaskLayersPanelView(maskState: state.maskEditorState)
                            .frame(width: state.leftPanelWidth)
                            .padding(.leading, 12)
                            .allowsHitTesting(!state.isCubeMetricsSelectionMode)
                    } else {
                        PipelinePanel()
                            .environmentObject(state)
                            .frame(width: state.leftPanelWidth)
                            .padding(.leading, 12)
                            .disabled(state.isCurrentCubeProcessingInProgress)
                            .allowsHitTesting(!state.isCubeMetricsSelectionMode)
                    }
                    
                    panelResizeHandle { translation in
                        if leftPanelDragStartWidth == nil {
                            leftPanelDragStartWidth = state.leftPanelWidth
                        }
                        let baseWidth = leftPanelDragStartWidth ?? state.leftPanelWidth
                        state.setLeftPanelWidth(baseWidth + translation.width)
                    } onEnded: {
                        leftPanelDragStartWidth = nil
                    }
                }
                
                if state.viewMode == .mask && state.cube != nil {
                    MaskEditorView(maskState: state.maskEditorState)
                        .environmentObject(state)
                } else {
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
                                Text(state.localized("content_view.open_cube"))
                                    .font(.system(size: 14, weight: .medium))
                                Text("Cmd + O")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(state.localized("content_view.empty_hint"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                            if state.showAlignmentVisualization && state.alignmentPointsEditable && currentImageSize.width > 0 {
                                let fittedSize = fittingSize(imageSize: currentImageSize, in: geo.size)
                                AlignmentPointsOverlay(
                                    result: state.activeAlignmentResult,
                                    params: state.activeAlignmentParams,
                                    currentChannel: Int(state.currentChannel),
                                    originalSize: currentImageSize,
                                    displaySize: fittedSize
                                )
                                .frame(width: fittedSize.width, height: fittedSize.height)
                                .scaleEffect(state.zoomScale * tempZoomScale)
                                .offset(
                                    x: state.imageOffset.width + dragOffset.width,
                                    y: state.imageOffset.height + dragOffset.height
                                )
                            }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .overlay(alignment: .topLeading) {
                        if state.isCurrentCubeAlignmentInProgress {
                            AlignmentProcessingToastView(
                                title: state.localized("content.alignment.processing.title"),
                                progress: state.alignmentProgress,
                                message: state.alignmentProgressMessage
                            )
                            .frame(maxWidth: 320)
                            .padding(12)
                            .allowsHitTesting(false)
                        } else if state.isCurrentCubePipelineInProgress {
                            PipelineProcessingToastView(
                                message: state.currentCubePipelineProcessingMessage
                            )
                            .frame(maxWidth: 320)
                            .padding(12)
                            .allowsHitTesting(false)
                        }
                    }
                    .allowsHitTesting(!state.isCurrentCubeProcessingInProgress && !state.isCubeMetricsSelectionMode)
                    .background(
                        TrackpadScrollCatcher { delta in
                            guard state.cube != nil else { return }
                            guard !state.isCurrentCubeProcessingInProgress else { return }
                            state.moveImage(by: delta)
                        }
                        .allowsHitTesting(false)
                    )
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
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard !state.alignmentPointsEditable else { return }
                                if state.activeAnalysisTool == .spectrumGraphROI {
                                    handleROIDrag(value: value, geoSize: geo.size)
                                } else if state.activeAnalysisTool == .ruler {
                                    return
                                } else {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                guard !state.alignmentPointsEditable else { return }
                                if state.activeAnalysisTool == .spectrumGraphROI {
                                    handleROIDragEnd(value: value, geoSize: geo.size)
                                } else if state.activeAnalysisTool == .ruler {
                                    return
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
                        } else if state.activeAnalysisTool == .roiCursor {
                            handleROICursorClick(at: location, geoSize: geo.size)
                        } else if state.activeAnalysisTool == .ruler,
                                  state.rulerMode == .measure {
                            handleRulerClick(at: location, geoSize: geo.size)
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($isImageFocused)
                    .onAppear {
                        isImageFocused = true
                    }
                    .onKeyPress(.leftArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI,
                              state.activeAnalysisTool != .ruler else { return .ignored }
                        state.moveImage(by: CGSize(width: 20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI,
                              state.activeAnalysisTool != .ruler else { return .ignored }
                        state.moveImage(by: CGSize(width: -20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI,
                              state.activeAnalysisTool != .ruler else { return .ignored }
                        state.moveImage(by: CGSize(width: 0, height: 20))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI,
                              state.activeAnalysisTool != .ruler else { return .ignored }
                        state.moveImage(by: CGSize(width: 0, height: -20))
                        return .handled
                    }
                    .onKeyPress(characters: CharacterSet(charactersIn: "dD"), phases: [.down]) { keyPress in
                        guard keyPress.modifiers.isEmpty else { return .ignored }
                        guard state.cube != nil else { return .ignored }
                        state.toggleRulerModeByHotkey()
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        guard state.activeAnalysisTool == .ruler,
                              state.rulerMode == .edit else { return .ignored }
                        state.deleteSelectedRulerPoint()
                        return .handled
                    }
                    .onKeyPress(.deleteForward) {
                        guard state.activeAnalysisTool == .ruler,
                              state.rulerMode == .edit else { return .ignored }
                        state.deleteSelectedRulerPoint()
                        return .handled
                    }
                    .onDeleteCommand {
                        guard state.activeAnalysisTool == .ruler,
                              state.rulerMode == .edit else { return }
                        state.deleteSelectedRulerPoint()
                    }
                    .onChange(of: geo.size) { _, newSize in
                        currentGeoSize = newSize
                    }
                    .onHover { isHovering in
                        if (state.activeAnalysisTool == .spectrumGraph
                            || state.activeAnalysisTool == .spectrumGraphROI
                            || state.activeAnalysisTool == .roiCursor
                            || state.activeAnalysisTool == .ruler),
                           state.cube != nil {
                            if isHovering {
                                NSCursor.crosshair.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            guard let pixel = pixelCoordinate(for: location, geoSize: geo.size) else {
                                rulerHoverPixel = nil
                                clearROICursorHoverState()
                                if lastCursorGeoPixel != nil {
                                    lastCursorGeoPixel = nil
                                    state.clearCursorGeoCoordinate()
                                }
                                return
                            }
                            if state.activeAnalysisTool == .roiCursor {
                                if rulerHoverPixel != nil {
                                    rulerHoverPixel = nil
                                }
                                roiCursorHoverBuffer.pixel = pixel
                            } else if state.activeAnalysisTool == .ruler,
                               state.rulerMode == .measure {
                                rulerHoverPixel = pixel
                            } else {
                                rulerHoverPixel = nil
                                clearROICursorHoverState()
                            }
                            if state.cube?.geoReference != nil {
                                if lastCursorGeoPixel != pixel {
                                    lastCursorGeoPixel = pixel
                                    state.updateCursorGeoCoordinate(pixelX: pixel.x, pixelY: pixel.y)
                                }
                            } else {
                                if lastCursorGeoPixel != nil {
                                    lastCursorGeoPixel = nil
                                    state.clearCursorGeoCoordinate()
                                }
                            }
                        case .ended:
                            rulerHoverPixel = nil
                            clearROICursorHoverState()
                            if lastCursorGeoPixel != nil {
                                lastCursorGeoPixel = nil
                                state.clearCursorGeoCoordinate()
                            }
                        }
                    }
                    .onChange(of: state.activeAnalysisTool) {
                        NSCursor.pop()
                        roiPreviewRect = nil
                        roiDragStartPixel = nil
                        if state.activeAnalysisTool != .roiCursor {
                            clearROICursorHoverState()
                        }
                        rulerHoverPixel = nil
                        ROICursorPreviewWindowManager.shared.hide()
                    }
                    .onChange(of: state.rulerMode) { _, mode in
                        if mode != .measure {
                            rulerHoverPixel = nil
                        }
                    }
                    .onChange(of: state.roiCursorSize) {
                        guard state.activeAnalysisTool == .roiCursor,
                              let pixel = roiCursorHoverBuffer.pixel else { return }
                        updateROICursor(at: pixel)
                    }
                    .onChange(of: state.cubeURL) {
                        roiPreviewRect = nil
                        roiDragStartPixel = nil
                        clearROICursorHoverState()
                        rulerHoverPixel = nil
                        if lastCursorGeoPixel != nil {
                            lastCursorGeoPixel = nil
                            state.clearCursorGeoCoordinate()
                        }
                        ROICursorPreviewWindowManager.shared.hide()
                    }
                    .background(
                        RulerDeleteKeyCatcher(
                            isActive: Binding(
                                get: {
                                    state.activeAnalysisTool == .ruler
                                        && state.rulerMode == .edit
                                        && state.selectedRulerPointID != nil
                                },
                                set: { _ in }
                            ),
                            onDelete: {
                                state.deleteSelectedRulerPoint()
                            }
                        )
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                    )
                    }
                    .coordinateSpace(name: imageCoordinateSpaceName)
                }

                if canShowRightPanel, state.cube != nil {
                    panelResizeHandle { translation in
                        if rightPanelDragStartWidth == nil {
                            rightPanelDragStartWidth = state.rightPanelWidth
                        }
                        let baseWidth = rightPanelDragStartWidth ?? state.rightPanelWidth
                        state.setRightPanelWidth(baseWidth - translation.width)
                    } onEnded: {
                        rightPanelDragStartWidth = nil
                    }

                    if let cube = state.cube {
                        ZStack(alignment: .trailing) {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ImageInfoPanel(cube: cube, layout: state.activeLayout)
                                        .id(cube.id)
                                    
                                    LibraryPanel()
                                }
                                .padding(12)
                            }
                            .frame(maxWidth: .infinity)
                            
                            GraphPanel(panelWidth: graphPanelWidth)
                                .environmentObject(state)
                        }
                        .frame(width: state.rightPanelWidth)
                        .padding(.trailing, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            if let cube = state.cube {
                GlassPanel(cornerRadius: 0, padding: 8) {
                    if state.viewMode == .mask {
                        maskModeBottomControls(cube: cube)
                    } else {
                        bottomControls(cube: cube)
                    }
                }
                .disabled(state.isCurrentCubeProcessingInProgress || state.isCubeMetricsSelectionMode)
            }
        }
        .frame(minWidth: 960, minHeight: 500)
        .onChange(of: state.viewMode) { _, newMode in
            if newMode == .mask {
                state.prepareMaskEditorForCurrentCube()
            }
        }
        .sheet(item: $state.pendingMatSelection) { request in
            MatVariableSelectionView(request: request)
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showExportView) {
            ExportView()
                .environmentObject(state)
        }
        .onChange(of: state.pendingExport) { _, newValue in
            if let exportInfo = newValue {
                performActualExport(
                    format: exportInfo.format,
                    wavelengths: exportInfo.wavelengths,
                    matVariableName: exportInfo.matVariableName,
                    matWavelengthsAsVariable: exportInfo.matWavelengthsAsVariable,
                    colorSynthesisConfig: exportInfo.colorSynthesisConfig,
                    tiffEnviCompatible: exportInfo.tiffEnviCompatible,
                    enviOptions: exportInfo.enviOptions
                )
                state.pendingExport = nil
            }
        }
    }
    
    private func panelResizeHandle(
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.8))
                    .frame(width: 1)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChanged(value.translation)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
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
    
    private func performActualExport(
        format: ExportFormat,
        wavelengths: Bool,
        matVariableName: String?,
        matWavelengthsAsVariable: Bool,
        colorSynthesisConfig: ColorSynthesisConfig?,
        tiffEnviCompatible: Bool,
        enviOptions: EnviExportOptions?
    ) {
        if state.exportEntireLibrary {
            guard !state.libraryEntries.isEmpty else { return }
            
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = state.localized("Выбрать папку")
            panel.message = state.localized("Выберите папку для сохранения экспортированных файлов библиотеки")
            
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
                colorSynthesisConfig: colorSynthesisConfig,
                tiffEnviCompatible: tiffEnviCompatible,
                enviOptions: enviOptions
            )
            return
        }
        
        guard let cube = state.cube else { return }
        
        let defaultBaseName = state.defaultExportBaseName
        
        // PNG Channels требует выбора директории, так как создаётся много файлов
        if format == .pngChannels {
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = true
            openPanel.canChooseFiles = false
            openPanel.canCreateDirectories = true
            openPanel.allowsMultipleSelection = false
            openPanel.prompt = state.localized("Выбрать папку")
            openPanel.message = LF("content.export.png_channels.choose_folder_message", defaultBaseName)
            
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
                    let result = PngChannelsExporter.export(cube: cube, to: baseURL, wavelengths: wavelengthsToExport, layout: currentLayout)
                    
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
        case .pngChannels:
            break // Обработано выше
        case .quickPNG:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType.png]
            panel.message = state.localized("Выберите путь для сохранения PNG изображения")
        case .npy:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType(filenameExtension: "npy") ?? .data]
            panel.message = state.localized("Выберите путь для сохранения")
        case .mat:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType(filenameExtension: "mat") ?? .data]
            panel.message = state.localized("Выберите путь для сохранения")
        case .tiff:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType.tiff]
            panel.message = state.localized("Выберите путь для сохранения TIFF")
        case .enviDat:
            panel.nameFieldStringValue = "\(defaultBaseName).dat"
            panel.allowedContentTypes = [UTType(filenameExtension: "dat") ?? .data]
            panel.message = state.localized("Выберите путь для сохранения")
        case .enviRaw:
            panel.nameFieldStringValue = "\(defaultBaseName).raw"
            panel.allowedContentTypes = [UTType(filenameExtension: "raw") ?? .data]
            panel.message = state.localized("Выберите путь для сохранения")
        case .maskPNG, .maskNpy, .maskMat:
            return // Маска экспортируется через ExportView
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
                    result = TiffExporter.export(
                        cube: cube,
                        to: saveURL,
                        wavelengths: wavelengthsToExport,
                        layout: currentLayout,
                        enviCompatible: tiffEnviCompatible
                    )
                case .enviDat, .enviRaw:
                    let exportOptions = enviOptions ?? EnviExportOptions.default(
                        binaryFileType: format == .enviRaw ? .raw : .dat,
                        sourceDataType: cube.originalDataType
                    )
                    result = EnviExporter.export(
                        cube: cube,
                        to: saveURL,
                        wavelengths: wavelengthsToExport,
                        layout: currentLayout,
                        options: exportOptions,
                        colorSynthesisConfig: colorSynthesisConfig ?? state.colorSynthesisConfig
                    )
                case .quickPNG:
                    result = QuickPNGExporter.export(
                        cube: cube,
                        to: saveURL,
                        layout: currentLayout,
                        wavelengths: currentWavelengths,
                        config: colorSynthesisConfig ?? state.colorSynthesisConfig
                    )
                case .pngChannels:
                    result = .failure(ExportError.writeError("PNG channels export handled elsewhere"))
                case .maskPNG, .maskNpy, .maskMat:
                    result = .failure(ExportError.writeError("Mask export handled elsewhere"))
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
    
    private func exportLibraryEntries(
        to destinationFolder: URL,
        format: ExportFormat,
        wavelengths: Bool,
        matVariableName: String?,
        matWavelengthsAsVariable: Bool,
        colorSynthesisConfig: ColorSynthesisConfig?,
        tiffEnviCompatible: Bool,
        enviOptions: EnviExportOptions?
    ) {
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
                        print(LF("content.export.log.skip_no_data", entry.displayName))
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
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("tiff")
                        result = TiffExporter.export(
                            cube: payload.cube,
                            to: target,
                            wavelengths: wavelengthsToExport,
                            layout: payload.layout,
                            enviCompatible: tiffEnviCompatible
                        )
                    case .enviDat, .enviRaw:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension(
                            format == .enviRaw ? "raw" : "dat"
                        )
                        var exportOptions = enviOptions ?? EnviExportOptions.default(
                            binaryFileType: format == .enviRaw ? .raw : .dat,
                            sourceDataType: payload.cube.originalDataType
                        )
                        exportOptions.binaryFileType = format == .enviRaw ? .raw : .dat
                        result = EnviExporter.export(
                            cube: payload.cube,
                            to: target,
                            wavelengths: wavelengthsToExport,
                            layout: payload.layout,
                            options: exportOptions,
                            colorSynthesisConfig: payload.colorSynthesisConfig
                        )
                    case .pngChannels:
                        let target = destinationFolder.appendingPathComponent(baseName)
                        result = PngChannelsExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport, layout: payload.layout)
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
                    case .maskPNG, .maskNpy, .maskMat:
                        result = .success(())
                    }
                    
                    switch result {
                    case .success:
                        print(LF("content.export.log.exported", entry.displayName))
                    case .failure(let error):
                        print(LF("content.export.log.error", entry.displayName, error.localizedDescription))
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
                Text(state.displayName(for: url))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(state.localized("Файл не выбран"))
                        .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
                if let error = state.loadError {
                    Text("•")
                        .foregroundColor(.secondary)
                Text(state.localized(error))
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
        let targetPixels = renderTargetPixels(for: cube, geoSize: geoSize)
        let view: AnyView
        let roiCursorSourceImage: NSImage?

        switch state.viewMode {
        case .gray:
            let chIdx = Int(state.currentChannel)
            if let nsImage = ImageRenderer.renderGrayscale(
                cube: cube,
                layout: state.activeLayout,
                channelIndex: chIdx,
                targetPixels: targetPixels
            ) {
                roiCursorSourceImage = nsImage
                view = AnyView(spectrumImageView(nsImage: nsImage, geoSize: geoSize))
            } else {
                roiCursorSourceImage = nil
                view = AnyView(
                    Text(state.localized("Не удалось построить изображение"))
                        .foregroundColor(.red)
                )
            }

        case .rgb:
            let config = state.colorSynthesisConfig
            let image: NSImage?
            switch config.mode {
            case .trueColorRGB:
                image = ImageRenderer.renderRGB(
                    cube: cube,
                    layout: state.activeLayout,
                    wavelengths: state.wavelengths,
                    mapping: config.mapping,
                    targetPixels: targetPixels
                )
            case .rangeWideRGB:
                image = ImageRenderer.renderRGBRange(
                    cube: cube,
                    layout: state.activeLayout,
                    wavelengths: state.wavelengths,
                    rangeMapping: config.rangeMapping,
                    targetPixels: targetPixels
                )
            case .pcaVisualization:
                image = state.pcaRenderedImage
            }

            if let nsImage = image {
                roiCursorSourceImage = nsImage
                view = AnyView(spectrumImageView(nsImage: nsImage, geoSize: geoSize))
            } else {
                roiCursorSourceImage = nil
                view = AnyView(
                    Text(state.localized(config.mode == .pcaVisualization ? "Нажмите «Применить PCA»" : "Не удалось построить RGB изображение"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                )
            }

        case .nd:
            if let indices = state.ndChannelIndices(),
               let nsImage = ImageRenderer.renderND(
                cube: cube,
                layout: state.activeLayout,
                positiveIndex: indices.positive,
                negativeIndex: indices.negative,
                palette: state.ndPalette,
                threshold: state.ndThreshold,
                preset: state.ndPreset,
                wdviSlope: Double(state.wdviSlope.replacingOccurrences(of: ",", with: ".")) ?? 1.0,
                wdviIntercept: Double(state.wdviIntercept.replacingOccurrences(of: ",", with: ".")) ?? 0.0,
                targetPixels: targetPixels
               ) {
                roiCursorSourceImage = nsImage
                view = AnyView(spectrumImageView(nsImage: nsImage, geoSize: geoSize))
            } else {
                roiCursorSourceImage = nil
                view = AnyView(
                    Text(state.localized("Не удалось построить ND"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                )
            }

        case .mask:
            roiCursorSourceImage = nil
            view = AnyView(EmptyView())
        }

        return view
            .task(id: roiCursorSourceImage.map(ObjectIdentifier.init)) {
                cacheROICursorSourceImage(roiCursorSourceImage)
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
            } else if state.activeAnalysisTool == .spectrumGraphROI || state.activeAnalysisTool == .roiCursor {
                SpectrumROIsOverlay(
                    samples: state.activeAnalysisTool == .roiCursor ? state.roiSamples : state.activeROISamples,
                    temporaryRect: state.activeAnalysisTool == .roiCursor ? roiCursorPreviewRect : roiPreviewRect,
                    temporaryColor: state.activeAnalysisTool == .roiCursor
                        ? (state.roiCursorSample?.displayColor ?? .accentColor)
                        : .accentColor,
                    originalSize: nsImage.size,
                    displaySize: fittedSize
                )
            } else if state.activeAnalysisTool == .ruler {
                RulerOverlay(
                    points: state.rulerPoints,
                    hoverPixel: state.rulerMode == .measure ? rulerHoverPixel : nil,
                    mode: state.rulerMode,
                    selectedPointID: state.selectedRulerPointID,
                    geoReference: state.cube?.geoReference,
                    originalSize: nsImage.size,
                    displaySize: fittedSize
                ) { id, x, y in
                    state.updateRulerPoint(id: id, pixelX: x, pixelY: y)
                } onSelectPoint: { id in
                    state.selectRulerPoint(id: id)
                    isImageFocused = true
                }
            }
            
            if state.showAlignmentVisualization && !state.alignmentPointsEditable {
                AlignmentPointsOverlay(
                    result: state.activeAlignmentResult,
                    params: state.activeAlignmentParams,
                    currentChannel: Int(state.currentChannel),
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
            cacheROICursorSourceImage(nsImage)
        }
        .onChange(of: nsImage.size) { _, newSize in
            currentImageSize = newSize
        }
        .onChange(of: state.activeAnalysisTool) {
            cacheROICursorSourceImage(nsImage)
        }
    }
    
    private func bottomControls(cube: HyperCube) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if cube.is2D {
                    Text(state.localized("Режим: 2D изображение"))
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
                        .padding(.trailing, 6)
                    
                    Picker("", selection: $state.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.leading, 2)
                    .frame(width: 160)
                    
                    if state.viewMode == .rgb {
                        Divider()
                            .frame(height: 18)
                            .padding(.leading, 8)
                        
                        Text(state.localized("Цветосинтез:"))
                            .font(.system(size: 11))
                            .padding(.leading, 4)
                        
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
                            Text(state.localized("Центрировать"))
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
                        Text(LF("content.dimensions.2d", dims2D.width, dims2D.height))
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
                } else if state.viewMode == .rgb {
                    colorSynthesisControls(cube: cube)
                } else if state.viewMode == .nd {
                    ndControls()
                }
                
                HStack(spacing: 12) {
                    Button {
                        showWavelengthPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wave.3.right")
                                .font(.system(size: 10))
                            Text(state.localized("Длины волн"))
                                .font(.system(size: 11))
                        }
                    }
                    .popover(isPresented: $showWavelengthPopover, arrowEdge: .top) {
                        wavelengthPopoverContent
                    }
                    
                    if let lambda = state.wavelengths {
                        Text(LF("content.lambda.channels_count", lambda.count))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if let first = lambda.first, let last = lambda.last {
                            Text(LF("content.lambda.range_brackets", String(format: "%.0f", first), String(format: "%.0f", last)))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(state.localized("λ не заданы"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func maskModeBottomControls(cube: HyperCube) -> some View {
        HStack {
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
                .padding(.trailing, 6)
            
            Picker("", selection: $state.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.leading, 2)
            .frame(width: 200)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    state.resetZoom()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text(state.localized("Центрировать"))
                            .font(.system(size: 11))
                    }
                }
                .disabled(state.zoomScale == 1.0 && state.imageOffset == .zero)
                
                Text("Zoom: \(String(format: "%.1f", state.zoomScale))x")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Divider()
                    .frame(height: 18)
                
                if let firstMask = state.maskEditorState.maskLayers.first {
                    Text(LF("content.mask.size", firstMask.width, firstMask.height))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func grayscaleChannelControls(cube: HyperCube) -> some View {
                VStack(alignment: .leading, spacing: 8) {
                    let channelIdx = Int(state.currentChannel)
                    let wavelengthText: String = {
                        if let wavelengths = state.wavelengths,
                           channelIdx < wavelengths.count {
                            return LF("content.channel.wavelength_suffix", String(format: "%.2f", wavelengths[channelIdx]))
                        }
                        return ""
                    }()
                    
                    HStack {
                        Text(LF("content.channel.current", channelIdx, max(state.channelCount - 1, 0), wavelengthText))
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
            
    @ViewBuilder
    private func colorSynthesisControls(cube: HyperCube) -> some View {
        switch state.colorSynthesisConfig.mode {
        case .trueColorRGB:
            let mapping = state.colorSynthesisConfig.mapping.clamped(maxChannelCount: max(state.channelCount, 0))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Каналы цветосинтеза"))
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
            
        case .rangeWideRGB:
            RangeWideColorControls(cube: cube)
                .environmentObject(state)
            
        case .pcaVisualization:
            pcaColorControls(cube: cube)
        }
    }
    
    private func colorMappingDescription(mapping: RGBChannelMapping) -> String {
        func channelInfo(label: String, index: Int) -> String {
            if let wavelengths = state.wavelengths, index < wavelengths.count {
                return LF("content.color_mapping.channel_nm", label, index, String(format: "%.1f", wavelengths[index]))
            }
            return LF("content.color_mapping.channel", label, index)
        }
        
        let red = channelInfo(label: "R", index: mapping.red)
        let green = channelInfo(label: "G", index: mapping.green)
        let blue = channelInfo(label: "B", index: mapping.blue)
        return "\(red) • \(green) • \(blue)"
    }
    
    private func ndControls() -> some View {
        let menuLabelInset: CGFloat = 6
        return VStack(alignment: .leading, spacing: 8) {
            Text(state.localized("ND индексы"))
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Пресет")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, menuLabelInset)
                    Picker("", selection: $state.ndPreset) {
                        ForEach(NDIndexPreset.allCases) { preset in
                            Text(preset.localizedTitle).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                switch state.ndPreset {
                case .ndvi:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Red (нм)"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        TextField("660", text: $state.ndviRedTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("NIR (нм)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("840", text: $state.ndviNIRTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                case .ndsi:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Green (нм)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("555", text: $state.ndsiGreenTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("SWIR (нм)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("1610", text: $state.ndsiSWIRTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                case .adaptive:
                    let maxChannel = max(state.channelCount - 1, 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Канал +"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Stepper(value: $state.adaptiveNDPositiveChannel, in: 0...maxChannel) {
                            Text("ch \(state.adaptiveNDPositiveChannel)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .frame(width: 120, alignment: .leading)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Канал -"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Stepper(value: $state.adaptiveNDNegativeChannel, in: 0...maxChannel) {
                            Text("ch \(state.adaptiveNDNegativeChannel)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .frame(width: 120, alignment: .leading)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ")
                            .font(.system(size: 10))
                        Button {
                            let roiIDs = Set(state.roiSamples.map(\.id))
                            adaptiveNDConfig = AdaptiveNDEstimationConfig(
                                positiveROIIDs: state.adaptiveNDPositiveROIIDs.intersection(roiIDs),
                                negativeROIIDs: state.adaptiveNDNegativeROIIDs.intersection(roiIDs)
                            )
                            if adaptiveNDConfig.positiveROIIDs.isEmpty,
                               adaptiveNDConfig.negativeROIIDs.isEmpty,
                               state.roiSamples.count >= 2 {
                                adaptiveNDConfig.positiveROIIDs = [state.roiSamples[0].id]
                                adaptiveNDConfig.negativeROIIDs = [state.roiSamples[1].id]
                            }
                            showAdaptiveNDSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text(state.localized("Подобрать по ROI…"))
                            }
                        }
                    }
                case .wdvi:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Red (нм)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("660", text: $state.ndviRedTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("NIR (нм)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("840", text: $state.ndviNIRTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("a (slope)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("1.0", text: $state.wdviSlope)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("b (intercept)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("0.0", text: $state.wdviIntercept)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ")
                            .font(.system(size: 10))
                    Button {
                            let roiIDs = Set(state.roiSamples.map { $0.id })
                            wdviAutoConfig = WDVIAutoEstimationConfig(
                                selectedROIIDs: roiIDs,
                                lowerPercentile: wdviAutoConfig.lowerPercentile,
                                upperPercentile: wdviAutoConfig.upperPercentile,
                                zScoreThreshold: wdviAutoConfig.zScoreThreshold,
                                method: wdviAutoConfig.method
                            )
                            showWDVIAutoSheet = true
                    } label: {
                        HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                Text(state.localized("Автооценка почвы…"))
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Палитра"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, menuLabelInset)
                    Picker("", selection: $state.ndPalette) {
                        ForEach(NDPalette.allCases) { palette in
                            Text(palette.localizedTitle).tag(palette)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 200, alignment: .leading)
                
                if state.ndPalette == .binaryVegetation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Порог ND"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack {
                            Slider(value: $state.ndThreshold, in: -1...1, step: 0.01)
                                .frame(width: 180)
                            Text(String(format: "%.2f", state.ndThreshold))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 50, alignment: .leading)
                        }
                        Button {
                            _ = state.addCurrentNDBinaryAsMaskLayer()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up.fill")
                                Text(state.localized("Добавить как слой маски"))
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(state.cube == nil || state.channelCount < 2)
                    }
                }
            }
        }
    }
    
    private var wdviAutoSheet: some View {
        let rois = state.roiSamples
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.localized("Автооценка линии почвы (WDVI)"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            
            if rois.isEmpty {
                Text(state.localized("Сохранённых ROI нет — добавьте области на изображении и повторите."))
                                .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(state.localized("ROI для оценки"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button(state.localized("Выбрать все")) {
                            wdviAutoConfig.selectedROIIDs = Set(rois.map { $0.id })
                        }
                        Button(state.localized("Очистить")) {
                            wdviAutoConfig.selectedROIIDs.removeAll()
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(rois) { roi in
                                Toggle(isOn: Binding(
                                    get: { wdviAutoConfig.selectedROIIDs.contains(roi.id) },
                                    set: { isOn in
                                        if isOn {
                                            wdviAutoConfig.selectedROIIDs.insert(roi.id)
                                        } else {
                                            wdviAutoConfig.selectedROIIDs.remove(roi.id)
                                        }
                                    }
                                )) {
                                    Text(roi.displayName ?? "ROI \(roi.id.uuidString.prefix(4))")
                                        .font(.system(size: 11))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                        .frame(maxHeight: 180)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text(state.localized("Фильтрация и регрессия"))
                    .font(.system(size: 11, weight: .medium))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.localized("Обрезка по перцентилям"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Text(state.localized("Нижний"))
                            .font(.system(size: 10))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { wdviAutoConfig.lowerPercentile * 100 },
                            set: { v in wdviAutoConfig.lowerPercentile = min(v / 100, wdviAutoConfig.upperPercentile - 0.01) }
                        ), in: 0...20, step: 0.5)
                        Text(String(format: "%.1f%%", wdviAutoConfig.lowerPercentile * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                    }
                    HStack(spacing: 12) {
                        Text(state.localized("Верхний"))
                            .font(.system(size: 10))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { wdviAutoConfig.upperPercentile * 100 },
                            set: { v in wdviAutoConfig.upperPercentile = max(v / 100, wdviAutoConfig.lowerPercentile + 0.01) }
                        ), in: 80...100, step: 0.5)
                        Text(String(format: "%.1f%%", wdviAutoConfig.upperPercentile * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.localized("Отсечение по z-score"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Slider(value: $wdviAutoConfig.zScoreThreshold, in: 0...5, step: 0.1)
                                .frame(width: 220)
                            Text(String(format: "%.1f", wdviAutoConfig.zScoreThreshold))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.localized("Метод регрессии"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Picker("", selection: $wdviAutoConfig.method) {
                            ForEach(WDVIAutoRegressionMethod.allCases) { method in
                                Text(method.localizedTitle).tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button(state.localized("Отмена")) {
                    showWDVIAutoSheet = false
                }
                Button(state.localized("Рассчитать")) {
                    var normalizedConfig = wdviAutoConfig
                    normalizedConfig.lowerPercentile = max(0, min(0.5, normalizedConfig.lowerPercentile))
                    normalizedConfig.upperPercentile = min(1, max(normalizedConfig.lowerPercentile + 0.01, normalizedConfig.upperPercentile))
                    state.runWDVIAutoEstimation(config: normalizedConfig)
                    showWDVIAutoSheet = false
                }
                .disabled(rois.isEmpty || wdviAutoConfig.selectedROIIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var adaptiveNDSheet: some View {
        let rois = state.roiSamples
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(state.localized("Адаптивный индекс"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            Text(state.localized("Выберите две группы ROI. Алгоритм автоматически найдёт пару каналов с максимальным разделением групп."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if rois.isEmpty {
                Text(state.localized("Сохранённых ROI нет — добавьте области на изображении и повторите."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 12) {
                    adaptiveROISelectionColumn(
                        title: state.localized("ROI для группы A"),
                        selected: Binding(
                            get: { adaptiveNDConfig.positiveROIIDs },
                            set: { adaptiveNDConfig.positiveROIIDs = $0 }
                        ),
                        opposite: Binding(
                            get: { adaptiveNDConfig.negativeROIIDs },
                            set: { adaptiveNDConfig.negativeROIIDs = $0 }
                        ),
                        rois: rois
                    )

                    adaptiveROISelectionColumn(
                        title: state.localized("ROI для группы B"),
                        selected: Binding(
                            get: { adaptiveNDConfig.negativeROIIDs },
                            set: { adaptiveNDConfig.negativeROIIDs = $0 }
                        ),
                        opposite: Binding(
                            get: { adaptiveNDConfig.positiveROIIDs },
                            set: { adaptiveNDConfig.positiveROIIDs = $0 }
                        ),
                        rois: rois
                    )
                }
            }

            Divider()

            HStack {
                Text(
                    state.localizedFormat(
                        "adaptive.nd.current_pair",
                        state.adaptiveNDPositiveChannel,
                        state.adaptiveNDNegativeChannel
                    )
                )
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Spacer()
                Button(state.localized("Отмена")) {
                    showAdaptiveNDSheet = false
                }
                Button(state.localized("Рассчитать")) {
                    let positive = adaptiveNDConfig.positiveROIIDs.subtracting(adaptiveNDConfig.negativeROIIDs)
                    let negative = adaptiveNDConfig.negativeROIIDs.subtracting(adaptiveNDConfig.positiveROIIDs)
                    state.runAdaptiveNDEstimation(
                        config: AdaptiveNDEstimationConfig(
                            positiveROIIDs: positive,
                            negativeROIIDs: negative
                        )
                    )
                    showAdaptiveNDSheet = false
                }
                .disabled(
                    rois.isEmpty
                    || adaptiveNDConfig.positiveROIIDs.isEmpty
                    || adaptiveNDConfig.negativeROIIDs.isEmpty
                )
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 430)
    }

    private func adaptiveROISelectionColumn(
        title: String,
        selected: Binding<Set<UUID>>,
        opposite: Binding<Set<UUID>>,
        rois: [SpectrumROISample]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button(state.localized("Выбрать все")) {
                    selected.wrappedValue = Set(rois.map(\.id))
                    opposite.wrappedValue.subtract(selected.wrappedValue)
                }
                .buttonStyle(.borderless)
                Button(state.localized("Очистить")) {
                    selected.wrappedValue.removeAll()
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rois) { roi in
                        Toggle(isOn: Binding(
                            get: { selected.wrappedValue.contains(roi.id) },
                            set: { isOn in
                                if isOn {
                                    selected.wrappedValue.insert(roi.id)
                                    opposite.wrappedValue.remove(roi.id)
                                } else {
                                    selected.wrappedValue.remove(roi.id)
                                }
                            }
                        )) {
                            Text(roi.displayName ?? "ROI \(roi.id.uuidString.prefix(4))")
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            .frame(maxHeight: 250)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    @ViewBuilder
    private func pcaColorControls(cube: HyperCube) -> some View {
        let config = state.pcaPendingConfig ?? state.colorSynthesisConfig.pcaConfig
        let maxComponents = max(1, min(state.channelCount, 3))
        let componentOptions = Array(0..<maxComponents) // рассчитываем первые 3 компоненты
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Область расчёта PCA"))
                        .font(.system(size: 10, weight: .medium))
                    Picker("", selection: Binding(
                        get: { config.computeScope },
                        set: { newValue in
                            state.updatePCAConfig { $0.computeScope = newValue }
                        })) {
                        ForEach(PCAComputeScope.allCases) { scope in
                            Text(scope.localizedTitle).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preprocess")
                        .font(.system(size: 10, weight: .medium))
                    Picker("", selection: Binding(
                        get: { config.preprocess },
                        set: { newValue in
                            state.updatePCAConfig {
                                $0.preprocess = newValue
                                $0.basis = nil
                                $0.clipUpper = nil
                                $0.explainedVariance = nil
                            }
                        })) {
                        ForEach(PCAPreprocess.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.localized("Маппинг компонентов → RGB"))
                        .font(.system(size: 10, weight: .medium))
                    HStack(spacing: 8) {
                        pcaComponentPicker(label: "R", value: config.mapping.red, options: componentOptions) { newVal in
                            state.updatePCAConfig { $0.mapping.red = newVal }
                        }
                        pcaComponentPicker(label: "G", value: config.mapping.green, options: componentOptions) { newVal in
                            state.updatePCAConfig { $0.mapping.green = newVal }
                        }
                        pcaComponentPicker(label: "B", value: config.mapping.blue, options: componentOptions) { newVal in
                            state.updatePCAConfig { $0.mapping.blue = newVal }
                        }
                    }
                }
                
                Toggle("Lock basis", isOn: Binding(
                    get: { config.lockBasis },
                    set: { newValue in
                        state.updatePCAConfig { $0.lockBasis = newValue }
                    })
                )
                .font(.system(size: 10))
                .toggleStyle(.switch)
                .frame(width: 140, alignment: .leading)
            }
            
            if config.computeScope == .roi {
                HStack(spacing: 10) {
                    Text(state.localized("ROI для PCA"))
                        .font(.system(size: 10, weight: .medium))
                    Picker("ROI", selection: Binding(
                        get: { config.selectedROI ?? state.displayedROISamples.first?.id },
                        set: { newID in
                            state.updatePCAConfig { $0.selectedROI = newID }
                        })) {
                        if state.displayedROISamples.isEmpty {
                            Text(state.localized("Нет сохранённых ROI")).tag(Optional<UUID>.none)
                        } else {
                            ForEach(state.displayedROISamples) { sample in
                                Text(sample.displayName ?? "ROI \(sample.id.uuidString.prefix(6))")
                                    .tag(Optional(sample.id))
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            
            HStack(spacing: 10) {
                Text(state.localized("Отрезать верхние выбросы"))
                    .font(.system(size: 10, weight: .medium))
                Slider(
                    value: Binding(
                        get: { config.clipTopPercent },
                        set: { newValue in
                            state.updatePCAConfig {
                                $0.clipTopPercent = newValue
                                $0.basis = nil
                                $0.clipUpper = nil
                            }
                        }
                    ),
                    in: 0...5,
                    step: 0.1
                )
                Text(String(format: "%.1f %%", config.clipTopPercent))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
            }
            
            if let ev = config.explainedVariance, !ev.isEmpty {
                let total = ev.reduce(0, +)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(ev.enumerated()), id: \.0) { item in
                        let value = total > 0 ? item.element / total : 0
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(Color.accentColor.opacity(item.offset == 0 ? 0.9 : 0.6))
                                .frame(width: 18, height: CGFloat(max(4.0, value * 70.0)))
                            Text("PC\(item.offset + 1)")
                                .font(.system(size: 9, weight: .medium))
                            Text(String(format: "%.1f%%", value * 100))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    state.applyPCAVisualization()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(state.localized("Применить PCA"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    state.isPCAApplying
                    || state.cube == nil
                    || (config.computeScope == .roi && (config.selectedROI == nil && state.displayedROISamples.isEmpty))
                )
                
                if state.isPCAApplying {
                    ProgressView(state.localized(state.pcaProgressMessage ?? "Обработка…"))
                        .progressViewStyle(.linear)
                        .frame(width: 160)
                } else if state.pcaRenderedImage == nil {
                    Text(state.localized("Настройте параметры и нажмите «Применить»"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(state.localized("PCA: спектры пикселей; lock basis сохраняет базис до смены параметров."))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if config.computeScope == .roi,
               config.selectedROI == nil,
               let first = state.displayedROISamples.first?.id {
                state.updatePCAConfig { $0.selectedROI = first }
            }
        }
        .onChange(of: config.computeScope) { _, scope in
            if scope == .roi,
               config.selectedROI == nil,
               let first = state.displayedROISamples.first?.id {
                state.updatePCAConfig { $0.selectedROI = first }
            }
        }
    }
    
    private func pcaComponentPicker(label: String, value: Int, options: [Int], onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
            Picker("", selection: Binding(
                get: { value },
                set: { onChange($0) }
            )) {
                ForEach(options, id: \.self) { idx in
                    Text("PC\(idx + 1)").tag(idx)
                }
            }
            .frame(width: 80)
            .pickerStyle(.menu)
        }
    }
    
    private var trimControlButtons: some View {
        VStack(spacing: 4) {
            if state.isTrimMode {
                TrimActionButton(
                    icon: "checkmark",
                    color: .green,
                    tooltip: state.localized("Применить обрезку")
                ) {
                    state.applyTrim()
                }
                
                TrimActionButton(
                    icon: "xmark",
                    color: .red,
                    tooltip: state.localized("Отменить")
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
                .help(state.localized("Обрезать каналы"))
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
                Text(LF("content.trim.range_nm", String(format: "%.0f", wavelengths[startCh]), String(format: "%.0f", wavelengths[endCh])))
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text(LF("content.trim.channels_count", trimCount))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text(LF("content.trim.range_channel", startCh, endCh))
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text(LF("content.trim.channels_count", trimCount))
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
            Text(state.localized("Настройка длин волн"))
                .font(.system(size: 12, weight: .semibold))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("Диапазон (нм):"))
                    .font(.system(size: 11))
                
                HStack(spacing: 8) {
                    Text(state.localized("от"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("400", text: $state.lambdaStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    
                    Text(state.localized("до"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("1000", text: $state.lambdaEnd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                
                if state.channelCount > 1 {
                    let step = calculateDisplayStep()
                    Text(LF("content.lambda.step", String(format: "%.2f", step)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Button(state.localized("Применить диапазон")) {
                    state.generateWavelengthsFromParams()
                    showWavelengthPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text(state.localized("Или загрузить из файла:"))
                    .font(.system(size: 11))
                
                Button(state.localized("Выбрать .txt файл…")) {
                    openWavelengthTXT()
                    showWavelengthPopover = false
                }
                .controlSize(.small)
            }
            
            if let lambda = state.wavelengths {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.localized("Текущие значения:"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(LF("content.channels_count", lambda.count))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let first = lambda.first, let last = lambda.last {
                        Text(LF("content.lambda.range", String(format: "%.1f", first), String(format: "%.1f", last)))
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
        panel.prompt = state.localized("Выбрать txt")
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

    private func renderTargetPixels(for cube: HyperCube, geoSize: CGSize) -> CGSize? {
        guard geoSize.width > 0, geoSize.height > 0 else { return nil }

        let sourceSize: CGSize
        if cube.is2D, let dims2D = cube.dims2D {
            sourceSize = CGSize(width: dims2D.width, height: dims2D.height)
        } else {
            guard let axes = cube.axes(for: state.activeLayout) else { return nil }
            let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
            sourceSize = CGSize(width: dims[axes.width], height: dims[axes.height])
        }

        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let fittedSize = fittingSize(imageSize: sourceSize, in: geoSize)
        let backingScale = CGFloat(NSScreen.main?.backingScaleFactor ?? 2.0)
        let zoomFactor = min(max(state.zoomScale, 1.0), 3.0)
        let scaleMultiplier = backingScale * zoomFactor

        var targetWidth = max(1, Int((fittedSize.width * scaleMultiplier).rounded()))
        var targetHeight = max(1, Int((fittedSize.height * scaleMultiplier).rounded()))

        let maxDimension = 3072
        if targetWidth > maxDimension || targetHeight > maxDimension {
            let downscale = min(
                Double(maxDimension) / Double(targetWidth),
                Double(maxDimension) / Double(targetHeight)
            )
            targetWidth = max(1, Int((Double(targetWidth) * downscale).rounded()))
            targetHeight = max(1, Int((Double(targetHeight) * downscale).rounded()))
        }

        return CGSize(width: targetWidth, height: targetHeight)
    }
    
    private func handleImageClick(at location: CGPoint, geoSize: CGSize) {
        guard state.activeAnalysisTool == .spectrumGraph else { return }
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        state.extractSpectrum(at: pixel.x, pixelY: pixel.y)
    }

    private func handleRulerClick(at location: CGPoint, geoSize: CGSize) {
        guard state.activeAnalysisTool == .ruler, state.rulerMode == .measure else { return }
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        state.addRulerPoint(pixelX: pixel.x, pixelY: pixel.y)
    }

    private func handleROICursorClick(at location: CGPoint, geoSize: CGSize) {
        guard state.activeAnalysisTool == .roiCursor else { return }
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        let rect = roiCursorRect(around: pixel)
        roiCursorHoverBuffer.pixel = pixel
        roiCursorHoverPixel = pixel
        roiCursorPreviewRect = rect
        state.updateROICursorSpectrum(for: rect, force: true)
        state.saveROICursorSample()
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

    private func roiCursorRect(around pixel: PixelCoordinate) -> SpectrumROIRect {
        let width = max(Int(currentImageSize.width.rounded()), 1)
        let height = max(Int(currentImageSize.height.rounded()), 1)
        let requestedSize = max(1, state.roiCursorSize)
        let rectWidth = min(requestedSize, width)
        let rectHeight = min(requestedSize, height)
        let halfWidth = rectWidth / 2
        let halfHeight = rectHeight / 2

        let maxMinX = max(0, width - rectWidth)
        let maxMinY = max(0, height - rectHeight)
        let minX = max(0, min(pixel.x - halfWidth, maxMinX))
        let minY = max(0, min(pixel.y - halfHeight, maxMinY))

        return SpectrumROIRect(
            minX: minX,
            minY: minY,
            width: rectWidth,
            height: rectHeight
        )
    }

    private func updateROICursor(at pixel: PixelCoordinate) {
        guard state.activeAnalysisTool == .roiCursor else { return }
        roiCursorHoverPixel = pixel
        let rect = roiCursorRect(around: pixel)
        guard rect != roiCursorPreviewRect || state.roiCursorRect == nil else { return }
        roiCursorPreviewRect = rect
        state.updateROICursorSpectrum(for: rect)
    }

    private func clearROICursorHoverState() {
        guard roiCursorHoverPixel != nil
                || roiCursorPreviewRect != nil
                || state.roiCursorSample != nil
                || state.roiCursorRect != nil else {
            return
        }
        roiCursorHoverBuffer.pixel = nil
        roiCursorHoverPixel = nil
        roiCursorPreviewRect = nil
        state.clearROICursorState()
    }

    private var roiCursorSchedulerID: String {
        let cubeID = state.cube?.id.uuidString ?? "none"
        return "roi-cursor-\(state.activeAnalysisTool.rawValue)-\(cubeID)-\(state.roiCursorUpdateFPSLimit)"
    }

    @MainActor
    private func runROICursorSchedulerLoop() async {
        while !Task.isCancelled {
            if state.activeAnalysisTool == .roiCursor,
               state.cube != nil,
               let pixel = roiCursorHoverBuffer.pixel {
                updateROICursor(at: pixel)
                let interval = max(state.roiCursorRefreshInterval ?? (1.0 / 120.0), 1.0 / 240.0)
                let sleepNanoseconds = UInt64((interval * 1_000_000_000.0).rounded())
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            } else {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func cacheROICursorSourceImage(_ image: NSImage?) {
        let nextID = image.map(ObjectIdentifier.init)
        guard cachedROICursorSourceImageID != nextID else { return }
        DispatchQueue.main.async {
            cachedROICursorSourceImageID = nextID
            state.setROICursorSourceImage(image)
        }
    }

    private var roiCursorPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.localized("window.roi_cursor.title"))
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))

                if let roiImage = state.roiCursorPreviewImage {
                    Image(nsImage: roiImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Text(state.localized("roi.cursor.window.empty"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.65))
        )
    }
}
