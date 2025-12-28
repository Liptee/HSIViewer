Окей, вот “дока под твой проект”: как выкинуть тупые циклы и map, перевести пайплайн на Float + Accelerate (vDSP/vImage), и где втыкать Metal compute когда Accelerate уже не вывозит / нужен realtime.

Я буду давать готовые куски кода, которые ты реально можешь растащить по файлам типа HyperCube+Statistics.swift, DataNormalization.swift, ImageRenderer.swift, PipelineOperation.swift, *Loader.swift.

Опора на Apple: Accelerate (vDSP/vImage/vForce) и Metal compute.  ￼

⸻

1) Главная правка архитектуры: один внутренний формат куба

Твой главный тормоз сейчас — переаллокации и Double-болото. Делаем так:
	•	Внутри пайплайна держим Float32 (почти всегда достаточно и быстрее по памяти/кэшу).
	•	Куб хранится planar, channel-major: data[(c * H * W) + (y * W) + x]
	•	Конвертации типов (UInt8/UInt16/Double) делаем только на границах: загрузка → Float, рендер → UInt8/ARGB и т.п.

Accelerate прямо про это: high-performance CPU vectorization + type conversion/арифметика.  ￼

1.1 Базовый контейнер куба (копипаста)

import Accelerate

struct HyperCubeF {
    let width: Int
    let height: Int
    let channels: Int
    var data: [Float]          // planar, C-major

    @inline(__always) var planeCount: Int { width * height }

    init(width: Int, height: Int, channels: Int, fill: Float = 0) {
        self.width = width
        self.height = height
        self.channels = channels
        self.data = [Float](repeating: fill, count: width * height * channels)
    }

    @inline(__always)
    func planeOffset(_ c: Int) -> Int { c * planeCount }

    @inline(__always)
    subscript(x: Int, y: Int, c: Int) -> Float {
        get { data[planeOffset(c) + y * width + x] }
        set { data[planeOffset(c) + y * width + x] = newValue }
    }

    mutating func withMutablePlanePointer<T>(_ c: Int, _ body: (UnsafeMutablePointer<Float>, Int) throws -> T) rethrows -> T {
        let off = planeOffset(c)
        return try data.withUnsafeMutableBufferPointer { buf in
            try body(buf.baseAddress!.advanced(by: off), planeCount)
        }
    }

    func withPlanePointer<T>(_ c: Int, _ body: (UnsafePointer<Float>, Int) throws -> T) rethrows -> T {
        let off = planeOffset(c)
        return try data.withUnsafeBufferPointer { buf in
            try body(buf.baseAddress!.advanced(by: off), planeCount)
        }
    }
}


⸻

2) Статистики без циклов: min/max/mean/sumsq/std (vDSP)

Ты в отчёте правильно наметил: vDSP_minv, vDSP_maxv, vDSP_meanv, vDSP_svesq. Это прям стандартные кирпичи.  ￼

2.1 Обёртка для статистики плоскости (Float)

import Accelerate

struct PlaneStats {
    var min: Float
    var max: Float
    var mean: Float
    var rms: Float
    var std: Float
}

@inline(__always)
func statsFloat(_ ptr: UnsafePointer<Float>, count n: Int) -> PlaneStats {
    var mn: Float = 0
    var mx: Float = 0
    var mean: Float = 0
    var sumsq: Float = 0

    vDSP_minv(ptr, 1, &mn, vDSP_Length(n))     //  [oai_citation:3‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_minv?utm_source=chatgpt.com)
    vDSP_maxv(ptr, 1, &mx, vDSP_Length(n))     //  [oai_citation:4‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_maxv?utm_source=chatgpt.com)
    vDSP_meanv(ptr, 1, &mean, vDSP_Length(n))  //  [oai_citation:5‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_meanv?utm_source=chatgpt.com)
    vDSP_svesq(ptr, 1, &sumsq, vDSP_Length(n)) //  [oai_citation:6‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_svesq?utm_source=chatgpt.com)

    let invN = 1.0 / Float(n)
    let meanSq = sumsq * invN
    let variance = max(0, meanSq - mean * mean)
    let std = sqrt(variance)
    let rms = sqrt(meanSq)

    return PlaneStats(min: mn, max: mx, mean: mean, rms: rms, std: std)
}

2.2 Статистика на весь куб (параллельно по каналам)

import Foundation

