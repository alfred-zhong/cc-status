#!/usr/bin/swift
import AppKit
import Foundation

// 生成应用图标
// 设计：深色圆角矩形 + 绿色圆 + 白色 "C"

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// 1. 圆角矩形背景（深色）
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 224, yRadius: 224)

// 2. 渐变背景
let gradient = NSGradient(colors: [
    NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0),
    NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0),
])!
gradient.draw(in: bgPath, angle: -90)

// 3. 绿色圆（主视觉）
let circleRadius: CGFloat = 360
let circleRect = NSRect(
    x: (size - circleRadius * 2) / 2,
    y: (size - circleRadius * 2) / 2,
    width: circleRadius * 2,
    height: circleRadius * 2
)

// 圆的高光效果
let circleGradient = NSGradient(colors: [
    NSColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0),
    NSColor(red: 0.15, green: 0.70, blue: 0.30, alpha: 1.0),
])!
circleGradient.draw(in: NSBezierPath(ovalIn: circleRect), angle: -90)

// 4. 白色 "C" 字母
let text = "C"
let font = NSFont.systemFont(ofSize: 560, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let textSize = text.size(withAttributes: attrs)
let textRect = NSRect(
    x: (size - textSize.width) / 2,
    y: (size - textSize.height) / 2 - 20,  // 微调居中
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attrs)

image.unlockFocus()

// 保存为 PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to generate PNG\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Generated: \(outputPath)")
