#!/usr/bin/swift
// render.swift - draw the README demo scenes frame by frame.
//
//   swift demo/render.swift <scene> <out-dir>     scene: remind | email
//
// These are recreations drawn with AppKit, not screen recordings: the desktop,
// dialogs and mail app are made up, and the toolbar is redrawn to match the app.
// demo/render.sh turns the frames into GIFs.
import AppKit

let W: CGFloat = 960, H: CGFloat = 600, FPS = 15.0

// MARK: drawing helpers (top-left coordinates)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: H - y - h, width: w, height: h) }
func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: H - y) }
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor, r: CGFloat = 0) {
  c.setFill(); NSBezierPath(roundedRect: R(x, y, w, h), xRadius: r, yRadius: r).fill()
}
func outline(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor, r: CGFloat, width: CGFloat) {
  c.setStroke(); let p = NSBezierPath(roundedRect: R(x + width / 2, y + width / 2, w - width, h - width), xRadius: r, yRadius: r)
  p.lineWidth = width; p.stroke()
}
func shadow(_ blur: CGFloat, _ dy: CGFloat, _ a: CGFloat, _ body: () -> Void) {
  NSGraphicsContext.saveGraphicsState()
  let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: -dy); s.shadowColor = hex(0, a); s.set()
  body(); NSGraphicsContext.restoreGraphicsState()
}
enum Align { case left, center, right }
@discardableResult
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor, weight: NSFont.Weight = .regular,
          align: Align = .left, mono: Bool = false) -> CGFloat {
  let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
  let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
  let sz = (s as NSString).size(withAttributes: a)
  let dx: CGFloat = align == .left ? 0 : align == .center ? -sz.width / 2 : -sz.width
  (s as NSString).draw(at: P(x + dx, y + sz.height), withAttributes: a)
  return sz.width
}
func width(_ s: String, _ size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
  (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
}
func symbol(_ name: String, _ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, _ c: NSColor, weight: NSFont.Weight = .medium) {
  guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
          .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return }
  let img = NSImage(size: base.size, flipped: false) { r in base.draw(in: r); c.set(); r.fill(using: .sourceAtop); return true }
  img.draw(in: R(cx - base.size.width / 2, cy - base.size.height / 2, base.size.width, base.size.height))
}
func cursor(_ x: CGFloat, _ y: CGFloat, pressed: Bool = false) {
  let k: CGFloat = pressed ? 0.9 : 1
  let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.2, 13.2), (7, 19.5), (9.6, 18.4), (7, 12.3), (12.4, 12.3)]
  let path = NSBezierPath()
  for (i, (px, py)) in pts.enumerated() { let pt = P(x + px * k, y + py * k); i == 0 ? path.move(to: pt) : path.line(to: pt) }
  path.close()
  shadow(3, 1.5, 0.35) { hex(0x000000).setFill(); path.fill() }
  hex(0xffffff).setStroke(); path.lineWidth = 1.4; path.stroke()
  if pressed { hex(0xffffff, 0.55).setStroke(); let ring = NSBezierPath(ovalIn: R(x - 9, y - 9, 18, 18)); ring.lineWidth = 2; ring.stroke() }
}

// MARK: timing helpers

