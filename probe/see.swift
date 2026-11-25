// Read-only probe: find the game window, capture it, OCR it. Sends no input.
import AppKit
import ScreenCaptureKit
import Vision

func die(_ m: String) -> Never { print("HATA: \(m)"); exit(1) }

@main struct See {
  static func main() async throws {
    setvbuf(stdout, nil, _IONBF, 0)
    let out = CommandLine.arguments[1]
    print("ekranKaydi=\(CGPreflightScreenCaptureAccess()) erisilebilirlik=\(AXIsProcessTrusted())")
    guard CGPreflightScreenCaptureAccess() else { die("Ekran Kaydı izni yok") }
    _ = await MainActor.run { NSApplication.shared }
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    let wins = content.windows.filter {
      let a = $0.owningApplication
      let n = (a?.applicationName ?? "") + (a?.bundleIdentifier ?? "")
      return n.lowercased().replacingOccurrences(of: " ", with: "").contains("shoptitans")
    }
    for w in wins { print("win id=\(w.windowID) frame=\(w.frame) onScreen=\(w.isOnScreen) layer=\(w.windowLayer) app=\(w.owningApplication?.bundleIdentifier ?? "?") title=\(w.title ?? "")") }
    guard let w = wins.filter({ $0.windowLayer == 0 }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { die("Oyun penceresi bulunamadı") }
    let filter = SCContentFilter(desktopIndependentWindow: w)
    let cfg = SCStreamConfiguration()
    let s = CGFloat(filter.pointPixelScale)
    cfg.width = Int(filter.contentRect.width * s); cfg.height = Int(filter.contentRect.height * s)
    cfg.showsCursor = false
    cfg.ignoreShadowsSingleWindow = true
    let t0 = Date()
    let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    let t1 = Date()
    guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { die("PNG") }
    try png.write(to: URL(fileURLWithPath: out))
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate; r.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: img).perform([r])
    let t2 = Date()
    print("goruntu \(img.width)x\(img.height) yakala=\(Int(t1.timeIntervalSince(t0)*1000))ms ocr=\(Int(t2.timeIntervalSince(t1)*1000))ms")
    for o in r.results ?? [] {
      guard let c = o.topCandidates(1).first else { continue }
      let b = o.boundingBox
      print(String(format: "%.2f @(%.3f,%.3f) %@", c.confidence, b.midX, 1 - b.midY, c.string))
    }
  }
}
