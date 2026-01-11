# Loquax

A lightweight Swift client for Gemini Live API.

# Installation

Add the following dependency to your Package.swift:

```swift
.package(url: "https://github.com/renshi-a/Loquax", from: "0.1.1")
```

Or add the package via Xcode: File > Add Packages... and enter the repository URL: https://github.com/renshi-a/Loquax

# Usage

Loquax features a minimal and intuitive interface.

```swift
let loquax = Loquax(model: .gemini25flashNativeAudioPreview122025)
```

Connect within your view’s lifecycle:

```
.task {
     try loquax.connect(apiKey: "YOUR API KEY")
}
```

Begin the live session:

```
try await self.loquax.startLiveChat()
```

# License

This library is released under the MIT license. See LICENSE for details.
