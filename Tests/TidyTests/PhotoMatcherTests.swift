import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Tidy

final class PhotoMatcherTests: XCTestCase {
    /// A photo-like scene: a gradient sky with overlapping shapes, moved `shift` of the width to the right.
    private func scene(shift: Double = 0, seed: UInt64 = 1) -> CGImage {
        let width = 1200, height = 900
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                                      CGColor(red: 0.9, green: 0.8, blue: 0.6, alpha: 1)] as CFArray,
                             locations: nil)!
        context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        var generator = SplitMix(seed: seed)
        let dx = shift * Double(width)
        for _ in 0..<40 {
            context.setFillColor(red: generator.next(), green: generator.next(), blue: generator.next(), alpha: 1)
            let rect = CGRect(x: generator.next() * Double(width) + dx, y: generator.next() * Double(height),
                              width: 40 + generator.next() * 200, height: 40 + generator.next() * 200)
            context.fillEllipse(in: rect)
        }
        return context.makeImage()!
    }

    /// Saves and reloads the image as a lower-quality JPEG, like a photo re-saved from a chat app.
    private func recompressed(_ image: CGImage) -> CGImage {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        CGImageDestinationFinalize(destination)
        let source = CGImageSourceCreateWithData(data, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    private func difference(_ a: CGImage, _ b: CGImage) -> Double {
        PhotoMatcher.difference(PhotoMatcher.fingerprint(of: a)!, PhotoMatcher.fingerprint(of: b)!)
    }

    func testResavedCopyCountsAsDuplicate() {
        let original = scene()
        XCTAssertLessThanOrEqual(difference(original, recompressed(original)), PhotoMatcher.threshold)
    }

    func testShotAMomentLaterIsNotADuplicate() {
        // The camera moved just 1% between shots.
        XCTAssertGreaterThan(difference(scene(), scene(shift: 0.01)), PhotoMatcher.threshold)
    }

    func testCopySetsSplitsCopiesFromLookAlikes() {
        let original = scene()
        let prints = [original, scene(shift: 0.03), recompressed(original), scene(seed: 2)]
            .map(PhotoMatcher.fingerprint(of:))
        XCTAssertEqual(PhotoMatcher.copySets(prints), [[0, 2]])
    }
}

/// Small deterministic random numbers, so the test scenes are the same on every run.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}