func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
func ease(_ v: Double) -> Double { let t = clamp(v); return t * t * (3 - 2 * t) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
/// Progress 0...1 of t through [a, b].
func span(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }

// MARK: the desktop

let calendar = Calendar(identifier: .gregorian)
let day0 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!
func dateLabel(_ offset: Int) -> String {
  let d = calendar.date(byAdding: .day, value: offset, to: day0)!
  let f = DateFormatter(); f.dateFormat = "EEE MMM d"; return f.string(from: d) + "   9:41 AM"
}

func desktop(dayOffset: Int = 0, app: String = "Finder") {
  NSGradient(colors: [hex(0xf6d5c3), hex(0xd9c2e6), hex(0x9fb7e3)])!.draw(in: R(0, 0, W, H), angle: -70)
  // soft hills, for a calm wallpaper
  hex(0xffffff, 0.18).setFill()
  let hill = NSBezierPath(); hill.move(to: P(0, 470)); hill.curve(to: P(W, 430), controlPoint1: P(300, 380), controlPoint2: P(640, 520))
  hill.line(to: P(W, H)); hill.line(to: P(0, H)); hill.close(); hill.fill()
  // menu bar
  box(0, 0, W, 26, hex(0xffffff, 0.55))
  symbol("circle.grid.2x2.fill", 18, 13, 11, hex(0x1d1d1f))
  var x: CGFloat = 36
  for (i, item) in [app, "File", "Edit", "View", "Window", "Help"].enumerated() {
    x += text(item, x, 6, 13, hex(0x1d1d1f), weight: i == 0 ? .bold : .regular) + 18
  }
  text(dateLabel(dayOffset), W - 14, 6, 13, hex(0x1d1d1f), align: .right, mono: true)
  symbol("wifi", W - 186, 13, 12, hex(0x1d1d1f))
}

// MARK: Replicat's toolbar, redrawn

enum HudState { case empty, loaded(String), recording(Double), countdown(Int), playing(String, Double), stopped(String) }

func hud(_ x: CGFloat, _ y: CGFloat, _ s: HudState, selected: Bool = false) {
  let w: CGFloat = 236, h: CGFloat = 80
  shadow(14, 6, 0.35) { box(x, y, w, h, hex(0x2c2c2e, 0.94), r: 12) }
  var ring: NSColor? = nil, keys: [(String, String)] = [], info = ""
  var recording = false, playing = false, progress = 0.0
  switch s {
  case .empty: keys = [("⌃⌥⇧R", "record")]; info = "Nothing recorded yet"
  case .loaded(let i): keys = [("⌃⌥⇧P", "play"), ("⌃⌥⇧R", "re-record")]; info = i
  case .recording(let sec): recording = true; ring = hex(0xff453a); keys = [("⌃⌥⇧R", "stop recording")]
    info = String(format: "● Recording  0:%02d", Int(sec))
  case .countdown(let n): playing = true; ring = hex(0x30d158); keys = [("Esc", "cancel")]; info = "Playing in \(n)…"
  case .playing(let i, let f): playing = true; ring = hex(0x30d158); keys = [("Esc", "stop (or move the mouse)")]; info = i; progress = f
  case .stopped(let m): keys = [("⌃⌥⇧P", "play"), ("⌃⌥⇧R", "re-record")]; info = m
  }
  if ring == nil && selected { ring = hex(0x0a84ff) }
  // buttons
  let row: [(String, NSColor)] = [("folder", hex(0xe5e5ea)), ("square.and.arrow.down", hex(0xe5e5ea)), ("|", .clear),
    (recording ? "stop.circle.fill" : "record.circle", hex(0xff453a)),
    (playing ? "stop.fill" : "play.fill", playing ? hex(0x30d158) : hex(0xe5e5ea)), ("|", .clear),
    ("slider.horizontal.3", hex(0xe5e5ea))]
  var bx = x + 26
  for (name, c) in row {
    if name == "|" { box(bx - 4, y + 13, 1, 16, hex(0xffffff, 0.18)); bx += 6; continue }
    symbol(name, bx + 4, y + 21, 15, c); bx += 34
  }
  // hint line: keys bold in the state colour, words quieter
  let accent = recording ? hex(0xff453a) : playing ? hex(0x30d158) : hex(0xffffff)
  let parts = keys.enumerated().map { (i, k) in (k.0, " " + k.1, i) }
  let total = parts.reduce(CGFloat(0)) { $0 + width($1.0, 12, weight: .bold) + width($1.1, 12, weight: .medium) } + CGFloat(max(0, parts.count - 1)) * 16
  var hx = x + w / 2 - total / 2
  for (k, word, i) in parts {
    hx += text(k, hx, y + 37, 12, accent, weight: .bold)
    hx += text(word, hx, y + 37, 12, i == 0 ? hex(0xffffff) : hex(0xffffff, 0.6), weight: .medium) + 16
  }
  text(info, x + w / 2, y + 56, 11, hex(0xffffff, 0.62), align: .center, mono: true)
  if let ring { outline(x, y, w, h, ring, r: 12, width: 3) }
  if playing && progress > 0 {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: R(x, y, w, h), xRadius: 12, yRadius: 12).addClip()
    box(x, y + h - 3, w * CGFloat(progress), 3, hex(0x30d158))
    NSGraphicsContext.restoreGraphicsState()
  }
}

