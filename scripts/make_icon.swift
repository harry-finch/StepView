import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let inputPath = "/Users/mugen/.gemini/antigravity-ide/brain/479a07d6-5f45-431f-823b-f96788224810/stepview_app_icon_1791374283313.jpg"
let projectDir = FileManager.default.currentDirectoryPath
let resourcesDir = "\(projectDir)/StepView/Resources"
let iconsetDir = "\(projectDir)/build/StepView.iconset"

try? FileManager.default.removeItem(atPath: iconsetDir)
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// 1. Chargement de l'image source en CGImage (pixels réels garantis)
let url = URL(fileURLWithPath: inputPath) as CFURL
guard let source = CGImageSourceCreateWithURL(url, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Impossible de charger l'image source en CGImage")
}

print("Image source : \(cgImage.width)x\(cgImage.height) pixels")

// 2. Découpage du squircle central (coordonnées en pixels réels : x:168, y:168, 688x688)
let cropRect = CGRect(x: 168, y: 168, width: 688, height: 688)
guard let cropped = cgImage.cropping(to: cropRect) else {
    fatalError("Échec du recadrage CGImage")
}

// 3. Rendu du master 1024x1024 avec squircle macOS officiel
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let masterCtx = CGContext(
    data: nil,
    width: 1024,
    height: 1024,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Échec de création du master CGContext")
}

masterCtx.interpolationQuality = .high

// Cible : 824x824 centré à (100, 100) avec rayon d'arrondi de 185
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let clipPath = CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Ombre portée sous le squircle
masterCtx.saveGState()
masterCtx.setShadow(
    offset: CGSize(width: 0, height: -12),
    blur: 24,
    color: CGColor(gray: 0, alpha: 0.35)
)
masterCtx.setFillColor(CGColor(gray: 0, alpha: 0.8))
masterCtx.addPath(clipPath)
masterCtx.fillPath()
masterCtx.restoreGState()

// Dessin de l'icône dans le squircle découpé
masterCtx.saveGState()
masterCtx.addPath(clipPath)
masterCtx.clip()
masterCtx.draw(cropped, in: iconRect)
masterCtx.restoreGState()

guard let masterCGImage = masterCtx.makeImage() else {
    fatalError("Échec de création du master CGImage")
}

// 4. Génération de toutes les résolutions du iconset
let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconSizes {
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError() }

    ctx.interpolationQuality = .high
    ctx.draw(masterCGImage, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let resized = ctx.makeImage() else { fatalError() }
    let destURL = URL(fileURLWithPath: "\(iconsetDir)/\(name)") as CFURL
    guard let dest = CGImageDestinationCreateWithURL(destURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError()
    }
    CGImageDestinationAddImage(dest, resized, nil)
    CGImageDestinationFinalize(dest)
}

print("✓ Toutes les images du iconset ont été exportées avec succès dans \(iconsetDir)")

// 5. Génération du fichier AppIcon.icns
let icnsOutput = "\(resourcesDir)/AppIcon.icns"
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsOutput]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    let size = (try? FileManager.default.attributesOfItem(atPath: icnsOutput)[.size] as? Int64) ?? 0
    print("✓ AppIcon.icns généré avec succès (\(size / 1024) Ko) dans \(icnsOutput)")
} else {
    fatalError("Erreur iconutil : code \(process.terminationStatus)")
}
