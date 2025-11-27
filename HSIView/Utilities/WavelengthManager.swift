import Foundation

class WavelengthManager {
    static func loadFromFile(url: URL) -> Result<[Double], Error> {
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
            
            guard !values.isEmpty else {
                return .failure(NSError(
                    domain: "WavelengthManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Не удалось распарсить длины волн"]
                ))
            }
            
            return .success(values)
        } catch {
            return .failure(error)
        }
    }
    
    static func generate(start: Double, channels: Int, step: Double) -> [Double] {
        guard channels > 0, step > 0 else { return [] }
        
        var wavelengths = [Double]()
        wavelengths.reserveCapacity(channels)
        
        for i in 0..<channels {
            wavelengths.append(start + Double(i) * step)
        }
        
        return wavelengths
    }
    
    static func calculateEnd(start: Double, channels: Int, step: Double) -> Double {
        return start + Double(max(channels - 1, 0)) * step
    }
}


