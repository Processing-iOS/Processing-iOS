# Processing

A free, open-source port of the Processing programming environment to iOS, with support for Processing (.pde) and P5.js (.js) projects.

All features are included without in-app purchases or subscriptions, including code-error assistance and exporting source files. The obsolete Add to Home Screen flow has been removed; sketches run inside the app.

The app requests a native App Store rating once, when returning to the editor after the first successful sketch run. Compilation, setup, and runtime errors do not trigger the request. An app-wide, unversioned UserDefaults flag remembers the request across launches and updates. Apple decides whether the rating dialog is displayed; the app does not retry even if Apple suppresses it.

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

## Projects and recovery

Import accepts a project folder or multiple source files. Folder imports detect Processing or p5.js, preserve `data` and other assets, and keep the main file first when the project is renamed. Imports are staged and validated before appearing in My Projects. Existing projects and files are never overwritten; unreadable source, duplicate names, and unavailable Files providers show errors. Importing source files from the folder browser updates the editor tabs immediately.

Edits are saved automatically after a short pause, and while typing continuously at least every two seconds. The editor shows saving status and retains unsaved buffers if a write fails. **History** previews and restores earlier versions of the current file; restoring also keeps the current code. Up to 100 local versions are kept, with checkpoints at most once every 30 seconds during ordinary editing. History is stored in the project's hidden `.processing-history` folder.

**Import → Open Folder from Files…** links a folder for editing in place. A permission-bearing bookmark remembers it across launches. This works with locations that support folder access in Files, including iCloud Drive; provider availability and downloads still depend on Files. Remove Link removes the entry from My Projects without deleting the external folder. Duplicate makes a separate local copy. Rename linked folders in Files.

Clean editor buffers refresh when returning from another app. If an external edit conflicts with unsaved code, saving stops and offers **Keep My Changes** (preserving the external version in History) or **Save My Copy and Load Files Version** (putting the local code in a visible `Conflicts` subfolder). Runs use a coordinated temporary snapshot of linked projects, while image exports go to the original folder. Local p5.js JSON/text data loads are adapted to WebKit's file responses.

The share button exports the whole project as a ZIP or a folder through Files, including all source files, assets, and project libraries. Hidden recovery history and generated runtime documents are excluded. ZIPs can be expanded in Files before importing their project folder.

## Code completion

**Reference** opens a bundled, searchable guide for the current project's language, with 18 topics and copyable examples for drawing, transforms, touch, pixels, camera, sensors, and image export. Reading and searching work offline. The optional Online button opens Processing's reference or the p5.js v1 reference; newer online APIs may differ from the bundled runtimes.

Start typing a name in the editor to see completions above the keyboard after two characters. Tap a suggestion, or press **Tab** on a hardware keyboard to accept the first one. **Control-Space** requests completions for a shorter prefix; **Escape** dismisses the suggestions. Swipe the strip to see more matches. The keyboard button ends editing and restores the editor toolbar.

Syntax coloring scans comments and literals together so URLs, escaped quotes, and separate block comments cannot recolor neighboring code. Typing schedules coloring off the main thread and applies only attributes to the current text snapshot, preserving the caret, scrolling, marked text, and native undo history.

Completions include common Processing or P5.js functions, constants, keywords, and names used in the project's source files. Function suggestions show a signature and insert parentheses with the caret inside; existing parentheses and arguments are preserved. Normal Undo/Redo works. Suggestions are suppressed in comments, quoted strings, and after member-access dots. This is offline name completion, without type or scope inference.

## Retina rendering

Leaving a run disposes its Processing/p5 instance, cancels timeouts, intervals, and animation callbacks, stops capture and playback, and removes the temporary runtime document. Each run starts with a fresh WebView. A regression check runs 20 successive sketches and verifies release of their controllers, WebViews, and runtime files.

Processing sketches automatically render at the screen's pixel density, including 2D, P3D, and offscreen graphics. Sketch dimensions, touch coordinates, and the legacy `width * height` pixel array remain in logical pixels. Pixel-array operations retain their logical resolution; vector drawing uses the full-resolution canvas.

P5.js retains its built-in Retina support and still honors an explicit `pixelDensity(1)` for pixel-based sketches.

## Processing compatibility and image export

