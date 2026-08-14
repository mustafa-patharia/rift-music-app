// Render the Rift DMG window background: near-black canvas with warm,
// blurred aurora glows (crimson → orange → amber, bottom-heavy) — matches
// the website hero + app brand palette.
//
//   swift scripts/dmg-bg.swift build/dmg-bg.png
//
// Output is 1200×800 (@2x for a 600×400 DMG window → crisp on retina).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg-bg.png"
let W = 1200, H = 800
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

// base fill — brand near-black (#07080a)
ctx.setFillColor(CGColor(red: 7/255, green: 8/255, blue: 10/255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// soft radial glow. CG origin = bottom-left, so low y = bottom of window.
func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
          _ rr: CGFloat, _ gg: CGFloat, _ bb: CGFloat, _ a: CGFloat) {
    let colors = [CGColor(red: rr/255, green: gg/255, blue: bb/255, alpha: a),
                  CGColor(red: rr/255, green: gg/255, blue: bb/255, alpha: 0)] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
}

// warm aurora, bottom-weighted like the website hero
glow(250,  110, 640, 255,  47,  58, 0.55)  // crimson  #ff2f3a  bottom-left
glow(980,   90, 660, 255, 107,  74, 0.42)  // orange   #ff6b4a  bottom-right
glow(610,   30, 560, 255, 179,  71, 0.26)  // amber    #ffb347  bottom-center
glow(120,  680, 520, 255,  90,  80, 0.14)  // faint crimson top-left lift

guard let img = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("✓ \(out)")
