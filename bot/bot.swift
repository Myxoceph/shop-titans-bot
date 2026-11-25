// Craft bot. Screen in, ordinary mouse clicks out. Hold Esc to stop.
// Usage: bot <maxMinutes> <maxCrafts>
import AppKit
import ScreenCaptureKit
import Vision

let bundle = "com.ripostegames.shopr"
func plain(_ z: String) -> String { z.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")).filter { $0.isLetter || $0.isNumber } }
struct T { let s: String; let x, y: Double }
struct Shot { let img: CGImage; let t: [T]; let frame: CGRect
  func first(_ s: String) -> T? { t.first { $0.s == s } }
  // Punctuation, spaces, case and accents are ignored: OCR adds stray commas and drops spaces.
  func has(_ s: String) -> Bool { let k = plain(s); return t.contains { plain($0.s).contains(k) } }
  func one(_ n: String...) -> Bool { t.contains { n.contains($0.s) } }
  var buyer: Bool { has("wants to buy") || (one("Sell", "Restock") && first("Wait") != nil && (one("Surcharge") || one("Discount"))) }
  var seller: Bool { has("wants to sell") || (one("Buy") && first("Wait") != nil && (has("Pay less") || has("Pay more"))) }
  var header: String { t.filter { $0.y > 0.115 && $0.y < 0.165 && $0.x > 0.36 && $0.x < 0.7 }.max { $0.s.count < $1.s.count }?.s ?? "" }
}
var logFile: FileHandle?
func log(_ m: String) {
  let l = "\(ISO8601DateFormatter().string(from: Date())) \(m)\n"; print(l, terminator: "")
  logFile?.write(l.data(using: .utf8)!)
}
func tag() -> String { let f = DateFormatter(); f.dateFormat = "MMdd_HHmmss"; return f.string(from: Date()) }
func esc() -> Bool { CGEventSource.keyState(.combinedSessionState, key: 53) }
func save(_ i: CGImage, _ n: String) { try? NSBitmapImageRep(cgImage: i).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "logs/\(n).png")) }
func stop(_ why: String, _ s: Shot? = nil) -> Never {
  if let s { save(s.img, "stop"); save(s.img, "stop_\(tag())"); log("ekrandaki yazilar: \(s.t.map { $0.s })") }
  log("DURDU: \(why)"); exit(0)
}
func nap(_ s: Double) async { // polls Esc
  let end = Date().addingTimeInterval(s)
  while Date() < end { if esc() { stop("Esc") }; try? await Task.sleep(nanoseconds: 50_000_000) }
}
func front() -> Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle }
func activate() { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-b", bundle]; try? p.run(); p.waitUntilExit() }
func ocr(_ i: CGImage) -> [T] {
  let r = VNRecognizeTextRequest(); r.recognitionLevel = .accurate; r.usesLanguageCorrection = false
  try? VNImageRequestHandler(cgImage: i).perform([r])
  return (r.results ?? []).compactMap { o in o.topCandidates(1).first.map { T(s: $0.string, x: o.boundingBox.midX, y: 1 - o.boundingBox.midY) } }
}
func grab() async throws -> Shot? {
  let c = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
  guard let w = c.windows.filter({ $0.owningApplication?.bundleIdentifier == bundle && $0.windowLayer == 0 && $0.frame.height > 300 }).max(by: { $0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height }) else { return nil }
  let f = SCContentFilter(desktopIndependentWindow: w), k = SCStreamConfiguration(), z = CGFloat(f.pointPixelScale)
  k.width = Int(f.contentRect.width*z); k.height = Int(f.contentRect.height*z); k.showsCursor = false; k.ignoreShadowsSingleWindow = true
  let i = try await SCScreenshotManager.captureImage(contentFilter: f, configuration: k)
  return Shot(img: i, t: ocr(i), frame: w.frame)
}
func look() async -> Shot {
  for n in 1...5 {
    if esc() { stop("Esc") }
    if !front() { activate(); await nap(3) }
    if let s = try? await grab() { return s }
    log("yakalama basarisiz (\(n)/5)"); await nap(3)
  }
  stop("ekran yakalanamadi")
}
func crop(_ s: Shot, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ up: Int = 1) -> CGImage { // 0...1 fractions
  let W = Double(s.img.width), H = Double(s.img.height)
  let c = s.img.cropping(to: CGRect(x: x*W, y: y*H, width: w*W, height: h*H))!
  let cw = c.width*up, ch = c.height*up
  let g = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  g.interpolationQuality = .high; g.draw(c, in: CGRect(x: 0, y: 0, width: cw, height: ch)); return g.makeImage()!
}
func isCoin(_ s: Shot, _ x: Double, _ y: Double) -> Bool {
  let c = crop(s, x, y, 0.012, 0.017), d = c.dataProvider!.data! as Data; var t = [0,0,0]; let n = c.width*c.height
  for i in 0..<n { for k in 0..<3 { t[k] += Int(d[i*4+k]) } }
  return t[0]/n > 200 && t[2]/n < 110
}
func tap(_ s: Shot, _ x: Double, _ y: Double, _ why: String) async {
  // Never click the currency bar / gem "+" / hamburger, nor the Store and offer icons on the left.
  if y < 0.085 || (x < 0.165 && y > 0.2 && y < 0.45) { stop("yasak bolge (\(x),\(y)) \(why)", s) }
  if esc() { stop("Esc") }
  guard front() else { log("tiklama atlandi, oyun onde degil: \(why)"); return }
  let p = CGPoint(x: s.frame.minX + x*s.frame.width, y: s.frame.minY + y*s.frame.height)
  func e(_ t: CGEventType) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
  e(.mouseMoved); await nap(0.1); e(.leftMouseDown); await nap(0.1); e(.leftMouseUp)
  log("tik: \(why)")
}
func greenPlus(_ s: Shot) -> Bool {
  let c = crop(s, 0.838, 0.024, 0.025, 0.034), d = c.dataProvider!.data! as Data; let n = c.width*c.height; var k = 0
  for i in 0..<n { let r = Int(d[i*4]), g = Int(d[i*4+1]), b = Int(d[i*4+2]); if g > 120 && g > r + 50 && g > b + 40 { k += 1 } }
  return k * 4 > n
}
func gems(_ s: Shot) -> Int? { // only when the "+" sits next to it: some windows show gold in this spot
  guard s.t.contains(where: { $0.s == "+" && $0.y < 0.07 && abs($0.x-0.850) < 0.02 }) || greenPlus(s) else { return nil }
  return s.t.first { $0.y < 0.07 && abs($0.x - 0.805) < 0.015 }.flatMap { Int($0.s.replacingOccurrences(of: ",", with: "")) }
}
func blobs(_ s: Shot, _ xr: ClosedRange<Double>, _ yr: ClosedRange<Double>, scale: Int = 1, _ hit: (Int, Int, Int) -> Bool) -> [(x: Double, y: Double, w: Int, h: Int, n: Int, ring: Double)] {
  let gw = 294*scale, gh = 184*scale
  let g = CGContext(data: nil, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: gw*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  g.interpolationQuality = .high; g.draw(s.img, in: CGRect(x: 0, y: 0, width: gw, height: gh))
  let d = g.data!.assumingMemoryBound(to: UInt8.self)
  var on = [Bool](repeating: false, count: gw*gh)
  for y in Int(yr.lowerBound*Double(gh))..<Int(yr.upperBound*Double(gh)) { for x in Int(xr.lowerBound*Double(gw))..<Int(xr.upperBound*Double(gw)) {
    let i = (y*gw+x)*4; on[y*gw+x] = hit(Int(d[i]), Int(d[i+1]), Int(d[i+2]))
  } }
  var out: [(x: Double, y: Double, w: Int, h: Int, n: Int, ring: Double)] = []
  for k in 0..<gw*gh where on[k] {
    var mem: [Int] = []; var st = [k], n = 0, x0 = gw, x1 = 0, y0 = gh, y1 = 0; on[k] = false
    while let q = st.popLast() {
      let x = q % gw, y = q / gw; n += 1; mem.append(q); x0 = min(x0,x); x1 = max(x1,x); y0 = min(y0,y); y1 = max(y1,y)
      for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] { let u = x+dx, v = y+dy; if u >= 0, u < gw, v >= 0, v < gh, on[v*gw+u] { on[v*gw+u] = false; st.append(v*gw+u) } }
    }
    // ring: how much of the outer frame band of the bounding box (above the pointer) belongs to the blob
    let bw = x1-x0+1, bh = y1-y0+1, band = max(1, min(bw, bh)/7), yb = y0 + bh*80/100
    var inRing = 0, ringAll = 0
    func isRing(_ x: Int, _ y: Int) -> Bool { y <= yb && (x < x0+band || x > x1-band || y < y0+band) }
    for y in y0...y1 { for x in x0...x1 where isRing(x, y) { ringAll += 1 } }
    for q in mem where isRing(q % gw, q / gw) { inRing += 1 }
    out.append((Double(x0+x1)/2/Double(gw), Double(y0+y1)/2/Double(gh), x1-x0+1, y1-y0+1, n, Double(inRing)/Double(max(1, ringAll))))
  }
  return out
}
// Pale or yellow speech bubbles.
func bubbleDebug(_ s: Shot) -> [String] {
  blobs(s, 0.17...0.83, 0.12...0.8, scale: 3) { r, g, b in r > 222 && g > 215 && b > 195 && r-b < 40 || r > 220 && g > 210 && b > 90 && b < 165 && r-b > 70 }
    .filter { $0.n >= 120 && $0.w >= 16 && $0.h >= 12 }.map { String(format: "(%.3f,%.3f %dx%d n=%d ring=%.2f)", $0.x, $0.y, $0.w, $0.h, $0.n, $0.ring) }
}
func bubbles(_ s: Shot, _ big: Int = 31) -> [(x: Double, y: Double)] {
  func pale(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    if r > 222 && g > 215 && b > 195 && r-b < 40 { return true }
    return r > 220 && g > 210 && b > 90 && b < 165 && r-b > 70
  }
  var out: [(x: Double, y: Double)] = []
  for b in blobs(s, 0.17...0.83, 0.12...0.8, scale: 3, pale) {
    let w = Double(b.w), h = Double(b.h), n = Double(b.n)
    if b.ring < 0.6 || b.n < 180 || b.w < 20 || b.w > big*3 || b.h < 15 || b.h > big*3 { continue }
    if n < 0.22*w*h || w > 2.4*h || h > 1.9*w { continue }
    var skip = false
    for t in s.t {
      let dx = abs(t.x-b.x), dy = abs(t.y-b.y), done = t.s.hasPrefix("COMPLETE")
      if done { if dx < 0.07 && dy < 0.04 { skip = true }; continue }
      // Thought bubbles contain words; requests contain only a picture.
      let letters = t.s.filter { $0.isLetter }.count
      if letters >= 2 && dx < w/882/2 && dy < h/552/2 && secs(t.s) == nil { skip = true }
      // Toasts at the top centre.
      if b.y < 0.25 && dx < 0.12 && dy < 0.05 && t.s.count > 4 { skip = true }
    }
    if !skip { out.append((b.x, b.y)) }
  }
  return out
}
// Round red close button.
func redX(_ s: Shot) -> (x: Double, y: Double)? {
  blobs(s, 0.5...0.95, 0.09...0.5) { r, g, b in r > 200 && g > 50 && g < 120 && b < 90 }
    .filter { $0.w >= 9 && $0.w <= 18 && $0.h >= 9 && $0.h <= 18 && $0.n >= 50 }.max { $0.n < $1.n }.map { ($0.x, $0.y) }
}
// Gem buttons are cyan; only buttons whose background is plain green count as safe.
func greenAt(_ s: Shot, _ t: T) -> Bool {
  let c = crop(s, t.x-0.07, t.y-0.016, 0.02, 0.03), d = c.dataProvider!.data! as Data; var v = [0,0,0]; let n = c.width*c.height
  for i in 0..<n { for k in 0..<3 { v[k] += Int(d[i*4+k]) } }
  return v[1]/n > 190 && v[0]/n < 160 && v[2]/n < 150
}
// Sell is green when the item is in stock, grey otherwise.
func coinNear(_ s: Shot) -> Bool {
  let c = crop(s, 0.48, 0.243, 0.055, 0.05), d = c.dataProvider!.data! as Data; let n = c.width*c.height; var k = 0
  for i in 0..<n { let r = d[i*4], g = d[i*4+1], b = d[i*4+2]; if r > 225 && g > 140 && g < 205 && b < 60 { k += 1 } }
  return Double(k)/Double(n) > 0.06
}
func arrow(_ s: Shot) -> Bool {
  let c = crop(s, 0.648, 0.225, 0.045, 0.05), d = c.dataProvider!.data! as Data; let n = c.width*c.height; var k = 0
  for i in 0..<n { let r = d[i*4], g = d[i*4+1], b = d[i*4+2]; if r > 225 && g > 150 && g < 225 && b < 110 { k += 1 } }
  return Double(k)/Double(n) > 0.12
}
// Mood faces above the heroes on the quest screen: red = cannot handle it, green = fine.
// Quest material in the "Missing components" window, told apart by the icon's colour.
func material(_ s: Shot) -> String {
  let c = crop(s, 0.472, 0.44, 0.056, 0.095), d = c.dataProvider!.data! as Data; let n = c.width*c.height
  var k = 0, R = 0, G = 0, B = 0
  for i in 0..<n { let r = Int(d[i*4]), g = Int(d[i*4+1]), b = Int(d[i*4+2]); if r+g+b > 210 { k += 1; R += r; G += g; B += b } }
  guard k * 20 > n else { return "" }
  R /= k; G /= k; B /= k
  if G > R + 25 && B > R + 15 { return "Glow Shroom" }
  if R > B + 35 && R > G + 12 { return "Elven Wood" }
  if abs(R-G) < 22 && abs(G-B) < 30 { return "Iron Pine Cone" }
  return ""
}
var debugFaces = false
func faces(_ s: Shot) -> (red: Int, green: Int, yellow: Int, other: Int) {
  var r = 0, g = 0, w = 0, o = 0
  for b in blobs(s, 0.1...0.53, 0.15...0.6, scale: 3, { r, g, b in r > 225 && g > 218 && b > 195 }) {
    let a = Double(b.w)/Double(b.h)
    if b.w < 20 || b.w > 48 || b.h < 22 || b.h > 60 || a < 0.6 || a > 1.15 || b.n < 180 { continue }
    let c = crop(s, b.x-0.0115, b.y-0.0215, 0.023, 0.036), d = c.dataProvider!.data! as Data; let n = c.width*c.height
    var kr = 0, kg = 0, ky = 0, kd = 0
    for i in 0..<n { let R = Int(d[i*4]), G = Int(d[i*4+1]), B = Int(d[i*4+2]); if R > 190 && G < 110 && B < 90 { kr += 1 } else if G > R + 40 && G > B + 40 && G > 90 { kg += 1 } else if R > 200 && G > 140 && B < 130 { ky += 1 } else if R < 75 && G < 75 && B < 80 { kd += 1 } }
    if debugFaces { print("yuz (\(b.x),\(b.y)) \(b.w)x\(b.h) r=\(Double(kr)/Double(n)) g=\(Double(kg)/Double(n)) y=\(Double(ky)/Double(n)) d=\(Double(kd)/Double(n))") }
    if kr * 5 > n, kr > kg { r += 1 } else if kg * 5 > n { g += 1 } else if ky * 6 > n, kd * 8 > n { g += 1 /* sunglasses: easily strong enough */ } else if ky * 10 > n * 3 { w += 1 } else { o += 1 }
  }
  return (r, g, w, o)
}
func sellGreen(_ s: Shot) -> Bool {
  let c = crop(s, 0.745, 0.775, 0.03, 0.03), d = c.dataProvider!.data! as Data; var v = [0,0,0]; let n = c.width*c.height
  for i in 0..<n { for k in 0..<3 { v[k] += Int(d[i*4+k]) } }
  return v[1]/n > 190 && v[0]/n < 170 && v[2]/n < 160
}
func gold(_ s: Shot) -> Int? { s.t.first { $0.y < 0.07 && abs($0.x-0.698) < 0.03 }.flatMap { Int($0.s.replacingOccurrences(of: ",", with: "")) } }
// Weapon tab has 7 sub-tabs, armour tab has 10.
struct Line: Codable { var stock: Int; var value: Int; var names: [String]; var at: Date; var craftable: Bool }
// OCR mixes Cyrillic look-alikes in and adds or swaps a letter: map to the closest name already known.
var knownNames: [String] = []
func fold(_ z: String) -> String {
  let m: [Character: Character] = ["а":"a","в":"b","с":"c","е":"e","н":"h","к":"k","м":"m","о":"o","р":"p","т":"t","у":"y","х":"x","п":"n","д":"a","и":"u"]
  return String(plain(z).lowercased().map { m[$0] ?? $0 }.filter { $0.isLetter })
}
func dist(_ a: String, _ b: String) -> Int {
  let x = Array(a), y = Array(b); var d = Array(0...y.count)
  for i in 0..<x.count { var p = d[0]; d[0] = i + 1; for j in 0..<y.count { let o = d[j+1]; d[j+1] = min(o + 1, d[j] + 1, p + (x[i] == y[j] ? 0 : 1)); p = o } }
  return d[y.count]
}
func norm(_ z: String) -> String {
  let n = fold(z); if n.count < 6 || knownNames.contains(n) { return n }
  let best = knownNames.filter { abs($0.count - n.count) <= 1 && $0.count >= 6 }.map { ($0, dist($0, n)) }.min { $0.1 < $1.1 }
  if let best, best.1 <= 1 { return best.0 }
  return n
}
let plan: [(cat: Double, sub: Double, name: String)] = {
  let w = (0..<7).map { (cat: 0.706, sub: 0.103 + 0.0433*Double($0), name: "silah\($0+1)") }
  let a = (0..<10).map { (cat: 0.766, sub: 0.103 + 0.0433*Double($0), name: "zirh\($0+1)") }
  var o: [(cat: Double, sub: Double, name: String)] = [] // interleave so materials are spread
  let m = (0..<7).map { (cat: 0.827, sub: 0.103 + 0.0433*Double($0), name: "iksir\($0+1)") }
  for k in 0..<10 { if k < 7 { o.append(w[k]) }; o.append(a[k]); if k < 7 { o.append(m[k]) } }
  return o
}()
func energy(_ s: Shot) -> (Int, Int)? {
  func ok(_ z: String) -> (Int, Int)? {
    let p: [Int] = (z.components(separatedBy: " ").last ?? "").components(separatedBy: "/").compactMap { (v: String) -> Int? in Int(v) }
    // Reject misreads such as 222/62.
    return p.count == 2 && p[1] > 0 && p[0] * 2 <= p[1] * 3 ? (p[0], p[1]) : nil
  }
  if let e = s.t.first(where: { $0.y < 0.07 && abs($0.x-0.598) < 0.05 && $0.s.contains("/") }), let v = ok(e.s) { return v }
  // The lightning icon gets read as a digit: look again at the number alone, enlarged.
  return ocr(crop(s, 0.574, 0.022, 0.055, 0.038, 3)).compactMap { ok($0.s) }.first
}
func price(_ s: Shot) -> Int? {
  if let v = s.t.first(where: { $0.y > 0.235 && $0.y < 0.29 && abs($0.x-0.56) < 0.06 }).flatMap({ num($0.s) }) { return v }
  // Full-frame OCR misses short numbers: read the price box enlarged.
  return ocr(crop(s, 0.53, 0.235, 0.085, 0.058, 3)).compactMap { num($0.s) }.first
}
// "1d 2h", "14m 15s", "14m.12s" -> seconds
func secs(_ z: String) -> Double? {
  var n = "", t = 0.0, hit = false
  for c in z { if c.isNumber { n.append(c) } else if let u = ["d": 86400.0, "h": 3600, "m": 60, "s": 1][String(c)], let v = Double(n) { t += v*u; n = ""; hit = true } else { n = "" } }
  return hit ? t : nil
}
func num(_ z: String) -> Int? { Int(z.filter { !",.-+ ".contains($0) }) } // a stray dash from the coin icon is not a sign
func stamp(_ f: String) -> Date { Date(timeIntervalSince1970: Double((try? String(contentsOfFile: "logs/\(f)", encoding: .utf8)) ?? "0") ?? 0) }
func putStamp(_ f: String, _ d: Date) { try? "\(d.timeIntervalSince1970)".write(toFile: "logs/\(f)", atomically: true, encoding: .utf8) }
// Positions in the Design view. Bins come last and only when nothing else can be upgraded.
let furniture: [(name: String, x: Double, y: Double, bin: Bool)] = [
  ("Rack", 0.35, 0.303, false), ("Mannequin", 0.402, 0.14, false), ("Table", 0.655, 0.327, false),
  ("Trunk", 0.57, 0.215, false), ("Counter", 0.515, 0.438, false), ("Wood Bin", 0.480, 0.125, true), ("Iron Bin", 0.524, 0.162, true), ("Leather Bin", 0.519, 0.70, true)]
// Second known camera position (after a finished upgrade zooms in).
let layoutB: [(x: Double, y: Double)] = [(0.25,0.59),(0.31,0.42),(0.585,0.64),(0.50,0.486),(0.432,0.78),(0.403,0.376),(0.45,0.428),(0.459,1.086)]
// The silver Iron Bin anchors the Design view; everything else is placed relative to it.
// Iron Bin position plus zoom relative to layoutB, from the orange Counter and the silver bin straight above it.
func anchor(_ s: Shot) -> (x: Double, y: Double, k: Double)? {
  let orange = blobs(s, 0.17...0.85, 0.2...0.86) { r, g, b in r > 170 && g > 65 && g < 135 && b < 75 && r - g > 75 }.filter { $0.n >= 12 && $0.w <= 30 && $0.h <= 30 }.sorted { $0.n > $1.n }.prefix(4)
  let silver = blobs(s, 0.17...0.85, 0.1...0.85, scale: 2) { r, g, b in r > 120 && abs(r-g) < 18 && abs(g-b) < 20 }.filter { $0.n >= 25 && $0.w >= 7 && $0.w <= 44 && $0.h >= 6 && $0.h <= 44 }
  var best: (x: Double, y: Double, k: Double, n: Int)?
  for c in orange { for v in silver {
    let dy = c.y - v.y, k = 0.61 + (dy - 0.198) * 2.03
    guard dy > 0.1, dy < 0.45, abs((c.x - v.x) + 0.012*k) < 0.03 else { continue }
    if best == nil || v.n + c.n*4 > best!.n { best = (v.x, v.y, k, v.n + c.n*4) }
  } }
  return best.map { ($0.x, $0.y, $0.k) }
}
// Quest badge: yellow = free slot, green "+" = buy a slot, red "!" = other.
func greenBadge(_ s: Shot) -> Bool {
  let c = crop(s, 0.866, 0.831, 0.02, 0.030), d = c.dataProvider!.data! as Data; let n = c.width*c.height; var k = 0
  for i in 0..<n { let r = d[i*4], g = d[i*4+1], b = d[i*4+2]; if g > 150 && r < 140 && b < 140 { k += 1 } }
  return Double(k)/Double(n) > 0.35
}
func yellowBadge(_ s: Shot) -> Bool {
  let c = crop(s, 0.866, 0.831, 0.02, 0.030), d = c.dataProvider!.data! as Data; let n = c.width*c.height; var k = 0
  for i in 0..<n { let r = d[i*4], g = d[i*4+1], b = d[i*4+2]; if r > 200 && g > 140 && g < 220 && b < 120 { k += 1 } }
  return Double(k)/Double(n) > 0.35
}
let craftSlots = 4
func robotCheck(_ s: Shot) -> Bool { s.has("not a robot") || s.has("verification code") }
struct Card { let name: String; let x: Double; let left: Int; let coin: Bool; let tier: Int; let stock: Int }
// "x2" next to the picture; no label means none in stock.
func stockAt(_ s: Shot, _ l: Double) -> Int {
  if let t = s.t.first(where: { $0.y > 0.695 && $0.y < 0.735 && $0.x > l+0.07 && $0.x < l+0.14 && $0.s.lowercased().hasPrefix("x") }) { return Int(t.s.dropFirst().filter { $0.isNumber }) ?? 1 }
  return ocr(crop(s, l+0.088, 0.692, 0.045, 0.045, 3)).compactMap { (t: T) -> Int? in t.s.lowercased().hasPrefix("x") ? (Int(t.s.dropFirst().filter { $0.isNumber }) ?? 1) : nil }.first ?? 0
}
// Tier number in the round badge at the card's top-left corner.
func tierAt(_ s: Shot, _ l: Double) -> Int {
  for (dx, dy, w, h) in [(0.002, 0.622, 0.026, 0.044), (-0.002, 0.616, 0.034, 0.056), (0.005, 0.628, 0.02, 0.034)] {
    if let v = ocr(crop(s, l+dx, dy, w, h, 4)).compactMap({ Int($0.s.trimmingCharacters(in: .whitespaces)) }).first, v >= 1, v <= 15 { return v }
  }
  return 0
}
func cards(_ s: Shot) -> [Card] {
  var out: [Card] = []
  for n in 0..<5 {
    let l = 0.0857 + Double(n)*0.1438
    guard let lab = s.t.first(where: { $0.y > 0.735 && $0.y < 0.775 && $0.x > l && $0.x < l+0.138 }),
          let pr = s.t.first(where: { $0.y > 0.855 && $0.y < 0.89 && $0.x > l && $0.x < l+0.138 && $0.s.contains("/") }) else { continue }
    // Locked cards show a sentence ("Craft 18 ...", "Hire ...") instead of a numeric cost.
    if s.t.contains(where: { $0.x > l && $0.x < l+0.138 && ($0.y > 0.78 && $0.y < 0.85 || $0.y > 0.855 && $0.y < 0.89) && $0.s.filter { $0.isLetter }.count >= 4 }) { continue }
    let words: [String] = lab.s.components(separatedBy: " ").filter { (w: String) -> Bool in w.count >= 3 && w.allSatisfy { (ch: Character) -> Bool in ch.isLetter || ch == "'" } }
    let p: [Int] = pr.s.components(separatedBy: "/").compactMap { (v: String) -> Int? in Int(v) }
    guard !words.isEmpty, p.count == 2, p[1] > p[0] else { continue }
    out.append(Card(name: words.joined(separator: " "), x: l + 0.069, left: p[1]-p[0], coin: isCoin(s, l+0.1157, 0.860), tier: tierAt(s, l), stock: stockAt(s, l)))
  }
  return out.sorted { (-$0.tier, $0.coin ? 1 : 0, $0.left) < (-$1.tier, $1.coin ? 1 : 0, $1.left) }
}

// Heroes standing on the quest platform: the power number above each one.
func party(_ s: Shot) -> [(x: Double, y: Double, p: Int)] {
  s.t.filter { $0.x > 0.15 && $0.x < 0.5 && $0.y > 0.40 && $0.y < 0.49 }.compactMap { t in
    guard t.s.filter({ $0.isLetter }).isEmpty, let a = Int(t.s.filter { $0.isNumber }), a >= 100 else { return nil }
    // The leading "1," is sometimes lost next to the star: read it again enlarged and keep the longer number ending the same way.
    let z = ocr(crop(s, max(0, t.x - 0.032), t.y - 0.02, 0.066, 0.04, 3)).compactMap { Int($0.s.filter { $0.isNumber }) }.first { $0 > a && $0 < 100000 && "\($0)".hasSuffix("\(a)") }
    return (t.x, t.y, z ?? a) }
}
// Purple "cannot" faces are not counted by faces(), so every hero must have a face that was counted.
func partyOK(_ s: Shot, yellow: Bool) -> Bool {
  let f = faces(s), n = party(s).count
  return n > 0 && f.red == 0 && f.other == 0 && f.green + f.yellow == n && (yellow || f.yellow == 0)
}

@main struct Bot {
  static func main() async {
    setvbuf(stdout, nil, _IONBF, 0)
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fixture", let i = NSImage(contentsOfFile: CommandLine.arguments[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      let s = Shot(img: i, t: ocr(i), frame: .zero)
      debugFaces = true
      print("robot=\(robotCheck(s))"); print("alici=\(s.buyer) satici=\(s.seller) gem=\(String(describing: gems(s))) malzeme=\(material(s)) yuz=\(faces(s)) hata=\(bubbleDebug(s).joined(separator: " ")) altinIkon=\(coinNear(s)) ok=\(arrow(s)) capa=\(String(describing: anchor(s))) sure=\(s.t.filter { $0.y > 0.44 && $0.y < 0.72 && $0.x > 0.52 }.map { ($0.s, secs($0.s)) }) sariRozet=\(yellowBadge(s)) balon=\(bubbles(s)) enerji=\(String(describing: energy(s))) yesilSat=\(sellGreen(s)) fiyat=\(String(describing: price(s))) altin=\(String(describing: gold(s))) X=\(String(describing: redX(s))) kart=\(cards(s))"); exit(0)
    }
    guard CommandLine.arguments.count == 3, let mins = Double(CommandLine.arguments[1]), let maxC = Int(CommandLine.arguments[2]) else { print("kullanim: bot <dakika> <maksCraft>"); exit(1) }
    if FileManager.default.fileExists(atPath: "logs/bot.log") { try? FileManager.default.moveItem(atPath: "logs/bot.log", toPath: "logs/bot_\(tag()).log") }
    FileManager.default.createFile(atPath: "logs/bot.log", contents: nil); logFile = FileHandle(forWritingAtPath: "logs/bot.log")
    _ = await MainActor.run { NSApplication.shared }
    let end = Date().addingTimeInterval(mins*60)
    var made = 0, unknown = 0, free = 0, base: Int? = nil, bad = Set<String>(), blockedUntil = Date.distantPast
    var dailyTries = 0, needMat: [String: Date] = [:], questRest = Date.distantPast, restWake = Date.distantPast, wanted: [String: Date] = [:], queue: [String: [Date]] = [:], lines: [String: Line] = [:], lastLine = "", values: [String: Int] = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: URL(fileURLWithPath: "logs/values.json")))) ?? [:], slotsKnown = false, offerTried: [String: Int] = [:], waitRow = 0, seen: [String: Int] = [:], offerNeed = 0, offerFails = 0, offerSince = Date(), hops = 0, restocked: [String: Date] = [:], restockItem = "", riskSeen = 0, starve = Date(), heroesDue = true, optLeft = 0, heroTab = 0, heroTrips = 0, firstWait: [String: Date] = [:], upSeen = Date.distantPast, questFails = 0, questHold = Date.distantPast, gemAsks = 0, trial = 0, waiting: [String: (Int, Date)] = [:], layout = 0, layoutTry = 0, stockWait: [String: Date] = [:], keepSuggest = false, upNext = Date.distantPast, upTries = 0, upUntil = stamp("upgrade_until.txt"), upIdx = -1, upBlocked = false, upWhy = "", questAt = stamp("quest_until.txt"), goCity = false, questBan: [String: Date] = [:], questName = "", lastQuestTap = 0, cust = "", applied = "", basePrice: [String: Int] = [:], talked: [String: Date] = [:], unread = 0, waits = 0, lastSoldAt = Date(), prices: [Int] = ((try? String(contentsOfFile: "logs/prices.txt", encoding: .utf8)) ?? "").components(separatedBy: ",").compactMap { (v: String) -> Int? in Int(v) }, earned = 0, lastHead = "", banned: [String: Date] = [:], generic = 0, closes = 0, claims = 0, turn = Int((try? String(contentsOfFile: "logs/turn.txt", encoding: .utf8)) ?? "") ?? 0, misses = 0, room = -1, capAt = Date.distantPast, skipB: [(x: Double, y: Double, t: Date)] = [], suggested = false, achAt = Date.distantPast, bought = 0, noGem = 0, talks = 0, notCustomers: [(x: Double, y: Double)] = [], lastBubble: (x: Double, y: Double)? = nil, researchTried = false, completes = 0, sold = 0, invFull = false, collects = 0, noSaleUntil = Date.distantPast, skip = 0, empty = 0
    if let d = try? Data(contentsOf: URL(fileURLWithPath: "logs/lines.json")), let l = try? JSONDecoder().decode([String: Line].self, from: d) { lines = l }
    knownNames = Array(values.keys)
    let started = Date()
    var progAt = Date(), progSig = "", forceUntil = Date.distantPast, forced = false, relaunches: [Date] = [], lookRow = 0, lastNames: [String] = [], lastCat = -1.0, custItem = "", custAt = Date.distantPast, giftTry = 0, rankTry = 0, offerPending: Date? = nil, saveFor = 0, saveAt = Date.distantPast, refuseSeen = "", craftSeen = Date.distantPast, upMin = 0, upMinAt = Date.distantPast, yellowOK = true, questSent = false, optAt = Date.distantPast, bossBan = Date.distantPast, strong: [Int] = [], bossHold = Date.distantPast
    // Short area bans are dropped too, so every area is open again when the next hero wakes up.
    func restNow() {
      questRest = restWake > Date().addingTimeInterval(20) ? restWake : Date().addingTimeInterval(180)
      questBan = questBan.filter { $0.value > Date().addingTimeInterval(301) }
      log("takim dinleniyor: \(Int(questRest.timeIntervalSinceNow))s")
    }
    // Stuck: keep a picture, then quit and reopen the game like a player would. At most 3 times an hour.
    func recover(_ why: String, _ s: Shot) async {
      save(s.img, "stuck_\(tag())"); log("KURTARMA (\(why)): \(s.t.map { $0.s })")
      relaunches = relaunches.filter { Date().timeIntervalSince($0) < 3600 }
      if relaunches.count >= 3 { stop("kurtarma ise yaramadi: \(why)", s) }
      relaunches.append(Date())
      let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
      apps.forEach { _ = $0.terminate() }; await nap(6); apps.filter { !$0.isTerminated }.forEach { _ = $0.forceTerminate() }; await nap(3)
      activate(); await nap(30)
      unknown = 0; closes = 0; generic = 0; talks = 0; riskSeen = 0; gemAsks = 0; noGem = 0; empty = 0; cust = ""; applied = ""; skipB = []; notCustomers = []; lastBubble = nil; upIdx = -1; restockItem = ""; noSaleUntil = Date.distantPast; offerNeed = 0; room = -1; lastHead = ""; lastCat = -1; giftTry = 0; rankTry = 0
      progAt = Date(); forced = false
    }
    func invRoomOK(_ r: Int) -> Bool { r != 0 }
    var anyNonBin = false
    func nextUp(_ i: Int, _ none: Bool) -> Int { // none: this piece has no upgrade at all
      if i < furniture.count, !furniture[i].bin, !none { anyNonBin = true }
      let k = i + 1
      if k >= furniture.count || (furniture[k].bin && anyNonBin) { return -1 }
      return k
    }
    while Date() < end {
      let s = await look()
      if let g = gems(s) {
        if let b = base, g < b { let again = await look(); if let h = gems(again), h < b { stop("GEM AZALDI \(b)->\(h)", again) } }
        else { base = max(base ?? g, g) }
      }
      // The game asks whether a human is playing. The bot never answers, closes or restarts around it: it stops and calls the user.
      if robotCheck(s) {
        let v = Process(); v.executableURL = URL(fileURLWithPath: "/usr/bin/say"); v.arguments = ["-v", "Yelda", "Dikkat, oyun robot doğrulaması istiyor. Bot durdu."]; try? v.run()
        stop("ROBOT DOGRULAMASI, kullanici bekleniyor", s)
      }
      let sig = "\(sold)/\(made)/\(bought)"
      if sig != progSig { progSig = sig; progAt = Date(); forced = false; relaunches = relaunches.filter { Date().timeIntervalSince($0) < 3600 }; generic = 0; talks = 0; closes = 0; gemAsks = 0; riskSeen = 0; giftTry = 0; rankTry = 0 }
      // No sale, craft or purchase for 3 minutes: sell waiting customers at the plain price. Still nothing: reopen the game.
      let idle = Date().timeIntervalSince(progAt)
      if idle > 180, !forced { forced = true; forceUntil = Date().addingTimeInterval(120); waiting = [:]; skipB = []; notCustomers = []; offerNeed = 0; log("BEKCI: 3 dk ilerleme yok, bekleyenler normal fiyattan satilacak"); save(s.img, "bekci_\(tag())") }
      if idle > 420 { await recover("7 dk ilerleme yok", s); continue }
      // Any "spend gems" question: Cancel, nothing else. Checked before every other rule.
      if s.has("Unlock crafting slot") || s.has("Unlock quest slot") || s.has("Buy With Gems") {
        unknown = 0; restockItem = ""; free = 0; log("SLOT SATISI kapatiliyor"); for k in restocked.keys where Date().timeIntervalSince(restocked[k]!) < 90 { restocked[k] = Date.distantPast }
        if let x = blobs(s, 0.6...0.75, 0.2...0.45, { r, g, b in r > 200 && g > 50 && g < 120 && b < 90 }).filter({ $0.n >= 50 }).max(by: { $0.n < $1.n }) { await tap(s, x.x, x.y, "slot satisi X") } else if let x = redX(s) { await tap(s, x.x, x.y, "X") } else { stop("slot satisi kapatilamadi", s) }
        await nap(2)
      }
      else if s.has("gems to") || s.has("Spend gems") || (s.first("Gems") != nil && s.first("Cancel") != nil) {
        unknown = 0; gemAsks += 1; log("GEM TEKLIFI reddediliyor: \(s.t.filter { $0.y > 0.35 && $0.y < 0.7 }.map { $0.s })")
        if s.has("being upgraded") { upIdx = -1; upUntil = Date().addingTimeInterval(600) }
        if gemAsks > 8 { stop("cok fazla gem teklifi", s) }
        if let c = s.first("Cancel") { await tap(s, c.x, c.y, "Cancel") } else if let x = redX(s) { await tap(s, x.x, x.y, "gem teklifi X") } else { stop("gem teklifi kapatilamadi", s) }
        await nap(2.5)
      }
      else if s.has("BLUEPRINT RESEARCHED") || s.has("LEVEL UP!"), let b = s.first("Continue") { unknown = 0; researchTried = false; log("acildi: \(s.t.map{$0.s})"); await tap(s, b.x, b.y, "Continue"); await nap(2.5) }
      else if s.has("guildmate to receive your gift") {
        unknown = 0; giftTry += 1; save(s.img, "guild_gift_\(min(giftTry, 3))"); log("GUILD HEDIYE \(giftTry): \(s.t.map { "\($0.s)@\(String(format: "%.2f,%.2f", $0.x, $0.y))" })")
        if giftTry > 4 { await recover("guild hediye", s); continue }
        if let m = s.t.filter({ $0.s.hasPrefix("Lv") && $0.y > 0.15 }).min(by: { ($0.y, $0.x) < ($1.y, $1.x) }) { await tap(s, m.x, m.y, "uye sec"); await nap(1.5) }
        let q = await look()
        if q.has("guildmate to receive your gift"), let c = q.first("Confirm") {
          if greenAt(q, c) || greenAt(q, T(s: "", x: c.x + 0.02, y: c.y)) { await tap(q, c.x, c.y, "hediye Confirm") } else { save(q.img, "guild_gift_gri"); log("Confirm yesil degil") }
        }
        await nap(3)
      }
      // The only button on this screen. A green button carries no gem price.
      else if s.has("Champion Coins Received"), let b = s.first("Rank Up") ?? s.first("OK") ?? s.first("Continue"), greenAt(s, b) {
        unknown = 0; rankTry += 1; if rankTry > 4 { await recover("rank up", s); continue }
        save(s.img, "rankup_\(rankTry)"); log("sampiyon: \(s.t.map { $0.s })"); await tap(s, b.x, b.y, b.s); await nap(4); let q = await look(); save(q.img, "rankup_after"); log("sampiyon sonrasi: \(q.t.map { $0.s })")
      }
      else if s.has("Welcome Back!"), s.has("missed while you were away"), let x = redX(s) { unknown = 0; await tap(s, x.x, x.y, "Welcome Back X"); await nap(2.5) }
      else if s.has("Pedigree"), s.has("Feed"), let b = s.first("Back") { unknown = 0; if let l = lastBubble { notCustomers.append(l); lastBubble = nil; achAt = Date() }; await tap(s, b.x, b.y, "evcil hayvan Back"); await nap(2.5) }
      else if s.has("RESOURCES RECEIVED") { // the lone OK is often missed by OCR
        unknown = 0; if offerPending != nil { offerPending = nil; log("OZEL TEKLIF ALINDI (kaynak)") }; offerFails = 0; offerNeed = 0
        if let b = s.first("OK"), b.y > 0.85 { await tap(s, b.x, b.y, "OK") } else if greenAt(s, T(s: "", x: 0.53, y: 0.93)) { await tap(s, 0.499, 0.93, "OK konumu") }
        await nap(2)
      }
      // Right-hand button here costs gems: only the exact "Collect" on the left half is allowed.
      else if s.has("MASTERPIECE"), let b = s.t.first(where: { $0.s == "Collect" && $0.x < 0.46 && $0.y > 0.85 }) { unknown = 0; log("masterpiece: \(s.t.map{$0.s})"); await tap(s, b.x, b.y, "Collect"); await nap(2.5) }
      else if s.has("ITEM RECEIVED") || s.has("UPGRADE FINISHED"), let b = s.t.first(where: { $0.s.hasPrefix("OK") && $0.s.count <= 3 && $0.y > 0.85 && abs($0.x - 0.5) < 0.05 }) { unknown = 0; log("alindi: \(s.t.map{$0.s})"); if s.has("ITEM RECEIVED"), offerNeed > 0, !s.has("Scroll") { log("OZEL TEKLIF ALINDI"); offerNeed = 0; offerFails = 0 }; await tap(s, b.x, b.y, "OK"); await nap(2.5) }
      else if s.t.filter({ $0.s == "Achievements" }).count >= 2 {
        unknown = 0
        if let c = s.t.first(where: { $0.s.hasPrefix("CLAIM REWARD") }), claims < 10 { claims += 1; await tap(s, c.x, c.y, "basarim odulu"); await nap(3); continue }
        claims = 0; if let b = lastBubble { notCustomers.append(b); lastBubble = nil; empty = 0 }
        achAt = Date(); await tap(s, 0.702, 0.130, "basarimlar X"); await nap(2.5)
      }
      else if s.has("BLUEPRINT DISCOVERED"), let c = s.first("Continue") {
        unknown = 0
        // Scroll cost is shown as have/need below the button; a gem price has no slash.
        let q: [Int] = s.t.first { $0.s.contains("/") && $0.x < 0.5 && $0.y > 0.88 }?.s.components(separatedBy: "/").compactMap { (v: String) -> Int? in Int(v) } ?? []
        if !researchTried, q.count == 2, q[0] >= q[1], let r = s.first("Research now") { researchTried = true; await tap(s, r.x, r.y + 0.02, "Research \(s.t.map{$0.s}) \(q)") }
        else { researchTried = false; await tap(s, c.x, c.y, "Continue (arastirma yok)") }
        await nap(3)
      }
      else if s.seller, let no = s.first("Refuse") {
        unknown = 0; empty = 0
        let v = price(s), g = gold(s)
        let sk = "S" + plain(s.header) + "\(v ?? -1)"
        if talked[sk] == nil, let st = s.first("Small talk") { talked[sk] = Date(); await tap(s, st.x, st.y, "Small talk (satici)"); await nap(2.5); continue }
        // An expensive seller is never refused: keep them waiting and save up.
        let big = v.map { $0 >= 3000 } ?? true
        if big, let v { saveFor = v; saveAt = Date() }
        if Date().timeIntervalSince(saveAt) > 1200 { saveFor = 0 }
        let canBig = big && (v ?? .max) <= (g ?? 0)
        let spare = saveFor == 0 || (v ?? 0) * 10 <= (g ?? 0)
        // Never buy without enough gold: the game could offer gems for the difference.
        if offerNeed == 0, room >= 1, let v, let g, big ? canBig : (v * 2 <= g && spare), v <= g, base != nil, let buy = s.first("Buy") { bought += 1; if big { saveFor = 0; saveAt = Date.distantPast }; room -= 1; await tap(s, buy.x, buy.y, "SATIN AL \(v) altin=\(g) yer=\(room)"); capAt = Date.distantPast }
        else if big, let w = s.first("Wait") {
          log("PAHALI SATICI, bekletiliyor: \(v ?? -1) altin=\(g ?? -1) yer=\(room)"); if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval((g ?? 0) < (v ?? 0) ? 60 : 20))); lastBubble = nil }
          if room < 1 { capAt = Date.distantPast }; noSaleUntil = Date().addingTimeInterval(1)
          if hops < 3, arrow(s) { hops += 1; await tap(s, 0.665, 0.249, "sonraki musteri >") } else { hops = 0; await tap(s, w.x, w.y, "Wait (pahali satici)") }
        }
        else if room < 1 || offerNeed > 0, Date().timeIntervalSince(talked[sk] ?? Date()) < 300, let w = s.first("Wait") { // inventory not read yet: do not lose the seller
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(30))); lastBubble = nil }
          noSaleUntil = Date().addingTimeInterval(4); if room < 0 { capAt = Date.distantPast }; await tap(s, w.x, w.y, "satici bekle yer=\(room)")
        }
        else if refuseSeen != sk { refuseSeen = sk; await nap(1) } // refuse only after two identical reads
        else { await tap(s, no.x, no.y, "saticiyi reddet fiyat=\(v ?? -1) altin=\(g ?? -1) yer=\(room)") }
        await nap(2.5)
      }
      else if s.has("has a special offer"), let w = s.first("Wait") {
        unknown = 0; empty = 0
        let v = price(s), g = gold(s), coin = coinNear(s)
        let need = s.t.first { $0.y > 0.24 && $0.y < 0.31 && $0.x < 0.5 && $0.s.lowercased().hasPrefix("x") }.flatMap { Int($0.s.dropFirst().filter { $0.isNumber }) } ?? 1
        // Resources and consumables do not use inventory space: buy directly, capped at a tenth of the gold.
        let title = s.t.filter { $0.y > 0.19 && $0.y < 0.24 }.map { $0.s }.joined(separator: " ")
        let resource = need > 12 || ["Iron", "Wood", "Leather", "Herb", "Drink"].contains { r in title.hasSuffix(r) }
        let okey = title + "\(v ?? -1)"
        let affordable = (offerTried[okey] ?? 0) < 3 && (!resource || (v ?? 0) * 10 <= (g ?? 0)) && Date().timeIntervalSince(saveAt) > 1200 && coin && v != nil && g != nil && v! + 500 <= g!
        if affordable, base != nil, resource || room >= need || need <= 2, offerFails < 3, let buy = s.first("Buy") {
          offerTried[okey, default: 0] += 1; await tap(s, buy.x, buy.y, "OZEL TEKLIF AL \(title) x\(need) \(v!) altin=\(g!) yer=\(room)"); await nap(2)
          let q = await look(); capAt = Date.distantPast
          if let g2 = gold(q), g2 < g! { log("OZEL TEKLIF ALINDI"); offerNeed = 0; offerFails = 0; lastBubble = nil } else if !q.has("has a special offer") { offerPending = Date(); lastBubble = nil; log("teklif kapandi, sonuc bekleniyor") } else { offerFails += 1; room = -1; log("alinamadi (\(offerFails)): \(q.t.filter { $0.y > 0.1 && $0.y < 0.2 }.map{$0.s})") }
        }
        else if affordable, !resource, need > room, Date().timeIntervalSince(offerSince) < 1500 || offerNeed == 0 {
          if offerNeed == 0 { offerSince = Date() }
          offerNeed = need; offerFails = 0; log("OZEL TEKLIF icin yer aciliyor: gereken=\(need) yer=\(room)"); hops = 0
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(room < 0 ? 12 : 40))); lastBubble = nil }
          if room < 0 { capAt = Date.distantPast }
          if arrow(s) { await tap(s, 0.665, 0.249, "sonraki musteri >") } else { noSaleUntil = Date().addingTimeInterval(4); await tap(s, w.x, w.y, "Wait") }
        }
        else {
          log("ozel teklif alinmadi \(title) x\(need) fiyat=\(v ?? -1) altin=\(g ?? -1) altinMi=\(coin)"); noSaleUntil = Date().addingTimeInterval(5); if resource { offerNeed = 0 }
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(90))); lastBubble = nil }
          if hops < 3, arrow(s) { hops += 1; noSaleUntil = Date.distantPast; await tap(s, 0.665, 0.249, "sonraki musteri >") } else { hops = 0; await tap(s, w.x, w.y, "Wait") }
        }
        await nap(2.5)
      }
      else if s.has("Tap to open the gift") { unknown = 0; await tap(s, 0.5, 0.5, "hediye ac"); await nap(4) }
      else if s.has("Max Capacity") {
        unknown = 0; capAt = Date()
        let q: [Int] = (s.t.first { $0.s.contains("Max Capacity") }?.s.components(separatedBy: " ").last ?? "").components(separatedBy: "/").compactMap { (v: String) -> Int? in Int(v) }
        room = q.count == 2 ? q[1]-q[0] : -1; invFull = room == 0; collects = 0; log("envanter \(q) yer=\(room)")
        await tap(s, 0.883, 0.135, "envanter X"); await nap(2.5)
      }
      else if s.has("has a gift for you") || s.has("wants to help with"), s.first("FREE!") != nil, let x = s.first("Accept") { unknown = 0; empty = 0; lastBubble = nil; await tap(s, x.x, x.y, "ucretsiz hediye"); await nap(3) }
      else if upIdx >= 0, s.first("Edit Shop") != nil, s.first("Instant upgrade") == nil, s.first("Back") == nil {
        unknown = 0; var fp = (x: furniture[upIdx].x, y: furniture[upIdx].y)
        if layout == 0, let a = anchor(s) { fp = (a.x + (layoutB[upIdx].x - 0.45)*a.k, a.y + (layoutB[upIdx].y - 0.428)*a.k) }
        let visible = fp.x > 0.2 && fp.x < 0.83 && fp.y > 0.1 && fp.y < 0.85 && !(fp.x > 0.4 && fp.x < 0.6 && fp.y > 0.86)
        if !visible { log("ekran disi: \(furniture[upIdx].name)"); if layout == 0 { layout = 1 } else { layout = 0; upIdx = nextUp(upIdx, false) }; if let b = s.first("Done") { await tap(s, b.x, b.y, "Design kapat"); await nap(2.5) }; continue }
        await tap(s, fp.x, fp.y, "mobilya sec \(furniture[upIdx].name)"); await nap(2)
        let q = await look()
        if let u = q.first("Upgrade"), q.first("Back") != nil { await tap(q, u.x, u.y, "Upgrade ekrani"); layout = 0; await nap(2.2) }
        else if let b = q.first("Back") ?? q.first("Done") { log("yukseltme secenegi yok: \(furniture[upIdx].name) duzen=\(layout)")
          if layout == 0 { layout = 1 } else { layout = 0; upIdx = nextUp(upIdx, false) }; await tap(q, b.x, b.y, "Design kapat"); await nap(2.5) }
      }
      else if s.first("Instant upgrade") != nil {
        unknown = 0
        let nm = s.t.first { $0.y > 0.24 && $0.y < 0.27 && $0.x > 0.52 && $0.x < 0.7 }?.s ?? "?"
        let cost = s.t.first { $0.y > 0.75 && $0.y < 0.785 && $0.x > 0.55 && $0.x < 0.66 }.flatMap { num($0.s) }
        let tm = s.t.compactMap { z in z.y > 0.44 && z.y < 0.72 && z.x > 0.52 ? secs(z.s) : nil }.first
        // Only the left button, and only when the gold is really there: a short balance could turn into a gem offer.
        let isBin = s.t.contains { $0.y > 0.27 && $0.y < 0.3 && $0.x > 0.5 && $0.x < 0.66 && $0.s.contains("Bin") }
        if upIdx >= 0, !isBin || furniture[upIdx].bin, let cost, let g = gold(s), cost > 0, g >= cost + 1000, let b = s.t.first(where: { $0.s.hasPrefix("Upgr") && $0.x < 0.66 && $0.y > 0.7 }) {
          let until = Date().addingTimeInterval((tm ?? 600) + 20); upUntil = until; putStamp("upgrade_until.txt", until)
          await tap(s, b.x, 0.755, "YUKSELT \(nm) \(cost) altin=\(g) sure=\(Int(tm ?? -1))s"); upIdx = -1; completes = 0; await nap(2.5)
        } else {
          if cost != nil { log("diyalog: \(s.t.filter { $0.x > 0.5 && $0.y > 0.24 && $0.y < 0.8 }.map { $0.s })"); save(s.img, "upgrade_skip") }; if let cost, cost > 0, !isBin || anyNonBin == false { if Date().timeIntervalSince(upMinAt) > 1800 { upMin = cost } else { upMin = min(upMin, cost) }; upMinAt = Date() }; log("yukseltilemez: \(nm) bedel=\(cost ?? -1) altin=\(gold(s) ?? -1)")
          upIdx = upIdx >= 0 ? nextUp(upIdx, cost == nil) : -1
          if upIdx < 0 { upUntil = Date().addingTimeInterval(600) }
          await tap(s, 0.879, 0.254, "yukseltme X"); await nap(2)
        }
      }
      else if upIdx < 0, s.first("Edit Shop") != nil, let d = s.first("Done") { unknown = 0; await tap(s, d.x, d.y, "Design Done"); await nap(2.5) }
      // City
      else if s.first("Shop") != nil, s.t.contains(where: { $0.s.hasPrefix("Quest") && $0.y > 0.92 }) {
        unknown = 0
        let slots = s.t.filter { $0.y > 0.95 && $0.x > 0.5 && $0.x < 0.79 }
        if let d = slots.first(where: { secs($0.s) == nil && $0.s.count >= 4 }), lastQuestTap < 4 { lastQuestTap += 1; await tap(s, d.x, 0.92, "quest odulu (\(d.s))"); await nap(3); continue }
        if heroesDue, goCity, Date().timeIntervalSince(optAt) > 1200 { optLeft = 6; heroTab = 0; heroTrips += 1; if heroTrips > 3 { heroesDue = false; heroTrips = 0 } else { await tap(s, 0.203, 0.93, "Chars ac"); await nap(3); continue } }
        heroTrips = 0
        // A digit on the badge means a free party slot; "+" would offer to buy one and is never clicked.
        let badge: Bool? = yellowBadge(s) ? true : nil
        if goCity, badge != nil, Date() > questAt, Date() > questHold, Date() > questRest { await tap(s, 0.838, 0.91, "Quest ac"); await nap(3); continue }
        let nextT = slots.compactMap { secs($0.s) }.min()
        if badge != nil, questHold < Date() { questAt = min(Date().addingTimeInterval(nextT.map { $0 + 5 } ?? 240), max(questRest, Date().addingTimeInterval(30))) }
        else if Date() < questHold, nextT == nil { questAt = questHold } else if let nextT { questAt = Date().addingTimeInterval(nextT + 5) } else if questAt < Date() { questAt = Date().addingTimeInterval(180) }
        putStamp("quest_until.txt", questAt); lastQuestTap = 0; goCity = false
        log("quest: sonraki kontrol \(Int(questAt.timeIntervalSinceNow))s sonra")
        await tap(s, 0.124, 0.93, "dukkana don"); await nap(3.5)
      }
      else if s.t.filter({ $0.s == "Explore Area" }).count >= 1, s.has("Sort by") {
        unknown = 0; questBan = questBan.filter { $0.value > Date() }
        if questSent { questSent = false; await tap(s, 0.883, 0.135, "quest X (bos slot kontrolu)"); await nap(2.5); continue }
        // A boss card has no material counter; while a party is inside it shows a countdown instead of a button.
        let boss = s.t.first { l in l.y > 0.735 && l.y < 0.77 && l.s.filter { $0.isLetter }.count >= 5 && !s.t.contains { $0.y > 0.795 && $0.y < 0.82 && abs($0.x-l.x) < 0.05 && $0.s.contains("/") } && s.t.contains { $0.y > 0.85 && $0.y < 0.885 && abs($0.x-l.x) < 0.05 && secs($0.s) == nil && !$0.s.contains("Unlock") && $0.s.filter { $0.isLetter }.count >= 4 } }
        if let boss, Date() > bossBan, Date() > questRest { log("BOSS karti acik: \(boss.s) \(s.t.filter { abs($0.x-boss.x) < 0.06 && $0.y > 0.7 }.map { $0.s })"); save(s.img, "boss_kart"); questName = "BOSS " + boss.s; bossBan = Date().addingTimeInterval(300); await tap(s, boss.x, 0.69, "boss"); await nap(2.5); continue }
        var o: [(n: String, x: Double, have: Int, need: Int)] = []
        for l in s.t where l.y > 0.735 && l.y < 0.77 {
          guard let c = s.t.first(where: { $0.y > 0.795 && $0.y < 0.82 && abs($0.x-l.x) < 0.05 && $0.s.contains("/") }), s.t.contains(where: { $0.s == "Explore Area" && abs($0.x-l.x) < 0.04 }) else { continue }
          let q: [Int] = c.s.components(separatedBy: "/").compactMap { (v: String) -> Int? in Int(v.trimmingCharacters(in: .whitespaces)) }
          if q.count == 2, q[1] > 0, questBan[l.s] == nil { o.append((l.s, l.x, q[0], q[1])) }
        }
        log("quest secenekleri: \(o.map { "\($0.n) \($0.have)/\($0.need)" })")
        needMat = needMat.filter { Date().timeIntervalSince($0.value) < 3600 }
        let pref = o.filter { q in needMat.keys.contains { q.n.hasSuffix($0) || $0.hasSuffix(q.n) } }
        if !pref.isEmpty { log("eksik malzeme onceligi: \(needMat.keys.sorted())") }
        if Date() < questRest { goCity = false; await tap(s, 0.883, 0.135, "quest X (takim dinleniyor)"); await nap(2.5); continue }
        if let c = (pref.isEmpty ? o : pref).min(by: { Double($0.have)/Double($0.need) < Double($1.have)/Double($1.need) }), c.have < c.need { questName = c.n; await tap(s, c.x, 0.69, "quest \(c.n)"); await nap(2.5) }
        else { restNow(); questAt = questRest; goCity = false; await tap(s, 0.883, 0.135, "quest X"); await nap(2.5) }
      }
      else if s.has("Select Party"), s.has("Heal All") { unknown = 0; await tap(s, 0.894, 0.172, "takim secici X"); await nap(2) } // Heal All is never pressed
      else if s.first("Boost") != nil, s.first("Info") != nil, s.t.contains(where: { $0.y > 0.76 && $0.y < 0.81 && $0.x > 0.65 && $0.x < 0.8 }) {
        unknown = 0
        var q = s, why = ""
        let isBoss = questName.hasPrefix("BOSS")
        if isBoss { save(s.img, "boss_detay"); log("BOSS ekrani: \(s.t.map { $0.s })") }
        func diff(_ z: Shot) -> String { z.t.first { $0.y > 0.66 && $0.y < 0.70 && $0.x > 0.6 }?.s ?? "?" }
        func button(_ z: Shot) -> T? { z.t.first { $0.y > 0.76 && $0.y < 0.81 && $0.x > 0.65 && $0.x < 0.8 && ($0.s.hasPrefix("Explore") || isBoss) && greenAt(z, T(s: "", x: $0.x - 0.01, y: $0.y)) } }
        func good(_ z: Shot, _ y: Bool) -> Bool { button(z) != nil && partyOK(z, yellow: y) }
        // Medium pays about three times as much as Easy; used only when every face is green.
        if !isBoss, diff(q) == "Easy", party(q).reduce(0, { $0 + $1.p }) >= 900 { await tap(q, 0.875, 0.65, "zorluk +"); await nap(1.6); q = await look() }
        for _ in 0..<2 where !isBoss && diff(q) != "Easy" && !good(q, false) { await tap(q, 0.594, 0.65, "zorluk - (\(diff(q)) yuz=\(faces(q)))"); await nap(1.6); q = await look() }
        let y = yellowOK && !isBoss && diff(q) == "Easy"
        var ok = good(q, y)
        // Free places on the platform: add rested heroes, strongest first, until the faces are good. A card with a countdown is resting and is not touched.
        if !ok, !isBoss, diff(q) == "Easy" {
          for _ in 0..<3 where party(q).count < 3 && !partyOK(q, yellow: y) {
            if !q.has("Select Party") {
              guard let pl = q.t.first(where: { $0.s == "+" && $0.x < 0.5 && $0.y > 0.5 && $0.y < 0.65 }) else { break }
              await tap(q, pl.x, pl.y, "takima ekle +"); await nap(1.6); q = await look()
              if !q.has("Select Party") { break }
            }
            // Shortest rest countdown under the hero cards: the moment the next hero can be sent.
            let rests = q.t.filter { $0.x > 0.55 && $0.y > 0.33 && $0.y < 0.8 }.compactMap { secs($0.s) }
            if let m = rests.min() { restWake = Date().addingTimeInterval(min(900, max(30, m + 5))) }
            let free = q.t.compactMap { t -> (T, Int)? in
              guard t.x > 0.55, t.y > 0.33, t.y < 0.75, t.s.filter({ $0.isLetter }).isEmpty, let p = Int(t.s.filter { $0.isNumber }), p >= 100, !q.t.contains(where: { abs($0.x-t.x) < 0.04 && $0.y > t.y + 0.02 && $0.y < t.y + 0.06 && secs($0.s) != nil }) else { return nil }
              return (t, p) }
            guard let c = free.max(by: { $0.1 < $1.1 }) else { log("hazir kahraman yok: \(q.t.filter { $0.x > 0.55 }.map { $0.s })"); break }
            let n = party(q).count
            await tap(q, c.0.x - 0.01, c.0.y - 0.05, "takima ekle \(c.1)"); await nap(1.6); q = await look()
            if party(q).count <= n { break }
          }
          if q.has("Select Party") { await tap(q, 0.894, 0.172, "takim secici X"); await nap(1.6); q = await look() }
          ok = good(q, y)
        }
        // Keep the party as small as the faces allow, so the other heroes can fill the remaining quest slots.
        if ok, !isBoss {
          for _ in 0..<3 {
            let men = party(q).sorted { $0.p < $1.p }
            // Heroes under 500 cannot go alone anywhere: they stay with the strong ones, gain XP and shorten the trip.
            guard men.count > 1, let w = men.first(where: { $0.p >= 500 }), men.contains(where: { $0.p > w.p }) else { break }
            await tap(q, w.x - 0.013, w.y + 0.155, "takimdan cikar \(w.p) \(men.map { $0.p })"); await nap(1.6)
            let z = await look()
            guard party(z).count == men.count - 1 else { why = "cikmadi"; q = z; break }
            if z.has("Select Party"), partyOK(z, yellow: y) { q = z; continue }
            if z.has("Select Party"), let c = z.t.first(where: { t in t.x > 0.55 && t.y > 0.33 && t.y < 0.75 && (Int(t.s.filter { $0.isNumber }).map { $0 == w.p || $0 >= 100 && "\($0)".hasSuffix("\(w.p)") } ?? false) && !z.t.contains { abs($0.x-t.x) < 0.04 && $0.y > t.y + 0.02 && $0.y < t.y + 0.06 && secs($0.s) != nil } }) { await tap(z, c.x - 0.01, c.y - 0.05, "geri ekle \(w.p)"); await nap(1.6) } else { log("geri eklenemedi \(w.p): \(z.t.map { $0.s })"); save(z.img, "quest_picker") }
            q = await look(); break
          }
          if q.has("Select Party") { await tap(q, 0.894, 0.172, "takim secici X"); await nap(1.6); q = await look() }
          ok = good(q, y)
        }
        let mood = faces(q), men = party(q).map { $0.p }, dur = q.t.first { $0.y > 0.80 && $0.y < 0.845 && $0.x > 0.3 && $0.x < 0.42 }.flatMap { secs($0.s) }
        if ok, !isBoss, Date() < bossHold, men.contains(where: { $0 >= 900 }) { ok = false; why = "boss icin ayrildi" }
        if ok, isBoss { bossHold = .distantPast }
        if ok, let b = button(q) {
          log("QUEST GONDER \(questName) \(diff(q)) takim=\(men) yuz=\(mood) sure=\(Int(dur ?? -1))s"); questBan[questName] = Date().addingTimeInterval(20); questSent = true
          await tap(q, b.x, b.y, "\(b.s)"); await nap(3)
          let z = await look(); if z.first("Boost") != nil { log("gonderilemedi: \(z.t.map { $0.s })"); questBan[questName] = Date().addingTimeInterval(600); questSent = false; save(z.img, "quest_fail"); await tap(z, 0.894, 0.172, "quest detay X"); await nap(2) }
        } else {
          log("quest gonderilmedi \(questName) \(diff(q)) takim=\(men) yuz=\(mood) \(why): \(q.t.map{$0.s})"); save(q.img, "quest_skip"); questBan[questName] = Date().addingTimeInterval(300)
          // The same resting heroes would fail in every area: come back when some have rested. A boss refusal does not block ordinary quests.
          // Boss open but the party is not strong enough yet: keep the strong heroes out of ordinary quests for up to 45 minutes, once per boss.
          if isBoss, Date().timeIntervalSince(bossHold) > 3*3600 { bossHold = Date().addingTimeInterval(2700); log("BOSS icin guclu kahramanlar ayriliyor") }
          // Nobody is free: sleep until the first countdown ends. Free heroes with bad faces: the other areas are tried first.
          if !isBoss, men.isEmpty { restNow() }
          await tap(q, 0.894, 0.172, "quest detay X"); await nap(2.5)
        }
      }
      else if s.first("Skins") != nil || s.first("Edit") != nil || s.first("Rotate") != nil || s.first("Confirm") != nil, let x = s.first("Back") { unknown = 0; if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(60))) }; await tap(s, x.x, x.y, "mobilya Back"); await nap(2.5) }
      else if s.has("QUEST FAILED"), let b = s.t.first(where: { $0.s == "Continue" && $0.y > 0.85 }) {
        // Weak or hurt party: give it half an hour before the next attempt.
        unknown = 0; heroesDue = true; questFails += 1; yellowOK = false; questHold = Date().addingTimeInterval(600); log("QUEST BASARISIZ \(questFails): \(s.t.map{$0.s})"); await tap(s, b.x, b.y, "Continue"); await nap(3)
      }
      else if s.has("QUEST COMPLETE"), let b = s.t.first(where: { $0.s.hasPrefix("Collect") && $0.y > 0.85 }) { unknown = 0; log("QUEST ODULU: \(s.t.map{$0.s})"); heroesDue = true; questRest = .distantPast; await tap(s, b.x, b.y, "Collect All"); await nap(3) }
      // User approved: only while the window says both FREE and "at no cost".
      else if s.has("ROYAL MERCHANT FREE TRIAL"), s.has("at no cost"), s.first("FREE") != nil, trial < 3, let b = s.t.first(where: { $0.s.hasPrefix("Let") && $0.y > 0.7 }) { unknown = 0; trial += 1; await tap(s, b.x, b.y, "ucretsiz deneme"); await nap(4) }
      // OCR sometimes misses the lone "OK": accept the known green button of these reward windows.
      else if s.has("ITEM RECEIVED") || s.has("UPGRADE FINISHED") || s.has("TASK COMPLETED"), greenAt(s, T(s: "", x: 0.53, y: 0.93)) { unknown = 0; log("alindi (OK okunmadi): \(s.t.map{$0.s})"); if s.has("ITEM RECEIVED"), !s.has("Scroll") { offerNeed = 0; offerFails = 0 }; await tap(s, 0.499, 0.93, "OK konumu"); await nap(2.5) }
      else if s.first("Info") != nil, s.has("Aspiring") || s.has("Rank") , s.first("City") == nil, s.first("Boost") == nil, s.first("Optimize") == nil, let x = redX(s) { unknown = 0; heroesDue = false; optAt = Date(); log("sampiyon sayfasi"); await tap(s, x.x, x.y, "sampiyon X"); await nap(2.5) }
      // Hero page. Only Optimize, the ">" arrow and X are used; the heart (heal) can cost gems.
      else if s.has("Max equipment tier"), let o = s.first("Optimize") {
        unknown = 0
        let nm = s.t.first { abs($0.y-0.257) < 0.02 && $0.x > 0.55 && $0.x < 0.68 }?.s ?? "?", pw = s.t.first { abs($0.y-0.436) < 0.02 && $0.x < 0.6 }?.s ?? "?"
        if optLeft > 0 {
          optLeft -= 1
          if !s.has("On Quest") { await tap(s, o.x, o.y, "Optimize \(nm) guc=\(pw)"); await nap(2.5); let q = await look(); log("kahraman \(nm) \(pw) -> \(q.t.first { abs($0.y-0.436) < 0.02 && $0.x < 0.6 }?.s ?? "?")"); if q.first("Optimize") == nil { continue } }
          else { log("kahraman \(nm) questte") }
          if optLeft > 0 { await tap(s, 0.419, 0.487, "sonraki kahraman"); await nap(2) }
        } else { heroesDue = false; optAt = Date(); await tap(s, 0.879, 0.254, "kahraman X"); await nap(2) }
      }
      else if s.has("Unlock Hero Slot") { unknown = 0; await tap(s, 0.680, 0.365, "slot teklifi X"); await nap(2) }
      else if s.first("Champions") != nil, s.first("Workers") != nil, let hb = s.first("Heroes") {
        unknown = 0
        // Cards left of 0.37 are "add slot" and "heal": both can cost gems.
        let heroes = s.t.filter { $0.s == "Power" && $0.x > 0.37 && $0.y > 0.75 }
        if heroesDue, optLeft > 0, s.has("Add Hero Slot"), let h = heroes.min(by: { $0.x < $1.x }) { await tap(s, h.x, 0.69, "kahraman kart"); await nap(2.5) }
        else if heroesDue, optLeft > 0, heroTab < 2 { heroTab += 1; await tap(s, hb.x, 0.95, "Heroes sekmesi"); await nap(2) }
        else { heroesDue = false; heroTab = 0; await tap(s, 0.883, 0.135, "Chars X"); await nap(2.5) }
      }
      else if s.first("SPIN") != nil || s.has("Reroll") || (s.has("Furniture Upgrade") && s.first("Cancel") == nil) {
        riskSeen += 1; log("RISKLI PENCERE, sadece X: \(s.t.prefix(10).map{$0.s})"); save(s.img, "risk\(riskSeen % 4)")
        if let b = lastBubble { notCustomers.append(b); lastBubble = nil; achAt = Date() }
        if riskSeen > 12 { stop("riskli pencere kapanmiyor", s) }
        if s.first("SPIN") != nil, let sh = s.t.first(where: { $0.s == "Shop" && $0.x < 0.25 && $0.y > 0.85 }) { await tap(s, sh.x, 0.915, "Shop (carktan cik)") }
        else if let x = redX(s) { await tap(s, x.x, x.y, "X") }
        await nap(4)
      }
      else if s.has("Missing requirements"), let x = redX(s) { unknown = 0; restockItem = ""; for k in restocked.keys where Date().timeIntervalSince(restocked[k]!) < 90 { restocked[k] = Date.distantPast }; await tap(s, x.x, x.y, "eksik pencere X"); await nap(2) }
      else if s.has("unlocked"), let b = s.t.first(where: { $0.s.hasPrefix("Got it") }) { unknown = 0; log("bilgi: \(s.t.map{$0.s})"); await tap(s, b.x, b.y, "Got it"); await nap(2.5) }
      else if s.has("Daily login") {
        unknown = 0
        // The claimable day is the green card; everything else is red or gold.
        let g = blobs(s, 0.3...0.68, 0.36...0.78) { r, g, b in g > 190 && r > 90 && r < 175 && b < 165 && g > b + 50 }.filter { $0.w >= 14 && $0.h >= 10 }.max { $0.n < $1.n }
        if let g, dailyTries < 2 { dailyTries += 1; await tap(s, g.x, g.y, "gunluk odul CLAIM"); await nap(3.5) }
        else { if let b = lastBubble { notCustomers.append(b); lastBubble = nil; achAt = Date() }; await tap(s, 0.893, 0.108, "gunluk odul X"); await nap(2.5) }
      }
      else if s.has("BLITZ PASS"), s.has("Ends in") { unknown = 0; log("gem teklifi kapatiliyor"); await tap(s, 0.680, 0.332, "X (Blitz Pass)"); await nap(2.5) }
      else if s.has("inventory is full"), s.first("Wallace") != nil { unknown = 0; invFull = true; log("ENVANTER DOLU"); await tap(s, 0.5, 0.87, "konusmayi gec"); await nap(2.5) }
      else if s.buyer, let sell = s.first("Sell") ?? s.first("Restock"), let wait = s.first("Wait") {
        unknown = 0; empty = 0
        // Step to the next customer with ">" instead of going back to the shop, so one visible bubble is enough.
        func leave() async { cust = ""; if waitRow >= 3 { waitRow = 0; hops = 9; noSaleUntil = Date().addingTimeInterval(12) }; if hops < 3, arrow(s) { hops += 1; await tap(s, 0.665, 0.249, "sonraki musteri >") } else { hops = 0; await tap(s, wait.x, wait.y, "Wait") } }
        let letters = { (z: String) -> String in z.components(separatedBy: " ").map { (w: String) -> String in w.filter { $0.isLetter } }.filter { $0.count >= 3 }.joined(separator: " ") }
        let who = s.header, item = letters(s.t.first { $0.y > 0.19 && $0.y < 0.235 }?.s ?? ""), v = price(s), en = energy(s)
        let pw = plain(who), cls = pw.range(of: "want").map { String(pw[..<$0.lowerBound]) } ?? pw
        var key: String = String(cls.filter { $0.isLetter }.prefix(6)) + String(cls.filter { $0.isNumber })
        // Header misread for one frame: same item on the same open screen is the same customer.
        if key != cust, !cust.isEmpty, !item.isEmpty, norm(item) == custItem, Date().timeIntervalSince(custAt) < 8 { key = cust }
        custItem = norm(item); custAt = Date()
        if key != cust { cust = key; applied = ""; skip = 0; if keepSuggest { keepSuggest = false } else { suggested = false }; if basePrice[key] == nil, let v { basePrice[key] = v } }
        if applied.isEmpty, let v { basePrice[key] = v }
        guard let bp = basePrice[key] ?? v, let en else { // unreadable: look again a few times, then move on
          unread += 1; log("fiyat/enerji okunamadi \(unread)"); if unread >= 4 { unread = 0; if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(45))) }; await leave() }; await nap(2); continue
        }
        unread = 0
        let sorted = prices.sorted(), med = sorted.isEmpty ? 80 : sorted[sorted.count/2]
        // high: surcharge when the energy is there. waitWorthy: valuable enough to keep the customer waiting for it.
        let high = bp >= max(200, med), waitWorthy = offerNeed == 0 && bp >= max(600, med*2), low = bp <= 200
        let ct = s.t.first(where: { abs($0.x-0.834) < 0.03 && abs($0.y-0.638) < 0.03 })?.s.components(separatedBy: "-").last.flatMap({ Int($0) })
        let near = Double(en.0) >= 0.85*Double(en.1) // energy almost full: a discount would be wasted
        func sayTalk() async -> Bool {
          guard talked[key] == nil, let st = s.first("Small talk") else { return false }
          talked[key] = Date(); await tap(s, st.x, st.y, "Small talk \(item) enerji=\(en.0)"); await nap(2.5); return true
        }
        talked = talked.filter { Date().timeIntervalSince($0.value) < 900 }
        // OCR can garble one letter of the item ("TBlack Robe"): same buyer text means same customer.
        func same(_ o: String) -> Bool { o == key || o.components(separatedBy: "|").first == key.components(separatedBy: "|").first }
        // Valuable item, not enough energy: only the most valuable customer waits, others are sold normally.
        waiting = waiting.filter { Date().timeIntervalSince($0.value.1) < 180 }
        // Equal price: the one who started waiting first keeps waiting. Both must have been read twice, so a misread name cannot count as a second customer.
        let tied = waiting.contains { w in !same(w.key) && w.value.0 == bp && (seen[w.key] ?? 0) >= 2 && (seen[key] ?? 0) >= 2 && (firstWait[w.key] ?? .distantFuture) < (firstWait[key] ?? Date()) }
        let force = Date() < forceUntil
        let beaten = tied || waiting.contains { !same($0.key) && $0.value.0 > bp }
        let restock = s.first("Restock") != nil
        if !suggested, restock || (applied.isEmpty && !sellGreen(s)) {
          if stockWait[key] == nil { stockWait[key] = Date(); save(s.img, "stok_yok") }
          let waited = Date().timeIntervalSince(stockWait[key]!)
          if !item.isEmpty, wanted[norm(item)] == nil { wanted[norm(item)] = Date(); log("ISTENEN craft listesine: \(item)") }
          if waited > 480, bp < 200, s.first("Suggest") == nil, let no = s.first("Refuse") { log("uzun suredir karsilanamadi, reddet: \(item)"); wanted[norm(item)] = nil; stockWait[key] = nil; await tap(s, no.x, no.y, "Refuse (stok yok)"); await nap(2.5); continue }
          if restock, offerNeed == 0, slotsKnown, free > 0, restocked[key] == nil, invRoomOK(room), made < maxC, let rb = s.first("Restock") {
            restocked[key] = Date(); restockItem = item; log("RESTOCK \(item) \(bp)"); await tap(s, rb.x, rb.y, "Restock"); await nap(2.2)
            let m = await look()
            // Only the green Craft button; Market is never pressed here.
            if m.has("Missing requirements"), let cb = m.t.first(where: { $0.s == "Craft" && $0.y > 0.6 && $0.y < 0.75 && $0.x > 0.52 }) { await tap(m, cb.x, cb.y, "Restock > Craft"); await nap(2.2) }
            else { log("restock penceresi farkli: \(m.t.prefix(12).map{$0.s})"); save(m.img, "restock_odd"); restockItem = ""; restocked[key] = Date.distantPast; if let x = redX(m) { await tap(m, x.x, x.y, "X"); await nap(2) } }
            continue
          }
          // A craft was queued: give it a few minutes. Otherwise (or afterwards) offer something else for 5 energy.
          let queued = restocked[key].map { $0 != Date.distantPast } ?? false
          if !queued || waited > 240, let sg = s.first("Suggest"), en.0 >= 5 {
            suggested = true; log("STOK YOK, baska esya oner: \(item) \(bp)"); await tap(s, sg.x - 0.01, sg.y, "Suggest"); await nap(2); basePrice[key] = nil; keepSuggest = true; continue
          }
          log("STOK YOK bekle \(item) \(bp)"); waiting[key] = (bp, Date()); cust = ""
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(25))) }
          await leave(); await nap(2.5); continue
        }
        // Spend first when affordable, so a failed chat cannot cost the surcharge.
        if applied.isEmpty, !beaten, high || near, let ct, ct <= en.0, let sc = s.first("Surcharge") {
          applied = "S"; await tap(s, sc.x, sc.y, "Surcharge \(item) \(bp) enerji=\(en.0)-\(ct) medyan=\(med)"); await nap(1.5); continue
        }
        if await sayTalk() { continue }
        if firstWait[key] == nil { firstWait[key] = Date() }
        let close = offerNeed == 0 && bp >= 400 && (ct.map { $0 > en.0 && $0 - en.0 <= 5 } ?? false) && Date().timeIntervalSince(firstWait[key]!) < 90
        if !force, applied.isEmpty, waitWorthy || close, !beaten, Date().timeIntervalSince(firstWait[key]!) < (room == 0 || !arrow(s) ? ((ct ?? 99) - en.0 <= 5 ? 180 : 60) : 300), let ct, ct > en.0, ct <= en.1 {
          save(s.img, "beklet_\(waits % 6)"); log("BEKLET \(item) \(bp) enerji=\(en.0)/\(ct)"); waits += 1; waitRow += 1; seen[key, default: 0] += 1; waiting[key] = (bp, Date())
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(45))) }
          cust = ""; await leave(); await nap(2.5); continue
        }
        if applied.isEmpty, low, !near, let dc = s.first("Discount") {
          applied = "D"; await tap(s, dc.x, dc.y, "Discount \(item) \(bp) enerji=\(en.0) medyan=\(med)"); await nap(1.5); continue
        }
        if skip >= 1 {
          if !suggested, let sg = s.first("Suggest"), en.0 >= 25 { suggested = true; skip = 0; await tap(s, sg.x - 0.01, sg.y, "Suggest (stokta yok) \(key)"); await nap(2); cust = ""; continue }
          log("satilamadi: \(key)"); save(s.img, "sell_fail"); skip = 0; cust = ""
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(120))) }
          await leave(); await nap(2.5); continue
        }
        if restock { // opens the market: not used
          log("Restock'a basilmadi, bekle: \(item)"); cust = ""; suggested = false; noSaleUntil = Date().addingTimeInterval(8)
          if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(60))); lastBubble = nil }
          await leave(); await nap(2.5); continue
        }
        await tap(s, sell.x, sell.y, "Sell \(item) taban=\(bp) fiyat=\(v ?? -1) enerji=\(en.0)/\(en.1) zamBedeli=\(ct ?? -1) [\(applied)]"); await nap(2.5)
        let after = await look()
        guard let g0 = gold(s), let g1 = gold(after), g1 > g0 else { skip += 1; continue }
        lastBubble = nil; hops = 0; waitRow = 0; seen[key] = nil; if !item.isEmpty {
          let ni = norm(item); values[ni] = bp; lines.keys.forEach { k in if lines[k]!.names.contains(where: { ni.hasSuffix($0) || $0.hasSuffix(ni) }) { lines[k]!.stock = max(0, lines[k]!.stock - 1) } }
          if let d = try? JSONEncoder().encode(values) { try? d.write(to: URL(fileURLWithPath: "logs/values.json")) }
        }
        sold += 1; earned += g1-g0; lastSoldAt = Date(); prices.append(bp); if prices.count > 30 { prices.removeFirst() }
        try? prices.map(String.init).joined(separator: ",").write(toFile: "logs/prices.txt", atomically: true, encoding: .utf8)
        talked[key] = nil; firstWait[key] = nil; stockWait[key] = nil; restocked[key] = nil; keepSuggest = false; basePrice[key] = nil; waiting[key] = nil; cust = ""; applied = ""; suggested = false
        invFull = false; collects = 0; completes = 0; if room >= 0 { room += 1 }
      }
      else if s.first("Recent") != nil && s.first("Bookmark") != nil || s.t.contains(where: { $0.s == "Craft" && abs($0.y-0.411) < 0.02 && abs($0.x-0.536) < 0.02 }) || s.t.contains(where: { $0.s.contains("Dabbler") && $0.y > 0.12 && $0.y < 0.165 && $0.x < 0.3 }) {
        unknown = 0
        if !restockItem.isEmpty {
          let w = restockItem.components(separatedBy: " ").max { $0.count < $1.count } ?? restockItem
          let lab = s.t.first { l in l.y > 0.735 && l.y < 0.775 && l.s.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil && !s.t.contains { abs($0.x-l.x) < 0.06 && $0.y > 0.78 && $0.y < 0.85 && $0.s.filter { $0.isLetter }.count >= 4 } }
          var done = false
          if let lab, base != nil {
            let full = restockItem; restockItem = ""
            await tap(s, 0.0857 + 0.1438*((lab.x-0.0857)/0.1438).rounded(.down) + 0.069, 0.69, "restock uret \(full)"); await nap(1)
            let r = await look(); done = r.has("begun")
            if done { made += 1; log("BASLADI (restock) \(full) toplam=\(made)") } else { log("restock baslamadi \(full): \(r.t.prefix(10).map{$0.s})"); save(r.img, "restock_fail") }
            if r.has("Missing requirements"), let x = redX(r) { await tap(r, x.x, x.y, "eksik X"); await nap(1.5) }
          } else { log("restock karti yok/kilitli: \(restockItem)"); restockItem = "" }
          if !done { for k in restocked.keys where Date().timeIntervalSince(restocked[k]!) < 60 { restocked[k] = Date.distantPast } }
          await nap(0.8)
          let z = await look()
          if z.t.contains(where: { $0.s == "Craft" && abs($0.y-0.411) < 0.02 }) { await tap(z, 0.883, 0.135, "restock craft X"); await nap(2.2) }
          continue
        }
        guard free > 0, made < maxC, misses < plan.count + 4 else {
          if misses >= plan.count + 4 { blockedUntil = Date().addingTimeInterval(60); log("uretilebilir kart yok") }
          misses = 0; free = 0; await tap(s, 0.883, 0.135, "craft kapat"); await nap(2.5); continue
        }
        if base == nil { stop("gem okunamadi, craft yapilmaz", s) }
        // 1) a line known to hold fewer than 2 items  2) a line not looked at recently  3) the most valuable line.
        let now = Date()
        func fresh(_ n: String) -> Line? { lines[n].flatMap { now.timeIntervalSince($0.at) < ($0.craftable ? 900 + 300*Double(min($0.stock, 10)) : 1500) ? $0 : nil } }
        var pick: Int? = nil, why = ""
        wanted = wanted.filter { now.timeIntervalSince($0.value) < 900 }
        func wants(_ n: String) -> String? { wanted.keys.first { w in (lines[n]?.names ?? []).contains { $0.hasSuffix(w) || w.hasSuffix($0) } && banned.keys.first { norm($0) == w } == nil } }
        let order = (0..<plan.count).map { ($0 + turn) % plan.count }
        if let k = (0..<plan.count).first(where: { wants(plan[$0].name) != nil }) { pick = k; why = "istenen" }
        else if lookRow < 3, let k = order.first(where: { lines[plan[$0].name] == nil }) { pick = k; why = "bak" } // never looked at, e.g. a newly unlocked tab
        else if let k = order.filter({ fresh(plan[$0].name).map { $0.craftable && $0.stock < 2 } ?? false }).min(by: { fresh(plan[$0].name)!.stock < fresh(plan[$1].name)!.stock }) { pick = k; why = "eksik" }
        else if lookRow < 3 || !order.contains(where: { lines[plan[$0].name]?.craftable ?? false }), let k = order.first(where: { fresh(plan[$0].name) == nil }) { pick = k; why = "bak" }
        else {
          // Spread a little: every item already in stock lowers the line's appeal.
          func score(_ k: Int) -> Double { guard let l = lines[plan[k].name] else { return -1 }; return Double(l.value) / (1 + 0.25*Double(l.stock)) }
          if let k = order.filter({ lines[plan[$0].name]?.craftable ?? false }).max(by: { score($0) < score($1) }) { pick = k; why = "deger" }
        }
        guard let pk = pick else { misses = plan.count + 4; continue }
        let t = plan[pk]
        if why == "bak" { lookRow += 1 }
        if why == "bak" { turn = (pk + 1) % plan.count; try? "\(turn)".write(toFile: "logs/turn.txt", atomically: true, encoding: .utf8) }
        if lastCat != t.cat { await tap(s, t.cat, 0.952, "sekme \(t.name)"); await nap(0.8) }; lastCat = t.cat; await tap(s, t.sub, 0.957, "alt sekme \(t.name)"); await nap(0.8)
        var q = await look()
        let head = { (z: Shot) -> String in z.t.first { $0.y > 0.12 && $0.y < 0.165 && $0.x > 0.15 && $0.x < 0.3 && $0.s.filter { $0.isLetter }.count >= 5 }?.s ?? "" }
        let wantMap = ["silah1": "Sword", "silah2": "Axe", "silah5": "Spear", "silah6": "Bow", "silah7": "Staff", "iksir1": "Medicine", "iksir5": "Ring", "iksir6": "Amulet"]
        let want = wantMap[t.name]
        for k in 0..<3 {
          let h = head(q)
          // The title lags or is misread: different cards, or cards of the wanted kind, also prove the tab changed.
          let names = cards(q).map { norm($0.name) }
          let alien = wantMap.contains { $0.key != t.name && h.contains($0.value) } // still on another, known tab
          if !names.isEmpty, want != nil || !alien, want.map({ w in names.contains { $0.hasSuffix(w.lowercased()) } }) ?? (!lastNames.isEmpty && !names.contains { lastNames.contains($0) }) { break }
          if h.isEmpty || !alien && (want.map { h.contains($0) } ?? (h != lastHead || lastLine == t.name)) { break }
          await tap(q, t.sub + 0.002*Double(k), 0.950, "alt sekme tekrar \(t.name) (\(h))"); await nap(1.0); q = await look()
        }
        lastHead = head(q); lastLine = t.name; lastNames = cards(q).map { norm($0.name) }
        banned = banned.filter { $0.value > Date() }
        let lineCards = q.first("Craft") != nil || !head(q).isEmpty ? cards(q) : []
        // Items still in the craft queue are not in the on-screen stock yet.
        queue[t.name] = (queue[t.name] ?? []).filter { now.timeIntervalSince($0) < 240 }
        let lineStock = lineCards.reduce(0) { $0 + $1.stock } + (queue[t.name]?.count ?? 0)
        let usable = lineCards.filter { banned[$0.name] == nil }
        func worth(_ k: Card) -> Int { values[norm(k.name)] ?? [0, 70, 300, 1000, 2500, 6000][min(k.tier, 5)] }
        let wish = wants(t.name)
        let wishCard = usable.first { k in wanted.keys.contains { w in norm(k.name).hasSuffix(w) || w.hasSuffix(norm(k.name)) } }
        if why == "istenen", wishCard == nil, let wish { wanted[wish] = nil }
        guard let c = wishCard ?? usable.max(by: { worth($0) < worth($1) }) else {
          lines[t.name] = Line(stock: lineStock, value: 0, names: lineCards.map { norm($0.name) }, at: now, craftable: false); misses += 1; continue
        }
        lines[t.name] = Line(stock: lineStock, value: worth(c), names: lineCards.map { norm($0.name) }, at: now, craftable: true)
        if why == "istenen", wishCard == nil { misses += 1; continue }
        if wishCard != nil { wanted.keys.filter { w in norm(c.name).hasSuffix(w) || w.hasSuffix(norm(c.name)) }.forEach { wanted[$0] = nil }; why = "istenen" }
        if why == "bak", lineStock >= 2 { misses += 1; log("\(t.name) \(c.name) T\(c.tier) stok=\(lineStock) deger=\(worth(c)): yeterli, sonra"); continue }
        if why == "eksik", lineStock >= 2 { misses += 1; continue }
        // Try the best card; when its materials are missing, step down to the next one in the same tab right away.
        var tryCard: Card? = c, cur = q, started = false
        for attempt in 0..<4 {
          guard let k = tryCard else { break }
          await tap(cur, k.x, 0.69, "craft \(t.name) \(k.name) T\(k.tier) stok=\(lineStock) deger=\(worth(k)) [\(why)]\(attempt > 0 ? " alt-tier" : "")"); await nap(0.8)
          let r = await look()
          if r.has("begun") { started = true; lookRow = 0; made += 1; free -= 1; misses = 0; lines[t.name]?.stock += 1; queue[t.name, default: []].append(Date()); collects = 0; log("BASLADI \(k.name) toplam=\(made)"); break }
          save(r.img, "craft_fail"); banned[k.name] = Date().addingTimeInterval(1200)
          guard r.has("Missing requirements") else { log("baslamadi \(k.name): \(r.t.prefix(8).map{$0.s})"); break }
          let win = r.t.filter { $0.x > 0.3 && $0.x < 0.7 && $0.y > 0.3 && $0.y < 0.75 }.map { $0.s }
          var mat = ""
          if r.has("Missing components"), !win.contains("Craft") { mat = material(r); if !mat.isEmpty { needMat[mat] = Date() } }
          log("baslamadi \(k.name): \(win) malzeme=\(mat)")
          // The window may offer paid ways out: only the X is used.
          let x = blobs(r, 0.6...0.75, 0.2...0.45, { r, g, b in r > 200 && g > 50 && g < 120 && b < 90 }).filter { $0.n >= 50 }.max { $0.n < $1.n }
          await tap(r, x?.x ?? 0.680, x?.y ?? 0.323, "eksik kaynak X"); await nap(1.3)
          cur = await look()
          if cur.has("Missing requirements") || cur.first("City") != nil { break }
          tryCard = usable.filter { banned[$0.name] == nil }.max { worth($0) < worth($1) }
        }
        if !started { misses += 1; lines[t.name]?.craftable = usable.contains { banned[$0.name] == nil } }
        if let d = try? JSONEncoder().encode(lines) { try? d.write(to: URL(fileURLWithPath: "logs/lines.json")) }
        await nap(1)
      }
      else if s.first("City") != nil, let cr = s.first("Craft") {
        unknown = 0
        if s.has("Tap the bubble"), talks < 40, let b = bubbles(s, 45).first(where: { $0.y > 0.4 && abs($0.x-0.5) < 0.09 }) { talks += 1; await tap(s, b.x, b.y, "NPC balonu"); await nap(3); continue }
        if gems(s) == nil { noGem += 1; if noGem >= 10 { stop("gem okunamiyor, muhtemelen ogretici", s) }; await nap(4); continue } else { noGem = 0 }
        if completes < 5, let c = s.t.first(where: { $0.s.hasPrefix("COMPLETE") && $0.y > 0.2 && $0.y < 0.75 }) { completes += 1; await tap(s, c.x, c.y, "biten yukseltme"); await nap(3); continue }
        // A countdown over the furniture means an upgrade is already running.
        if let left = s.t.filter({ $0.x > 0.18 && $0.x < 0.83 && $0.y > 0.1 && $0.y < 0.8 && $0.s.count <= 9 && $0.s.contains { $0.isNumber } }).compactMap({ secs($0.s) }).max(), left > 20 {
          let u = Date().addingTimeInterval(left + 10); if abs(u.timeIntervalSince(upUntil)) > 60 { let ok = abs(u.timeIntervalSince(upSeen)) < 30; upSeen = u; if ok { upUntil = u; putStamp("upgrade_until.txt", u); upIdx = -1; log("yukseltme suruyor: \(Int(left))s") } }
        }
        skipB = skipB.filter { $0.t > Date() }
        if Date().timeIntervalSince(achAt) > 300 { notCustomers = [] }
        let bs = bubbles(s).filter { b in !notCustomers.contains { abs($0.x-b.x) < 0.04 && abs($0.y-b.y) < 0.06 } && !skipB.contains { abs($0.x-b.x) < 0.03 && abs($0.y-b.y) < 0.04 } }
        let raw = bubbles(s).count
        let parked = saveFor > 0 && Date().timeIntervalSince(saveAt) < 300 ? 1 : 0 // the seller we are saving for
        if raw <= parked || !bs.isEmpty { starve = Date() }
        else if Date().timeIntervalSince(starve) > 30 { log("UYARI: \(raw) balon var ama hepsi atlaniyor, yasaklar siliniyor (skip=\(skipB.count) musteriDegil=\(notCustomers.count))"); skipB = []; notCustomers = []; starve = Date(); noSaleUntil = Date.distantPast }
        if room < 0, Date().timeIntervalSince(capAt) > 20, let iv = s.first("Inventory") { capAt = Date(); await tap(s, iv.x, iv.y, "envanter ac"); await nap(2.5); continue }
        if Date().timeIntervalSince(questAt) > 45, craftSeen != .distantPast || Date().timeIntervalSince(started) > 150, let ct = s.first("City") { goCity = true; await tap(s, ct.x, 0.93, "City (quest bekliyor)"); await nap(4); continue }
        if Date() > noSaleUntil, empty < 4, let b = bs.min(by: { $0.x < $1.x }) { empty += 1; lastBubble = b; log("balon hedef=(\(String(format: "%.3f,%.3f", b.x, b.y)))"); if empty >= 2 { save(s.img, "bostik\(empty)"); log("onceki balon acilmadi, hedef=(\(b.x),\(b.y))") }; await tap(s, b.x, b.y, "musteri \(bs.count) balon"); await nap(2.5); continue }
        if empty >= 4 { empty = 0; noSaleUntil = Date().addingTimeInterval(20) }
        if collects >= craftSlots + 2 { invFull = true } // more taps than slots without a craft in between: nothing is being collected
        if !invFull, offerNeed == 0, let r = s.t.filter({ $0.s == "Ready" && $0.y > 0.9 }).max(by: { $0.x < $1.x }) { collects += 1; await tap(s, r.x, 0.92, "topla"); await nap(2.5); continue }
        if Date().timeIntervalSince(craftSeen) < 60, Date().timeIntervalSince(saveAt) > 1200, Date() > upUntil, upIdx >= 0 || Date().timeIntervalSince(upMinAt) > 1800 || (gold(s) ?? 0) >= upMin + 1000, upIdx >= 0 || Date() > upNext, let dz = s.first("Design") { if upIdx < 0 { upIdx = 0; anyNonBin = false; upNext = Date().addingTimeInterval(300) }; upTries += 1; if upTries > 14 { upTries = 0; upIdx = -1; upUntil = Date().addingTimeInterval(600) } else { await tap(s, dz.x, 0.93, "Design ac"); await nap(3); continue } } else { upTries = 0 }
        if Date() > questAt, craftSeen != .distantPast || Date().timeIntervalSince(started) > 150, let ct = s.first("City") { goCity = true; await tap(s, ct.x, 0.93, "City"); await nap(4); continue }
        if Date().timeIntervalSince(capAt) > (offerNeed > 0 ? 90 : 240), let iv = s.first("Inventory") { capAt = Date(); await tap(s, iv.x, iv.y, "envanter ac"); await nap(2.5); continue }
        if made >= maxC, sold == 0 { if !s.t.contains(where: { $0.y > 0.95 && $0.x > 0.55 && $0.x < 0.79 }) { stop("craft limiti doldu, toplanacak yok") }; await nap(5); continue }
        // Badge on the Craft button = free slots.
        let b = ocr(crop(s, 0.855, 0.815, 0.04, 0.06, 3)).first { Int($0.s) != nil }
        // Badge may show "!" instead of a count: then start one craft only if no craft is visible.
        // Badge: number = free slots, green "+" = all busy (would sell a slot), red "!" hides the number.
        let strip = ocr(crop(s, 0.48, 0.945, 0.31, 0.05, 2)).filter { $0.s == "Ready" || secs($0.s) != nil || $0.s.filter { $0.isNumber }.count >= 1 }.count
        free = greenBadge(s) ? 0 : (b.flatMap { Int($0.s) }.map { min($0, craftSlots) } ?? max(0, craftSlots - strip))
        if raw <= parked, free == 0 || Date() < blockedUntil || room == 0, Date().timeIntervalSince(lastSoldAt) < 1200 { progAt = Date() }
        slotsKnown = true; craftSeen = Date(); log("dukkan: satis=\(sold) kazanc=\(earned) bekletme=\(waits) alim=\(bought) craft=\(made) bos slot=\(free) gem=\(gems(s).map(String.init) ?? "?")")
        if offerNeed > 0, Date().timeIntervalSince(offerSince) > 1500 { offerNeed = 0 }
        if free > 0, offerNeed == 0, !invFull, room < 0 || room > 1, Date() > blockedUntil { lastCat = -1; lookRow = 0; lastNames = []; await tap(s, cr.x, cr.y, "Craft ac"); await nap(2.0) } else { await nap(5) }
      }
      // Story dialogue: speaker label plus a long text line in the lower box, no currency bar on screen.
      else if talks < 40, gems(s) == nil, s.t.contains(where: { abs($0.x-0.235) < 0.06 && abs($0.y-0.778) < 0.03 }),
              s.t.contains(where: { $0.y > 0.82 && $0.y < 0.93 && $0.s.count > 8 }), s.first("OK") == nil, s.first("Continue") == nil {
        talks += 1; log("konusma: \(s.t.map{$0.s})"); await tap(s, 0.5, 0.87, "konusma"); await nap(2.5)
      }
      else if let b = s.t.first(where: { t in ["OK","OKl","Continue","Collect","Claim","Great!"].contains(t.s) && t.y > 0.6 && greenAt(s, t) }) { generic += 1; if generic > 30 { stop("cok fazla pencere", s) }; log("yesil pencere: \(s.t.map{$0.s})"); await tap(s, b.x, b.y, b.s); await nap(2.5) }
      else if unknown >= 3, let w = s.first("Wait") { unknown = 0; log("bilinmeyen ziyaretci: \(s.t.map{$0.s})"); save(s.img, "visitor"); if let b = lastBubble { skipB.append((b.x, b.y, Date().addingTimeInterval(60))) }; await tap(s, w.x, w.y, "Wait"); await nap(2.5) }
      else if unknown >= 3, closes < 40, let x = redX(s) { closes += 1; unknown = 0; log("X ile kapat: \(s.t.prefix(8).map{$0.s})"); save(s.img, "closed\(closes)"); await tap(s, x.x, x.y, "X"); await nap(3) }
      else if unknown >= 4, let b = s.t.first(where: { ["Close","Skip","Later","Not now","No thanks","Cancel","Back","Done","Got it!"].contains($0.s) && $0.y > 0.3 }) { closes += 1; log("guvenli dugme: \(b.s) \(s.t.map { $0.s })"); save(s.img, "unknown_\(tag())"); unknown += 1; if unknown >= 12 { await recover("tanimadigim ekran", s); continue }; await tap(s, b.x, b.y, b.s); await nap(3) }
      else { unknown += 1; if unknown == 3 { save(s.img, "unknown_\(tag())") }; log("bilinmeyen ekran \(unknown)/15: \(s.t.prefix(6).map{$0.s})"); if unknown >= 12 { await recover("tanimadigim ekran", s); continue }; await nap(4) }
    }
    stop("sure doldu")
  }
}
