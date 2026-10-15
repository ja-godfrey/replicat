// Replicat - a TinyTask-style macro recorder for macOS.
//
// A small floating toolbar (Open, Save, Record, Play, settings) plus a menu-bar
// icon that turns red while recording and green while playing. Records the mouse
// and keyboard exactly as you did them, timing included, and plays them back.
//
//   ⌃⌥⇧R  start / stop recording        (TinyTask: Ctrl+Shift+Alt+R)
//   ⌃⌥⇧P  start / stop playback         (TinyTask: Ctrl+Shift+Alt+P)
//   Esc   stops playback; so does moving the mouse or clicking (can be turned off)
//
// Each event is stored as macOS's own serialized CGEvent, so playback reproduces
// clicks, double-clicks, drags, scrolling, modifier keys and typing faithfully.
// Events Replicat posts are tagged, so they're never re-recorded and never trip the
// stop-on-mouse-move guard. The hotkeys and clicks on Replicat itself are left out.
//
// Settings (gear menu): speed (presets or any decimal), repeat count, trim to the
// first and last click/key (default on; the full recording is always kept, so
// turning it off brings the edges back), stop when the mouse moves, and a 3-2-1
// countdown. Recordings remember the screen layout they were made on; playing on
// a different layout (e.g. TV off, laptop only) asks first.
//
// Files: .replicat (binary plist). The last recording is kept automatically in
// ~/Library/Application Support/Replicat/last.replicat and reloaded at launch.
// Needs one permission: Accessibility.
import Cocoa
import Carbon.HIToolbox

let TAG: Int64 = 0x5245_5043_4154                // "REPCAT": marks events we post
let SUPPORT = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("Replicat")
let LAST = SUPPORT.appendingPathComponent("last.replicat")
let HOTKEY_MODS: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
let MODMASK: UInt64 = CGEventFlags([.maskShift, .maskControl, .maskAlternate, .maskCommand]).rawValue
let LOOP_GAP = 0.15                               // seconds between repeats
let LOGFILE = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Replicat.log")

/// Window and app lifecycle, so a toolbar that vanishes can be explained afterwards.
func trace(_ s: String) {
  let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  let line = "\(f.string(from: Date())) \(s)\n"
  if let h = try? FileHandle(forWritingTo: LOGFILE) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
  else { try? line.write(to: LOGFILE, atomically: true, encoding: .utf8) }
}

func clock(_ s: Double) -> String { let n = max(0, Int(s.rounded())); return String(format: "%d:%02d", n / 60, n % 60) }

// MARK: - Model

struct Step {
  var t: Double                                   // seconds from the start
  var data: Data                                  // the serialized CGEvent
  private(set) var type: CGEventType = .null
  private(set) var mods: UInt64 = 0               // modifier keys held, after this event
  private(set) var at: CGPoint = .zero

  init(t: Double, data: Data) {
    self.t = t; self.data = data
    if let e = CGEvent(withDataAllocator: nil, data: data as CFData) {
      type = e.type; mods = e.flags.rawValue & MODMASK; at = e.location
    }
  }
  func retimed(_ t: Double) -> Step { var s = self; s.t = t; return s }

  var isClick: Bool { [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) }
  /// Something you did, as opposed to the pointer travelling or a modifier changing.
  var isAction: Bool {
    isClick || [.leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel, .keyDown, .keyUp].contains(type)
  }
}

struct Macro {
  var steps: [Step] = []                          // the full recording, never trimmed
  var screens: [CGRect]? = nil                    // display layout it was recorded on

  /// The recording from the first click/key to the last one. Modifier keys held
  /// going into the first action come along (shift-click stays a shift-click), as
  /// do releases right after the last one (no stuck ⌘ between loops).
  var trimmed: [Step] {
    guard let a = steps.firstIndex(where: { $0.isAction }),
          let z = steps.lastIndex(where: { $0.isAction }) else { return steps }
    let t0 = steps[a].t, tz = steps[z].t
    var out = steps[..<a].filter { $0.type == .flagsChanged }.map { $0.retimed(t0) }
    out += steps[a...z]
    out += steps[(z + 1)...].filter { $0.type == .flagsChanged }.map { $0.retimed(min($0.t, tz + 0.05)) }
    return out.map { $0.retimed($0.t - t0) }
  }
}