In a p5.js project, **Tools → JavaScript Libraries** imports local browser-compatible `.js` bundles. Tap Edit and drag to set their load order; they run after the bundled p5.js/p5.sound and before the sketch. Swipe **Exclude** to stop loading a library while retaining its source file. Importing that same file again enables it; different content with the same name is rejected without overwriting anything. Tap a library to read/copy its source and use Files to edit it.

The ordered `.processing-libraries.json` list and `libraries/` folder travel with project copies and exports. Library syntax/runtime errors identify the library and line; Show in Code opens its source. Missing files, invalid lists, and paths outside the project stop the run with an actionable error. Limits are 32 libraries and 16 MB of combined JavaScript. Use classic scripts or browser/UMD builds compatible with p5.js 1.4.0; npm installation, Node.js APIs, and ES modules are not supported. Relative asset paths resolve from the project folder.

The bundled runtimes are Processing.js 1.6.6 and p5.js 1.4.0. PDE sketches support the Processing.js API, with additions for `circle`, `square`, `displayWidth`, `displayHeight`, `fullScreen`, and `StringList`. The list supports append/get/set/remove, size/clear, hasValue, sort/sortReverse/reverse/shuffle, upper/lower, copy, join, array/toArray, and iteration. Parameterized functions, PVector math, map, and ellipse modes are covered by runtime regression checks.

`saveFrame("frame-####.png")` in Processing and `saveCanvas("frame", "png")` in p5.js write images into the project's **exports** folder, available through the folder browser and Files. PNG and JPEG are supported, including Retina pixels and numbered Processing filenames. Use simple filenames without folder paths. Image limits are 16 million pixels, 8192 pixels per side, and 18 MB encoded image data. A busy export queue reports an error instead of accumulating unbounded images; lower `frameRate()` for image sequences.

Desktop Java `.jar` libraries and packages such as `processing.video` cannot run in the browser runtime. Unsupported imports explain this at their source location; use `CameraView` for camera input. Core imports and built-in collection imports are accepted. These additions do not provide full desktop Processing 4 compatibility.

The bundled Processing.js copies also contain touch fixes: the first touch is delivered immediately, old mouse/initialization listeners are removed correctly so gestures do not accumulate duplicate callbacks, and each new contact resets previous mouse coordinates so separate strokes do not get connected. Keep these fixes when updating the library.

## Sensor inputs

`Example_Sensors` displays the available readings. Define any of these callbacks in a Processing sketch, or use `function name(...)` in a global p5.js sketch. Only the sensors with defined callbacks are started; callbacks must exist by the end of `setup()`.

| Callback | Values and units |
| --- | --- |
| `accelerometerUpdated(x, y, z)` | Acceleration including gravity, in g (existing API) |
| `gyroscopeUpdated(x, y, z)` | Raw rotation rate, in radians/second (existing API) |
| `orientationUpdated(roll, pitch, yaw)` | Orientation, in radians; yaw is relative, not compass north |
| `gravityUpdated(x, y, z)` | Gravity vector, in g |
| `userAccelerationUpdated(x, y, z)` | Acceleration with gravity removed, in g |
| `rotationRateUpdated(x, y, z)` | Device-motion rotation rate, in radians/second |
| `magnetometerUpdated(x, y, z)` | Raw magnetic field, in microtesla; includes nearby magnetic interference |
| `altimeterUpdated(relativeAltitude, pressure)` | Relative altitude in meters and pressure in kilopascals |
| `sensorStatusUpdated(sensor, status)` | Callback name and `waiting`, `active`, `unavailable`, `denied`, or `error` |

Vector axes follow the device: +X points right, +Y toward its top, and +Z out of the screen. Rotating the interface does not remap them. Motion updates are delivered at up to 30 Hz; altitude updates arrive at the hardware's slower rate. Sensing pauses in the background and stops when leaving the sketch. Orientation and relative altitude establish a new reference when sensing restarts. Simulators and devices without a sensor report `unavailable`; they do not generate simulated readings.

```java
float tilt = 0;
void setup() { size(screenWidth, screenHeight); }
void draw() {
  background(20);
  ellipse(width / 2 + tilt * 100, height / 2, 40, 40);
}
void gravityUpdated(float x, float y, float z) { tilt = x; }
```