/// A key press shown as keycaps at the bottom, with what it does.
func keyCaption(_ keys: [String], _ what: String, alpha: Double) {
  guard alpha > 0.01 else { return }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(alpha))
  let capW: [CGFloat] = keys.map { max(34, width($0, 17, weight: .semibold) + 18) }
  let total = capW.reduce(0, +) + CGFloat(keys.count - 1) * 6 + 14 + width(what, 15, weight: .medium) + 36
  let x0 = W / 2 - total / 2, y0: CGFloat = H - 70
  shadow(12, 4, 0.3) { box(x0, y0, total, 48, hex(0x1c1c1e, 0.88), r: 14) }
  var x = x0 + 18
  for (k, cw) in zip(keys, capW) {
    box(x, y0 + 9, cw, 30, hex(0x3a3a3c), r: 7); box(x, y0 + 9, cw, 27, hex(0x48484a), r: 7)
    text(k, x + cw / 2, y0 + 13, 17, hex(0xffffff), weight: .semibold, align: .center); x += cw + 6
  }
  text(what, x + 8, y0 + 15, 15, hex(0xffffff, 0.9), weight: .medium)
  NSGraphicsContext.restoreGraphicsState()
}

/// A caption across the top-left: what this part of the demo shows.
func banner(_ s: String, alpha: Double) {
  guard alpha > 0.01 else { return }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(alpha))
  let w = width(s, 18, weight: .semibold) + 32
  shadow(10, 3, 0.25) { box(24, 44, w, 38, hex(0xffffff, 0.92), r: 10) }
  text(s, 40, 52, 18, hex(0x1d1d1f), weight: .semibold)
  NSGraphicsContext.restoreGraphicsState()
}
func fade(_ t: Double, _ a: Double, _ b: Double, edge: Double = 0.25) -> Double {
  min(span(t, a, a + edge), 1 - span(t, b - edge, b))
}

// MARK: scene 1 - "Remind Me Tomorrow", forever

let HUDX: CGFloat = W - 236 - 20, HUDY: CGFloat = 40

func updateDialog(_ alpha: Double, pressed: Bool) {
  guard alpha > 0.01 else { return }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(alpha))
  let x: CGFloat = 250, y: CGFloat = 200, w: CGFloat = 400, h: CGFloat = 176
  shadow(30, 12, 0.3) { box(x, y, w, h, hex(0xf5f5f7), r: 14) }
  box(x + 22, y + 24, 52, 52, hex(0x8e8e93), r: 12)
  symbol("gearshape.fill", x + 48, y + 50, 30, hex(0xffffff))
  text("Software Update", x + 92, y + 26, 15, hex(0x1d1d1f), weight: .bold)
  text("An update is ready to install.", x + 92, y + 49, 13, hex(0x3c3c43))
  text("Your Mac will restart to finish installing.", x + 92, y + 67, 13, hex(0x3c3c43))
  // buttons
  box(x + 92, y + 120, 168, 32, pressed ? hex(0xc7c7cc) : hex(0xe5e5ea), r: 8)
  text("Remind Me Tomorrow", x + 176, y + 127, 13, hex(0x1d1d1f), weight: .medium, align: .center)
  box(x + 272, y + 120, 106, 32, hex(0x0a84ff), r: 8)
  text("Install Now", x + 325, y + 127, 13, hex(0xffffff), weight: .medium, align: .center)
  NSGraphicsContext.restoreGraphicsState()
}
let REMIND = (x: CGFloat(426), y: CGFloat(336))       // the "Remind Me Tomorrow" button
let HOME = (x: CGFloat(520), y: CGFloat(470))          // where the pointer rests