enum MacroFile {
  static func write(_ m: Macro, to url: URL) throws {
    var p: [String: Any] = ["format": "replicat", "version": 2,
                            "steps": m.steps.map { ["t": $0.t, "d": $0.data] as [String: Any] }]
    if let s = m.screens { p["screens"] = s.map { [$0.minX, $0.minY, $0.width, $0.height] } }
    let d = try PropertyListSerialization.data(fromPropertyList: p, format: .binary, options: 0)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try d.write(to: url, options: .atomic)
  }
  static func read(_ url: URL) throws -> Macro {
    let d = try Data(contentsOf: url)
    guard let p = try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
          let arr = p["steps"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
    var m = Macro()
    m.steps = arr.compactMap { s in
      guard let t = s["t"] as? Double, let d = s["d"] as? Data else { return nil }
      return Step(t: t, data: d)
    }
    m.screens = (p["screens"] as? [[Double]])?.compactMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
    return m
  }
}

/// The active displays, in global coordinates, in a stable order.
func currentScreens() -> [CGRect] {
  var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
  CGGetActiveDisplayList(16, &ids, &n)
  return ids.prefix(Int(n)).map { CGDisplayBounds($0).integral }.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
}
func describe(_ screens: [CGRect]) -> String {
  "\(screens.count) screen\(screens.count == 1 ? "" : "s") (" +
  screens.map { "\(Int($0.width))×\(Int($0.height))" }.joined(separator: " + ") + ")"
}

// MARK: - Recording

final class Recorder {
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var start: UInt64 = 0
  private var down = Set<Int64>()               // key codes pressed during the recording
  private var steps: [Step] = []
  var ignore: () -> [CGRect] = { [] }           // Replicat's toolbar and menu-bar icon, CG coordinates

  var isRecording: Bool { tap != nil }
  var elapsed: Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 }

  func begin() -> Bool {
    let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown,
      .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
      .otherMouseDragged, .scrollWheel, .keyDown, .keyUp, .flagsChanged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    steps = []; down = []
    start = DispatchTime.now().uptimeNanoseconds
    let me = Unmanaged.passUnretained(self).toOpaque()
    // An active (default) tap only needs Accessibility; it passes every event on untouched.
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, me in
          Unmanaged<Recorder>.fromOpaque(me!).takeUnretainedValue().saw(type, event)
          return Unmanaged.passUnretained(event)
        }, userInfo: me) else { return false }
    tap = t
    source = CFMachPortCreateRunLoopSource(nil, t, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    return true
  }

  private func saw(_ type: CGEventType, _ e: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return
    }
    if e.getIntegerValueField(.eventSourceUserData) == TAG { return }      // our own playback
    let code = e.getIntegerValueField(.keyboardEventKeycode)
    switch type {
    case .keyDown, .keyUp:
      // The record/play hotkeys stay out of the macro.
      if (code == Int64(kVK_ANSI_R) || code == Int64(kVK_ANSI_P)) && e.flags.isSuperset(of: HOTKEY_MODS) { return }
      if type == .keyDown { down.insert(code) }
      else if !down.contains(code) { return }   // a key already held when recording began
      else { down.remove(code) }
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
      if ignore().contains(where: { $0.contains(e.location) }) { return }  // clicks on Replicat itself
    default: break
    }
    guard let d = e.data as Data? else { return }
    steps.append(Step(t: elapsed, data: d))
  }

  /// Stop, and return the recording with the hotkeys' own modifier presses removed.
  func end() -> [Step] {
    if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil; source = nil
    var s = steps
    // Modifier changes in the first moment are the start hotkey being let go.
    while let f = s.first, f.type == .flagsChanged, f.t < 1.0 { s.removeFirst() }
    // After the last real event, keep modifier releases (the end of your last
    // shortcut) but stop at the first press: that's the stop hotkey going down,
    // and left in it would replay as a stuck key.
    guard let last = s.lastIndex(where: { $0.type != .flagsChanged }) else { return [] }
    var keep = Array(s[...last]); var held = s[last].mods
    for st in s[(last + 1)...] {
      if st.mods & ~held != 0 { break }
      keep.append(st); held = st.mods
    }
    let t0 = keep.first?.t ?? 0
    return keep.map { $0.retimed($0.t - t0) }
  }
}

// MARK: - Playback

