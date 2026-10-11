import UIKit
import SafariServices

struct ReferenceTopic {
    let id: String
    let title: String
    let keywords: String
    let explanation: String
    let example: String
}

/// Original, bundled guidance for the actual runtimes shipped by this app.
enum OfflineReference {
    static func topics(language: String) -> [ReferenceTopic] {
        let js = language == "js"
        let fn = js ? "function" : "void"
        let canvas = js ? "createCanvas(320, 240);" : "size(320, 240);"
        func sketch(_ body: String) -> String {
            "\(fn) setup() {\n  \(canvas)\n  \(body.replacingOccurrences(of: "\n", with: "\n  "))\n  noLoop();\n}"
        }
        let push = js ? "push()" : "pushMatrix()", pop = js ? "pop()" : "popMatrix()"
        var topics = [
            ReferenceTopic(id: "start", title: "Start here: setup and draw", keywords: "setup draw animation frameRate noLoop loop redraw millis",
                explanation: "setup() runs once. draw() repeats until noLoop() stops it; redraw() requests another frame. frameRate(30) requests 30 frames per second. Use millis() for elapsed time and frameCount for the frame number. Each Run starts fresh. Back stops the sketch and its camera, sensors, and timers.",
                example: "\(fn) setup() {\n  \(canvas)\n  frameRate(30);\n}\n\n\(fn) draw() {\n  background(24);\n  circle(160 + sin(millis() / 500.0) * 80, 120, 40);\n}"),
            ReferenceTopic(id: "canvas", title: js ? "Canvas size and Retina" : "Canvas size and Retina",
                keywords: "size createCanvas fullScreen width height screenWidth screenHeight windowWidth windowHeight pixelDensity P3D WEBGL",
                explanation: js
                    ? "Call createCanvas(width, height) once in setup(). windowWidth and windowHeight describe the available view; width and height describe the canvas. p5.js uses the screen's pixel density automatically. pixelDensity(1) opts out when you need a simple pixel array. Use resizeCanvas() in windowResized() to respond to size changes."
                    : "Call size(width, height) in setup(), or use size(screenWidth, screenHeight) to fill the view. width and height describe the canvas. Retina rendering is automatic, including P3D and offscreen graphics. Drawing and touch coordinates stay in logical pixels. fullScreen() is also supported. Desktop settings() and newer renderers are not required here.",
                example: sketch("background(24);\nfill(255);\ncircle(width / 2, height / 2, 80);")),
            ReferenceTopic(id: "shapes", title: "Shapes and coordinates",
                keywords: "rect ellipse circle square line point triangle quad rectMode ellipseMode CENTER CORNER",
                explanation: "The 2D origin is the top left: x increases rightward and y downward. rect(x, y, w, h) uses a corner by default; ellipse(x, y, w, h) uses a center. circle(x, y, diameter) and square(x, y, side) are shortcuts. rectMode(CENTER) or ellipseMode(CORNER) changes the anchor. line(x1, y1, x2, y2) joins two points.",
                example: sketch("background(24);\nfill(255, 160, 40);\nrect(20, 30, 100, 70);\nellipse(210, 90, 90, 60);\nstroke(255);\nline(20, 180, 300, 180);")),
            ReferenceTopic(id: "color", title: "Color, fill, and outlines",
                keywords: "background fill stroke noStroke noFill strokeWeight color colorMode RGB HSB lerpColor alpha",
                explanation: "background() repaints the canvas. fill() sets the interior color for future shapes; stroke() sets their outline and strokeWeight() its width. noStroke() and noFill() disable those parts. One number is grayscale; three numbers are red, green, blue (0–255 by default). A fourth number sets opacity. colorMode(HSB, 360, 100, 100) switches to hue, saturation, brightness.",
                example: sketch("background(18, 24, 34);\nnoStroke();\nfill(0, 180, 255);\ncircle(135, 120, 120);\nfill(255, 80, 120, 140);\ncircle(200, 120, 120);")),
            ReferenceTopic(id: "transforms", title: "Move, rotate, and scale",
                keywords: "translate rotate scale resetMatrix push pop pushMatrix popMatrix pushStyle popStyle radians degrees",
                explanation: "translate(x, y) moves the origin. rotate(angle) turns it; angles use radians by default, so radians(45) is useful. scale(amount) changes drawing size. Save and restore the transform around a group of shapes. " + (js ? "push()/pop() also preserve drawing styles." : "pushMatrix()/popMatrix() preserve transforms; use pushStyle()/popStyle() for drawing styles."),
                example: sketch("background(24);\n\(push);\ntranslate(width / 2, height / 2);\nrotate(PI / 4);\nrectMode(CENTER);\nrect(0, 0, 100, 60);\n\(pop);")),
            ReferenceTopic(id: "paths", title: "Custom shapes and curves",
                keywords: "beginShape endShape vertex curveVertex bezierVertex bezier arc CLOSE",
                explanation: "Place vertex(x, y) calls between beginShape() and endShape(CLOSE) to draw a closed polygon. Omit CLOSE for an open path. bezier() draws a curve using two endpoints and two control points. arc(x, y, w, h, start, stop) draws part of an ellipse; its angles use radians.",
                example: sketch("background(24);\nfill(255, 180, 40);\nbeginShape();\nvertex(160, 25);\nvertex(280, 200);\nvertex(40, 200);\nendShape(CLOSE);")),
            ReferenceTopic(id: "text", title: "Draw text",
                keywords: "text textSize textAlign textFont textWidth LEFT RIGHT CENTER BASELINE",
                explanation: "text(value, x, y) draws a string or number. textSize() sets its size; fill() sets its color. textAlign(CENTER, CENTER) centers it around the specified point. textWidth() measures the current font's text. Use the default font for an example that needs no imported assets.",
                example: sketch("background(24);\nfill(255);\ntextSize(28);\ntextAlign(CENTER, CENTER);\ntext(\"Hello, Processing!\", width / 2, height / 2);")),
            ReferenceTopic(id: "math", title: "Randomness and mapping",
                keywords: "random randomSeed noise noiseSeed map constrain dist lerp sin cos atan2 abs floor ceil round sqrt pow min max",
                explanation: "random(low, high) returns a value below high. randomSeed() repeats a random sequence; noise() provides smoother changes. map(value, a, b, c, d) converts between numeric ranges without clamping. constrain(value, low, high) clamps it. dist() measures distance and lerp(a, b, amount) interpolates. sin()/cos() use radians.",
                example: sketch("background(24);\nrandomSeed(7);\nnoStroke();\nfor (\(js ? "let" : "int") i = 0; i < 12; i++) {\n  fill(40 + i * 16, 160, 230);\n  circle(random(width), random(height), 20);\n}")),
            ReferenceTopic(id: "input", title: "Touch and mouse input",
                keywords: "touch mouseX mouseY pmouseX pmouseY mousePressed mouseDragged mouseReleased touches touchStarted touchMoved touchEnded",
                explanation: "mouseX/mouseY contain the current pointer location and pmouseX/pmouseY the previous location. Use mouseDragged() for drawing strokes. Processing maps the first finger to mouse callbacks; p5.js also offers touches[] and touchStarted()/touchMoved()/touchEnded() for multiple fingers. Return false from p5 touch callbacks to suppress the browser's default gesture.",
                example: "\(fn) setup() {\n  \(canvas)\n  background(255);\n  stroke(20);\n  strokeWeight(4);\n}\n\n\(fn) mouseDragged() {\n  line(pmouseX, pmouseY, mouseX, mouseY);\n}"),
            ReferenceTopic(id: "console", title: "Print and debug",
                keywords: "console log warn error print println debugging",
                explanation: "Open Console while running, or … → Console after returning to the editor. Copy preserves the output and Clear empties it. The console keeps a bounded recent history, so printing every frame can remove older messages. Syntax/runtime errors also appear here.",
                example: sketch(js ? "console.log(\"Canvas:\", width, height);\nconsole.warn(\"A sample warning\");" : "println(\"Canvas width: \" + width);\nprintln(\"Hello from Processing\");")),
            ReferenceTopic(id: "export", title: "Save a canvas image",
                keywords: "saveFrame saveCanvas PNG JPEG exports share screenshot",
                explanation: "Save PNG or JPEG to the project's exports folder, then share it through the folder browser. Retina pixels are included. Use a simple filename without a path. Images are limited to 16 million pixels and 8192 pixels per side. Saving too quickly reports a busy queue; prefer a touch callback or a low frame rate. " + (js ? "Use saveCanvas(\"picture\", \"png\")." : "Use saveFrame(\"picture-####.png\") to include the frame number."),
                example: sketch("background(30, 110, 180);\ncircle(160, 120, 100);\n" + (js ? "saveCanvas(\"picture\", \"png\");" : "saveFrame(\"picture-####.png\");"))),
            ReferenceTopic(id: "camera", title: "CameraView: front and back",
                keywords: "CameraView camera selfie mirror permission draw setFacing stop start status",
                explanation: "Create CameraView(\"front\") or CameraView(\"back\") once in setup(). Permission is requested automatically. draw(x, y, w, h) fills the rectangle without stretching, cropping the edges when needed. CameraView works in a 2D canvas and respects transforms. Mirror a selfie with translate(width, 0) and scale(-1, 1), as below. setFacing(), stop(), start(), status, and message are available. Test real frames on a physical device.",
                example: "\(js ? "let camera;" : "CameraView camera;")\n\n\(fn) setup() {\n  \(canvas)\n  camera = new CameraView(\"front\");\n}\n\n\(fn) draw() {\n  background(24);\n  \(push);\n  translate(width, 0);\n  scale(-1, 1);\n  camera.draw(20, 20, width - 40, height - 40);\n  \(pop);\n}"),
            ReferenceTopic(id: "sensors", title: "Motion and other sensors",
                keywords: "accelerometerUpdated gyroscopeUpdated orientationUpdated gravityUpdated userAccelerationUpdated rotationRateUpdated magnetometerUpdated altimeterUpdated sensorStatusUpdated",
                explanation: "Define a callback before setup finishes to start that sensor. Acceleration/gravity use g; gyroscope/rotation rate use radians per second; roll, pitch, yaw use radians. Magnetometer readings use microtesla; altimeter readings use relative meters and kilopascals. Axes follow the device: +x right, +y top, +z toward you. Motion runs at up to 30 Hz. Sensors pause in the background; unsupported devices and simulators report unavailable. Import Example_Sensors for every callback.",
                example: "\(js ? "let" : "float") tilt = 0;\n\(fn) setup() { \(canvas) }\n\(fn) draw() {\n  background(24);\n  circle(width / 2 + tilt * 100, height / 2, 40);\n}\n\(fn) gravityUpdated(\(js ? "x, y, z" : "float x, float y, float z")) { tilt = x; }\n\(fn) sensorStatusUpdated(\(js ? "sensor, status" : "String sensor, String status")) {\n  \(js ? "console.log(sensor, status);" : "println(sensor + \": \" + status);")\n}"),
            ReferenceTopic(id: "files", title: "Projects, data, and recovery",
                keywords: "Files import assets folder iCloud sharing undo redo autosave rename duplicate conflict",
                explanation: "Project source files live at the folder's top level. The project-named file runs first, then other source files in name order. Put assets in data/ and use paths such as data/photo.png. Import can copy a whole project; Open Folder from Files links one for editing in place. Share exports a whole ZIP or folder. The bottom toolbar's Undo and Redo icons reverse your recent edits. Conflicting external edits are preserved until you choose a version.",
                example: ""),
            ReferenceTopic(id: "compatibility", title: "Supported versions and limits",
                keywords: "Processing.js p5.js Java JavaScript jar library npm import settings P3D WEBGL compatibility",
                explanation: js
                    ? "This app bundles p5.js 1.4.0 and p5.sound. Use p5 v1 global-mode sketches, with function setup()/draw() and preload() for assets. Modern p5 v2 examples may need changes. Java Processing source is a different language; rename alone does not convert it. Browser-compatible JavaScript can run here, but Node.js APIs, npm installation, and desktop Java .jar libraries are unavailable. The online reference may describe newer 1.x additions."
                    : "This app runs Processing.js 1.6.6, with additions for StringList, circle, square, fullScreen, displayWidth/displayHeight, CameraView, sensors, and image export. It does not implement every desktop Processing 4 API. Desktop Java .jar libraries cannot run here. Use CameraView instead of processing.video. Check examples and supported APIs before importing a desktop sketch. Online Processing documentation describes desktop behavior.",
                example: "")
        ]
        topics.append(ReferenceTopic(id: "images", title: "Load an image",
            keywords: "image loadImage preload PImage imageMode data assets",
            explanation: "Import an image through the folder browser; it is placed in data/. This example needs data/photo.png. Load it before drawing, then image(img, x, y, w, h) positions and scales it. " + (js ? "preload() waits for p5 v1 asset loaders before setup()." : "Processing.js uses the @pjs preload directive for local images."),
            example: js
                ? "let photo;\nfunction preload() { photo = loadImage(\"data/photo.png\"); }\nfunction setup() {\n  \(canvas)\n  image(photo, 0, 0, width, height);\n  noLoop();\n}"
                : "/* @pjs preload=\"data/photo.png\"; */\nPImage photo;\nvoid setup() {\n  \(canvas)\n  photo = loadImage(\"data/photo.png\");\n  image(photo, 0, 0, width, height);\n  noLoop();\n}"))
        topics.append(ReferenceTopic(id: "collections", title: js ? "Arrays and vectors" : "StringList and vectors",
            keywords: "StringList array append get size sort join PVector createVector add mult normalize",
            explanation: js
                ? "Use JavaScript arrays to collect values; push() appends and length counts elements. createVector(x, y) creates a p5.Vector. add(), mult(), and normalize() change that vector, so use copy() when you need to preserve it."
                : "StringList stores strings: append(), get(index), size(), sort(), and join(separator) are available. Indexes start at zero. PVector stores x/y/z; add(), mult(), and normalize() change it, so copy it before modifying it if needed.",
            example: sketch(js
                ? "let names = [\"Blue\", \"Amber\"];\nnames.push(\"Coral\");\nnames.sort();\nconsole.log(names.join(\", \"));\nlet position = createVector(120, 80);\ncircle(position.x, position.y, 40);"
                : "StringList names = new StringList();\nnames.append(\"Blue\");\nnames.append(\"Amber\");\nnames.sort();\nprintln(names.join(\", \"));\nPVector position = new PVector(120, 80);\ncircle(position.x, position.y, 40);")))
        topics.append(ReferenceTopic(id: "pixels", title: "Reading and changing pixels",
            keywords: "pixels loadPixels updatePixels set get pixelDensity Retina",
            explanation: js
                ? "loadPixels() reads an RGBA array. Retina density increases its dimensions; call pixelDensity(1) before drawing if you want width × height pixels. Each pixel uses four entries: red, green, blue, alpha. Call updatePixels() after changes. get()/set() are simpler for individual pixels."
                : "loadPixels() exposes width × height packed colors in logical pixels, even on Retina screens. Set pixels[y * width + x] to color(r, g, b), then call updatePixels(). Vector drawing still uses the screen's full resolution. get()/set() are simpler for individual pixels.",
            example: sketch((js ? "pixelDensity(1);\n" : "") + "background(24);\nloadPixels();\n" + (js
                ? "for (let i = 0; i < pixels.length; i += 4) {\n  pixels[i] = 255;\n  pixels[i + 3] = 255;\n}"
                : "for (int i = 0; i < pixels.length; i++) {\n  pixels[i] = color(255, 24, 24);\n}") + "\nupdatePixels();")))
        return topics
    }