func sceneRemind(_ t: Double) {
  // 0.0-1.4  idle;  1.4 ⌃⌥⇧R;  1.6-3.2 pointer to the button;  3.3 click;  4.3 ⌃⌥⇧R stop
  // 5.6 ⌃⌥⇧P;  6.0-12.0 fast loops (a day each);  12.0-14.4 "3 years later";  14.6 mouse moves -> stop
  let loopStart = 6.0, loopLen = 0.5, loops = 12
  var day = 0
  var dialog = 1.0, pressed = false
  var cx = HOME.x, cy = HOME.y, down = false
  var state: HudState = .empty
  var counter: String? = nil

  if t < 1.4 { state = .empty }
  else if t < 4.3 {
    state = .recording(t - 1.4)
    let m = ease(span(t, 1.7, 3.1)); cx = lerp(HOME.x, REMIND.x, m); cy = lerp(HOME.y, REMIND.y, m)
    if t >= 3.25 && t < 3.45 { pressed = true; down = true }
    dialog = 1 - span(t, 3.45, 3.75)
    if t > 3.75 { let back = ease(span(t, 3.8, 4.2)); cx = lerp(REMIND.x, HOME.x, back); cy = lerp(REMIND.y, HOME.y, back) }
  } else if t < 5.6 {
    state = .loaded("Recording  ·  0:01  ·  4×  ·  loop"); dialog = span(t, 4.6, 4.9)
  } else if t < 12.0 {
    let l = max(0, t - loopStart), i = Int(l / loopLen), f = l.truncatingRemainder(dividingBy: loopLen) / loopLen
    if t < loopStart { state = .playing("▶ loop 1  ·  starting", 0); dialog = 1 }
    else {
      day = i
      state = .playing("▶ loop \(i + 1)  ·  0:00 left", f)
      // each pass: dialog appears, pointer darts to the button, click, dialog gone
      dialog = f < 0.65 ? 1 : 1 - span(f, 0.65, 0.8)
      let m = ease(span(f, 0.05, 0.45)); cx = lerp(HOME.x, REMIND.x, m); cy = lerp(HOME.y, REMIND.y, m)
      if f >= 0.5 && f < 0.65 { pressed = true; down = true }
      if f > 0.8 { let back = ease(span(f, 0.8, 1)); cx = lerp(REMIND.x, HOME.x, back); cy = lerp(REMIND.y, HOME.y, back) }
      counter = "postponed \(i + 1) day\(i == 0 ? "" : "s")"
    }
    _ = loops
  } else if t < 14.6 {
    day = 1095
    let f = (t - 12.0).truncatingRemainder(dividingBy: loopLen) / loopLen
    state = .playing("▶ loop 1,096  ·  0:00 left", f)
    dialog = f < 0.65 ? 1 : 1 - span(f, 0.65, 0.8)
    let m = ease(span(f, 0.05, 0.45)); cx = lerp(HOME.x, REMIND.x, m); cy = lerp(HOME.y, REMIND.y, m)
    if f >= 0.5 && f < 0.65 { pressed = true; down = true }
    if f > 0.8 { let back = ease(span(f, 0.8, 1)); cx = lerp(REMIND.x, HOME.x, back); cy = lerp(REMIND.y, HOME.y, back) }
    counter = "postponed 1,096 days"
  } else {
    // a human grabs the mouse: playback stops on its own
    day = 1095; dialog = 1
    state = t < 14.9 ? .playing("▶ loop 1,097  ·  0:00 left", 0.1) : .stopped("Stopped: you moved the mouse")
    let wig = span(t, 14.6, 15.2)
    cx = HOME.x + CGFloat(sin(wig * .pi * 6)) * 26 * CGFloat(1 - wig) + 60 * CGFloat(ease(wig))
    cy = HOME.y - 30 * CGFloat(ease(wig))
    counter = "postponed 1,096 days"
  }

  desktop(dayOffset: day, app: "Finder")
  updateDialog(dialog, pressed: pressed)
  if let counter {
    let cw = width(counter, 14, weight: .semibold) + 26
    shadow(8, 2, 0.2) { box(W / 2 - cw / 2, 140, cw, 30, hex(0xffffff, 0.9), r: 15) }
    text(counter, W / 2, 146, 14, hex(0x1d1d1f), weight: .semibold, align: .center, mono: true)
  }
  hud(HUDX, HUDY, state)
  banner("Record it once", alpha: fade(t, 0.3, 4.4))
  banner("Replay it at 4×, on a loop", alpha: fade(t, 5.4, 11.9))
  banner("3 years later", alpha: fade(t, 12.0, 14.5))
  banner("Grab the mouse to stop", alpha: fade(t, 14.6, 17.0))
  keyCaption(["⌃", "⌥", "⇧", "R"], "start recording", alpha: fade(t, 1.3, 2.4))
  keyCaption(["⌃", "⌥", "⇧", "R"], "stop recording", alpha: fade(t, 4.2, 5.3))
  keyCaption(["⌃", "⌥", "⇧", "P"], "play", alpha: fade(t, 5.5, 6.6))
  cursor(cx, cy, pressed: down)
}

