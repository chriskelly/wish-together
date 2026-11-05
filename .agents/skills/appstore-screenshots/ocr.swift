// Prints the text macOS Vision recognises in one PNG.
//   swift ocr.swift <file.png> [> out.txt]
import AppKit
import Vision

let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path) else { print("ERR load"); exit(2) }
var r = NSRect(origin: .zero, size: img.size)
guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { print("ERR cg"); exit(2) }
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = true
try VNImageRequestHandler(cgImage: cg).perform([req])
for o in req.results ?? [] {
  if let t = o.topCandidates(1).first { print(t.string) }
}
