import AppKit

// 生成 GitHub 社交预览图（1280×640）：应用图标、名称与一句话介绍，简约浅色背景。
// 用法：swift Scripts/social-preview.swift 仓库根目录；输出 Branding/social-preview.png。
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let size = NSSize(width: 1280, height: 640)
guard let icon = NSImage(contentsOf: root.appendingPathComponent("Branding/AppIcon-preview.png")),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
let brand = NSColor(srgbRed: 0x30 / 255, green: 0xBB / 255, blue: 0xA9 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0.11, green: 0.13, blue: 0.15, alpha: 1)
let muted = NSColor(srgbRed: 0.40, green: 0.44, blue: 0.48, alpha: 1)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGradient(starting: .white, ending: NSColor(srgbRed: 0.92, green: 0.98, blue: 0.96, alpha: 1))?
    .draw(in: NSRect(origin: .zero, size: size), angle: -60)

// 右下角一道淡色叶形弧，呼应图标，不抢主体。
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 1280, y: 120))
leaf.curve(to: NSPoint(x: 880, y: 0), controlPoint1: NSPoint(x: 1120, y: 150), controlPoint2: NSPoint(x: 960, y: 90))
leaf.line(to: NSPoint(x: 1280, y: 0))
leaf.close()
brand.withAlphaComponent(0.10).setFill()
leaf.fill()

icon.draw(in: NSRect(x: 110, y: 180, width: 280, height: 280))

func draw(_ text: String, _ font: NSFont, _ color: NSColor, at point: NSPoint, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: point)
}
let left: CGFloat = 450
draw("轻程", .systemFont(ofSize: 84, weight: .bold), ink, at: NSPoint(x: left, y: 388))
draw("TaskEase", .systemFont(ofSize: 44, weight: .medium), brand, at: NSPoint(x: left + 196, y: 404))
draw("调整应用优先级，锁定 CPU 占用上限", .systemFont(ofSize: 34, weight: .medium), ink, at: NSPoint(x: left, y: 316))
draw("减少后台耗电，实时查看 CPU、GPU、内存与温度", .systemFont(ofSize: 26, weight: .regular), muted, at: NSPoint(x: left, y: 268))

// 底部标签：平台与开源信息。
var x = left
for tag in ["macOS 菜单栏", "Apple Silicon", "免费开源"] {
    let font = NSFont.systemFont(ofSize: 20, weight: .medium)
    let width = (tag as NSString).size(withAttributes: [.font: font]).width + 32
    let pill = NSBezierPath(roundedRect: NSRect(x: x, y: 184, width: width, height: 40), xRadius: 20, yRadius: 20)
    brand.withAlphaComponent(0.12).setFill()
    pill.fill()
    draw(tag, font, NSColor(srgbRed: 0.10, green: 0.50, blue: 0.45, alpha: 1), at: NSPoint(x: x + 16, y: 192))
    x += width + 12
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])?
    .write(to: root.appendingPathComponent("Branding/social-preview.png"))