// MARK: scene 2 - "Per my last email", 2×, 3 times

struct Mail { let from: String; let subject: String; let preview: String }
let inbox = [Mail(from: "Dana", subject: "Quick question", preview: "Did you get a chance to look at the…"),
             Mail(from: "Marcus", subject: "Following up", preview: "Bumping this to the top of your inbox"),
             Mail(from: "Priya", subject: "Circling back", preview: "Looping back on the below, any…"),
             Mail(from: "Dana", subject: "Just checking in", preview: "Any update on this? No rush!")]
let REPLY = "Per my last email,"
let MX: CGFloat = 90, MY: CGFloat = 66, MW: CGFloat = 600, MH: CGFloat = 430
let ROW1 = (x: MX + 120, y: MY + 74)
let REPLYBTN = (x: MX + MW - 116, y: MY + 66)
let SEND = (x: MX + MW - 56, y: MY + MH - 40)

func mailWindow(answered: Int, slide: Double, selected: Bool, typed: Int, pressed: String?) {
  shadow(30, 12, 0.28) { box(MX, MY, MW, MH, hex(0xffffff), r: 12) }
  box(MX, MY, MW, 40, hex(0xf2f2f7), r: 12); box(MX, MY + 28, MW, 12, hex(0xf2f2f7))
  for (i, c) in [0xff5f57, 0xfebc2e, 0x28c840].enumerated() { box(MX + 16 + CGFloat(i) * 20, MY + 14, 12, 12, hex(UInt32(c)), r: 6) }
  text("Inbox", MX + 100, MY + 11, 14, hex(0x1d1d1f), weight: .semibold)
  // list
  let listW: CGFloat = 240
  box(MX + listW, MY + 40, 1, MH - 40, hex(0xe5e5ea))
  let remaining = Array(inbox.dropFirst(answered))
  if remaining.isEmpty {
    symbol("checkmark.circle", MX + listW / 2, MY + 200, 34, hex(0x8e8e93))
    text("Inbox zero", MX + listW / 2, MY + 228, 14, hex(0x8e8e93), weight: .semibold, align: .center)
  }
  for (i, m) in remaining.enumerated() {
    let y = MY + 44 + CGFloat(i) * 66 - CGFloat(ease(slide)) * 66
    if i == 0 && slide > 0 { continue }
    if i == 0 && selected { box(MX + 6, y, listW - 12, 62, hex(0x0a84ff), r: 8) }
    let ink = i == 0 && selected ? hex(0xffffff) : hex(0x1d1d1f), sub = i == 0 && selected ? hex(0xffffff, 0.85) : hex(0x6e6e73)
    box(MX + 14, y + 12, 7, 7, i == 0 && selected ? hex(0xffffff) : hex(0x0a84ff), r: 3.5)
    text(m.from, MX + 28, y + 6, 13, ink, weight: .bold)
    text(m.subject, MX + 28, y + 24, 12, ink, weight: .medium)
    text(m.preview, MX + 28, y + 41, 11, sub)
  }
  // reading pane
  guard let m = remaining.first, selected, slide == 0 else { return }
  let px = MX + listW + 20
  text(m.subject, px, MY + 56, 17, hex(0x1d1d1f), weight: .bold)
  text("From: \(m.from)", px, MY + 80, 12, hex(0x6e6e73))
  text(m.preview.replacingOccurrences(of: "…", with: "?"), px, MY + 112, 13, hex(0x3c3c43))
  box(REPLYBTN.x - 34, REPLYBTN.y - 13, 68, 26, pressed == "reply" ? hex(0xc7c7cc) : hex(0xe5e5ea), r: 7)
  text("Reply", REPLYBTN.x, REPLYBTN.y - 8, 12, hex(0x1d1d1f), weight: .medium, align: .center)
  guard typed >= 0 else { return }
  box(px, MY + 170, MW - listW - 40, 170, hex(0xf9f9fb), r: 8); outline(px, MY + 170, MW - listW - 40, 170, hex(0xd1d1d6), r: 8, width: 1)
  text("Re: \(m.subject)", px + 12, MY + 180, 12, hex(0x6e6e73), weight: .medium)
  let shown = String(REPLY.prefix(typed))
  let tw = text(shown, px + 12, MY + 206, 15, hex(0x1d1d1f))
  if typed < REPLY.count { box(px + 13 + tw, MY + 206, 1.5, 18, hex(0x0a84ff)) }
  box(SEND.x - 40, SEND.y - 14, 80, 28, pressed == "send" ? hex(0x0060df) : hex(0x0a84ff), r: 7)
  text("Send", SEND.x, SEND.y - 8, 13, hex(0xffffff), weight: .semibold, align: .center)
}

