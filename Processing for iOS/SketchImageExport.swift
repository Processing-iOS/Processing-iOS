import Foundation
import ImageIO

@objc final class SketchImageExport: NSObject {
    @objc static func save(_ payload: [String: Any], in folder: URL) throws -> String {
        guard let name = payload["name"] as? String,
              let encoded = payload["data"] as? String, encoded.utf8.count <= 24_000_000 else {
            throw ProjectFileError(message: "The saved image is too large (maximum 18 MB). Use a smaller canvas.")
        }
        try ProjectFiles.validateName(name)
        guard ["png", "jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased()),
              let data = Data(base64Encoded: encoded),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_777_216 else {
            throw ProjectFileError(message: "Cannot save this image. Use PNG or JPEG and a canvas with at most 16 million pixels.")
        }
        let exports = folder.appendingPathComponent("exports", isDirectory: true)
        guard exports.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/") else {
            throw ProjectFileError(message: "The exports folder must be inside this project.")
        }
        try ProjectFiles.write(folder, options: []) { _ in
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            try data.write(to: exports.appendingPathComponent(name), options: .atomic)
        }
        return "exports/" + name
    }
}
