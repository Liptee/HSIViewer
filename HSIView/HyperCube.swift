import Foundation
import AppKit

// Как интерпретировать оси
enum CubeLayout: String, CaseIterable, Identifiable {
    case auto = "Auto (min dim = C)"
    case chw  = "CHW"
    case hwc  = "HWC"

    var id: String { rawValue }
}

// Режим отображения
enum ViewMode: String, CaseIterable, Identifiable {
    case gray = "Gray"
    case rgb  = "RGB"

    var id: String { rawValue }
}

// Храним исходный куб, как он лежит в MATLAB (dims[0..2], col-major)
struct HyperCube {
    let dims: (Int, Int, Int)  // (d0, d1, d2)
    let data: [Double]         // длина = d0*d1*d2

    var totalChannelsAuto: Int {
        let arr = [dims.0, dims.1, dims.2]
        return arr.min() ?? dims.0
    }
}

// Вычисляем индекс в 1D-массиве MATLAB (col-major, как в matio)
func matlabLinearIndex(i0: Int, i1: Int, i2: Int,
                       d0: Int, d1: Int, d2: Int) -> Int {
    // i0 + d0 * (i1 + d1 * i2)
    return i0 + d0 * (i1 + d1 * i2)
}

// Генерация ч/б картинки из одного канала
func makeSliceImage(from cube: HyperCube,
                    layout: CubeLayout,
                    channelIndex: Int) -> NSImage? {

    let (d0, d1, d2) = cube.dims
    if d0 <= 0 || d1 <= 0 || d2 <= 0 { return nil }

    let cAxis: Int
    let hAxis: Int
    let wAxis: Int

    switch layout {
    case .auto:
        let dimsArr = [d0, d1, d2]
        guard let minDim = dimsArr.min(),
              let idx = dimsArr.firstIndex(of: minDim) else { return nil }
        cAxis = idx
        let other = [0, 1, 2].filter { $0 != cAxis }
        hAxis = other[0]
        wAxis = other[1]

    case .chw:
        cAxis = 0; hAxis = 1; wAxis = 2

    case .hwc:
        hAxis = 0; wAxis = 1; cAxis = 2
    }

    let dimsArr = [d0, d1, d2]
    let cCount = dimsArr[cAxis]
    guard channelIndex >= 0, channelIndex < cCount else { return nil }

    let h = dimsArr[hAxis]
    let w = dimsArr[wAxis]

    var slice = [Double](repeating: 0.0, count: h * w)
    var minVal = Double.greatestFiniteMagnitude
    var maxVal = -Double.greatestFiniteMagnitude

    for y in 0..<h {
        for x in 0..<w {
            var idx3 = [0, 0, 0]
            idx3[cAxis] = channelIndex
            idx3[hAxis] = y
            idx3[wAxis] = x

            let lin = matlabLinearIndex(i0: idx3[0],
                                        i1: idx3[1],
                                        i2: idx3[2],
                                        d0: d0, d1: d1, d2: d2)

            let v = cube.data[lin]
            let idx2 = y * w + x
            slice[idx2] = v
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
        }
    }

    if maxVal == minVal {
        maxVal = minVal + 1.0
    }

    var pixels = [UInt8](repeating: 0, count: h * w)
    let scale = 255.0 / (maxVal - minVal)

    for i in 0..<slice.count {
        let v = (slice[i] - minVal) * scale
        let clamped = max(0.0, min(255.0, v))
        pixels[i] = UInt8(clamped.rounded())
    }

    let colorSpace = CGColorSpaceCreateDeviceGray()
    let bytesPerRow = w * 1

    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        return nil
    }

    guard let cgImage = CGImage(
        width: w,
        height: h,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    ) else {
        return nil
    }

    let nsImage = NSImage(cgImage: cgImage,
                          size: NSSize(width: w, height: h))
    return nsImage
}

