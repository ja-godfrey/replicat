#!/usr/bin/swift
// make-icon.swift - draw Replicat's app icon (a cat whose nose is a record button)
// into AppIcon.icns and icon.png. Run from the repo root: swift assets/make-icon.swift
import AppKit

func draw(_ px: Int) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = CGFloat(px) / 1024                     // design on a 1024 grid
  func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
  func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
  }
  // Rounded-square tile (macOS icon grid: 824 inside 1024, centred).
  let tile = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
  NSGradient(starting: c(0x3b3f5c), ending: c(0x181a26))!.draw(in: tile, angle: -90)
  // Cat head: ears + face, one shape.
  let head = NSBezierPath()
  head.move(to: p(282, 640)); head.line(to: p(318, 812)); head.line(to: p(452, 700))
  head.line(to: p(572, 700)); head.line(to: p(706, 812)); head.line(to: p(742, 640))
  head.curve(to: p(512, 270), controlPoint1: p(800, 420), controlPoint2: p(680, 270))
  head.curve(to: p(282, 640), controlPoint1: p(344, 270), controlPoint2: p(224, 420))
  head.close()
  c(0xf4f1ea).setFill(); head.fill()
  // Inner ears.
  for (a, b, d) in [((318, 770), (300, 660), (410, 690)), ((706, 770), (724, 660), (614, 690))] {
    let e = NSBezierPath(); e.move(to: p(CGFloat(a.0), CGFloat(a.1))); e.line(to: p(CGFloat(b.0), CGFloat(b.1)))
    e.line(to: p(CGFloat(d.0), CGFloat(d.1))); e.close(); c(0xe8b4b8).setFill(); e.fill()
  }
  // Eyes: calm, half-closed (it has seen you click "Remind Me Tomorrow" before).
  c(0x22243a).setFill()
  NSBezierPath(roundedRect: r(372, 520, 92, 30), xRadius: 15 * s, yRadius: 15 * s).fill()
  NSBezierPath(roundedRect: r(560, 520, 92, 30), xRadius: 15 * s, yRadius: 15 * s).fill()
  // Nose = record button.
  c(0xff453a).setFill(); NSBezierPath(ovalIn: r(466, 404, 92, 92)).fill()
  c(0xffffff, 0.35).setFill(); NSBezierPath(ovalIn: r(486, 448, 30, 30)).fill()
  // Whiskers.
  c(0x22243a, 0.55).setStroke()
  for (y1, y2) in [(450, 470), (420, 420), (390, 370)] {
    for side in [-1.0, 1.0] {
      let w = NSBezierPath(); w.lineWidth = 9 * s; w.lineCapStyle = .round
      w.move(to: p(512 + CGFloat(side) * 120, CGFloat(y1))); w.line(to: p(512 + CGFloat(side) * 250, CGFloat(y2))); w.stroke()
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let set = "assets/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
  let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
  try! draw(pt * scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(set)/\(name)"))
}
try! draw(256).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/icon.png"))
let t = Process(); t.launchPath = "/usr/bin/iconutil"; t.arguments = ["-c", "icns", set, "-o", "assets/AppIcon.icns"]
try! t.run(); t.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
print("wrote assets/AppIcon.icns and assets/icon.png")