extension HyperCubeF {
    func statsPerChannel() -> [PlaneStats] {
        var out = Array(repeating: PlaneStats(min: 0, max: 0, mean: 0, rms: 0, std: 0), count: channels)

        data.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: channels) { c in
                let p = base.advanced(by: planeOffset(c))
                out[c] = statsFloat(p, count: planeCount)
            }
        }
        return out
    }
}


⸻

3) Нормализация: min-max / z-score / clip — одним-двумя проходами

Apple прямо говорит: vDSP — альтернатива for/map для арифметики по массивам.  ￼

3.1 Min-Max в один проход (vDSP_vsmsa + vDSP_vclip)

Формула:
out = (x - min) / (max - min)
Переписываем как:
out = x * invRange + (-min * invRange)
Это ровно vDSP_vsmsa (a*scalar + scalar).  ￼

import Accelerate

enum NormError: Error { case zeroRange }

@inline(__always)
func minMaxNormalizeInPlace(_ x: UnsafeMutablePointer<Float>, count n: Int,
                            clipTo unit: Bool = true) throws -> PlaneStats {
    let st = statsFloat(UnsafePointer(x), count: n)
    let range = st.max - st.min
    if range == 0 { throw NormError.zeroRange }

    var invRange = 1.0 as Float / range
    var add = (-st.min) * invRange

    // x = x * invRange + add
    vDSP_vsmsa(x, 1, &invRange, &add, x, 1, vDSP_Length(n)) //  [oai_citation:9‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vsmsa?utm_source=chatgpt.com)

    if unit {
        var lo: Float = 0
        var hi: Float = 1
        vDSP_vclip(x, 1, &lo, &hi, x, 1, vDSP_Length(n)) //  [oai_citation:10‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vclip?utm_source=chatgpt.com)
    }
    return st
}

3.2 Z-score (стандартизация)

out = (x - mean) / std = x*(1/std) + (-mean/std)

enum ZError: Error { case zeroStd }

@inline(__always)
func zScoreInPlace(_ x: UnsafeMutablePointer<Float>, count n: Int) throws -> PlaneStats {
    let st = statsFloat(UnsafePointer(x), count: n)
    if st.std == 0 { throw ZError.zeroStd }

    var invStd = 1.0 as Float / st.std
    var add = (-st.mean) * invStd
    vDSP_vsmsa(x, 1, &invStd, &add, x, 1, vDSP_Length(n)) //  [oai_citation:11‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vsmsa?utm_source=chatgpt.com)
    return st
}

3.3 Встраивание в твои файлы (CubeNormalization.swift, DataNormalization.swift)

extension HyperCubeF {
    mutating func normalizeMinMaxPerChannel() {
        for c in 0..<channels {
            try? withMutablePlanePointer(c) { p, n in
                _ = try minMaxNormalizeInPlace(p, count: n)
            }
        }
    }

    mutating func normalizeMinMaxPerChannelParallel() {
        data.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: channels) { c in
                let p = base.advanced(by: planeOffset(c))
                _ = try? minMaxNormalizeInPlace(p, count: planeCount)
            }
        }
    }
}


⸻

4) Конвертация типов без циклов: UInt8/UInt16/Double ⇄ Float

4.1 UInt8 → Float: vDSP_vfltu8

￼

import Accelerate

func u8ToFloat(_ src: UnsafePointer<UInt8>, _ dst: UnsafeMutablePointer<Float>, count n: Int) {
    vDSP_vfltu8(src, 1, dst, 1, vDSP_Length(n)) //  [oai_citation:13‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vfltu8?utm_source=chatgpt.com)
}

4.2 UInt16 → Float: vDSP_vfltu16

￼

func u16ToFloat(_ src: UnsafePointer<UInt16>, _ dst: UnsafeMutablePointer<Float>, count n: Int) {
    vDSP_vfltu16(src, 1, dst, 1, vDSP_Length(n)) //  [oai_citation:15‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vfltu16?utm_source=chatgpt.com)
}

4.3 Double ↔ Float: vDSP_vdpsp / vDSP_vspdp

Apple даёт это как часть “Type conversion”.  ￼

func doubleToFloat(_ src: UnsafePointer<Double>, _ dst: UnsafeMutablePointer<Float>, count n: Int) {
    vDSP_vdpsp(src, 1, dst, 1, vDSP_Length(n)) //  [oai_citation:17‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vdpsp?utm_source=chatgpt.com)
}