    static func search(_ query: String, language: String) -> [ReferenceTopic] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return topics(language: language).filter { topic in
            let text = topic.title + " " + topic.keywords + " " + topic.explanation
            return words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }
}

final class OfflineReferenceViewController: UITableViewController, UISearchResultsUpdating {
    private let language: String
    private var topics: [ReferenceTopic]
    private let search = UISearchController(searchResultsController: nil)

    init(language: String) {
        self.language = language
        topics = OfflineReference.topics(language: language)
        super.init(style: .insetGrouped)
        title = language == "js" ? "p5.js Reference" : "Processing Reference"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search APIs and topics"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
    }

    @objc private func close() { dismiss(animated: true) }

    func updateSearchResults(for searchController: UISearchController) {
        topics = OfflineReference.search(searchController.searchBar.text ?? "", language: language)
        let empty = UILabel()
        empty.text = "No matching topics"
        empty.textAlignment = .center
        empty.textColor = .secondaryLabel
        tableView.backgroundView = topics.isEmpty ? empty : nil
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Available offline · " + (language == "js" ? "p5.js 1.4.0" : "Processing.js 1.6.6")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { topics.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "topic") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "topic")
        let topic = topics[indexPath.row]
        cell.textLabel?.text = topic.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = topic.keywords
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .caption1)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(ReferenceDetailViewController(topic: topics[indexPath.row], language: language), animated: true)
    }
}

