import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var tempZoomScale: CGFloat = 1.0
    @State private var showWavelengthPopover: Bool = false
    @FocusState private var isImageFocused: Bool
    
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
                                .scaleEffect(state.zoomScale)
                                .offset(state.imageOffset)
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
                                .scaleEffect(tempZoomScale)
                                .focusable()
                                .focused($isImageFocused)
                                .onAppear {
                                    isImageFocused = true
                                }
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
                    .onKeyPress(.leftArrow) {
                        state.moveImage(by: CGSize(width: 20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        state.moveImage(by: CGSize(width: -20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        state.moveImage(by: CGSize(width: 0, height: 20))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        state.moveImage(by: CGSize(width: 0, height: -20))
                        return .handled
                    }
                }
                
                if let cube = state.cube {
                    Divider()
                    
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
                    colorSynthesisMode: exportInfo.colorSynthesisMode
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
    
    private func performActualExport(format: ExportFormat, wavelengths: Bool, matVariableName: String?, matWavelengthsAsVariable: Bool, colorSynthesisMode: ColorSynthesisMode?) {
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
                colorSynthesisMode: colorSynthesisMode
            )
            return
        }
        
        guard let cube = state.cube else { return }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let defaultBaseName = state.defaultExportBaseName
        
        switch format {
        case .tiff:
            panel.nameFieldStringValue = defaultBaseName
            panel.allowedContentTypes = []
            panel.message = "Выберите базовое имя файла (будет создано много PNG)"
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
            guard response == .OK, let saveURL = panel.url else {
                return
            }
            
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
                    result = TiffExporter.export(cube: cube, to: saveURL, wavelengths: wavelengthsToExport)
                case .quickPNG:
                    result = QuickPNGExporter.export(
                        cube: cube,
                        to: saveURL,
                        layout: currentLayout,
                        wavelengths: currentWavelengths,
                        mode: colorSynthesisMode ?? .trueColorRGB
                    )
                }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("Export successful")
                    case .failure(let error):
                        print("Export error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func exportLibraryEntries(to destinationFolder: URL, format: ExportFormat, wavelengths: Bool, matVariableName: String?, matWavelengthsAsVariable: Bool, colorSynthesisMode: ColorSynthesisMode?) {
        let entries = state.libraryEntries
        guard !entries.isEmpty else { return }
        let includeWavelengths = wavelengths
        
        DispatchQueue.global(qos: .userInitiated).async {
            for entry in entries {
                autoreleasepool {
                    guard let payload = state.exportPayload(for: entry) else {
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
                        result = TiffExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport)
                    case .quickPNG:
                        if let mode = colorSynthesisMode {
                            let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("png")
                            result = QuickPNGExporter.export(
                                cube: payload.cube,
                                to: target,
                                layout: payload.layout,
                                wavelengths: payload.wavelengths,
                                mode: mode
                            )
                        } else {
                            result = .failure(ExportError.writeError("Не выбран режим цветосинтеза"))
                        }
                    }
                    
                    switch result {
                    case .success:
                        print("Экспортирован \(entry.fileName)")
                    case .failure(let error):
                        print("Ошибка экспорта \(entry.fileName): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
    
    private var topBar: some View {
        HStack {
            if let url = state.cubeURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Файл не выбран")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let error = state.loadError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            
            Text(appVersion)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(8)
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
                    let fittedSize = fittingSize(imageSize: nsImage.size, in: geoSize)
                    
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedSize.width,
                               height: fittedSize.height,
                               alignment: .center)
                        .background(Color.black.opacity(0.02))
                } else {
                    Text("Не удалось построить изображение")
                        .foregroundColor(.red)
                }
                
            case .rgb:
                if let lambda = state.wavelengths,
                   lambda.count >= state.channelCount,
                   let nsImage = ImageRenderer.renderRGB(
                    cube: cube,
                    layout: state.activeLayout,
                    wavelengths: lambda
                   ) {
                    
                    let fittedSize = fittingSize(imageSize: nsImage.size, in: geoSize)
                    
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedSize.width,
                               height: fittedSize.height,
                               alignment: .center)
                        .background(Color.black.opacity(0.02))
                } else {
                    Text("Для RGB нужен список λ длиной ≥ \(state.channelCount)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
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
            
            if !cube.is2D && state.viewMode == .gray {
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
            
            if !cube.is2D {
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