// RGB-синтез на основе списка длин волн
// wavelengths: длина == количеству каналов (по cAxis)
func makeRGBImage(from cube: HyperCube,
                  layout: CubeLayout,
                  wavelengths: [Double]) -> NSImage? {

    let (d0, d1, d2) = cube.dims
    if d0 <= 0 || d1 <= 0 || d2 <= 0 { return nil }

    let cAxis: Int
    let hAxis: Int
    let wAxis: Int

    switch layout {
    case .auto:
        let dimsArr = [d0, d1, d2]
        guard let minDim = dimsArr.min(),
              let idx = dimsArr.firstIndex(of: minDim) else { return nil }
        cAxis = idx
        let other = [0, 1, 2].filter { $0 != cAxis }
        hAxis = other[0]
        wAxis = other[1]

    case .chw:
        cAxis = 0; hAxis = 1; wAxis = 2

    case .hwc:
        hAxis = 0; wAxis = 1; cAxis = 2
    }

    let dimsArr = [d0, d1, d2]
    let cCount = dimsArr[cAxis]
    if cCount == 0 { return nil }
    guard wavelengths.count >= cCount else {
        // список волн короче количества каналов
        return nil
    }

    let h = dimsArr[hAxis]
    let w = dimsArr[wAxis]

    // выбираем ближайшие к этим длинам волн (очень грубо, но работает)
    let targetR = 630.0
    let targetG = 530.0
    let targetB = 450.0

    func closestIndex(to target: Double) -> Int {
        var bestIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        for i in 0..<cCount {
            let d = abs(wavelengths[i] - target)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }

    let idxR = closestIndex(to: targetR)
    let idxG = closestIndex(to: targetG)
    let idxB = closestIndex(to: targetB)

    var sliceR = [Double](repeating: 0.0, count: h * w)
    var sliceG = [Double](repeating: 0.0, count: h * w)
    var sliceB = [Double](repeating: 0.0, count: h * w)

    var minR = Double.greatestFiniteMagnitude
    var maxR = -Double.greatestFiniteMagnitude
    var minG = Double.greatestFiniteMagnitude
    var maxG = -Double.greatestFiniteMagnitude
    var minB = Double.greatestFiniteMagnitude
    var maxB = -Double.greatestFiniteMagnitude

    for y in 0..<h {
        for x in 0..<w {
            var idx3 = [0, 0, 0]
            idx3[hAxis] = y
            idx3[wAxis] = x

            // R
            idx3[cAxis] = idxR
            var lin = matlabLinearIndex(i0: idx3[0],
                                        i1: idx3[1],
                                        i2: idx3[2],
                                        d0: d0, d1: d1, d2: d2)
            let vR = cube.data[lin]

            // G
            idx3[cAxis] = idxG
            lin = matlabLinearIndex(i0: idx3[0],
                                    i1: idx3[1],
                                    i2: idx3[2],
                                    d0: d0, d1: d1, d2: d2)
            let vG = cube.data[lin]

            // B
            idx3[cAxis] = idxB
            lin = matlabLinearIndex(i0: idx3[0],
                                    i1: idx3[1],
                                    i2: idx3[2],
                                    d0: d0, d1: d1, d2: d2)
            let vB = cube.data[lin]

            let idx2 = y * w + x
            sliceR[idx2] = vR
            sliceG[idx2] = vG
            sliceB[idx2] = vB

            if vR < minR { minR = vR }
            if vR > maxR { maxR = vR }

            if vG < minG { minG = vG }
            if vG > maxG { maxG = vG }

            if vB < minB { minB = vB }
            if vB > maxB { maxB = vB }
        }
    }

    if maxR == minR { maxR = minR + 1.0 }
    if maxG == minG { maxG = minG + 1.0 }
    if maxB == minB { maxB = minB + 1.0 }

    let scaleR = 255.0 / (maxR - minR)
    let scaleG = 255.0 / (maxG - minG)
    let scaleB = 255.0 / (maxB - minB)

    var pixels = [UInt8](repeating: 0, count: h * w * 4) // RGBA

    for i in 0..<h*w {
        let r = (sliceR[i] - minR) * scaleR
        let g = (sliceG[i] - minG) * scaleG
        let b = (sliceB[i] - minB) * scaleB

        let r8 = UInt8(max(0.0, min(255.0, r)).rounded())
        let g8 = UInt8(max(0.0, min(255.0, g)).rounded())
        let b8 = UInt8(max(0.0, min(255.0, b)).rounded())

        let base = i * 4
        pixels[base + 0] = r8
        pixels[base + 1] = g8
        pixels[base + 2] = b8
        pixels[base + 3] = 255
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = w * 4

    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        return nil
    }

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

    guard let cgImage = CGImage(
        width: w,
        height: h,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    ) else {
        return nil
    }

    let nsImage = NSImage(cgImage: cgImage,
                          size: NSSize(width: w, height: h))
    return nsImage
}

// ------- Загрузка MAT (как раньше) -------

func loadMatCube(url: URL) -> HyperCube? {
    var cCube = MatCube3D(
        data: nil,
        dims: (0, 0, 0),
        rank: 0
    )

    var nameBuf = [CChar](repeating: 0, count: 256)

    let ok: Bool = url.path.withCString { cPath in
        load_first_3d_double_cube(cPath, &cCube, &nameBuf, nameBuf.count)
    }

    guard ok, cCube.rank == 3, let ptr = cCube.data else {
        free_cube(&cCube)
        return nil
    }

    let d0 = Int(cCube.dims.0)
    let d1 = Int(cCube.dims.1)
    let d2 = Int(cCube.dims.2)
    let count = d0 * d1 * d2

    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let arr = Array(buffer)

    free_cube(&cCube)

    return HyperCube(dims: (d0, d1, d2), data: arr)
}

func loadTIFFCube(url: URL) -> HyperCube? {
    var cCube = TiffCube3D(
        data: nil,
        dims: (0, 0, 0),
        rank: 0
    )

    let ok: Bool = url.path.withCString { cPath in
        load_tiff_cube(cPath, &cCube)
    }

    guard ok, cCube.rank == 3, let ptr = cCube.data else {
        free_tiff_cube(&cCube)
        return nil
    }

    let d0 = Int(cCube.dims.0)
    let d1 = Int(cCube.dims.1)
    let d2 = Int(cCube.dims.2)
    let count = d0 * d1 * d2

    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let arr = Array(buffer)

    free_tiff_cube(&cCube)

    return HyperCube(dims: (d0, d1, d2), data: arr)
}
