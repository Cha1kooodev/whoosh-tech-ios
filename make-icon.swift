import AppKit

// Генерирует иконку 1024×1024 для iOS-приложения.
// Использование: swift make-icon.swift /путь/icon-1024.png

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let full = NSRect(x: 0, y: 0, width: size, height: size)
NSColor(calibratedRed: 0.043, green: 0.055, blue: 0.075, alpha: 1).setFill()
full.fill()

let plate = NSBezierPath(roundedRect: full.insetBy(dx: 150, dy: 150), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 1.0, green: 0.831, blue: 0.0, alpha: 1).setFill()
plate.fill()

let letter = NSAttributedString(string: "W", attributes: [
    .font: NSFont.systemFont(ofSize: 560, weight: .black),
    .foregroundColor: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
])
let letterSize = letter.size()
letter.draw(at: NSPoint(x: (size - letterSize.width) / 2,
                        y: (size - letterSize.height) / 2 + 10))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

try png.write(to: URL(fileURLWithPath: out))
print("ok: \(out)")
