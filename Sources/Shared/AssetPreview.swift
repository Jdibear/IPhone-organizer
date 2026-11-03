import AVKit
import Photos
import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#else
import AppKit
private typealias PlatformImage = NSImage
#endif

/// Shows a photo at full quality or plays a video, so you can see it properly before deleting it.
struct AssetPreviewContent: View {
    let asset: PHAsset
    /// Full-screen views get playback controls and zooming; the hold-to-preview bubble just plays.
    var isInteractive = false

    var body: some View {
        if asset.mediaType == .video {
            AssetVideoView(asset: asset, showsControls: isInteractive)
        } else {
            AssetPhotoView(asset: asset, isZoomable: isInteractive)
        }
    }

    /// The size that fits `bounds` without changing the photo's shape.
    static func fittedSize(for asset: PHAsset, in bounds: CGSize) -> CGSize {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return bounds }
        let scale = min(bounds.width / CGFloat(asset.pixelWidth), bounds.height / CGFloat(asset.pixelHeight))
        return CGSize(width: CGFloat(asset.pixelWidth) * scale, height: CGFloat(asset.pixelHeight) * scale)
    }
}

private struct AssetPhotoView: View {
    let asset: PHAsset
    let isZoomable: Bool

    @State private var image: PlatformImage?
    @State private var requestID: PHImageRequestID?
    @State private var didFail = false
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var drag = CGSize.zero

    var body: some View {
        ZStack {
            if let image {
                picture(image)
            } else if didFail {
                unavailable
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onDisappear {
            if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        }
    }

    @ViewBuilder
    private func picture(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        let view = Image(uiImage: image).resizable().scaledToFit()
        #else
        let view = Image(nsImage: image).resizable().scaledToFit()
        #endif
        if isZoomable { zoomable(view) } else { view }
    }

    private func zoomable(_ view: some View) -> some View {
        view
            .scaleEffect(zoom * pinch)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { value in
                        zoom = min(max(zoom * value.magnification, 1), 6)
                        pinch = 1
                        if zoom == 1 { offset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { if zoom > 1 { drag = $0.translation } }
                    .onEnded { value in
                        guard zoom > 1 else { return }
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        drag = .zero
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    zoom = zoom > 1 ? 1 : 2.5
                    offset = .zero
                }
            }
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.icloud")
                .font(.title)
            Text("Couldn't load this photo. Check your connection and try again.")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding()
    }

    private func load() {
        let options = PHImageRequestOptions()
        // Shows a quick version straight away, then the sharp one. Originals may have to come from iCloud.
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: min(asset.pixelWidth, 2800), height: min(asset.pixelHeight, 2800))
        requestID = PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFit, options: options
        ) { result, info in
            if let result {
                image = result
            } else if info?[PHImageErrorKey] != nil {
                didFail = true
            }
        }
    }
}

private struct AssetVideoView: View {
    let asset: PHAsset
    let showsControls: Bool

    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var isVisible = false
    @State private var didFail = false
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                #if canImport(UIKit)
                if showsControls {
                    VideoPlayer(player: player)
                } else {
                    PlayerLayerView(player: player)
                }
                #else
                VideoPlayer(player: player)
                #endif
            } else if didFail {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.icloud").font(.title)
                    Text("Couldn't load this video. Check your connection and try again.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: stop)
    }

    private func load() {
        isVisible = true
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            DispatchQueue.main.async {
                guard isVisible else { return }
                guard let item else {
                    didFail = true
                    return
                }
                #if canImport(UIKit)
                // Plays with sound even when the ring switch is on silent, like the Photos app.
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                #endif
                let player = AVPlayer(playerItem: item)
                if !showsControls {
                    // The preview bubble has no controls, so keep playing from the start.
                    endObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                    ) { _ in
                        player.seek(to: .zero)
                        player.play()
                    }
                }
                self.player = player
                player.play()
            }
        }
    }

    private func stop() {
        isVisible = false
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

#if canImport(UIKit)
/// Plain video with no controls, for the preview bubble, where controls couldn't be tapped anyway.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
    }
}
#endif
