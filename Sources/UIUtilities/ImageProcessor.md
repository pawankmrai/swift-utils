# ImageProcessor

Memory-efficient `UIImage` resizing, cropping, rounding, tinting, compression, and ImageIO-backed downsampling.

## API

| Method | Description |
|---|---|
| `.resized(to:mode:)` | Resize with `.aspectFit`, `.aspectFill`, or `.exact` |
| `.cropped(to:)` | Crop to a pixel `CGRect` |
| `.croppedToCircle()` | Mask to a centered circle |
| `.rounded(radius:)` | Apply rounded corners |
| `.tinted(with:)` | Recolor non-transparent pixels, preserving alpha mask |
| `.compressedJPEGData(maxSizeInBytes:initialQuality:)` | Binary-search JPEG compression to hit a byte budget |
| `.normalizedOrientation()` | Bake EXIF orientation into pixel data (`.up`) |
| `UIImage.downsampled(from:to:scale:)` (Data) | Decode a thumbnail directly via ImageIO, skipping full-resolution decode |
| `UIImage.downsampled(from:to:scale:)` (URL) | Same, reading straight from disk |

### `ImageResizeMode`

`.aspectFit`, `.aspectFill`, `.exact`

## Examples

```swift
import SwiftUtilsUIUtilities

// Resize for a grid cell, preserving aspect ratio and letterboxing
let thumbnail = photo.resized(to: CGSize(width: 120, height: 120), mode: .aspectFit)

// Fill an avatar circle
let avatar = photo
    .resized(to: CGSize(width: 100, height: 100), mode: .aspectFill)?
    .croppedToCircle()

// Rounded card image
imageView.image = photo.rounded(radius: 12)

// Tint a template icon
let iconView = UIImageView(image: UIImage(named: "bell")?.tinted(with: .systemBlue))

// Compress a camera photo to fit under a 500 KB upload limit
if let uploadData = photo.compressedJPEGData(maxSizeInBytes: 500_000) {
    try uploadData.write(to: uploadURL)
}

// Fix orientation before pixel-level processing (e.g. Core Image filters)
let upright = photo.normalizedOrientation()

// Load a fast thumbnail from a large photo file without decoding it in full first
if let data = try? Data(contentsOf: largePhotoURL),
   let thumb = UIImage.downsampled(from: data, to: CGSize(width: 200, height: 200)) {
    cell.imageView.image = thumb
}

// Or decode straight from disk, useful in a table/collection view cell provider
let cellThumbnail = UIImage.downsampled(from: fileURL, to: CGSize(width: 80, height: 80))
```

### Why downsample instead of `UIImage(data:)` + `.resized(to:)`?

`UIImage(data:)` fully decodes the source image into memory at its native resolution before
any resizing happens — for a 12 MP camera photo that's tens of megabytes just to render a
100×100 thumbnail. `UIImage.downsampled(from:to:scale:)` uses `CGImageSourceCreateThumbnailAtIndex`
to decode directly at (approximately) the target size, which is dramatically cheaper in both
time and memory when populating scrollable lists of images.
