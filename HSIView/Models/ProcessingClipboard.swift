import Foundation

struct ProcessingClipboard {
    let pipelineOperations: [PipelineOperation]
    let spectralTrimRange: ClosedRange<Int>?
    let trimStart: Double
    let trimEnd: Double
}
