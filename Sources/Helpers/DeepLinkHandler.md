# DeepLinkHandler

A declarative deep link routing system with named parameters, wildcards, and query extraction.

## API

| Method | Description |
|---|---|
| `register(_:scheme:handler:)` | Register a URL pattern with handler |
| `handle(_:)` | Route an incoming URL (returns `true` if matched) |
| `canHandle(_:)` | Dry-run check without executing |
| `setFallback(_:)` | Handler for unmatched URLs |

### RouteContext

| Property | Description |
|---|---|
| `url` | The original URL |
| `pathParameters` | Extracted `:named` params |
| `queryParameters` | Parsed query string |
| `scheme` | URL scheme |

## Examples

```swift
import SwiftUtilsHelpers

let router = DeepLinkHandler()

// Simple route with a path parameter
router.register("product/:id") { context in
    let productId = context.pathParameters["id"]!
    navigateToProduct(productId)
}

// Multiple parameters
router.register("user/:userId/posts/:postId") { context in
    let userId = context.pathParameters["userId"]!
    let postId = context.pathParameters["postId"]!
    showPost(userId: userId, postId: postId)
}

// Scheme-specific route
router.register("settings/*", scheme: "myapp") { context in
    openSettings()
}

// Fallback for unmatched URLs
router.setFallback { context in
    showNotFound(url: context.url)
}

// Handle an incoming URL (e.g., from AppDelegate or SceneDelegate)
let url = URL(string: "myapp://product/42?ref=push&campaign=summer")!
router.handle(url)
// Routes to product handler with:
//   pathParameters: ["id": "42"]
//   queryParameters: ["ref": "push", "campaign": "summer"]

// Check before routing
if router.canHandle(url) {
    router.handle(url)
} else {
    openInBrowser(url)
}
```
