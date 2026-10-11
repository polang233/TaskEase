import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 从统一的矢量轮廓生成图标图层、界面标识和菜单栏模板；在仓库根目录运行。
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let format = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

struct Layer {
    let name: String
    let color: CGColor
    let path: CGPath
    let svg: String
}

/// 仅解析源文件使用的绝对 M/L/C/Z 命令，未知格式立即报错。
func path(from definition: String) -> CGPath {
    let tokens = definition.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    let result = CGMutablePath()
    var index = 0
    func number() -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]), value.isFinite else {
            fatalError("Invalid SVG coordinate")
        }
        index += 1
        return CGFloat(value)
    }
    func point() -> CGPoint { CGPoint(x: number(), y: number()) }
    while index < tokens.count {
        let command = tokens[index]
        index += 1
        switch command {
        case "M": result.move(to: point())
        case "L": result.addLine(to: point())
        case "C":
            let first = point(), second = point(), end = point()
            result.addCurve(to: end, control1: first, control2: second)
        case "Z": result.closeSubpath()
        default: fatalError("Unsupported SVG command: \(command)")
        }
    }
    return result
}

final class Source: NSObject, XMLParserDelegate {
    var layers: [Layer] = []
    var side: CGFloat = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String]) {
        if elementName == "svg" {
            let box = attributes["viewBox"]?.split(separator: " ").compactMap { Double($0) }
            guard let box, box.count == 4, box[0] == 0, box[1] == 0,
                  box[2] > 0, box[2] == box[3] else { fatalError("Expected a square SVG viewBox") }
            side = CGFloat(box[2])
        }
        guard elementName == "path" else { return }
        guard let name = attributes["id"], let definition = attributes["d"],
              let fill = attributes["fill"], fill.count == 7, fill.hasPrefix("#"),
              let rgb = UInt32(fill.dropFirst(), radix: 16) else { fatalError("Invalid SVG layer") }
        let color = CGColor(colorSpace: colorSpace, components: [
            CGFloat((rgb >> 16) & 255) / 255, CGFloat((rgb >> 8) & 255) / 255,
            CGFloat(rgb & 255) / 255, 1
        ])!
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 \(Int(side)) \(Int(side))\">\n  <path fill=\"\(fill)\" d=\"\(definition)\"/>\n</svg>\n"
        layers.append(Layer(name: name, color: color, path: path(from: definition), svg: svg))
    }
}

let sourceURL = root.appendingPathComponent("Branding/TaskEaseMark.svg")
let source = Source()
let parser = XMLParser(contentsOf: sourceURL)!
parser.delegate = source
guard parser.parse(), source.side > 0,
      source.layers.map(\.name) == ["RearLeaf", "FrontLeaf"] else { fatalError("Cannot read branding source") }
let bounds = source.layers.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }

/// 小图标直接栅格化矢量，并留出透明边距，避免缩放彩色图片造成轮廓粘连。
func render(size: Int, cropped: Bool, monochrome: Bool = false) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: colorSpace, bitmapInfo: format)!
    let area = cropped ? bounds : CGRect(x: 0, y: 0, width: source.side, height: source.side)
    let available = CGFloat(size) * (cropped ? (monochrome ? 0.84 : 0.9) : 1)
    let scale = available / max(area.width, area.height)
    context.translateBy(x: (CGFloat(size) - area.width * scale) / 2,
                        y: (CGFloat(size) + area.height * scale) / 2)
    context.scaleBy(x: scale, y: -scale)
    context.translateBy(x: -area.minX, y: -area.minY)
    for layer in source.layers {
        context.saveGState()
        if monochrome {
            // 菜单栏的小尺寸光学校正：两层各外移 0.3pt，让弧形留白保持清晰。
            let offset = CGFloat(size) / 18 * 0.3 / scale
            context.translateBy(x: layer.name == "RearLeaf" ? -offset : offset, y: 0)
        }
        context.setFillColor(monochrome ? CGColor(gray: 0, alpha: 1) : layer.color)
        context.addPath(layer.path)
        context.fillPath()
        context.restoreGState()
    }
    return context.makeImage()!
}

func save(_ image: CGImage, at path: String) throws {
    let url = root.appendingPathComponent(path)
    let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Cannot save \(path)") }
    print(path)
}

// 图层共用完整画布，保持前后顺序和位置；材质与光照由 Icon Composer 处理。
for layer in source.layers {
    let path = "TaskEase/Resources/AppIcon.icon/Assets/\(layer.name).svg"
    try layer.svg.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    print(path)
}
try save(render(size: 1024, cropped: false), at: "Branding/TaskEaseMark.png")
try save(render(size: 512, cropped: true), at: "TaskEase/Resources/Assets.xcassets/TaskEaseMark.imageset/Mark.png")
try save(render(size: 18, cropped: true, monochrome: true), at: "TaskEase/Resources/Assets.xcassets/TaskEaseMenu.imageset/Menu.png")
try save(render(size: 36, cropped: true, monochrome: true), at: "TaskEase/Resources/Assets.xcassets/TaskEaseMenu.imageset/Menu@2x.png")
