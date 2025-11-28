import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var tempZoomScale: CGFloat = 1.0
    @FocusState private var isImageFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            topBar
            
            HStack(spacing: 0) {
                if state.cube != nil {
                    PipelinePanel()
                        .environmentObject(state)
                        .padding(12)
                    
                    Divider()
                }
                
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
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
                        .frame(
                            width: geo.size.width,
                            height: geo.size.height,
                            alignment: .center
                        )
                    }
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
                    VStack(spacing: 0) {
                        Divider()
                        
                        ScrollView {
                            VStack(spacing: 12) {
                                ImageInfoPanel(cube: cube, layout: state.layout)
                                    .id(cube.id)
                            }
                            .padding(12)
                        }
                        .frame(width: 260)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    }
                }
            }
            
            if let cube = state.cube {
                bottomControls(cube: cube)
                    .padding(8)
                    .border(Color(NSColor.separatorColor), width: 0.5)
            }
        }
        .frame(minWidth: 960, minHeight: 500)
        .sheet(isPresented: $state.showExportView) {
            ExportView()
                .environmentObject(state)
        }
        .onChange(of: state.pendingExport) { newValue in
            if let exportInfo = newValue {
                performActualExport(format: exportInfo.format, wavelengths: exportInfo.wavelengths)
                state.pendingExport = nil
            }
        }
    }
    
    private func performActualExport(format: ExportFormat, wavelengths: Bool) {
        guard let cube = state.cube else { return }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        
        if format == .tiff {
            panel.nameFieldStringValue = "hypercube"
            panel.allowedContentTypes = []
            panel.message = "Выберите базовое имя файла (будет создано много PNG)"
        } else {
            panel.nameFieldStringValue = "hypercube.\(format.fileExtension)"
            if format == .npy {
                panel.allowedContentTypes = [UTType(filenameExtension: "npy") ?? .data]
            }
            panel.message = "Выберите путь для сохранения"
        }
        
        panel.begin { response in
            guard response == .OK, let saveURL = panel.url else {
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Void, Error>
                
                switch format {
                case .npy:
                    result = NpyExporter.export(cube: cube, to: saveURL, exportWavelengths: wavelengths)
                case .tiff:
                    result = TiffExporter.export(cube: cube, to: saveURL, exportWavelengths: wavelengths)
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
                    layout: state.layout,
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
                    layout: state.layout,
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
                HStack {
                    Text("Канал: \(Int(state.currentChannel)) / \(max(state.channelCount - 1, 0))")
                        .font(.system(size: 11))
                    
                    Slider(value: $state.currentChannel,
                           in: 0...Double(max(state.channelCount - 1, 0)),
                           step: 1.0)
                }
            }
            
            if !cube.is2D {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Длины волн (нм):")
                        .font(.system(size: 11))
                    
                    HStack(spacing: 8) {
                        Button("Загрузить из txt…") {
                            openWavelengthTXT()
                        }
                        
                        Text("или диапазон:")
                            .font(.system(size: 11))
                        
                        HStack(spacing: 4) {
                            Text("от")
                                .font(.system(size: 11))
                            TextField("start", text: $state.lambdaStart)
                                .frame(width: 50)
                            Text("до")
                                .font(.system(size: 11))
                            TextField("end", text: $state.lambdaEnd)
                                .frame(width: 50)
                            Text("шаг")
                                .font(.system(size: 11))
                            TextField("step", text: $state.lambdaStep)
                                .frame(width: 50)
                        }
                        
                        Button("Сгенерировать") {
                            state.generateWavelengthsFromParams()
                        }
                    }
                    
                    if let lambda = state.wavelengths {
                        Text("λ count: \(lambda.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text("λ пока не заданы")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            state.updateChannelCount()
        }
        .onChange(of: state.layout) { _ in
            state.updateChannelCount()
        }
        .onChange(of: state.cube?.dims.0) { _ in
            state.updateChannelCount()
        }
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