func floatToDouble(_ src: UnsafePointer<Float>, _ dst: UnsafeMutablePointer<Double>, count n: Int) {
    vDSP_vspdp(src, 1, dst, 1, vDSP_Length(n)) //  [oai_citation:18‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vspdp?utm_source=chatgpt.com)
}


⸻

5) Калибровка “по формуле” (CubeCalibrator): gain/bias на канал

Твой кейс: коэффициенты зависят от канала, но применяются ко всей плоскости.

5.1 CPU (vDSP_vsmsa) — быстро и просто

￼

extension HyperCubeF {
    /// out = in * gain[c] + bias[c]
    mutating func applyPerChannelAffine(gain: [Float], bias: [Float]) {
        precondition(gain.count == channels && bias.count == channels)

        data.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: channels) { c in
                var g = gain[c]
                var b = bias[c]
                let p = base.advanced(by: planeOffset(c))
                vDSP_vsmsa(p, 1, &g, &b, p, 1, vDSP_Length(planeCount))
            }
        }
    }
}

5.2 Когда надо реально быстро в UI — Metal compute

Metal — норм, когда ты гоняешь большие H×W×C и хочешь плавный интерактив (resize+render+коррекция на лету). База: MTLComputePipelineState, MTLComputeCommandEncoder, dispatchThreads.  ￼

5.2.1 Kernel (Metal Shading Language)
(Плоский 1D массив, один тред = один элемент)

#include <metal_stdlib>
using namespace metal;

kernel void affine_per_channel(
    device const float* in       [[buffer(0)]],
    device float* out            [[buffer(1)]],
    device const float* gain     [[buffer(2)]],
    device const float* bias     [[buffer(3)]],
    constant uint& planeCount    [[buffer(4)]],
    constant uint& channels      [[buffer(5)]],
    uint gid                     [[thread_position_in_grid]]
) {
    uint total = planeCount * channels;
    if (gid >= total) return;

    uint c = gid / planeCount;
    float x = in[gid];
    out[gid] = x * gain[c] + bias[c];
}

thread_position_in_grid и вся механика grid/threadgroups — это базовая модель compute в Metal (см. spec + “calculating threadgroup and grid sizes”).  ￼

5.2.2 Swift-обвязка (минимальная)

import Metal

final class MetalAffine {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init(library: MTLLibrary, device: MTLDevice = MTLCreateSystemDefaultDevice()!) throws {
        self.device = device
        self.queue = device.makeCommandQueue()!

        let fn = library.makeFunction(name: "affine_per_channel")!
        self.pipeline = try device.makeComputePipelineState(function: fn) //  [oai_citation:22‡Apple Developer](https://developer.apple.com/documentation/metal/mtlcomputepipelinestate?utm_source=chatgpt.com)
    }

    func encode(commandBuffer: MTLCommandBuffer,
                inBuf: MTLBuffer,
                outBuf: MTLBuffer,
                gainBuf: MTLBuffer,
                biasBuf: MTLBuffer,
                planeCount: UInt32,
                channels: UInt32) {
        let enc = commandBuffer.makeComputeCommandEncoder()! //  [oai_citation:23‡Apple Developer](https://developer.apple.com/documentation/metal/mtlcomputecommandencoder?language=objc&utm_source=chatgpt.com)
        enc.setComputePipelineState(pipeline)                 //  [oai_citation:24‡Apple Developer](https://developer.apple.com/documentation/metal/mtlcomputecommandencoder/setcomputepipelinestate%28_%3A%29?utm_source=chatgpt.com)

        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBuffer(outBuf, offset: 0, index: 1)
        enc.setBuffer(gainBuf, offset: 0, index: 2)
        enc.setBuffer(biasBuf, offset: 0, index: 3)

        var pc = planeCount
        var ch = channels
        enc.setBytes(&pc, length: MemoryLayout<UInt32>.size, index: 4)
        enc.setBytes(&ch, length: MemoryLayout<UInt32>.size, index: 5)

        let total = Int(planeCount) * Int(channels)
        let w = pipeline.threadExecutionWidth
        let threadsPerTG = MTLSize(width: w, height: 1, depth: 1)
        let threads = MTLSize(width: total, height: 1, depth: 1)
        enc.dispatchThreads(threads, threadsPerThreadgroup: threadsPerTG) //  [oai_citation:25‡Apple Developer](https://developer.apple.com/documentation/metal/mtlcomputecommandencoder/dispatchthreads%28_%3Athreadsperthreadgroup%3A%29?utm_source=chatgpt.com)
        enc.endEncoding()
    }

