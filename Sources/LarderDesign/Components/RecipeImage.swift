import Foundation
import ImageIO
import SwiftUI

/// A recipe's photo in the dish tile's frame, or the dish tile itself when the recipe has no photo or it cannot be read.
/// Decorative, like the tile; the row beside it carries the words.
public struct RecipeImage: View {
    @Environment(\.recipePhotoDirectory) private var directory
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @State private var loaded: (url: URL, image: CGImage)?
    private let title: String
    private let photoFileName: String?
    private let size: RecipeTile.Size

    /// Creates the image for a dish; `photoFileName` is the recipe's file in `recipePhotoDirectory`.
    public init(title: String, photoFileName: String?, size: RecipeTile.Size = .medium) {
        self.title = title
        self.photoFileName = photoFileName
        self.size = size
    }

    /// The photo's file, when there is a directory and the name is a plain file name inside it.
    private var fileURL: URL? {
        guard let directory, let photoFileName, !photoFileName.isEmpty, !photoFileName.contains("/"),
              photoFileName != ".", photoFileName != ".."
        else { return nil }
        return directory.appending(path: photoFileName, directoryHint: .notDirectory)
    }

    public var body: some View {
        let side = size.side * min(scale, 1.6)
        // Matches the tile: a banner runs edge to edge inside a card, which clips it; a tile has its own corners.
        let shape = RoundedRectangle(cornerRadius: size == .banner ? 0 : LarderRadius.tile, style: .continuous)
        Group {
            if let loaded, loaded.url == fileURL {
                Color.clear
                    .overlay {
                        Image(decorative: loaded.image, scale: displayScale)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(shape)
                    .frame(width: size == .banner ? nil : side, height: side)
                    .frame(maxWidth: size == .banner ? .infinity : nil)
                    .accessibilityHidden(true)
            } else {
                RecipeTile(title: title, size: size)
            }
        }
        .task(id: fileURL) {
            guard let fileURL else { return }
            // A banner can be as wide as the screen; anything else is a square tile.
            let points = size == .banner ? 430 : side
            let pixels = Int((points * displayScale).rounded(.up))
            if let image = await RecipePhotoCache.image(at: fileURL, maximumPixelSize: pixels) {
                loaded = (fileURL, image)
            }
        }
    }
}

/// Decoded photo thumbnails, so rows that scroll back into view do not read the file again.
private nonisolated enum RecipePhotoCache {
    // NSCache is documented as safe to use from any thread.
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 100
        return cache
    }()

    /// A thumbnail of the image file at `url` no larger than `maximumPixelSize`, decoded off the main actor;
    /// `nil` when the file is missing or is not an image.
    @concurrent static func image(at url: URL, maximumPixelSize: Int) async -> CGImage? {
        let key = "\(maximumPixelSize)|\(url.path(percentEncoded: false))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

#Preview("RecipeImage") {
    HStack(spacing: LarderSpacing.m) {
        RecipeImage(title: "Spinach red lentil dal", photoFileName: nil)
        RecipeImage(title: "Tomato baked cod", photoFileName: "missing.jpg", size: .large)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