/// One reply, as recorded: click the email, Reply, type, Send. f is 0...1 through it.
func replyPass(_ f: Double, rest: (CGFloat, CGFloat)) -> (cx: CGFloat, cy: CGFloat, down: Bool, selected: Bool, typed: Int, pressed: String?, sent: Double) {
  var cx = rest.0, cy = rest.1, down = false, selected = false, typed = -1, pressed: String? = nil, sent = 0.0
  func move(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ p: Double) { let m = ease(p); cx = lerp(a.0, b.0, m); cy = lerp(a.1, b.1, m) }
  if f < 0.14 { move(rest, (ROW1.x, ROW1.y), span(f, 0, 0.12)) }
  else if f < 0.30 { cx = ROW1.x; cy = ROW1.y; selected = true; down = f < 0.17; move((ROW1.x, ROW1.y), (REPLYBTN.x, REPLYBTN.y), span(f, 0.18, 0.28)) }
  else if f < 0.36 { selected = true; cx = REPLYBTN.x; cy = REPLYBTN.y; down = f < 0.33; pressed = down ? "reply" : nil; typed = f < 0.33 ? -1 : 0 }
  else if f < 0.74 { selected = true; typed = Int(Double(REPLY.count) * span(f, 0.37, 0.70)); move((REPLYBTN.x, REPLYBTN.y), (SEND.x, SEND.y), span(f, 0.50, 0.72)) }
  else if f < 0.82 { selected = true; typed = REPLY.count; cx = SEND.x; cy = SEND.y; down = f < 0.78; pressed = down ? "send" : nil }
  else { sent = span(f, 0.82, 0.95); move((SEND.x, SEND.y), rest, span(f, 0.85, 1.0)) }
  return (cx, cy, down, selected, typed, pressed, sent)
}