    func run(inBuf: MTLBuffer, outBuf: MTLBuffer, gainBuf: MTLBuffer, biasBuf: MTLBuffer,
             planeCount: Int, channels: Int) {
        let cb = queue.makeCommandBuffer()!
        encode(commandBuffer: cb,
               inBuf: inBuf, outBuf: outBuf,
               gainBuf: gainBuf, biasBuf: biasBuf,
               planeCount: UInt32(planeCount), channels: UInt32(channels))
        cb.commit()
        cb.waitUntilCompleted()
    }
}


⸻

6) Resize/rotate/crop для куба через vImage (без вложенных циклов)

vImage — это как раз “делайте геометрию/ресэмплинг/буферы нормально”. Apple отдельно пишет про ресэмплинг и high-quality фильтры (kvImageHighQualityResampling = Lanczos).  ￼

6.1 Универсальная обвязка vImage_Buffer + выделение памяти

vImageBuffer_Init — Apple рекомендует его, чтобы vImage сам выровнял память “как надо”.  ￼

import Accelerate

struct VImagePlane {
    var buffer: vImage_Buffer

    init(width: Int, height: Int) {
        buffer = vImage_Buffer(data: nil,
                               height: vImagePixelCount(height),
                               width: vImagePixelCount(width),
                               rowBytes: width * MemoryLayout<Float>.size)

        // vImage выделит и выровняет память
        let err = vImageBuffer_Init(&buffer,
                                    vImagePixelCount(height),
                                    vImagePixelCount(width),
                                    32, // bitsPerPixel для PlanarF
                                    vImage_Flags(kvImageNoFlags)) //  [oai_citation:28‡Apple Developer](https://developer.apple.com/documentation/accelerate/vimagebuffer_init%28_%3A_%3A_%3A_%3A_%3A%29?utm_source=chatgpt.com)
        precondition(err == kvImageNoError)
    }

    mutating func free() {
        free(buffer.data)
        buffer.data = nil
    }
}

6.2 Scale PlanarF (канал за каналом)

vImageScale_PlanarF — прям твой случай для куба в Float planar.  ￼
Флаг качества: kvImageHighQualityResampling.  ￼

import Accelerate

extension HyperCubeF {
    func resized(newW: Int, newH: Int, highQuality: Bool = true) -> HyperCubeF {
        var out = HyperCubeF(width: newW, height: newH, channels: channels)

        let srcRowBytes = width * MemoryLayout<Float>.size
        let dstRowBytes = newW * MemoryLayout<Float>.size

        let flags: vImage_Flags = highQuality ? vImage_Flags(kvImageHighQualityResampling) : vImage_Flags(kvImageNoFlags)

        data.withUnsafeBufferPointer { srcBuf in
            out.data.withUnsafeMutableBufferPointer { dstBuf in
                let srcBase = srcBuf.baseAddress!
                let dstBase = dstBuf.baseAddress!

                DispatchQueue.concurrentPerform(iterations: channels) { c in
                    var src = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: srcBase.advanced(by: planeOffset(c))),
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: srcRowBytes
                    )
                    var dst = vImage_Buffer(
                        data: UnsafeMutableRawPointer(dstBase.advanced(by: c * (newW * newH))),
                        height: vImagePixelCount(newH),
                        width: vImagePixelCount(newW),
                        rowBytes: dstRowBytes
                    )

                    let err = vImageScale_PlanarF(&src, &dst, nil, flags) //  [oai_citation:31‡Apple Developer](https://developer.apple.com/documentation/accelerate/vimagescale_planarf%28_%3A_%3A_%3A_%3A%29?changes=l_5_3&language=objc&utm_source=chatgpt.com)
                    precondition(err == kvImageNoError)
                }
            }
        }
        return out
    }
}

6.3 Rotate PlanarF (любой угол) и Rotate90

Есть vImageRotate_PlanarF и vImageRotate90_PlanarF/Planar8.  ￼

import Accelerate

