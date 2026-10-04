#!/usr/bin/env swift
import AppKit
import Foundation

struct IconCatalog: Decodable {
    struct Item: Decodable { let filename: String; let size: String; let scale: String }
    let images: [Item]
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
guard let logo = NSImage(contentsOf: root.appendingPathComponent("Assets/AutoMAA-logo.png")) else {
    fatalError("Missing project logo")
}

func render(size: Int, to url: URL) throws {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let source = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    let inset = CGFloat(size) * 0.06
    context.draw(source, in: CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset,
                                   height: CGFloat(size) - 2 * inset))
    guard let output = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url, options: .atomic)
}

let catalog = root.appendingPathComponent("Mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset")
let icons = try JSONDecoder().decode(IconCatalog.self, from: Data(contentsOf: catalog.appendingPathComponent("Contents.json")))
var written = Set<String>()
for icon in icons.images where written.insert(icon.filename).inserted {
    guard let points = Double(icon.size.split(separator: "x")[0]),
          let scale = Double(icon.scale.dropLast()) else { fatalError("Invalid icon size") }
    try render(size: Int(points * scale), to: catalog.appendingPathComponent(icon.filename))
}
for (density, size) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    try render(size: size, to: root.appendingPathComponent("Mobile/android/app/src/main/res/mipmap-\(density)/ic_launcher.png"))
}
print("Generated iOS and Android icons from the existing project logo.")
