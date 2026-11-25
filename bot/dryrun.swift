// Dry run on a saved screenshot: classify the screen, read craft cards, rank them. Contains no input code.
import AppKit
import Vision
struct T { let s: String; let x, y: CGFloat }
func ocr(_ i: CGImage) -> [T] {
  let r = VNRecognizeTextRequest(); r.recognitionLevel = .accurate; r.usesLanguageCorrection = false
  try? VNImageRequestHandler(cgImage: i).perform([r])
  return (r.results ?? []).compactMap { o in o.topCandidates(1).first.map { T(s: $0.string, x: o.boundingBox.midX, y: 1 - o.boundingBox.midY) } }
}
guard CommandLine.arguments.count == 2, let img = NSImage(contentsOfFile: CommandLine.arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("goruntu acilamadi"); exit(1) }
let W = CGFloat(img.width), H = CGFloat(img.height)
// Regions are in a 1470x923 reference frame.
func crop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, scale: CGFloat = 1) -> CGImage {
  let c = img.cropping(to: CGRect(x: x/1470*W, y: y/923*H, width: w/1470*W, height: h/923*H))!
  let cw = Int(CGFloat(c.width)*scale), ch = Int(CGFloat(c.height)*scale)
  let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high; ctx.draw(c, in: CGRect(x: 0, y: 0, width: cw, height: ch)); return ctx.makeImage()!
}
func read(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> String { ocr(crop(x,y,w,h,scale:2)).sorted{$0.x<$1.x}.map{$0.s}.joined(separator: " ") }
func rgb(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> [Int] {
  let c = crop(x,y,w,h), d = c.dataProvider!.data! as Data; var t = [0,0,0]; let n = c.width*c.height
  for i in 0..<n { for k in 0..<3 { t[k] += Int(d[i*4+k]) } }; return t.map{$0/n}
}
let all = ocr(img), has = { (s: String) in all.contains { $0.s == s } }
let screen = has("Recent") && has("Bookmark") ? "craft" : all.contains { $0.s.hasPrefix("Max Capacity") } ? "envanter" : has("City") && has("Craft") ? "dukkan" : "bilinmeyen"
print("ekran=\(screen)")
guard screen == "craft" else { print("karar: craft ekrani degil, islem yok"); exit(0) }
print("kaynaklar: \([1171,1232,1293].map { read($0-30, 515, 60, 25) })")
struct Card { let n: Int, name: String, stock: String, cost: String, done: Int, need: Int, coin: Bool }
var cards: [Card] = []
for n in 0..<5 { // the sixth card is cut off by the screen edge
  let l: CGFloat = 126 + CGFloat(n)*211.4
  let p = read(l+45, 792, 105, 26).split(separator: "/").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
  let c = rgb(l+170, 794, 18, 16)
  let coin = c[0] > 200 && c[2] < 110
  let k = Card(n: n, name: read(l+50, 682, 120, 25), stock: read(l+145, 645, 45, 30), cost: read(l+30, 754, 140, 26), done: p.count==2 ? p[0] : -1, need: p.count==2 ? p[1] : -1, coin: coin)
  cards.append(k); print("kart\(n+1) \(k) odulRGB=\(c)")
}
let ok = cards.filter { $0.need > 0 && !$0.coin }.sorted { ($0.need-$0.done, $0.n) < ($1.need-$1.done, $1.n) }
print("blueprint adaylari:"); for c in ok { print("  \(c.name): \(c.need-c.done) craft kaldi") }