final class Player {
  private let lock = NSLock()
  private var _stop = false, _round = 0, _loopStart: UInt64 = 0
  private(set) var stoppedBy: String?
  private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }
  private var stop: Bool { locked { _stop } }
  var round: Int { locked { _round } }
  var loopStart: UInt64 { locked { _loopStart } }
  private(set) var isPlaying = false

  // The guard: a tap that watches for you taking over (Esc, moving the mouse, clicking).
  var stopOnMouse = true
  private var guardTap: CFMachPort?, guardSource: CFRunLoopSource?
  private var moved = 0.0, lastMove: UInt64 = 0

  /// repeats: 0 = until stopped.
  func play(_ steps: [Step], speed: Double, repeats: Int, done: @escaping (String?) -> Void) {
    guard !steps.isEmpty, !isPlaying else { return }
    isPlaying = true; stoppedBy = nil
    locked { _stop = false; _round = 0 }
    startGuard()
    let events = steps.compactMap { s in CGEvent(withDataAllocator: nil, data: s.data as CFData).map { (s.t, $0) } }
    Thread.detachNewThread { [self] in
      var round = 0
      while !stop && (repeats == 0 || round < repeats) {
        round += 1
        let base = DispatchTime.now().uptimeNanoseconds
        locked { _round = round; _loopStart = base }
        for (t, e) in events {
          let target = base + UInt64(t / speed * 1e9)
          while !stop {                              // sleep in short slices so stop is quick
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= target { break }
            usleep(UInt32(min(target - now, 20_000_000) / 1000))
          }
          if stop { break }
          e.setIntegerValueField(.eventSourceUserData, value: TAG)
          e.timestamp = mach_absolute_time()
          e.post(tap: .cghidEventTap)
        }
        if !stop && (repeats == 0 || round < repeats) { usleep(UInt32(LOOP_GAP * 1e6)) }
      }
      releaseModifiers()
      DispatchQueue.main.async {
        self.stopGuard(); self.isPlaying = false
        done(self.stoppedBy)
      }
    }
  }

  func cancel(_ why: String? = nil) {
    lock.lock()
    if !_stop { _stop = true; if stoppedBy == nil { stoppedBy = why } }
    lock.unlock()
  }

  private func startGuard() {
    let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                .leftMouseDown, .rightMouseDown, .otherMouseDown]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    moved = 0; lastMove = 0
    let me = Unmanaged.passUnretained(self).toOpaque()
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, me in
          let p = Unmanaged<Player>.fromOpaque(me!).takeUnretainedValue()
          return p.watch(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: me) else { return }
    guardTap = t
    guardSource = CFMachPortCreateRunLoopSource(nil, t, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), guardSource, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
  }

  private func stopGuard() {
    if let guardTap { CGEvent.tapEnable(tap: guardTap, enable: false); CFMachPortInvalidate(guardTap) }
    if let guardSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), guardSource, .commonModes) }
    guardTap = nil; guardSource = nil
  }

  /// true = swallow the event (only the Esc that stops playback).
  private func watch(_ type: CGEventType, _ e: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let guardTap { CGEvent.tapEnable(tap: guardTap, enable: true) }
      return false
    }
    if e.getIntegerValueField(.eventSourceUserData) == TAG { return false }   // ours
    switch type {
    case .keyDown where e.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape):
      cancel("Esc"); return true
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
      guard stopOnMouse else { return false }
      // A real push of the mouse, not sensor jitter: 12 px within half a second.
      let now = DispatchTime.now().uptimeNanoseconds
      if now - lastMove > 500_000_000 { moved = 0 }
      lastMove = now
      moved += abs(Double(e.getIntegerValueField(.mouseEventDeltaX))) + abs(Double(e.getIntegerValueField(.mouseEventDeltaY)))
      if moved > 12 { cancel("you moved the mouse") }
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      if stopOnMouse { cancel("you clicked") }
    default: break
    }
    return false
  }

  /// If playback stopped mid-shortcut, let go of any modifier it was holding.
  private func releaseModifiers() {
    let src = CGEventSource(stateID: .hidSystemState)
    for code in [kVK_Shift, kVK_Control, kVK_Option, kVK_Command, kVK_RightShift,
                 kVK_RightControl, kVK_RightOption, kVK_RightCommand] {
      guard CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code)) else { continue }
      let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: false)
      e?.type = .flagsChanged; e?.flags = []
      e?.setIntegerValueField(.eventSourceUserData, value: TAG)
      e?.post(tap: .cghidEventTap)
    }
  }
}

// MARK: - Hotkeys (Carbon: global, no extra permission, and they don't leak into apps)

final class Hotkeys {
  private var refs: [EventHotKeyRef?] = []
  private static var actions: [UInt32: () -> Void] = [:]

  func register(_ key: Int, id: UInt32, _ action: @escaping () -> Void) {
    Hotkeys.actions[id] = action
    if refs.isEmpty {
      var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var hk = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
        Hotkeys.actions[hk.id]?()
        return noErr
      }, 1, &spec, nil, nil)
    }
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | shiftKey),
                        EventHotKeyID(signature: OSType(0x52504354), id: id), GetApplicationEventTarget(), 0, &ref)
    refs.append(ref)
  }
}

// MARK: - Toolbar views

