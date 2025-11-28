import Foundation

struct EnviHeader {
    let samples: Int      // W (width)
    let lines: Int        // H (height)
    let bands: Int        // C (channels)
    let dataType: Int     // ENVI data type code
    let interleave: String // bsq, bil, bip
    let byteOrder: Int    // 0 = little endian, 1 = big endian
    let headerOffset: Int // bytes to skip before data
    
    // Optional fields
    let wavelength: [Double]?
    let fwhm: [Double]?
    let wavelengthUnits: String?
    let description: String?
    let bandNames: [String]?
    
    var width: Int { samples }
    var height: Int { lines }
    var channels: Int { bands }
    
    var bytesPerPixel: Int {
        switch dataType {
        case 1: return 1   // int8
        case 2: return 2   // int16
        case 3: return 4   // int32
        case 4: return 4   // float32
        case 5: return 8   // float64
        case 12: return 2  // uint16
        case 13: return 4  // uint32
        case 14: return 8  // int64
        case 15: return 8  // uint64
        default: return 0
        }
    }
    
    var isLittleEndian: Bool { byteOrder == 0 }
}

class EnviHeaderParser {
    static func parse(from url: URL) throws -> EnviHeader {
        guard let content = try? String(contentsOf: url, encoding: .ascii) else {
            throw ImageLoadError.readError("Не удалось прочитать .hdr файл")
        }
        
        let lines = content.components(separatedBy: .newlines)
        
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
              firstLine.uppercased() == "ENVI" else {
            throw ImageLoadError.corruptedData
        }
        
        var fields: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""
        var inBraces = false
        
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if inBraces {
                currentValue += " " + trimmed
                if trimmed.contains("}") {
                    inBraces = false
                    if let key = currentKey {
                        fields[key] = currentValue
                    }
                    currentKey = nil
                    currentValue = ""
                }
            } else if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                var value = String(trimmed[trimmed.index(after: equalIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                
                if value.contains("{") && !value.contains("}") {
                    inBraces = true
                    currentKey = key
                    currentValue = value
                } else {
                    fields[key] = value
                }
            }
        }
        
        guard let samplesStr = fields["samples"], let samples = Int(samplesStr),
              let linesStr = fields["lines"], let lines = Int(linesStr),
              let bandsStr = fields["bands"], let bands = Int(bandsStr),
              let dataTypeStr = fields["data type"], let dataType = Int(dataTypeStr),
              let interleave = fields["interleave"]?.lowercased() else {
            throw ImageLoadError.corruptedData
        }
        
        let byteOrder = Int(fields["byte order"] ?? "0") ?? 0
        let headerOffset = Int(fields["header offset"] ?? "0") ?? 0
        
        let wavelength = parseArray(fields["wavelength"])
        let fwhm = parseArray(fields["fwhm"])
        let wavelengthUnits = fields["wavelength units"]?.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespaces)
        let description = fields["description"]?.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let bandNames: [String]? = fields["band names"].flatMap { value in
            let cleaned = value.replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
            return cleaned.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        
        return EnviHeader(
            samples: samples,
            lines: lines,
            bands: bands,
            dataType: dataType,
            interleave: interleave,
            byteOrder: byteOrder,
            headerOffset: headerOffset,
            wavelength: wavelength,
            fwhm: fwhm,
            wavelengthUnits: wavelengthUnits,
            description: description,
            bandNames: bandNames
        )
    }
    
    private static func parseArray(_ value: String?) -> [Double]? {
        guard let value = value else { return nil }
        
        let cleaned = value.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        
        let components = cleaned.components(separatedBy: ",")
        let doubles = components.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        
        return doubles.isEmpty ? nil : doubles
    }
}