private final class ReferenceDetailViewController: UIViewController {
    private let topic: ReferenceTopic
    private let language: String

    init(topic: ReferenceTopic, language: String) {
        self.topic = topic
        self.language = language
        super.init(nibName: nil, bundle: nil)
        title = topic.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let text = UITextView()
        text.isEditable = false
        text.adjustsFontForContentSizeCategory = true
        text.backgroundColor = .systemBackground
        text.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 24, right: 16)
        let content = NSMutableAttributedString(string: topic.title + "\n\n", attributes: [.font: UIFont.preferredFont(forTextStyle: .title2), .foregroundColor: UIColor.label])
        content.append(NSAttributedString(string: topic.explanation + "\n\n", attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label]))
        if !topic.example.isEmpty {
            content.append(NSAttributedString(string: "Example\n\n", attributes: [.font: UIFont.preferredFont(forTextStyle: .headline), .foregroundColor: UIColor.label]))
            content.append(NSAttributedString(string: topic.example, attributes: [.font: UIFontMetrics.default.scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular)), .foregroundColor: UIColor.label]))
        }
        text.attributedText = content
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            text.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Online", style: .plain, target: self, action: #selector(online))
        ]
        if !topic.example.isEmpty {
            navigationItem.rightBarButtonItems?.insert(UIBarButtonItem(title: "Copy Example", style: .plain, target: self, action: #selector(copyExample)), at: 0)
        }
    }

    @objc private func copyExample() {
        UIPasteboard.general.string = topic.example
        UIAccessibility.post(notification: .announcement, argument: "Example copied")
        navigationItem.rightBarButtonItems?.first?.title = "Copied"
    }

    @objc private func online() {
        let address = language == "js" ? "https://v1.p5js.org/reference/" : "https://processing.org/reference/"
        present(SFSafariViewController(url: URL(string: address)!), animated: true)
    }
}
