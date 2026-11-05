// Prints normalised boxes for OCR hits, so a tapped control can be located from
// a capture instead of guessed. Logical coordinates are px / scale (3x here).
//   swift bbox.swift <file.png> <substring>
import AppKit
import Vision

let path = CommandLine.arguments[1]
let needle = CommandLine.arguments[2].lowercased()
guard let img = NSImage(contentsOfFile: path) else { print("ERR load"); exit(2) }
var r = NSRect(origin: .zero, size: img.size)
guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { print("ERR cg"); exit(2) }
let w = Double(cg.width), h = Double(cg.height)
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = true
try VNImageRequestHandler(cgImage: cg).perform([req])
for o in req.results ?? [] {
  guard let t = o.topCandidates(1).first else { continue }
  guard t.string.lowercased().contains(needle) else { continue }
  let b = o.boundingBox // origin bottom-left, normalised
  let cx = (b.minX + b.width / 2) * w
  let cy = (1 - (b.minY + b.height / 2)) * h // top-left origin, pixels
  print(String(format: "%@  px(%.0f,%.0f)  logical(%.0f,%.0f)", t.string, cx, cy, cx / 3, cy / 3))
}
