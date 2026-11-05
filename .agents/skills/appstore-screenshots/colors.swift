// Prints the dominant quantised colours of one PNG, sampled on a 12 px grid.
//   swift colors.swift <file.png>
import AppKit

let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path) else { print("ERR load"); exit(2) }
var r = NSRect(origin: .zero, size: img.size)
guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { print("ERR cg"); exit(2) }
let w = cg.width, h = cg.height
var data = [UInt8](repeating: 0, count: w * h * 4)
data.withUnsafeMutableBytes { buffer in
  guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("ERR ctx")
    exit(2)
  }
  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
}
var counts: [String: Int] = [:]
var n = 0
for y in stride(from: 0, to: h, by: 12) {
  for x in stride(from: 0, to: w, by: 12) {
    let i = (y * w + x) * 4
    let key = String(format: "#%02X%02X%02X", (Int(data[i]) / 8) * 8, (Int(data[i + 1]) / 8) * 8, (Int(data[i + 2]) / 8) * 8)
    counts[key, default: 0] += 1
    n += 1
  }
}
print("size \(w)x\(h)")
for (k, v) in counts.sorted(by: { $0.value > $1.value }).prefix(8) {
  print(String(format: "%@ %.1f%%", k, Double(v) * 100 / Double(n)))
}
