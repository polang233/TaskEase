import AppKit
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root. Keep the generated source unchanged and
// prepare the image sizes and transparent padding required by app resources.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Branding/TaskEaseMark.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read Branding/TaskEaseMark.png")
}
let width = image.width
let height = image.height
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
let pixels = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                       bytesPerRow: width * 4, space: colorSpace, bitmapInfo: format)!
pixels.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let data = pixels.data!.assumingMemoryBound(to: UInt8.self)
var left = width, top = height, right = 0, bottom = 0
for y in 0..<height {
    for x in 0..<width where data[(y * width + x) * 4 + 3] > 200 {
        left = min(left, x); right = max(right, x)
        top = min(top, y); bottom = max(bottom, y)
    }
}
guard left < right, top < bottom,
      let cropped = image.cropping(to: CGRect(x: left, y: top,
          width: right - left + 1, height: bottom - top + 1)) else {
    fatalError("The logo has no visible foreground")
}

func write(_ input: CGImage, size: Int, padding: CGFloat, path: String) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: colorSpace, bitmapInfo: format)!
    let available = CGFloat(size) * (1 - padding * 2)
    let scale = available / CGFloat(max(input.width, input.height))
    let w = CGFloat(input.width) * scale, h = CGFloat(input.height) * scale
    context.interpolationQuality = .high
    context.draw(input, in: CGRect(x: (CGFloat(size) - w) / 2,
                                  y: (CGFloat(size) - h) / 2, width: w, height: h))
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
          let rendered = context.makeImage() else { fatalError("Cannot create PNG output") }
    CGImageDestinationAddImage(output, rendered, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Cannot save PNG output") }
    print(path)
}

try write(image, size: 1024, padding: 0, path: "TaskEase/Resources/AppIcon.icon/Assets/Leaves.png")
try write(cropped, size: 512, padding: 0.04,
          path: "TaskEase/Resources/Assets.xcassets/TaskEaseMark.imageset/Mark.png")
try write(cropped, size: 18, padding: 0.04,
          path: "TaskEase/Resources/Assets.xcassets/TaskEaseMenu.imageset/Menu.png")
try write(cropped, size: 36, padding: 0.04,
          path: "TaskEase/Resources/Assets.xcassets/TaskEaseMenu.imageset/Menu@2x.png")