extension HyperCubeF {
    func rotated(radians: Float, background: Float = 0, highQuality: Bool = true) -> HyperCubeF {
        // для простоты: выход того же размера; если хочешь “fit bounds” — это отдельная геометрия
        var out = HyperCubeF(width: width, height: height, channels: channels)

        let flags: vImage_Flags = highQuality ? vImage_Flags(kvImageHighQualityResampling) : vImage_Flags(kvImageNoFlags)
        let rowBytes = width * MemoryLayout<Float>.size

        data.withUnsafeBufferPointer { srcBuf in
            out.data.withUnsafeMutableBufferPointer { dstBuf in
                let srcBase = srcBuf.baseAddress!
                let dstBase = dstBuf.baseAddress!

                DispatchQueue.concurrentPerform(iterations: channels) { c in
                    var src = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: srcBase.advanced(by: planeOffset(c))),
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: rowBytes
                    )
                    var dst = vImage_Buffer(
                        data: UnsafeMutableRawPointer(dstBase.advanced(by: planeOffset(c))),
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: rowBytes
                    )
                    var bg = background
                    let err = vImageRotate_PlanarF(&src, &dst, nil, radians, &bg, flags) //  [oai_citation:33‡Apple Developer](https://developer.apple.com/documentation/accelerate/vimagerotate_planarf%28_%3A_%3A_%3A_%3A_%3A_%3A%29?language=objc&utm_source=chatgpt.com)
                    precondition(err == kvImageNoError)
                }
            }
        }
        return out
    }
}

6.4 Crop без копий: ROI через смещение указателя

Apple прямо продвигает “regions of interest”/cropping для vImage.  ￼

Для planar-буфера crop = просто другой data pointer + width/height, rowBytes тот же:

import Accelerate

@inline(__always)
func cropPlaneView(base: UnsafeMutablePointer<Float>,
                   srcW: Int, srcH: Int,
                   x0: Int, y0: Int,
                   cropW: Int, cropH: Int) -> vImage_Buffer {
    let rowBytes = srcW * MemoryLayout<Float>.size
    let start = base.advanced(by: y0 * srcW + x0)

    return vImage_Buffer(
        data: UnsafeMutableRawPointer(start),
        height: vImagePixelCount(cropH),
        width: vImagePixelCount(cropW),
        rowBytes: rowBytes
    )
}

Дальше ты можешь:
	•	либо рендерить ROI напрямую,
	•	либо копировать ROI в новый буфер через vImage copy/scale операции (если надо уплотнить rowBytes под cropW).

⸻

7) Рендер (ImageRenderer): Float [0..1] → UInt8 быстро

Твой отчёт предлагал vDSP_vclipD + vDSP_vsmulD + vDSP_vfixu8D. Если мы нормальные и живём в Float — делаем Float-версии: vDSP_vclip + vDSP_vsmul + vDSP_vfixu8.  ￼

7.1 PlanarF → Planar8 (через vDSP)

import Accelerate

func float01ToU8(_ src: UnsafePointer<Float>, dst: UnsafeMutablePointer<UInt8>, count n: Int) {
    // tmp = clip(src, 0..1)
    var tmp = [Float](repeating: 0, count: n)
    tmp.withUnsafeMutableBufferPointer { tbuf in
        var lo: Float = 0
        var hi: Float = 1
        vDSP_vclip(src, 1, &lo, &hi, tbuf.baseAddress!, 1, vDSP_Length(n)) //  [oai_citation:36‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vclip?utm_source=chatgpt.com)

        var scale: Float = 255
        vDSP_vsmul(tbuf.baseAddress!, 1, &scale, tbuf.baseAddress!, 1, vDSP_Length(n)) //  [oai_citation:37‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vsmul?utm_source=chatgpt.com)

        vDSP_vfixu8(tbuf.baseAddress!, 1, dst, 1, vDSP_Length(n)) //  [oai_citation:38‡Apple Developer](https://developer.apple.com/documentation/accelerate/vdsp_vfixu8?language=objc&utm_source=chatgpt.com)
    }
}

Это уже в разы лучше, чем for-loop. Но ещё лучше — убрать tmp: делать “clip → scale → fix” без промежуточной аллокации через пул буферов (см. ниже).

7.2 Без аллокаций: BufferPool (очень важно)

Ты сейчас в PipelineOperation.swift “каждый раз new Double-buffer” — это убийство.

Минимальный пул:

