import Foundation

protocol ImageLoader {
    static var supportedExtensions: [String] { get }
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError>
}

class ImageLoaderFactory {
    private static let loaders: [ImageLoader.Type] = [
        MatImageLoader.self,
        TiffImageLoader.self
    ]
    
    static func loader(for url: URL) -> ImageLoader.Type? {
        let ext = url.pathExtension.lowercased()
        return loaders.first { $0.supportedExtensions.contains(ext) }
    }
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        guard let loader = loader(for: url) else {
            return .failure(.unsupportedFormat(url.pathExtension))
        }
        return loader.load(from: url)
    }
}