## Camera input

`Example_Camera` uses the built-in `CameraView`. Choose the camera once in `setup()`, then pass its position and size to `camera.draw(x, y, width, height)` each frame, just like other drawing commands. Permission is requested automatically; the sketch needs no browser, video, or permission-handling code. The user must accept the iOS camera prompt once; subsequent runs reuse the app's authorization. Embedded frames and pages outside the local sketch are denied capture access.

```javascript
let camera;
function setup() {
  createCanvas(windowWidth, windowHeight);
  camera = new CameraView("back");
}
function draw() {
  background(20);
  camera.draw(20, 80, width - 40, height - 100);
}
```

In Processing, declare `CameraView camera;`, use `void setup()` / `void draw()`, and replace `createCanvas(...)` with `size(screenWidth, screenHeight)`; the camera calls are identical.

`new CameraView("back")` selects the rear camera; use `"front"` for the selfie camera. The default is `"back"`. Position and size belong in `camera.draw(x, y, width, height)`, so they can change or animate every frame. `camera.setFacing("front")` switches cameras; `camera.stop()` and `camera.start()` control capture manually. Read `camera.status` (`waiting`, `active`, `denied`, `unavailable`, `error`, `paused`, `stopped`) and `camera.message` for custom UI. Earlier sketches that passed a rectangle to the constructor and called `camera.draw()` still work.

CameraView draws into a **2D** sketch canvas, respects transforms and Retina density, and fills its rectangle without stretching the image (edges may be cropped). Draw more graphics afterward to overlay them. Loading and permission/device errors appear inside the rectangle automatically. Capture uses WebRTC's `getUserMedia()` with no audio, server, recording, or video upload.

The bundled selfie example selects `"front"` and mirrors the preview in sketch code: `push(); translate(width, 0); scale(-1, 1); camera.draw(20, 80, width - 40, height - 100); pop();`. In Processing, use `pushMatrix()` / `popMatrix()` instead of `push()` / `pop()`. The transform affects only the camera drawing, so titles and other graphics stay readable. CameraView does not mirror the input automatically; omit the transform for an unmirrored preview.

CameraView pauses in the background, resumes on return, and releases its tracks when the runner closes or fails. Denied access does not repeatedly prompt; after allowing access in Settings, run the sketch again or call `camera.start()`. All camera and microphone capture also stops natively when the runner closes or enters the background. Use a physical iPhone or iPad to test real camera frames and sensor values.

Both new samples are installed once on upgrades as well as fresh installations. The original camera sample is upgraded to CameraView only if its contents are unchanged; edited projects are preserved. Deleting a sample does not cause it to reappear.

Use **Import → Import sample projects…** to choose which bundled examples to restore. Nothing is selected by default; check one or more samples and tap **Import**. Only the selected samples are imported. Missing samples are restored, edited projects are kept alongside a fresh numbered copy, and unchanged samples are not duplicated on repeated imports.

## Sketch diagnostics

Swipe right or long-press a project or an item in its folder browser for **Rename** and **Duplicate**. Renames keep a source file's recovery history; project renames also update the main source filename. Duplicates include source files and assets but start with fresh history. Existing names are never overwritten. A copied source file keeps its declarations, so rename duplicate functions/classes before running it alongside the original.

The editor's **Tools** menu includes Find and Replace, Undo/Redo, Format Code, and Text Size (saved across launches). The keyboard accessory provides indentation, common code symbols, Undo/Redo, and completion suggestions. Return preserves indentation and splits a pair of braces onto separate lines. Formatting changes code indentation without rewriting multiline strings/comments, and remains undoable. On iOS 16 and later, search uses the native find/replace navigator; iOS 15 provides Find Next and Replace All.

The **Console** button in a running sketch displays Processing `print()`/`println()` and p5.js `print()`/JavaScript `console.log()`, `info()`, `warn()`, and `error()`. Return to **Tools → Console** in the editor to read the last run's output and errors. The resizable sheet supports selection, Copy, and Clear. Output is bounded; heavy logging drops earlier messages so it cannot consume unlimited memory.

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

[Download Processing on the App Store](https://itunes.apple.com/us/app/processing-icompiler/id648955851?mt=8).