final class FloatBufferPool {
    private var storage: [[Float]] = []
    private let lock = NSLock()

    func get(count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        if let i = storage.firstIndex(where: { $0.count == count }) {
            return storage.remove(at: i)
        }
        return [Float](repeating: 0, count: count)
    }

    func put(_ buf: [Float]) {
        lock.lock(); defer { lock.unlock() }
        storage.append(buf)
    }
}


⸻

8) Loader’ы: убираем append-ад и тройные циклы

Цель: считать сразу в конечный contiguous буфер, а не “слой за слоем append”.

8.1 Паттерн: Array(unsafeUninitializedCapacity:) + memcpy

func readRawFloats(from data: Data, count: Int) -> [Float] {
    precondition(data.count >= count * MemoryLayout<Float>.size)

    return [Float](unsafeUninitializedCapacity: count) { dstBuf, initializedCount in
        data.withUnsafeBytes { raw in
            memcpy(dstBuf.baseAddress!, raw.baseAddress!, count * MemoryLayout<Float>.size)
        }
        initializedCount = count
    }
}

Если вход не Float, а UInt8/UInt16 — читаешь байты один раз и конвертишь через vDSP (vDSP_vfltu8 / vDSP_vfltu16).  ￼

8.2 Перестановка ENVI/HWC→CHW: параллель по каналам

Если данные interleaved HWC и нет готовой “chunky float → planar float” функции под твой тип, делай хотя бы по каналам параллельно, чтобы убрать тройной цикл в один жирный проход по памяти:

func hwcToPlanarF(hwc: UnsafePointer<Float>, dst: UnsafeMutablePointer<Float>,
                  w: Int, h: Int, c: Int) {
    let plane = w * h
    DispatchQueue.concurrentPerform(iterations: c) { ch in
        let outPlane = dst.advanced(by: ch * plane)
        var idx = 0
        for i in 0..<plane {
            idx = i * c + ch
            outPlane[i] = hwc[idx]
        }
    }
}

Да, тут есть цикл. Но:
	•	тройного ада уже нет,
	•	распараллеливание по c часто даёт норм буст,
	•	дальше всё будет Accelerate.

⸻

9) “Минимальный старт” именно для твоего проекта (без лишней философии)
	1.	Включи Accelerate в target и выкинь Double из пайплайна.
	2.	В HyperCube+Statistics.swift замени расчёты на vDSP_minv/maxv/meanv/svesq.  ￼
	3.	В DataNormalization.swift / CubeNormalization.swift замени нормализацию на vDSP_vsmsa + vDSP_vclip.  ￼
	4.	В CubeResizer/CubeRotator/CubeSpatialCropper замени resize/rotate на vImageScale_PlanarF / vImageRotate_PlanarF + kvImageHighQualityResampling.  ￼
	5.	В ImageRenderer.swift сделай fast path: Float planar → UInt8 planar через vDSP_vclip + vDSP_vsmul + vDSP_vfixu8.  ￼
	6.	Добавь бенч в XCTest, иначе ты будешь “на глаз” дрочить оптимизацию.

9.1 XCTest benchmark-шаблон

import XCTest

final class CubeBench: XCTestCase {
    func testNormalize512x512x256() {
        var cube = HyperCubeF(width: 512, height: 512, channels: 256, fill: 0.5)

        // немного шума
        for i in stride(from: 0, to: cube.data.count, by: 97) {
            cube.data[i] = Float(i % 255) / 255.0
        }

        measure {
            cube.normalizeMinMaxPerChannelParallel()
        }
    }
}


⸻

10) Где ты точно получишь самый жирный профит
	•	Убрать Double из PipelineOperation.swift и перестать плодить новые буферы “на каждый шаг”.
	•	Перевести все статистики/нормализации на vDSP (это самый дешёвый выигрыш по трудозатратам).  ￼
	•	vImage для resize/rotate/crop (особенно с kvImageHighQualityResampling, если качество важно).  ￼
	•	Metal — когда надо realtime и ты хочешь “один проход по данным” на GPU, а CPU уже жрёт батарейку.

⸻

Если хочешь, я могу прямо разложить по твоим файлам (“вот функция в CubeNormalization.swift меняется на это, вот сигнатуры, вот куда пихнуть пул буферов”), но даже без этого — всё выше уже рабочий “скелет”, который можно вставлять и выкидывать циклы пачками.