/// Never takes the keyboard: after clicking it, typing still goes to the app you were in.
final class ToolbarPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  var onClick: () -> Void = {}
  override func sendEvent(_ e: NSEvent) {
    if e.type == .leftMouseDown || e.type == .rightMouseDown { onClick() }
    super.sendEvent(e)
  }
}

/// The ring drawn while the toolbar is selected (it never takes focus from your app,
/// so window-border tools don't ring it). Defaults to the system accent colour;
/// match your own border tool with e.g.
///   defaults write io.github.ja-godfrey.replicat focusRingColor "#e06c75"
var FOCUS_RING: NSColor {
  guard let hex = UserDefaults.standard.string(forKey: "focusRingColor")?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")),
        hex.count == 6, let v = UInt32(hex, radix: 16) else { return .controlAccentColor }
  return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

/// The toolbar's frosted background; drag anywhere that isn't a button.
final class Backdrop: NSVisualEffectView { override var mouseDownCanMoveWindow: Bool { true } }

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var panel: ToolbarPanel!
  let backdrop = Backdrop()
  let status = NSTextField(labelWithString: "")
  let hint = NSTextField(labelWithString: "")           // the keys that matter right now
  let bar = NSView()                                    // thin playback progress line
  var recBtn: NSButton!, playBtn: NSButton!, prefsBtn: NSButton!
  var statusItem: NSStatusItem!
  let recorder = Recorder(), player = Player(), hotkeys = Hotkeys()
  var macro = Macro()
  var fileName: String?
  var countdown = 0                                     // seconds left before playback starts
  var notice: (String, Date)?                           // e.g. "Stopped: Esc", shown briefly
  var ticker: Timer?
  var toolbarHidden = false
  var selected = false                                  // you last clicked the toolbar

  // ---- settings ----
  let defaults = UserDefaults.standard
  var speed: Double {
    get { let v = defaults.double(forKey: "speed"); return v > 0 ? v : 1 }
    set { defaults.set(newValue, forKey: "speed") }
  }
  var repeats: Int {                                   // 0 = continuous
    get { defaults.object(forKey: "repeats") as? Int ?? 1 }
    set { defaults.set(newValue, forKey: "repeats") }
  }
  var trim: Bool { get { defaults.object(forKey: "trim") as? Bool ?? true } set { defaults.set(newValue, forKey: "trim") } }
  var stopOnMouse: Bool { get { defaults.object(forKey: "stopOnMouse") as? Bool ?? true } set { defaults.set(newValue, forKey: "stopOnMouse") } }
  var useCountdown: Bool { get { defaults.bool(forKey: "countdown") } set { defaults.set(newValue, forKey: "countdown") } }

  var playable: [Step] { trim ? macro.trimmed : macro.steps }
  var length: Double { playable.last?.t ?? 0 }        // one pass, at 1×

  func applicationDidFinishLaunching(_ n: Notification) {
    buildMenu()
    buildPanel()
    buildStatusItem()
    ProcessInfo.processInfo.disableAutomaticTermination("toolbar app")
    ProcessInfo.processInfo.disableSuddenTermination()
    trace("launch")
    macro = (try? MacroFile.read(LAST)) ?? Macro()
    hotkeys.register(kVK_ANSI_R, id: 1) { [weak self] in self?.toggleRecord() }
    hotkeys.register(kVK_ANSI_P, id: 2) { [weak self] in self?.togglePlay() }
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
      // Notice the moment Accessibility is granted, then stop checking.
      Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
        guard AXIsProcessTrusted() else { return }
        t.invalidate(); self?.refresh()
      }
    }
    refresh()
  }

  // Replicat stays running if the toolbar is hidden; the Dock icon or menu-bar icon brings it back.
  func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
    toolbarHidden = false; showPanel(); return true
  }
  func applicationWillTerminate(_ n: Notification) { trace("quit") }
  func applicationDidHide(_ n: Notification) { trace("app hidden (⌘H or Hide Others) - unhiding"); NSApp.unhide(nil) }
  func windowDidResignKey(_ n: Notification) { selected = false; refresh() }
  func windowDidChangeScreen(_ n: Notification) { trace("toolbar moved to screen \(panel.screen?.localizedName ?? "?") at \(panel.frame)") }
  func windowDidChangeOcclusionState(_ n: Notification) {
    trace("toolbar \(panel.occlusionState.contains(.visible) ? "visible" : "NOT visible") at \(panel.frame)")
  }
  func application(_ s: NSApplication, openFile path: String) -> Bool { load(URL(fileURLWithPath: path)) }

  // ---- toolbar ----
  func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
    let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
    b.isBordered = false; b.toolTip = tip
    b.symbolConfiguration = .init(pointSize: 15, weight: .medium)
    b.contentTintColor = .labelColor
    b.widthAnchor.constraint(equalToConstant: 30).isActive = true
    b.heightAnchor.constraint(equalToConstant: 26).isActive = true
    return b
  }
  func divider() -> NSView {
    let v = NSBox(); v.boxType = .separator
    v.widthAnchor.constraint(equalToConstant: 1).isActive = true
    v.heightAnchor.constraint(equalToConstant: 16).isActive = true
    return v
  }

  func buildPanel() {
    panel = ToolbarPanel(contentRect: NSRect(x: 0, y: 0, width: 224, height: 58),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    panel.isMovableByWindowBackground = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.delegate = self
    panel.onClick = { [weak self] in self?.selected = true; self?.refresh() }
    // The toolbar never takes focus from your app, so "selected" ends at your next
    // click or keypress anywhere else (another app, or the same app you were in).
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
      guard let self, self.selected else { return }
      self.selected = false; self.refresh()
    }
    // Clicking any other app deselects it, like a normal window losing focus.
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                      object: nil, queue: .main) { [weak self] n in
      let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      guard let self, app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
      self.selected = false; self.refresh()
    }

    backdrop.material = .hudWindow
    backdrop.blendingMode = .behindWindow
    backdrop.state = .active
    backdrop.wantsLayer = true
    backdrop.layer?.cornerRadius = 12
    backdrop.layer?.masksToBounds = true
    backdrop.layer?.borderWidth = 1.5
    backdrop.layer?.borderColor = NSColor.clear.cgColor

    recBtn = button("record.circle", "Record / stop  ⌃⌥⇧R", #selector(toggleRecord))
    playBtn = button("play.fill", "Play / stop  ⌃⌥⇧P   (Esc also stops)", #selector(togglePlay))
    prefsBtn = button("slider.horizontal.3", "Speed, repeat and options", #selector(showPrefs(_:)))
    let row = NSStackView(views: [button("folder", "Open…  ⌘O", #selector(openDoc)),
                                  button("square.and.arrow.down", "Save…  ⌘S", #selector(saveDoc)),
                                  divider(), recBtn, playBtn, divider(), prefsBtn])
    row.spacing = 4
    status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    status.textColor = .secondaryLabelColor
    status.lineBreakMode = .byTruncatingTail
    status.alignment = .center
    hint.lineBreakMode = .byTruncatingTail
    hint.alignment = .center
    hint.widthAnchor.constraint(equalToConstant: 204).isActive = true
    let col = NSStackView(views: [row, hint, status])
    col.orientation = .vertical; col.alignment = .centerX; col.spacing = 3
    col.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 8, right: 10)
    col.translatesAutoresizingMaskIntoConstraints = false
    status.widthAnchor.constraint(equalToConstant: 204).isActive = true

    backdrop.addSubview(col)
    NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
                                 col.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
                                 col.topAnchor.constraint(equalTo: backdrop.topAnchor),
                                 col.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)])
    bar.wantsLayer = true
    bar.layer?.backgroundColor = NSColor.systemGreen.cgColor
    backdrop.addSubview(bar)
    panel.contentView = backdrop
    panel.setContentSize(backdrop.fittingSize)

    panel.setFrameAutosaveName("ReplicatHUD")
    if !panel.setFrameUsingName("ReplicatHUD") { panel.center() }
    panel.setContentSize(backdrop.fittingSize)          // the saved frame may predate a layout change
    panel.orderFrontRegardless()

    recorder.ignore = { [weak self] in
      guard let self, let h = NSScreen.screens.first?.frame.height else { return [] }
      let flip = { (f: NSRect) in CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height) }
      var r = [flip(self.panel.frame)]
      if let w = self.statusItem.button?.window { r.append(flip(w.frame)) }
      return r
    }
  }

  @objc func showPanel() {
    guard !toolbarHidden else { return }
    panel.level = .floating; panel.orderFrontRegardless()
  }
  @objc func toggleToolbar() {
    toolbarHidden.toggle()
    if toolbarHidden { panel.orderOut(nil) } else { showPanel() }
  }

  // ---- menu-bar icon ----
  func buildStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
  }

  /// One click on the menu-bar icon stops whatever is running; otherwise it opens the menu.
  @objc func statusClicked() {
    if recorder.isRecording { toggleRecord(); return }
    if player.isPlaying || countdown > 0 { togglePlay(); return }
    let m = NSMenu()
    m.addItem(withTitle: "Record  ⌃⌥⇧R", action: #selector(toggleRecord), keyEquivalent: "").target = self
    let p = m.addItem(withTitle: "Play  ⌃⌥⇧P", action: macro.steps.isEmpty ? nil : #selector(togglePlay), keyEquivalent: "")
    p.target = self
    m.addItem(.separator())
    m.addItem(withTitle: "Open…", action: #selector(openDoc), keyEquivalent: "").target = self
    m.addItem(withTitle: "Save…", action: macro.steps.isEmpty ? nil : #selector(saveDoc), keyEquivalent: "").target = self
    m.addItem(withTitle: toolbarHidden ? "Show Toolbar" : "Hide Toolbar", action: #selector(toggleToolbar), keyEquivalent: "").target = self
    m.addItem(.separator())
    m.addItem(withTitle: "Quit Replicat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    if let b = statusItem.button { m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 5), in: b) }
  }

  func buildMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Replicat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let fileItem = NSMenuItem(); main.addItem(fileItem)
    let file = NSMenu(title: "File")
    file.addItem(withTitle: "Open…", action: #selector(openDoc), keyEquivalent: "o")
    file.addItem(withTitle: "Save…", action: #selector(saveDoc), keyEquivalent: "s")
    file.addItem(withTitle: "Show/Hide Toolbar", action: #selector(toggleToolbar), keyEquivalent: "0")
    fileItem.submenu = file
    NSApp.mainMenu = main
  }

  // ---- settings menu ----
  @objc func showPrefs(_ sender: NSButton) {
    let m = NSMenu()
    m.addItem(.sectionHeader(title: "Speed"))
    let presets: [(String, Double)] = [("½×", 0.5), ("1× (as recorded)", 1), ("2×", 2), ("4×", 4), ("10×", 10), ("100× (fastest)", 100)]
    for (label, v) in presets {
      let i = m.addItem(withTitle: label, action: #selector(setSpeed(_:)), keyEquivalent: "")
      i.representedObject = v; i.state = speed == v ? .on : .off
    }
    let custom = presets.contains { $0.1 == speed }
    let c = m.addItem(withTitle: custom ? "Custom…" : "Custom (\(fmt(speed)))…", action: #selector(customSpeed), keyEquivalent: "")
    c.state = custom ? .off : .on
    m.addItem(.separator())
    m.addItem(.sectionHeader(title: "Repeat"))
    for (label, v) in [("Once", 1), ("2 times", 2), ("3 times", 3), ("5 times", 5), ("10 times", 10),
                       ("25 times", 25), ("100 times", 100), ("Continuously", 0)] {
      let i = m.addItem(withTitle: label, action: #selector(setRepeats(_:)), keyEquivalent: "")
      i.representedObject = v; i.state = repeats == v ? .on : .off
    }
    m.addItem(.separator())
    m.addItem(.sectionHeader(title: "Options"))
    m.addItem(withTitle: "Trim to first and last click or key", action: #selector(toggleTrim), keyEquivalent: "").state = trim ? .on : .off
    m.addItem(withTitle: "Stop when I move the mouse or click", action: #selector(toggleStopOnMouse), keyEquivalent: "").state = stopOnMouse ? .on : .off
    m.addItem(withTitle: "3-2-1 countdown before playing", action: #selector(toggleCountdown), keyEquivalent: "").state = useCountdown ? .on : .off
    let note = m.addItem(withTitle: "Esc always stops playback", action: nil, keyEquivalent: "")
    note.isEnabled = false
    m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
  }
  @objc func setSpeed(_ i: NSMenuItem) { speed = i.representedObject as! Double; refresh() }
  @objc func setRepeats(_ i: NSMenuItem) { repeats = i.representedObject as! Int; refresh() }
  @objc func toggleTrim() { trim.toggle(); refresh() }
  @objc func toggleStopOnMouse() { stopOnMouse.toggle() }
  @objc func toggleCountdown() { useCountdown.toggle() }

  /// "1.34×", "0.5×", "2×": as typed, no trailing zeros.
  func fmt(_ v: Double) -> String { v == 0.5 ? "½×" : String(format: "%g×", v) }

  /// Any speed, typed as a number: 1.34 = 34% faster, 0.75 = slower.
  @objc func customSpeed() {
    let a = NSAlert()
    a.messageText = "Playback speed"
    a.informativeText = "Any number from 0.01 to 1000. 1 plays as recorded, 1.34 is 34% faster, 0.75 is slower."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
    field.stringValue = String(format: "%g", speed)
    a.accessoryView = field
    a.addButton(withTitle: "Set"); a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = field
    NSApp.activate(ignoringOtherApps: true)
    guard a.runModal() == .alertFirstButtonReturn else { return }
    let text = field.stringValue.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "×", with: "").replacingOccurrences(of: "x", with: "")
      .replacingOccurrences(of: ",", with: ".")
    guard let v = Double(text), v >= 0.01, v <= 1000 else { NSSound.beep(); return }
    speed = v; refresh()
  }

  // ---- state → UI ----
  func refresh() {
    let recording = recorder.isRecording, playing = player.isPlaying, counting = countdown > 0
    let busy = recording || playing || counting
    recBtn.image = NSImage(systemSymbolName: recording ? "stop.circle.fill" : "record.circle", accessibilityDescription: nil)
    recBtn.contentTintColor = .systemRed
    playBtn.image = NSImage(systemSymbolName: playing || counting ? "stop.fill" : "play.fill", accessibilityDescription: nil)
    playBtn.contentTintColor = playing || counting ? .systemGreen : .labelColor
    playBtn.isEnabled = !recording && (!macro.steps.isEmpty || playing || counting)
    recBtn.isEnabled = !playing && !counting
    prefsBtn.isEnabled = !busy
    // Outline: red while recording, green while playing, else the focus ring when selected.
    let ring: NSColor = recording ? .systemRed : playing || counting ? .systemGreen : selected ? FOCUS_RING : .clear
    backdrop.layer?.borderColor = ring.cgColor
    backdrop.layer?.borderWidth = busy || selected ? 3 : 0

    // Progress line along the bottom edge while playing.
    var fraction = 0.0
    if playing, length > 0 {
      let el = Double(DispatchTime.now().uptimeNanoseconds &- player.loopStart) / 1e9 * speed
      fraction = min(1, max(0, el / length))
    }
    let w = backdrop.bounds.width
    bar.isHidden = !playing
    bar.frame = NSRect(x: 0, y: 0, width: w * fraction, height: 3)

    let rep = repeats == 0 ? "loop" : repeats == 1 ? "once" : "\(repeats)×"
    let mouseToo = stopOnMouse ? " (or move the mouse)" : ""
    var keys: [(String, String)] = []                  // what to press now, most likely first
    var info = ""
    let trusted = AXIsProcessTrusted()
    if !trusted {
      keys = [("Accessibility", "needed")]
      info = "Settings › Privacy & Security"
    } else if recording {
      keys = [("⌃⌥⇧R", "stop recording")]
      info = "● Recording  \(clock(recorder.elapsed))"
    } else if counting {
      keys = [("Esc", "cancel")]
      info = "Playing in \(countdown)…"
    } else if playing {
      keys = [("Esc", "stop" + mouseToo)]
      let r = player.round
      let leftThis = (1 - fraction) * length / speed
      let left = repeats == 0 ? leftThis : leftThis + Double(max(0, repeats - r)) * (length / speed + LOOP_GAP)
      let loops = repeats == 1 ? "" : repeats == 0 ? "loop \(r)  ·  " : "\(r) of \(repeats)  ·  "
      info = "▶ \(loops)\(clock(left)) left"
    } else if macro.steps.isEmpty {
      keys = [("⌃⌥⇧R", "record")]
      info = "Nothing recorded yet"
    } else {
      keys = [("⌃⌥⇧P", "play"), ("⌃⌥⇧R", "re-record")]
      info = "\(fileName ?? "Recording")  ·  \(clock(length / speed))  ·  \(fmt(speed))  ·  \(rep)"
    }
    if let (text, until) = notice, until > Date(), !busy { info = text }
    hint.attributedStringValue = keyLine(keys, accent: !trusted ? .systemOrange : recording ? .systemRed : playing || counting ? .systemGreen : .labelColor)
    status.stringValue = info

    // Menu-bar icon: grey when idle, red while recording, green while playing.
    if let b = statusItem?.button {
      let (sym, tint, title): (String, NSColor?, String) =
        recording ? ("record.circle.fill", .systemRed, " \(clock(recorder.elapsed))")
        : counting ? ("play.circle.fill", .systemGreen, " \(countdown)")
        : playing ? ("play.circle.fill", .systemGreen, repeats == 1 ? "" : " \(player.round)/\(repeats == 0 ? "∞" : String(repeats))")
        : ("record.circle", nil, "")
      let img = NSImage(systemSymbolName: sym, accessibilityDescription: "Replicat")
      img?.isTemplate = tint == nil
      b.image = img; b.contentTintColor = tint; b.title = title
    }
  }

  /// "⌃⌥⇧P play   ⌃⌥⇧R re-record": keys bold (in the state's colour), words quieter.
  func keyLine(_ keys: [(String, String)], accent: NSColor) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for (i, (k, what)) in keys.enumerated() {
      if i > 0 { out.append(NSAttributedString(string: "    ")) }
      out.append(NSAttributedString(string: k, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: accent]))
      out.append(NSAttributedString(string: " " + what, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: i == 0 ? NSColor.labelColor : NSColor.secondaryLabelColor]))
    }
    let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
    out.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: out.length))
    return out
  }

  /// While anything is running, keep the clock, progress and countdown moving.
  func startTicker(_ every: Double) {
    ticker?.invalidate()
    ticker = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in self?.refresh() }
  }
  func stopTicker() { ticker?.invalidate(); ticker = nil }

  // ---- actions ----
  @objc func toggleRecord() {
    if player.isPlaying || countdown > 0 { return }
    if recorder.isRecording {
      stopTicker()
      macro = Macro(steps: recorder.end(), screens: currentScreens()); fileName = nil
      try? MacroFile.write(macro, to: LAST)
      if macro.steps.isEmpty { notice = ("Nothing recorded", Date().addingTimeInterval(4)) }
    } else {
      guard AXIsProcessTrusted(), recorder.begin() else { NSSound.beep(); refresh(); return }
      startTicker(1)
    }
    showPanel(); refresh()
  }

  @objc func togglePlay() {
    if recorder.isRecording { return }
    if countdown > 0 { countdown = 0; stopTicker(); notice = ("Cancelled", Date().addingTimeInterval(3)); refresh(); return }
    if player.isPlaying { player.cancel("⌃⌥⇧P"); return }
    guard AXIsProcessTrusted(), !macro.steps.isEmpty else { NSSound.beep(); refresh(); return }
    guard screensOK() else { return }
    if useCountdown {
      countdown = 3
      stopTicker()
      ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
        guard let self else { t.invalidate(); return }
        self.countdown -= 1
        if self.countdown <= 0 { t.invalidate(); self.countdown = 0; self.startPlaying() } else { self.refresh() }
      }
      // Esc cancels the countdown too.
      if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
        if e.keyCode == UInt16(kVK_Escape), let self, self.countdown > 0 { self.togglePlay() }
      }) { DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { NSEvent.removeMonitor(m) } }
      showPanel(); refresh()
    } else {
      startPlaying()
    }
  }

  func startPlaying() {
    player.stopOnMouse = stopOnMouse
    player.play(playable, speed: speed, repeats: repeats) { [weak self] why in
      guard let self else { return }
      self.stopTicker()
      if let why { self.notice = ("Stopped: \(why)", Date().addingTimeInterval(4)) }
      self.showPanel(); self.refresh()
      DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) { [weak self] in self?.refresh() }
    }
    startTicker(0.1)
    showPanel(); refresh()
  }

  /// Recorded on a different screen layout? Clicks are absolute positions, so ask first.
  func screensOK() -> Bool {
    let now = currentScreens()
    let clicks = playable.filter { $0.isClick }
    let off = clicks.filter { c in !now.contains { $0.contains(c.at) } }.count
    let sameLayout = macro.screens.map { $0 == now } ?? true
    guard !sameLayout || off > 0 else { return true }
    let a = NSAlert()
    a.messageText = sameLayout ? "Some clicks are off-screen" : "Recorded on a different screen setup"
    var info = ""
    if let then = macro.screens, !sameLayout { info = "Recorded on \(describe(then)); now \(describe(now)). " }
    info += off > 0 ? "\(off) of \(clicks.count) click\(clicks.count == 1 ? "" : "s") would land outside every screen. "
                    : "Clicks may land in different places. "
    info += "Turn the same screens on, or play anyway."
    a.informativeText = info
    a.alertStyle = .warning
    a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Play Anyway")
    NSApp.activate(ignoringOtherApps: true)
    return a.runModal() == .alertSecondButtonReturn
  }

  @objc func openDoc() {
    let p = NSOpenPanel()
    p.allowedContentTypes = [.init(filenameExtension: "replicat")!]
    p.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    NSApp.activate(ignoringOtherApps: true)
    if p.runModal() == .OK, let u = p.url { _ = load(u) }
  }

  @discardableResult func load(_ u: URL) -> Bool {
    guard let m = try? MacroFile.read(u), !m.steps.isEmpty else { NSSound.beep(); return false }
    macro = m; fileName = u.deletingPathExtension().lastPathComponent
    try? MacroFile.write(macro, to: LAST)
    refresh(); return true
  }

  @objc func saveDoc() {
    guard !macro.steps.isEmpty else { NSSound.beep(); return }
    let p = NSSavePanel()
    p.allowedContentTypes = [.init(filenameExtension: "replicat")!]
    p.nameFieldStringValue = (fileName ?? "macro") + ".replicat"
    p.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    NSApp.activate(ignoringOtherApps: true)
    if p.runModal() == .OK, let u = p.url {
      do { try MacroFile.write(macro, to: u); fileName = u.deletingPathExtension().lastPathComponent }
      catch { NSAlert(error: error).runModal() }
      refresh()
    }
  }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
