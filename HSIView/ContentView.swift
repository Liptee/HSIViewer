import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        if let cube = state.cube {
                            cubeView(cube: cube, geoSize: geo.size)
                        } else {
                            Text("Открой .mat с 3D-матрицей (гиперкубом)")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height,
                        alignment: .center
                    )
                }
            }

            if let cube = state.cube {
                bottomControls(cube: cube)
                    .padding(8)
                    .border(Color(NSColor.separatorColor), width: 0.5)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // Верхняя панель
    private var topBar: some View {
        HStack {
            Button("Открыть .mat…") {
                openMatFile()
            }

            Divider()
                .frame(height: 20)

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

    // Рендер куба
    private func cubeView(cube: HyperCube, geoSize: CGSize) -> some View {
        Group {
            switch state.viewMode {
            case .gray:
                let chIdx = Int(state.currentChannel)
                if let nsImage = makeSliceImage(from: cube,
                                                layout: state.layout,
                                                channelIndex: chIdx) {
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
                    Text("Не удалось построить слайс")
                        .foregroundColor(.red)
                }

            case .rgb:
                if let lambda = state.wavelengths,
                   lambda.count >= state.channelCount,
                   let nsImage = makeRGBImage(from: cube,
                                              layout: state.layout,
                                              wavelengths: lambda) {

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

    // Нижняя панель управления
    private func bottomControls(cube: HyperCube) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // layout + режим
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

                Picker("", selection: $state.viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 160)

                Spacer()

                Text("dims: \(cube.dims.0) × \(cube.dims.1) × \(cube.dims.2)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // канал (только в gray-режиме)
            if state.viewMode == .gray {
                HStack {
                    Text("Канал: \(Int(state.currentChannel)) / \(max(state.channelCount - 1, 0))")
                        .font(.system(size: 11))

                    Slider(value: $state.currentChannel,
                           in: 0...Double(max(state.channelCount - 1, 0)),
                           step: 1.0)
                }
            }

            // работа с длинами волн
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

    // Открытие .mat / .tiff из диалога
    private func openMatFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Открыть"
        panel.allowedFileTypes = ["mat", "tif", "tiff"]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        state.open(url: url)
    }   // ← ВОТ ЭТА СКОБКА У ТЕБЯ ПРОПАДАЛА


    // Открытие txt с длинами волн
    private func openWavelengthTXT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать txt"
        panel.allowedFileTypes = ["txt"]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        state.loadWavelengthsFromTXT(url: url)
    }

    // Подбор размера, чтобы вписать картинку в окно
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
