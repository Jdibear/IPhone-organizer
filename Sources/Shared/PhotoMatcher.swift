import CoreGraphics
import Photos
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Decides whether photos are real copies by comparing their pixels, not just when they were taken.
/// Shots a moment apart (a slightly different pose or angle) differ far more than a re-saved copy does.
enum PhotoMatcher {
    /// Fingerprints are small grayscale versions of the photo, `side` × `side` pixels.
    static let side = 64
    /// Largest average pixel difference (0…1) that still counts as the same photo.
    /// A heavily re-compressed copy lands under 0.7%; a shot where the camera moved just 1% lands over 1.6%.
    static let threshold = 0.012

    static func fingerprint(of image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Average pixel difference between two fingerprints, from 0 (identical) to 1.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        let total = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(a.count * 255)
    }

    /// Splits photos into sets of real copies. Each set lists indexes into `prints`, oldest first;
    /// photos with no match (or no fingerprint) are left out.
    static func copySets(_ prints: [[UInt8]?]) -> [[Int]] {
        var sets: [[Int]] = []
        for (index, print) in prints.enumerated() {
            guard let print else { continue }
            if let match = sets.firstIndex(where: { difference(prints[$0[0]]!, print) <= threshold }) {
                sets[match].append(index)
            } else {
                sets.append([index])
            }
        }
        return sets.filter { $0.count > 1 }
    }

    /// Loads a small version of the photo and fingerprints it. Runs synchronously, so call off the main thread.
    static func fingerprint(of asset: PHAsset) -> [UInt8]? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        var result: CGImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 128, height: 128), contentMode: .aspectFill, options: options
        ) { image, _ in
            #if canImport(UIKit)
            result = image?.cgImage
            #else
            result = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #endif
        }
        return result.flatMap(fingerprint(of:))
    }
}