func sceneEmail(_ t: Double) {
  // 0-0.8 idle; 0.8 ⌃⌥⇧R; 1.0-5.4 one reply by hand; 5.6 ⌃⌥⇧R stop;
  // 6.2-8.0 settings: 2×, 3 times; 8.2 ⌃⌥⇧P; 8.4-15.0 three replies at 2×; then inbox zero
  let rest = (CGFloat(470), CGFloat(540))
  var answered = 0, slide = 0.0, selected = false, typed = -1, pressed: String? = nil
  var cx = rest.0, cy = rest.1, down = false
  var state: HudState = .empty
  var menu = 0.0

  if t < 0.8 { state = .empty }
  else if t < 5.6 {
    state = .recording(t - 0.8)
    let p = replyPass(span(t, 1.0, 5.4), rest: rest)
    (cx, cy, down, selected, typed, pressed) = (p.cx, p.cy, p.down, p.selected, p.typed, p.pressed); slide = p.sent
    if slide >= 1 { answered = 1; slide = 0 }
  } else if t < 8.2 {
    answered = 1
    state = .loaded("Recording  ·  0:04  ·  1×  ·  once")
    menu = fade(t, 6.4, 8.0, edge: 0.15)
    if t > 6.0 && t < 8.1 {
      let m = ease(span(t, 6.0, 6.4)); cx = lerp(rest.0, HUDX + 214, m); cy = lerp(rest.1, HUDY + 21, m)
      if t > 6.9 { let m2 = ease(span(t, 6.9, 7.2)); cy = lerp(HUDY + 21, HUDY + 150, m2); cx = HUDX + 150 }
      if t > 7.4 { let m3 = ease(span(t, 7.4, 7.7)); cy = lerp(HUDY + 150, HUDY + 312, m3) }
      down = (t > 6.4 && t < 6.5) || (t > 7.2 && t < 7.3) || (t > 7.7 && t < 7.8)
    }
    if t >= 7.25 { state = .loaded("Recording  ·  0:02  ·  2×  ·  once") }
    if t >= 7.75 { state = .loaded("Recording  ·  0:06  ·  2×  ·  3×") }
    if t >= 8.1 { cx = rest.0; cy = rest.1 }
  } else {
    let passLen = 2.2, start = 8.4
    let k = Int(max(0, t - start) / passLen), f = max(0, t - start).truncatingRemainder(dividingBy: passLen) / passLen
    if t < start || k >= 3 {
      answered = min(4, 1 + max(0, k))
      state = k >= 3 ? .stopped("Done  ·  replied 3 times") : .playing("▶ 1 of 3  ·  0:06 left", 0)
    } else {
      answered = 1 + k
      let p = replyPass(f, rest: rest)
      (cx, cy, down, selected, typed, pressed) = (p.cx, p.cy, p.down, p.selected, p.typed, p.pressed); slide = p.sent
      if slide >= 1 { answered += 1; slide = 0 }
      let left = (Double(3 - k) - f) * passLen
      state = .playing("▶ \(k + 1) of 3  ·  0:0\(Int(left.rounded())) left", f)
    }
  }

  desktop(app: "Mail")
  mailWindow(answered: answered, slide: slide, selected: selected, typed: typed, pressed: pressed)
  hud(HUDX, HUDY, state)
  if menu > 0.01 {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(menu))
    let mx = HUDX + 70, my = HUDY + 84
    shadow(16, 6, 0.3) { box(mx, my, 190, 268, hex(0xf2f2f7, 0.97), r: 8) }
    var y = my + 8
    func head(_ s: String) { text(s, mx + 12, y, 11, hex(0x8e8e93), weight: .semibold); y += 20 }
    func item(_ s: String, on: Bool, hot: Bool = false) {
      if hot { box(mx + 5, y - 2, 180, 20, hex(0x0a84ff), r: 4) }
      if on { text("✓", mx + 12, y, 13, hot ? hex(0xffffff) : hex(0x1d1d1f)) }
      text(s, mx + 30, y, 13, hot ? hex(0xffffff) : hex(0x1d1d1f)); y += 20
    }
    let after = t >= 7.25, after2 = t >= 7.75
    head("Speed")
    item("1× (as recorded)", on: !after); item("2×", on: after, hot: t > 7.0 && t < 7.4); item("4×", on: false)
    item("Custom…", on: false)
    y += 6; head("Repeat")
    item("Once", on: !after2); item("2 times", on: false); item("3 times", on: after2, hot: t > 7.5 && t < 7.9)
    item("Continuously", on: false)
    NSGraphicsContext.restoreGraphicsState()
  }
  banner("Record one reply", alpha: fade(t, 0.2, 5.7))
  banner("Pick a speed and a repeat count", alpha: fade(t, 5.9, 8.2))
  banner("Replay: 2×, 3 times", alpha: fade(t, 8.3, 15.2))
  banner("Inbox zero", alpha: fade(t, 15.2, 17.0))
  keyCaption(["⌃", "⌥", "⇧", "R"], "start recording", alpha: fade(t, 0.7, 1.8))
  keyCaption(["⌃", "⌥", "⇧", "R"], "stop recording", alpha: fade(t, 5.5, 6.4))
  keyCaption(["⌃", "⌥", "⇧", "P"], "play", alpha: fade(t, 8.1, 9.2))
  cursor(cx, cy, pressed: down)
}

// MARK: main

let args = CommandLine.arguments
guard args.count == 3, ["remind", "email"].contains(args[1]) else {
  FileHandle.standardError.write(Data("usage: swift demo/render.swift remind|email OUT_DIR\n".utf8)); exit(2)
}
let scene = args[1], out = args[2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let seconds = 17.0
for f in 0..<Int(seconds * FPS) {
  let t = Double(f) / FPS
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  scene == "remind" ? sceneRemind(t) : sceneEmail(t)
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/frame-%04d.png", out, f)))
}
print("\(scene): \(Int(seconds * FPS)) frames in \(out)")
