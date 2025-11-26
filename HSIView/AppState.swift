import Foundation
import AppKit   // важно для NSImage / NSBitmapImageRep
import ImageIO   // вот это добавь

final class AppState: ObservableObject {
    @Published var cube: HyperCube?
    @Published var cubeURL: URL?
    @Published var layout: CubeLayout = .auto
    @Published var currentChannel: Double = 0
    @Published var channelCount: Int = 0
    @Published var loadError: String?

    @Published var viewMode: ViewMode = .gray

    @Published var wavelengths: [Double]? = nil
    @Published var lambdaStart: String = "400"
    @Published var lambdaEnd: String   = ""    // будет вычисляться
    @Published var lambdaStep: String  = "1"
    // --- ЕДИНАЯ точка входа ---
    func open(url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "mat" {
            openMat(url: url)
        } else if ext == "tif" || ext == "tiff" {
            openTIFF(url: url)
        } else {
            loadError = "Неподдерживаемый формат: \(ext)"
        }
    }
    func updateChannelCount() {
        guard let cube = cube else {
            channelCount = 0
            currentChannel = 0
            return
        }

        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]

        switch layout {
        case .auto:
            channelCount = dimsArr.min() ?? d0
        case .chw:
            channelCount = d0
        case .hwc:
            channelCount = d2
        }

        if channelCount <= 0 {
            currentChannel = 0
        } else if Int(currentChannel) >= channelCount {
            currentChannel = Double(channelCount - 1)
        }
    }
    // --- MAT ---
    private func openMat(url: URL) {
        cubeURL = url
        loadError = nil
        cube = nil
        currentChannel = 0
        channelCount = 0

        if let hyper = loadMatCube(url: url) {
            cube = hyper
            layout = .auto
            updateChannelCount()
            if wavelengths == nil {
                generateWavelengthsFromParams()
            }
        } else {
            loadError = "Не удалось прочитать 3D-матрицу из .mat"
        }
    }

    // --- TIFF ---
    // --- TIFF через libtiff ---
    private func openTIFF(url: URL) {
        cubeURL = url
        loadError = nil
        cube = nil
        currentChannel = 0
        channelCount = 0

        if let hyper = loadTIFFCube(url: url) {
            cube = hyper
            layout = .chw
            updateChannelCount()
            if wavelengths == nil {
                generateWavelengthsFromParams()
            }
        } else {
            loadError = "Не удалось загрузить TIFF гиперкуб"
        }
    }

    // --- работа с λ ---

    func setWavelengths(_ lambda: [Double]) {
        guard !lambda.isEmpty else {
            wavelengths = nil
            return
        }
        wavelengths = lambda
    }

    func loadWavelengthsFromTXT(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var values: [Double] = []
            for line in lines {
                if let v = Double(line.replacingOccurrences(of: ",", with: ".")) {
                    values.append(v)
                }
            }

            if values.isEmpty {
                loadError = "Не удалось распарсить длины волн из txt"
            } else {
                wavelengths = values
                loadError = nil
            }
        } catch {
            loadError = "Ошибка чтения txt с длинами волн"
        }
    }

    func generateWavelengthsFromParams() {
        // Должен быть загружен гиперкуб
        guard cube != nil else {
            loadError = "Сначала открой гиперкуб"
            return
        }

        // Количество каналов зависит от layout (auto/chw/hwc)
        let channels = channelCount
        guard channels > 0 else {
            loadError = "Не удалось определить число каналов"
            return
        }

        // Старт и шаг — из строк (но по умолчанию 400 и 1)
        guard let start = Double(lambdaStart.replacingOccurrences(of: ",", with: ".")),
              let step  = Double(lambdaStep.replacingOccurrences(of: ",", with: ".")),
              step > 0 else {
            loadError = "Некорректные параметры λ (start/step)"
            return
        }

        // Конечную длину считаем по количеству каналов
        let end = start + Double(channels - 1) * step
        lambdaEnd = String(format: "%.4g", end)   // чтобы в UI отобразилось

        var arr: [Double] = []
        arr.reserveCapacity(channels)
        for i in 0..<channels {
            arr.append(start + Double(i) * step)
        }

        wavelengths = arr
        loadError = nil
    }
}

