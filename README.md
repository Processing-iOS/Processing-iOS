# Processing for iOS

A free, open-source port of the Processing programming environment to iOS, with support for Processing (.pde) and P5.js (.js) projects.

All features are included without in-app purchases or subscriptions, including code-error assistance and exporting source files. The obsolete Add to Home Screen flow has been removed; sketches run inside the app.

## Build with Xcode 27

Requirements: Xcode 27, iOS 15 or later, and CocoaPods 1.16.2. Use a current Ruby installation for CocoaPods.

```sh
gem install cocoapods -v 1.16.2
pod install
open "Processing for iOS.xcworkspace"
```

Select the **Processing for iOS** scheme and an iPhone or iPad simulator, then build and run. For a physical device, select your development team in Signing & Capabilities.

The workspace uses Tabman 3.2 / Pageboy 4.2 for the editor's file tabs and NSString+LevenshteinDistance for code suggestions. Exact dependency versions are recorded in `Podfile.lock`.

To check a device Release build without signing:

```sh
xcodebuild -workspace "Processing for iOS.xcworkspace" \
  -scheme "Processing for iOS" -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Code completion

Start typing a name in the editor to see completions above the keyboard after two characters. Tap a suggestion, or press **Tab** on a hardware keyboard to accept the first one. **Control-Space** requests completions for a shorter prefix; **Escape** dismisses the suggestions. Swipe the strip to see more matches. The keyboard button ends editing and restores the editor toolbar.

Completions include common Processing or P5.js functions, constants, keywords, and names used in the project's source files. Function suggestions show a signature and insert parentheses with the caret inside; existing parentheses and arguments are preserved. Normal Undo/Redo works. Suggestions are suppressed in comments, quoted strings, and after member-access dots. This is offline name completion, without type or scope inference.

## Sketch diagnostics

Sketches run from a saved source snapshot, with the project-named file first and other files sorted by name. Failed reads and saves stop execution instead of silently using incomplete or outdated code.

The runtime reports syntax errors, runtime exceptions, unhandled promise rejections, missing resources, and WebKit failures. A sketch that blocks the JavaScript thread for 10 seconds is stopped with a recovery message. Only the first failure is presented per run.

P5.js errors map back to the original file and line, including multi-file projects. Processing sketches receive a conservative check for unclosed comments, strings, and brackets before compilation. Processing.js does not provide a PDE source map: generated JavaScript line numbers are never shown as PDE locations, and unknown-name navigation is offered only for an unambiguous source token. Other compiler errors still show their full message and a way back to the editor.

“Show in Code” highlights the saved source. Suggestions replace only the identified token (or a recognized complete call), and are discarded if the source has changed. They are suggestions, not a guarantee that the replacement matches the sketch's intent.

Run the Swift Testing suite from **Product → Test** in Xcode, or:

```sh
xcodebuild -workspace "Processing for iOS.xcworkspace" \
  -scheme "Processing for iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

The suite executes real Processing and P5.js sketches in WKWebView, covering source mapping, Unicode/CRLF, HTML inside strings, asynchronous errors, failed file operations, and safe editor ranges.

[Processing](https://processing.org/) provides a simple, powerful language for visualizations, animations, and games.

[Download Processing for iOS on the App Store](https://itunes.apple.com/us/app/processing-icompiler/id648955851?mt=8).
