import AppKit

// 绘制 DMG 窗口背景：左侧应用、右侧“应用程序”，中间箭头提示拖动。
// 用法：swift Scripts/dmg-background.swift 输出目录；生成 background.png 与 background@2x.png。
let size = NSSize(width: 640, height: 400)
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let brand = NSColor(srgbRed: 0x30 / 255, green: 0xBB / 255, blue: 0xA9 / 255, alpha: 1)

func render(scale: CGFloat) throws {
    let pixels = NSSize(width: size.width * scale, height: size.height * scale)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSGradient(starting: NSColor(white: 1, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.98, blue: 0.97, alpha: 1))?
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
        NSAttributedString(string: string, attributes: attributes)
            .draw(in: NSRect(x: 0, y: y, width: 640, height: size * 1.6))
    }
    // Finder 坐标以左上为原点，图标中心位于 (160, 190) 与 (480, 190)，即绘图坐标 y = 210。
    text("将轻程拖到“应用程序”文件夹", size: 20, weight: .semibold, color: NSColor(white: 0.13, alpha: 1), y: 330)

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: 214))
    arrow.curve(to: NSPoint(x: 376, y: 218), controlPoint1: NSPoint(x: 290, y: 250), controlPoint2: NSPoint(x: 344, y: 250))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 10], count: 2, phase: 0)
    brand.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    // 箭头两翼与曲线末端切线各成约 35°。
    head.move(to: NSPoint(x: 381, y: 225))
    head.line(to: NSPoint(x: 385, y: 209))
    head.line(to: NSPoint(x: 369, y: 210))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text("首次打开若被系统拦截：系统设置 → 隐私与安全性 → 仍要打开", size: 12, weight: .regular,
         color: NSColor(white: 0.42, alpha: 1), y: 34)

    NSGraphicsContext.restoreGraphicsState()
    let name = scale > 1 ? "background@2x.png" : "background.png"
    try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name))
}

try render(scale: 1)
try render(scale: 2)
