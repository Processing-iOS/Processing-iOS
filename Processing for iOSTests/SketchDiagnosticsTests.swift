import Testing
@testable import Processing_for_iOS

struct SketchDiagnosticsTests {
    @Test(arguments: [
        "ReferenceError: Can't find variable: missingValue",
        "ReferenceError: missingValue is not defined",
        "SyntaxError: Unexpected token '}'",
        "TypeError: null is not an object (evaluating 'value.x')",
        "RangeError: Maximum call stack size exceeded",
        "Sketch failed for an unexpected reason"
    ])
    func runtimeErrorsAreNeverSilentlyDiscarded(message: String) {
        #expect(CodeErrorDetectionEngine.bug(fromString: message) != nil)
    }
}

import Foundation
import WebKit

// WebKit rendering requires the shared host window; keep these integration tests serial.
@Suite(.serialized)
@MainActor
struct SketchRuntimeTests {
    @Test func projectRenameAndDuplicatePreserveSourcesAssetsAndRecovery() throws {
        let fixture = try SketchFixture(language: "js", main: "function setup() { createCanvas(20,20); }")
        let originalFolder = fixture.project.folder
        let renamed = fixture.project.name + "Renamed", copyName = fixture.project.name + "Copy"
        let copyFolder = originalFolder.deletingLastPathComponent().appendingPathComponent(copyName)
        defer { fixture.remove(); try? FileManager.default.removeItem(at: originalFolder); try? FileManager.default.removeItem(at: copyFolder) }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let before = try #require(file.content)
        #expect(file.save(newContent: before + "\n// revised"))
        let asset = originalFolder.appendingPathComponent("data/palette.bin")
        try FileManager.default.createDirectory(at: asset.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1,2,3,255]).write(to: asset)
        try "temporary runtime".write(to: originalFolder.appendingPathComponent("__runtime_ignore.html"), atomically: true, encoding: .utf8)
        let collision = originalFolder.appendingPathComponent(renamed + ".js")
        try "// occupied".write(to: collision, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try ProjectFiles.renameProject(fixture.project, to: renamed) }
        #expect(FileManager.default.fileExists(atPath: originalFolder.path))
        #expect(try String(contentsOf: collision) == "// occupied")
        try FileManager.default.removeItem(at: collision)
        try ProjectFiles.renameProject(fixture.project, to: renamed)
        #expect(!FileManager.default.fileExists(atPath: originalFolder.path))
        let renamedFile = try #require(fixture.project.sourceCodeFiles.first)
        #expect(renamedFile.fileName == renamed + ".js")
        #expect(try renamedFile.history().contains { $0.content == before })
        try ProjectFiles.duplicateProject(fixture.project, as: copyName)
        #expect(try Data(contentsOf: copyFolder.appendingPathComponent("data/palette.bin")) == Data([1,2,3,255]))
        #expect(try String(contentsOf: copyFolder.appendingPathComponent(copyName + ".js")) == before + "\n// revised")
        #expect(!FileManager.default.fileExists(atPath: copyFolder.appendingPathComponent(".processing-history").path))
        #expect(!FileManager.default.fileExists(atPath: copyFolder.appendingPathComponent("__runtime_ignore.html").path))
        #expect(throws: (any Error).self) { try ProjectFiles.renameProject(fixture.project, to: copyName) }
        #expect(FileManager.default.fileExists(atPath: fixture.project.folder.path))
    }

    @Test func fileRenamingCarriesHistoryAndCannotReplaceAnotherFile() throws {
        let fixture = try SketchFixture(language: "pde", main: "void setup() {}")
        defer { fixture.remove() }
        let original = try #require(fixture.project.sourceCodeFiles.first)
        #expect(original.save(newContent: "void setup() { size(30,30); }"))
        try ProjectFiles.renameFile(URL(fileURLWithPath: original.filePath), to: "Main.pde", projectFolder: fixture.project.folder)
        let renamed = SourceCodeFile(filePath: fixture.project.folder.appendingPathComponent("Main.pde").path)
        #expect(try renamed.history().first?.content == "void setup() {}")
        try ProjectFiles.duplicateFile(URL(fileURLWithPath: renamed.filePath), as: "Copy.pde", projectFolder: fixture.project.folder)
        #expect(throws: (any Error).self) {
            try ProjectFiles.renameFile(URL(fileURLWithPath: renamed.filePath), to: "Copy.pde", projectFolder: fixture.project.folder)
        }
        #expect(try String(contentsOfFile: renamed.filePath) == "void setup() { size(30,30); }")
        #expect(throws: (any Error).self) {
            try ProjectFiles.renameFile(URL(fileURLWithPath: renamed.filePath), to: "Main.js", projectFolder: fixture.project.folder)
        }
        var latest = URL(fileURLWithPath: renamed.filePath)
        for index in 0..<8 {
            let name = "Version\(index).pde"
            try ProjectFiles.renameFile(latest, to: name, projectFolder: fixture.project.folder)
            latest = fixture.project.folder.appendingPathComponent(name)
        }
        #expect(try SourceCodeFile(filePath: latest.path).history().first?.content == "void setup() {}")
    }

    @Test func typingANewlineBetweenBracesIndentsAndKeepsTheClosingBrace() throws {
        let code = "function setup() {}"
        let fixture = try SketchFixture(language: "js", main: code)
        defer { fixture.remove() }
        let editor = PDEEditorViewController(sourceCodeFile: try #require(fixture.project.sourceCodeFiles.first))!
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let previousRoot = window.rootViewController
        window.rootViewController = editor
        defer { editor.editor.resignFirstResponder(); window.rootViewController = previousRoot }
        editor.loadViewIfNeeded()
        editor.editor.becomeFirstResponder()
        editor.editor.selectedRange = (code as NSString).range(of: "}")
        editor.editor.selectedRange.length = 0
        // Simulate UIKit's delegate callback before committing keyboard text.
        // Programmatic insertText alone deliberately bypasses shouldChangeText.
        func type(_ text: String) {
            let input = editor.editor!
            if input.delegate?.textView?(input, shouldChangeTextIn: input.selectedRange, replacementText: text) != false {
                input.insertText(text)
                input.delegate?.textViewDidChange?(input)
            }
        }
        type("\n")
        #expect(editor.editor.text == "function setup() {\n   \n}")
        type("\n")
        #expect(editor.editor.text == "function setup() {\n   \n   \n}")
        type("background(0);")
        #expect(editor.editor.text == "function setup() {\n   \n   background(0);\n}")
        #expect(editor.saveCode())
        #expect(try String(contentsOfFile: editor.sourceCodeFile.filePath) == editor.editor.text)
    }

    @Test func formattingPreservesLiteralContentsAndSupportsUndo() throws {
        let code = "function setup() {\nconst message = `first\n     untouched { line\nlast`;\nif (true) {\nbackground(0);\n}\n}"
        let fixture = try SketchFixture(language: "js", main: code)
        defer { fixture.remove() }
        let editor = PDEEditorViewController(sourceCodeFile: try #require(fixture.project.sourceCodeFiles.first))!
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let previousRoot = window.rootViewController
        window.rootViewController = editor
        defer { editor.editor.resignFirstResponder(); window.rootViewController = previousRoot }
        editor.loadViewIfNeeded()
        editor.editor.becomeFirstResponder()
        editor.formatCode()
        #expect(editor.editor.text.contains("`first\n     untouched { line\nlast`"))
        #expect(editor.editor.text.contains("\n      background(0);"))
        let undo = try #require(editor.editor.undoManager)
        #expect(undo.canUndo)
        undo.undo()
        #expect(editor.editor.text == code)
    }

    @Test func printedOutputReachesTheConsoleInBothLanguages() async throws {
        for language in ["pde", "js"] {
            let code = language == "pde"
                ? #"void setup() { size(20,20); print("Hello "); println(42); noLoop(); }"#
                : "function setup() { createCanvas(20,20); let value = {answer:42}; value.self = value; console.warn('Hello', value); noLoop(); }"
            let fixture = try SketchFixture(language: language, main: code)
            defer { fixture.remove() }
            let probe = RuntimeProbe()
            defer { probe.close() }
            try probe.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
            let output = try await probe.message(named: "iosbridge", event: "console")
            let records = try #require(output["records"] as? [[String: Any]])
            let text = records.compactMap { $0["text"] as? String }.joined()
            #expect(text.contains("Hello"))
            #expect(text.contains("42"))
            if language == "js" {
                #expect(text.contains("Circular"))
                #expect(records.first?["level"] as? String == "warn")
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            let allOutput = probe.consoleOutput
            #expect(!allOutput.contains("imported multiple times"))
        }
    }

    @Test func consoleKeepsRecentOutputAndErrorsAfterLeavingTheSketch() async throws {
        let fixture = try SketchFixture(language: "js", main: """
        function setup() {
          createCanvas(20,20);
          for (let i=0; i<10000; i++) console.log('line', i, 'x'.repeat(1000));
          console.log('LAST MESSAGE');
          missingConsoleValue();
        }
        """)
        defer { fixture.remove() }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let previousRoot = window.rootViewController
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        defer { window.rootViewController = previousRoot }
        let runner = try #require(RunSketchViewController(simpleTextProject: fixture.project))
        let console = try #require(runner.console)
        navigation.pushViewController(runner, animated: false)
        let deadline = Date().addingTimeInterval(10)
        while !console.text.contains("missingConsoleValue"), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        navigation.popViewController(animated: false)
        #expect(console.text.contains("LAST MESSAGE"))
        #expect(console.text.contains("missingConsoleValue"))
        #expect(console.text.contains("[ERROR]"))
        #expect(console.text.utf8.count <= 60_000)
        console.clear()
        #expect(console.text.isEmpty)
    }

    @Test(arguments: ["NotAllowedError", "NotFoundError", "cancelBeforePermissionCompletes"])
    func cameraExampleRequestsPermissionAutomaticallyAndHandlesFailure(outcome: String) async throws {
        let example = try #require(Bundle.main.url(forResource: "Example_Camera", withExtension: "js"))
        let fixture = try SketchFixture(language: "js", main: String(contentsOf: example, encoding: .utf8))
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        // Substitute only the browser capture boundary: the actual bundled sketch
        // and runtime must initiate access automatically and own cleanup.
        let setup = """
        // This wait belongs to the test harness, not to the stopped sketch.
        window.captureTestDelay = window.setTimeout.bind(window);
        window.cameraRequests = [];
        window.cameraSupported = typeof navigator.mediaDevices?.getUserMedia === 'function';
        if (cameraSupported) navigator.mediaDevices.getUserMedia = constraints => {
          cameraRequests.push(constraints);
          return new Promise((resolve, reject) => { window.finishCapture = resolve; window.denyCapture = reject; });
        };
        """
        browser.webView.configuration.userContentController.addUserScript(WKUserScript(
            source: setup, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        let result = try await browser.webView.callAsyncJavaScript("""
        if (!cameraSupported || cameraRequests.length !== 1) return {supported:cameraSupported, count:cameraRequests.length};
        if (outcome === 'cancelBeforePermissionCompletes') {
          const source = document.createElement('canvas');
          source.width = source.height = 20;
          source.getContext('2d').fillRect(0,0,20,20);
          const stream = source.captureStream();
          SketchRuntime.stop();
          finishCapture(stream);
          await new Promise(resolve => captureTestDelay(resolve, 0));
          return {supported:true, count:cameraRequests.length, audio:cameraRequests[0].audio,
            stopped:stream.getTracks().every(t => t.readyState === 'ended'), videos:document.querySelectorAll('video').length};
        }
        denyCapture(new DOMException('Test capture response', outcome));
        await new Promise(resolve => captureTestDelay(resolve, 0));
        return {supported:true, count:cameraRequests.length, audio:cameraRequests[0].audio,
          message:document.querySelector('[role=status]').textContent};
        """, arguments: ["outcome": outcome], in: nil, contentWorld: .page) as? [String: Any]
        #expect(result?["supported"] as? Bool == true)
        #expect(result?["count"] as? Int == 1)
        #expect(result?["audio"] as? Bool == false)
        if outcome == "cancelBeforePermissionCompletes" {
            #expect(result?["stopped"] as? Bool == true)
            #expect(result?["videos"] as? Int == 0)
        } else {
            #expect((result?["message"] as? String)?.contains(outcome == "NotAllowedError" ? "denied" : "No camera") == true)
        }
        #expect(browser.errors.isEmpty)
    }

    @Test(arguments: ["pde", "js"])
    func cameraViewDrawsAtAssignedBoundsAndManagesCaptureLifecycle(language: String) async throws {
        let code = language == "pde" ? """
        CameraView camera;
        float cameraX = 10, cameraY = 10, cameraWidth = 30, cameraHeight = 30;
        void setup() { size(80,60); camera = new CameraView("back"); }
        void draw() {
          background(255); pushMatrix(); translate(5,0); camera.draw(cameraX,cameraY,cameraWidth,cameraHeight); popMatrix();
          noStroke(); fill(255,0,0); rect(20,20,5,5);
        }
        String captureStatus() { return camera.status; }
        void switchCamera() { camera.setFacing("front"); }
        void retryCamera() { camera.start(); }
        void resizeCamera() { cameraX = 40; cameraY = 20; cameraWidth = 20; cameraHeight = 20; }
        """ : """
        let camera;
        let cameraX = 10, cameraY = 10, cameraWidth = 30, cameraHeight = 30;
        function setup() { createCanvas(80,60); camera = new CameraView("back"); }
        function draw() {
          background(255); push(); translate(5,0); camera.draw(cameraX,cameraY,cameraWidth,cameraHeight); pop();
          noStroke(); fill(255,0,0); rect(20,20,5,5);
        }
        function captureStatus() { return camera.status; }
        function switchCamera() { camera.setFacing("front"); }
        function retryCamera() { camera.start(); }
        function resizeCamera() { cameraX = 40; cameraY = 20; cameraWidth = 20; cameraHeight = 20; }
        """
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: 2)
        defer { browser.close() }
        browser.webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        window.captureRequests = []; window.captureStreams = [];
        navigator.mediaDevices.getUserMedia = constraints => {
          captureRequests.push(constraints);
          const source = document.createElement('canvas'); source.width = 100; source.height = 20;
          const ctx = source.getContext('2d'); ctx.fillStyle = '#00ff00'; ctx.fillRect(0,0,100,20);
          ctx.fillStyle = '#0000ff'; ctx.fillRect(35,0,30,20);
          const stream = source.captureStream(30); captureStreams.push(stream);
          // Supply a live frame source; a one-time paint before capture begins
          // need not produce any frames in WebKit's captureStream implementation.
          const frames = setInterval(() => {
            if (stream.getVideoTracks()[0].readyState === 'ended') { clearInterval(frames); return; }
            ctx.fillStyle = '#00ff00'; ctx.fillRect(0,0,100,20);
            ctx.fillStyle = '#0000ff'; ctx.fillRect(35,0,30,20);
          }, 33);
          return Promise.resolve(stream);
        };
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        let result = try await browser.webView.callAsyncJavaScript("""
        const sketch = window.Processing ? Processing.getInstanceById('Sketch') : window;
        const active = async () => {
          const deadline = Date.now()+5000;
          while (sketch.captureStatus() !== 'active') {
            if (Date.now() > deadline) throw new Error('Camera never became active: '+sketch.captureStatus()+', request '+captureRequests.length);
            await new Promise(resolve => setTimeout(resolve, 20));
          }
          sketch.draw();
        };
        await active();
        const canvas = document.querySelector('canvas'), ctx = canvas.getContext('2d');
        const pixel = (x,y) => Array.from(CanvasRenderingContext2D.prototype.getImageData.call(ctx,x*2,y*2,1,1).data);
        const pixels = [...pixel(5,15), ...pixel(16,15), ...pixel(43,15), ...pixel(47,15), ...pixel(22,22)];
        sketch.resizeCamera(); sketch.draw();
        const resized = [...pixel(16,15), ...pixel(46,25), ...pixel(66,25)];
        sketch.switchCamera();
        await active();
        const firstEnded = captureStreams[0].getTracks().every(t => t.readyState === 'ended');
        SketchRuntime.pauseCameras();
        const paused = sketch.captureStatus() === 'paused' && captureStreams[1].getTracks().every(t => t.readyState === 'ended');
        SketchRuntime.resumeCameras();
        await active();
        SketchRuntime.stop();
        sketch.retryCamera();
        return {pixels, resized, firstEnded, paused, count:captureRequests.length,
          facing:captureRequests.map(r => r.video.facingMode.ideal),
          ended:captureStreams.every(s => s.getTracks().every(t => t.readyState === 'ended'))};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        #expect(result?["pixels"] as? [Int] == [255,255,255,255, 0,0,255,255, 0,0,255,255, 255,255,255,255, 255,0,0,255])
        #expect(result?["resized"] as? [Int] == [255,255,255,255, 0,0,255,255, 255,255,255,255])
        #expect(result?["facing"] as? [String] == ["environment", "user", "user"])
        #expect(result?["count"] as? Int == 3)
        #expect(result?["firstEnded"] as? Bool == true)
        #expect(result?["paused"] as? Bool == true)
        #expect(result?["ended"] as? Bool == true)
        #expect(browser.errors.isEmpty)
    }

    @Test(arguments: ["pde", "js"])
    func sensorInputsReachSketchesWithUnitsAndStopAtTeardown(language: String) async throws {
        let code = language == "pde" ? """
        void setup() { size(40,30); noLoop(); background(0); }
        void gravityUpdated(float x, float y, float z) { background(128+x*100,128+y*100,128+z*100); }
        void altimeterUpdated(float meters, float kPa) { noStroke(); fill(meters,kPa,0); rect(0,0,5,5); }
        void sensorStatusUpdated(String sensor, String status) {
          if (sensor.equals("gravityUpdated") && status.equals("denied")) background(255,0,0);
        }
        """ : """
        function setup() { createCanvas(40,30); noLoop(); background(0); }
        function gravityUpdated(x,y,z) { background(128+x*100,128+y*100,128+z*100); }
        function altimeterUpdated(meters,kPa) { noStroke(); fill(meters,kPa,0); rect(0,0,5,5); }
        function sensorStatusUpdated(sensor,status) {
          if (sensor === 'gravityUpdated' && status === 'denied') background(255,0,0);
        }
        """
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: 1)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        let ready = try await browser.message(named: "iosbridge", event: "ready")
        #expect(Set(ready["sensors"] as? [String] ?? []) == ["gravityUpdated", "altimeterUpdated"])
        let colors = try await browser.webView.evaluateJavaScript("""
        (() => {
          const canvas = document.querySelector('canvas');
          const pixel = (x,y) => Array.from(canvas.getContext('2d').getImageData(x,y,1,1).data);
          SketchRuntime.updateSensors({readings:{gravityUpdated:[-0.5,0.25,1],altimeterUpdated:[12,101]}});
          const result = [...pixel(10,10), ...pixel(2,2)];
          SketchRuntime.updateSensors({readings:{gravityUpdated:[NaN,0,0],setup:[1,2,3],altimeterUpdated:[1]}});
          result.push(...pixel(10,10));
          SketchRuntime.updateSensors({statuses:{gravityUpdated:'denied'}});
          result.push(...pixel(10,10));
          SketchRuntime.stop();
          SketchRuntime.updateSensors({readings:{gravityUpdated:[0,0,0]}});
          result.push(...pixel(10,10));
          return result;
        })()
        """) as? [Int]
        #expect(colors == [78,153,228,255, 12,101,0,255, 78,153,228,255, 255,0,0,255, 255,0,0,255])
        #expect(browser.errors.isEmpty)
    }

    @Test func bundledSensorDashboardCompilesAndReceivesHardwareStatus() async throws {
        let example = try #require(Bundle.main.url(forResource: "Example_Sensors", withExtension: "pde"))
        let fixture = try SketchFixture(language: "pde", main: String(contentsOf: example, encoding: .utf8))
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        let ready = try await browser.message(named: "iosbridge", event: "ready")
        let sensors = try #require(ready["sensors"] as? [String])
        #expect(sensors.count == 8)
        _ = try await browser.webView.evaluateJavaScript("""
        SketchRuntime.updateSensors({statuses:{gravityUpdated:'unavailable',altimeterUpdated:'denied'},
          readings:{orientationUpdated:[0.1,0.2,0.3],magnetometerUpdated:[12,34,56]}});
        """)
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        #expect(browser.errors.isEmpty)
    }

    // The actual WebKit framebuffer is the contract: a larger CSS canvas or an
    // upscaled bitmap must not pass as high-density rendering.
    @Test(arguments: ["pde", "js"], [1, 2, 3])
    func sketchesRenderAtDisplayDensity(language: String, density: Int) async throws {
        let code = language == "pde" ? """
        void setup() { size(40,30); noLoop(); }
        void draw() {
          background(255); smooth(); noStroke(); fill(0);
          rect(10,0,1.0/\(density),height);
        }
        """ : """
        function setup() { createCanvas(40,30); noLoop(); }
        function draw() {
          background(255); noStroke(); fill(0);
          rect(10,0,1/\(density),height);
        }
        """
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: density)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let result = try await browser.webView.evaluateJavaScript("""
        (() => {
          const c = document.querySelector('canvas'), box = c.getBoundingClientRect();
          const ctx = c.getContext('2d');
          const pixels = CanvasRenderingContext2D.prototype.getImageData.call(ctx,10*\(density),5*\(density),2,1).data;
          return [Number(c.getAttribute('width')), Number(c.getAttribute('height')), box.width, box.height, ...pixels];
        })()
        """) as? [Int]
        #expect(result == [40*density, 30*density, 40, 30, 0, 0, 0, 255, 255, 255, 255, 255])
        #expect(browser.errors.isEmpty)
    }

    @Test(arguments: ["pde", "js"], [1, 2, 3])
    func threeDimensionalSketchesKeepTheirLogicalCameraAndFillTheRetinaViewport(language: String, density: Int) async throws {
        let code = language == "pde" ? """
        void setup() { size(40,30,P3D); noLoop(); }
        void draw() { background(255); noStroke(); fill(255,0,0); rect(0,0,width/2,height); }
        """ : """
        function setup() { createCanvas(40,30,WEBGL); noLoop(); }
        function draw() { background(255); noStroke(); fill(255,0,0); translate(-width/2,-height/2); rect(0,0,width/2,height); }
        """
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: density)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let result = try await browser.webView.evaluateJavaScript("""
        (() => {
          const c = document.querySelector('canvas'), gl = c.getContext('webgl') || c.getContext('experimental-webgl');
          const pixels = new Uint8Array(4);
          const read = (x) => { WebGLRenderingContext.prototype.readPixels.call(gl,x,15*\(density),1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels); return Array.from(pixels); };
          return [gl.drawingBufferWidth, gl.drawingBufferHeight, c.getBoundingClientRect().width, ...read(5*\(density)), ...read(35*\(density))];
        })()
        """) as? [Int]
        #expect(result == [40*density, 30*density, 40, 255, 0, 0, 255, 255, 255, 255, 255])
        #expect(browser.errors.isEmpty)
    }

    @Test(arguments: [1, 2, 3])
    func processingRetainsLogicalPixelsResizingAndMouseCoordinates(density: Int) async throws {
        let fixture = try SketchFixture(language: "pde", main: """
        void setup() { size(8,6); noLoop(); }
        """)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: density)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let result = try await browser.webView.evaluateJavaScript("""
        (() => {
          const p = Processing.getInstanceById('Sketch'), c = p.externals.canvas;
          p.size(40,30); p.background(255); p.translate(12,15); p.resetMatrix();
          p.loadPixels(); p.pixels.setPixel(3*40+2, p.color(10,20,30)); p.updatePixels();
          const color = p.get(2,3);
          c.dispatchEvent(new MouseEvent('mousemove', {clientX:12,clientY:15,bubbles:true}));
          // Processing's first-touch handler rewrites the inline style. Retina
          // canvases must retain their logical size through that initialization.
          const touch = new Touch({identifier:1,target:c,clientX:12,clientY:15,pageX:12,pageY:15});
          c.dispatchEvent(new TouchEvent('touchstart', {touches:[touch],targetTouches:[touch],changedTouches:[touch],bubbles:true}));
          const pixel = CanvasRenderingContext2D.prototype.getImageData.call(c.getContext('2d'),2*\(density),3*\(density),1,1).data;
          return [p.width,p.height,p.pixels.getLength(),Number(c.getAttribute('width')),Number(c.getAttribute('height')),
            c.getBoundingClientRect().width,p.red(color),p.green(color),p.blue(color),p.mouseX,p.mouseY,...pixel];
        })()
        """) as? [Int]
        #expect(result == [40,30,1200,40*density,30*density,40,10,20,30,12,15,10,20,30,255])
        #expect(browser.errors.isEmpty)
    }

    @Test(arguments: [1, 2, 3], [false, true])
    func processingOffscreenGraphicsPreserveDrawingAndPixelEdits(density: Int, pixelEdit: Bool) async throws {
        let fixture = try SketchFixture(language: "pde", main: """
        PGraphics layer;
        void setup() {
          size(40,30); noLoop(); layer = createGraphics(40,30,P2D);
          layer.beginDraw(); layer.background(255); layer.smooth(); layer.noStroke(); layer.fill(0);
          \(pixelEdit ? "layer.set(2,3,color(10,20,30));" : "layer.rect(10,0,1.0/\(density),30);")
          layer.endDraw();
        }
        void draw() { image(layer,0,0); }
        """)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: density)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let result = try await browser.webView.evaluateJavaScript("""
        (() => {
          const ctx = document.querySelector('canvas').getContext('2d');
          const read = (x,y,w) => Array.from(CanvasRenderingContext2D.prototype.getImageData.call(ctx,x,y,w,1).data);
          return [...read(10*\(density),5*\(density),2), ...read(2*\(density),3*\(density),1)];
        })()
        """) as? [Int]
        #expect(result == (pixelEdit ? [255,255,255,255,255,255,255,255,10,20,30,255] :
                            [0,0,0,255,255,255,255,255,255,255,255,255]))
        #expect(browser.errors.isEmpty)
    }

    @Test(arguments: [1, 3], [false, true])
    func processingDrawsSeparateStrokesFromTheFirstTouch(density: Int, nativeTouch: Bool) async throws {
        let example = try #require(Bundle.main.url(forResource: "Example_Draw", withExtension: "pde"))
        let fixture = try SketchFixture(language: "pde", main: String(contentsOf: example, encoding: .utf8))
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: density)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        let result = try await browser.webView.evaluateJavaScript("""
        (() => {
          const p = Processing.getInstanceById('Sketch'), c = p.externals.canvas;
          p.noLoop();
          const calls = [], colors = [];
          if (\(nativeTouch)) {
            let previous;
            p.touchStart = (e) => { calls.push('start'); previous = e.changedTouches[0]; };
            p.touchMove = (e) => {
              calls.push('move');
              const next = e.changedTouches[0];
              p.stroke(255); p.line(previous.offsetX,previous.offsetY,next.offsetX,next.offsetY);
              previous = next;
            };
            p.touchEnd = () => calls.push('end');
          } else {
            p.mousePressed = () => calls.push('start');
            p.mouseDragged = () => calls.push('move');
            p.mouseReleased = () => calls.push('end');
          }
          const send = (type,x,y) => {
            const box = c.getBoundingClientRect();
            const touch = new Touch({identifier:1,target:c,clientX:box.left+x,clientY:box.top+y,
              pageX:box.left+x,pageY:box.top+y});
            const active = type === 'touchend' ? [] : [touch];
            c.dispatchEvent(new TouchEvent(type, {touches:active,targetTouches:active,
              changedTouches:[touch],bubbles:true,cancelable:true}));
            p.redraw();
          };
          for (const y of [10,20]) {
            send('touchstart',10,y); send('touchmove',30,y); send('touchend',30,y);
            colors.push(p.red(p.get(20,y)));
          }
          // Touch-down must not draw from the origin or the previous stroke.
          colors.push(p.red(p.get(5,5)), p.red(p.get(20,15)));
          return {calls: calls.join(','), colors};
        })()
        """) as? [String: Any]
        #expect(result?["calls"] as? String == "start,move,end,start,move,end")
        #expect(result?["colors"] as? [Int] == [255, 255, 102, 102])
        #expect(browser.errors.isEmpty)
    }

    @Test func p5CanStillOptIntoLogicalPixels() async throws {
        let fixture = try SketchFixture(language: "js", main: """
        function setup() { pixelDensity(1); createCanvas(40,30); noLoop(); }
        """)
        defer { fixture.remove() }
        let browser = RuntimeProbe(density: 3)
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let result = try await browser.webView.evaluateJavaScript("[document.querySelector('canvas').width, pixelDensity()]") as? [Int]
        #expect(result == [40, 1])
        #expect(browser.errors.isEmpty)
    }

    struct FailureCase: Sendable {
        let language: String
        let main: String
        var helper: String? = nil
        let message: String
        var file: String? = nil
        var line: Int? = nil
    }

    @Test(arguments: [
        FailureCase(language: "js", main: "function setup() {\n  missingValue();\n}", message: "missingValue", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() { helper(); }", helper: "function helper() {\n  const value = null;\n  value.x();\n}", message: "TypeError", file: "Helper.js", line: 3),
        FailureCase(language: "js", main: "function setup() {\n const x = ;\n}", message: "SyntaxError", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() { createCanvas(20,20); }\nfunction draw() { throw new RangeError('draw failed'); }", message: "draw failed", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() {\n Promise.reject(new Error('async failed'));\n}", message: "async failed", file: "main", line: 2),
        FailureCase(language: "js", main: "throw 'plain thrown value';", message: "plain thrown value"),
        FailureCase(language: "js", main: "Promise.reject('   ');", message: "empty error"),
        FailureCase(language: "js", main: "function setup() {\n setTimeout(() => { throw new Error('timer failed'); }, 0);\n}", message: "timer failed", file: "main", line: 2),
        FailureCase(language: "js", main: "function setup() { helper(); }", helper: "// 🧑🏽‍💻\r\nfunction helper() {\r\n missingValue();\r\n}", message: "missingValue", file: "Helper.js", line: 3),
        FailureCase(language: "js", main: "function setup() {\n const element = document.createElement('img');\n element.src = 'data/missing.png';\n document.body.appendChild(element);\n}", message: "Could not load resource"),
        FailureCase(language: "js", main: "function preload() { loadImage('data/missing.png'); }\nfunction setup() { createCanvas(20,20); }", message: "Could not load resource", file: "main", line: 1),
        FailureCase(language: "js", main: "throw {toString() { throw 1; }, get stack() { throw 2; }};", message: "unreadable error"),
        FailureCase(language: "pde", main: "/* @pjs preload=\"data/missing.png\"; */\nvoid setup() { size(20,20); }", message: "Could not load resource"),
        FailureCase(language: "pde", main: "void setup() { size(20,20); }\nvoid draw() { missingValue(); }", message: "missingValue", file: "main", line: 2),
        FailureCase(language: "pde", main: "void setup() {\n int x = ;\n}", message: "SyntaxError")
    ])
    func actualRuntimeReportsFailures(example: FailureCase) async throws {
        let fixture = try SketchFixture(language: example.language, main: example.main,
                                        helper: example.helper.map { ["Helper.js": $0] } ?? [:])
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        #expect(program.preflightBug == nil)
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(program, in: fixture.project.folder)
        let payload = try await browser.message(named: "error")
        let bug = try #require(program.bug(fromMessage: payload))
        #expect(bug.message.contains(example.message))
        if let file = example.file {
            #expect(bug.fileName == (file == "main" ? fixture.mainName : file))
            #expect(bug.line == example.line)
            if !bug.wrongCode.isEmpty {
                let source = try #require(program.sources.first { $0.name == bug.fileName })
                #expect((source.content as NSString).substring(with: bug.range(inSource: source.content)) == bug.wrongCode)
            }
        }
    }

    @Test(arguments: ["js", "pde"])
    func validSketchRendersWithQuotesUnicodeAndHTMLInsideStrings(language: String) async throws {
        let literal = "</script><script>throw new Error('injected')</script> 🧑🏽‍💻 % %@"
        let code = language == "js" ?
            "const text = \"\(literal)\";\nfunction setup() { createCanvas(20,20); background(23,45,67); noLoop(); }" :
            "String text = \"\(literal)\";\nvoid setup() { size(20,20); background(23,45,67); noLoop(); }"
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        #expect(program.preflightBug == nil)
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(program, in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let pixel = try await browser.webView.evaluateJavaScript("Array.from(document.querySelector('canvas').getContext('2d').getImageData(0,0,1,1).data)") as? [Int]
        #expect(pixel == [23, 45, 67, 255])
        #expect(browser.errors.isEmpty)
    }

    @Test func executionOrderAndSecondFileLocationsStayStable() async throws {
        let fixture = try SketchFixture(language: "js", main: "const order = ['main'];", helper: [
            "ZLast.js": "order.push('last');\nfunction setup() { window.result = order.join(','); noLoop(); }",
            "AFirst.js": "order.push('first');"
        ])
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "ready")
        _ = try await browser.message(named: "iosbridge", event: "heartbeat")
        let order = try await browser.webView.evaluateJavaScript("window.result") as? String
        #expect(order == "main,first,last")
        #expect(browser.errors.isEmpty)
    }

    @Test func explicitlyHandledAssetFailuresCanRecover() async throws {
        let fixture = try SketchFixture(language: "js", main: "function setup() { loadImage('data/missing.png', () => {}, () => { window.webkit.messageHandlers.iosbridge.postMessage({event:'recovered'}); }); noLoop(); }")
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "iosbridge", event: "recovered")
        #expect(browser.errors.isEmpty)
    }

    @Test func reportsOnlyTheFirstFailure() async throws {
        let fixture = try SketchFixture(language: "js", main: "function setup() { setTimeout(() => { throw new Error('first'); }, 0); }")
        defer { fixture.remove() }
        let browser = RuntimeProbe()
        defer { browser.close() }
        try browser.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await browser.message(named: "error")
        _ = try await browser.webView.evaluateJavaScript("window.dispatchEvent(new ErrorEvent('error', {message:'second', error:new Error('second')}))")
        #expect(browser.errors.count == 1)
    }

    @Test(arguments: [
        ("void setup() {\n size(20,20);", 1, "Missing }"),
        ("void setup() {\n size(20,20];\n}", 2, "Unexpected closing"),
        ("/* unterminated", 1, "Unclosed block comment"),
        ("String value = \"unterminated;", 1, "Unclosed quoted literal")
    ])
    func processingStructureErrorsHaveOriginalLocations(code: String, line: Int, message: String) throws {
        let fixture = try SketchFixture(language: "pde", main: code)
        defer { fixture.remove() }
        let bug = try #require(fixture.project.prepareRuntime().preflightBug)
        #expect(bug.fileName == fixture.mainName)
        #expect(bug.line == line)
        #expect(bug.message.contains(message))
        #expect(bug.range(inSource: code).location != NSNotFound)
    }

    @Test func processingIgnoresBracketsAndIdentifiersInsideCommentsAndStrings() throws {
        let code = "// missingValue {\r\nString text = \"missingValue [ \\\"\";\r\nvoid setup() { missingValue(); }\r\n/* } */"
        let fixture = try SketchFixture(language: "pde", main: code, helper: ["Other.pde": "// missingValue"])
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        #expect(program.preflightBug == nil)
        let bug = try #require(program.bug(fromMessage: ["message": "ReferenceError: Can't find variable: missingValue"]))
        #expect(bug.fileName == fixture.mainName)
        #expect(bug.line == 3)
        #expect((code as NSString).substring(with: bug.range(inSource: code)) == "missingValue")
        #expect(bug.range(inSource: "// changed\n" + code).location == NSNotFound)
    }

    @Test func ambiguousProcessingReferencesDoNotGuessAFile() throws {
        let fixture = try SketchFixture(language: "pde", main: "void setup() { missingValue(); }",
                                        helper: ["Helper.pde": "void helper() { missingValue(); }"])
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        let bug = try #require(program.bug(fromMessage: ["message": "ReferenceError: Can't find variable: missingValue",
                                                         "url": "processing-generated.js", "line": 1]))
        #expect(!bug.hasSourceLocation)
    }

    @Test func bridgeRejectsMalformedPayloadsAndUnsafeLocations() throws {
        let fixture = try SketchFixture(language: "js", main: "let value = 1;")
        defer { fixture.remove() }
        let program = try fixture.project.prepareRuntime()
        for body: Any in [NSNull(), "oops", ["message": NSNull()], ["message": 42], ["message": ""]] {
            #expect(program.bug(fromMessage: body) == nil)
        }
        for line: Any in [-1, Int.max, true, "1", Double.infinity] {
            let bug = try #require(program.bug(fromMessage: ["message": "TypeError: invalid", "url": "sketch-source.js", "line": line]))
            #expect(!bug.hasSourceLocation)
        }
    }

    @Test(arguments: [false, true])
    func suggestionsOnlyReplaceTheLocatedTokenInUnchangedCode(editBeforeApplying: Bool) throws {
        let code = "void setup() {\n backgroun(23, 45, 67);\n}"
        let fixture = try SketchFixture(language: "pde", main: code)
        defer { fixture.remove() }
        let bug = try #require(fixture.project.prepareRuntime().bug(fromMessage: ["message": "ReferenceError: Can't find variable: backgroun"]))
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        editor.loadViewIfNeeded()
        editor.highlightCompilerError(ofCode: bug)
        if editBeforeApplying { editor.editor.text = "// a new edit\n" + code }
        editor.replaceCharacters(in: bug.range(inSource: code), with: "background")
        let expected = editBeforeApplying ? "// a new edit\n" + code : "void setup() {\n background(23, 45, 67);\n}"
        #expect(editor.editor.text == expected)
        if !editBeforeApplying { #expect(try String(contentsOfFile: file.filePath) == expected) }
    }

    @Test func failedSaveRetainsEditsAndDoesNotOverwriteTheStoredSketch() throws {
        let fixture = try SketchFixture(language: "js", main: "const original = 1;")
        defer { fixture.remove() }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let originalURL = URL(fileURLWithPath: file.filePath)
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        editor.loadViewIfNeeded()
        editor.editor.text = "const edited = 2;"
        file.filePath = fixture.project.folder.path // A directory cannot be replaced by a source file.
        #expect(!editor.saveCode())
        #expect(file.saveError != nil)
        #expect(file.content == "const edited = 2;")
        #expect(try String(contentsOf: originalURL) == "const original = 1;")
        file.filePath = originalURL.path
        #expect(editor.saveCode())
        #expect(file.saveError == nil)
        #expect(try String(contentsOf: originalURL) == "const edited = 2;")
    }

    @Test func editingAutosavesAndAnOldTabCannotRestoreStaleText() async throws {
        let fixture = try SketchFixture(language: "js", main: "const original = 1;")
        defer { fixture.remove() }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let oldEditor = PDEEditorViewController(sourceCodeFile: file)!
        oldEditor.loadViewIfNeeded()
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        editor.loadViewIfNeeded()
        editor.editor.text = "const edited = 2; // 🐻‍❄️"
        editor.textViewDidChange(editor.editor)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(try String(contentsOfFile: file.filePath) == "const edited = 2; // 🐻‍❄️")
        // Page controllers can outlive their visible tab. A lifecycle save must
        // never replace a newer shared buffer with an unchanged old view.
        #expect(oldEditor.saveCode())
        #expect(try String(contentsOfFile: file.filePath) == "const edited = 2; // 🐻‍❄️")
    }

    @Test func restoringHistoryPreservesBothVersionsAcrossReopening() throws {
        let fixture = try SketchFixture(language: "js", main: "const original = 1;")
        defer { fixture.remove() }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        #expect(file.save(newContent: "const revised = 2;"))
        let reopened = SourceCodeFile(filePath: file.filePath)
        let original = try #require(reopened.history().first)
        #expect(original.content == "const original = 1;")
        try reopened.restore(original)
        #expect(try String(contentsOfFile: file.filePath) == "const original = 1;")
        #expect(try SourceCodeFile(filePath: file.filePath).history().contains { $0.content == "const revised = 2;" })
        // An old model with no edits must also leave restored files untouched.
        #expect(file.save())
        #expect(try String(contentsOfFile: file.filePath) == "const original = 1;")
    }

    @Test func editorCompletionSupportsTypingUndoAndSaving() async throws {
        let fixture = try SketchFixture(language: "js", main: "bac")
        defer { fixture.remove() }
        let file = try #require(fixture.project.sourceCodeFiles.first)
        let editor = PDEEditorViewController(sourceCodeFile: file)!
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let previousRoot = window.rootViewController
        window.rootViewController = editor
        defer { editor.editor.resignFirstResponder(); window.rootViewController = previousRoot }
        editor.loadViewIfNeeded()
        #expect(editor.editor.becomeFirstResponder())
        editor.editor.selectedRange = NSRange(location: 3, length: 0)
        let show = try #require(editor.keyCommands?.first { $0.input == " " && $0.modifierFlags == .control })
        let showAction = try #require(show.action)
        #expect(UIApplication.shared.sendAction(showAction, to: editor, from: show, for: nil))
        let accept = try #require(editor.keyCommands?.first { $0.input == "\t" && $0.modifierFlags.isEmpty })
        let acceptAction = try #require(accept.action)
        #expect(UIApplication.shared.sendAction(acceptAction, to: editor, from: accept, for: nil))
        #expect(editor.editor.text == "background()")
        #expect(editor.editor.selectedRange.location == 11)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(editor.editor.selectedRange == NSRange(location: 11, length: 0))
        let undo = try #require(editor.editor.undoManager)
        #expect(undo.canUndo)
        undo.undo()
        #expect(editor.editor.text == "bac")
        undo.redo()
        #expect(editor.editor.text == "background()")
        #expect(editor.saveCode())
        #expect(try String(contentsOfFile: file.filePath) == "background()")
    }

    @Test(arguments: ["pde", "js"])
    func editorHighlightingEndsStringsAtTheirClosingQuote(language: String) throws {
        let code = #"""
        // 🧑🏽‍💻 Quotes must not change the arguments that follow them.
        camera = new CameraView("back", 20, 80, width - 40, height - 100);
        text("Camera input", 21, 41);
        text("An \"escaped\" quote", 22, 42);
        text("C:\\", 23, 43);
        text('single quoted', 24, 44);
        text("first", "second", 25, 45);
        text("https://example.com", 26, 46);
        /* first comment */ text("between comments", 27, 47); /* second comment */
        boolean enabled = true;
        interfaceCount = 28; classify = 29;
        """#
        let fixture = try SketchFixture(language: language, main: code)
        defer { fixture.remove() }
        let editor = PDEEditorViewController(sourceCodeFile: try #require(fixture.project.sourceCodeFiles.first))!
        editor.loadViewIfNeeded()
        let displayed = try #require(editor.editor.attributedText)
        #expect(displayed.string == code)
        let stringColor = try #require(displayed.attribute(.foregroundColor, at: (code as NSString).range(of: "back").location, effectiveRange: nil) as? UIColor)
        #expect(stringColor != UIColor.label)
        for token in ["Camera input", "escaped", "C:", "single quoted", "first", "second", "example.com", "between comments"] {
            let range = (code as NSString).range(of: token)
            #expect(displayed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor == stringColor)
        }
        // Assert the actual editor attributes, not the regex implementation.
        // These are code arguments, so a preceding string must not dim them.
        for token in ["20", "80", "width", "height", "100", "21", "22", "23", "24", "25", "26", "27", "interfaceCount", "classify"] {
            let range = (code as NSString).range(of: token)
            let color = try #require(displayed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor)
            #expect(color == UIColor.label, "Code after a closing quote was recolored: \(token)")
        }
    }

    @Test func processingCompatibilityHelpersRenderAndKeepDesktopMathSemantics() async throws {
        let fixture = try SketchFixture(language: "pde", main: """
        StringList words = new StringList();
        void paintAt(float x, float y, float extent) { square(x, y, extent); }
        void setup() {
          size(100,100); noLoop(); background(0); noStroke();
          words.append("beta"); words.append("alpha"); words.sort();
          PVector v = new PVector(3,4); v.normalize();
          if (words.get(0).equals("alpha") && words.size() == 2 && abs(v.mag()-1) < 0.001) fill(255,0,0);
          else fill(0);
          paintAt(0,0,map(5,0,10,0,40));
          fill(0,255,0); circle(50,50,20);
          ellipseMode(CORNERS); fill(0,0,255); ellipse(70,70,90,90);
        }
        """)
        defer { fixture.remove() }
        let probe = RuntimeProbe(density: 1)
        defer { probe.close() }
        try probe.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await probe.message(named: "iosbridge", event: "ready")
        let pixels = try await probe.webView.evaluateJavaScript("""
        (() => { const ctx = document.querySelector('canvas').getContext('2d');
        return [10,50,80].flatMap(n => Array.from(ctx.getImageData(n,n,1,1).data)); })()
        """) as? [Int]
        #expect(pixels == [255,0,0,255, 0,255,0,255, 0,0,255,255])
    }

    @Test func savingACanvasCreatesAnImageInBothLanguages() async throws {
        for language in ["pde", "js"] {
            let code = language == "pde"
                ? "void setup() { size(40,30); background(255,0,0); noLoop(); saveFrame(\"review.png\"); }"
                : "function setup() { createCanvas(40,30); background(255,0,0); noLoop(); saveCanvas('review','png'); }"
            let fixture = try SketchFixture(language: language, main: code)
            defer { fixture.remove() }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = try #require(scene.windows.first { $0.isKeyWindow })
            let previousRoot = window.rootViewController
            let navigation = UINavigationController(rootViewController: UIViewController())
            window.rootViewController = navigation
            defer { navigation.popViewController(animated: false); window.rootViewController = previousRoot }
            let runner = try #require(RunSketchViewController(simpleTextProject: fixture.project))
            navigation.pushViewController(runner, animated: false)
            let output = fixture.project.folder.appendingPathComponent("exports/review.png")
            let deadline = Date().addingTimeInterval(5)
            while !FileManager.default.fileExists(atPath: output.path), Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let image = try #require(UIImage(contentsOfFile: output.path))
            let bitmap = try #require(image.cgImage)
            let density = Int(ceil(window.screen.scale))
            #expect(bitmap.width == 40 * density && bitmap.height == 30 * density)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            #expect(pixel == [255, 0, 0, 255])
        }
    }

    @Test func desktopLibraryImportsExplainTheSupportedAlternative() throws {
        let fixture = try SketchFixture(language: "pde", main: "// import fake.example.*;\nimport processing.video.*;\nvoid setup() {}")
        defer { fixture.remove() }
        let bug = try #require(fixture.project.prepareRuntime().preflightBug)
        #expect(bug.line == 2)
        #expect(bug.message.contains("CameraView"))
        #expect(bug.message.contains("processing.video"))
    }

    @Test func stoppingARuntimeCancelsUserWorkAndRemovesItsCanvas() async throws {
        let fixture = try SketchFixture(language: "js", main: """
        window.workCount = 0;
        function setup() {
          createCanvas(80, 80);
          setInterval(function() { window.workCount++; }, 10);
          setTimeout(function() { window.workCount += 1000; }, 500);
          function animate() { window.workCount++; requestAnimationFrame(animate); }
          requestAnimationFrame(animate);
        }
        """)
        defer { fixture.remove() }
        let probe = RuntimeProbe()
        defer { probe.close() }
        try probe.load(fixture.project.prepareRuntime(), in: fixture.project.folder)
        _ = try await probe.message(named: "iosbridge", event: "ready")
        let count = try await probe.webView.evaluateJavaScript("SketchRuntime.stop(); window.workCount") as? Int
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(try await probe.webView.evaluateJavaScript("window.workCount") as? Int == count)
        #expect(try await probe.webView.evaluateJavaScript("document.querySelectorAll('canvas').length") as? Int == 0)
    }

    @Test func repeatedRunsReleaseTheirViewsAndTemporaryFiles() async throws {
        let pde = try SketchFixture(language: "pde", main: "void setup() { size(40,40); background(255); noLoop(); }")
        let js = try SketchFixture(language: "js", main: "function setup() { createCanvas(40,40); background(255); noLoop(); }")
        defer { pde.remove(); js.remove() }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let previousRoot = window.rootViewController
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        defer { window.rootViewController = previousRoot }
        for iteration in 0..<20 {
            let fixture = iteration.isMultiple(of: 2) ? pde : js
            var runner: RunSketchViewController? = RunSketchViewController(simpleTextProject: fixture.project)
            weak var releasedRunner = runner
            navigation.pushViewController(try #require(runner), animated: false)
            let deadline = Date().addingTimeInterval(10)
            while runner?.completedSuccessfully != true, Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            try #require(runner?.completedSuccessfully == true, "Run \(iteration) did not start")
            weak var releasedWebView = runner?.sketchWebView
            navigation.popViewController(animated: false)
            let teardownDeadline = Date().addingTimeInterval(2)
            while runner?.sketchWebView != nil, Date() < teardownDeadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(runner?.sketchWebView == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.folder.path).allSatisfy { !$0.hasPrefix("__runtime_") })
            runner = nil
            while (releasedRunner != nil || releasedWebView != nil), Date() < teardownDeadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(releasedRunner == nil)
            #expect(releasedWebView == nil)
        }
    }

    @Test func importingNeverOverwritesAnExistingProject() throws {
        let fixture = try SketchFixture(language: "js", main: "const original = 1;")
        defer { fixture.remove() }
        let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let file = incoming.appendingPathComponent(fixture.mainName)
        try "const incoming = 2;".write(to: file, atomically: true, encoding: .utf8)
        let rejected = P5JSProject(withProjectName: fixture.project.name, importingFiles: [file])
        #expect(rejected.initializationError != nil)
        #expect(try String(contentsOf: fixture.project.folder.appendingPathComponent(fixture.mainName)) == "const original = 1;")
    }

    @Test(arguments: ["pde", "js"])
    func folderImportPreservesSourcesAssetsAndMainFileOrder(language: String) throws {
        let incoming = FileManager.default.temporaryDirectory.appendingPathComponent("Incoming folder " + UUID().uuidString)
        try FileManager.default.createDirectory(at: incoming.appendingPathComponent("data"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let source = language == "js" ? "function setup() {}" : "void setup() {}"
        try source.write(to: incoming.appendingPathComponent(incoming.lastPathComponent + "." + language), atomically: true, encoding: .utf8)
        try "// helper 🧑🏽‍💻".write(to: incoming.appendingPathComponent("A_helper." + language), atomically: true, encoding: .utf8)
        try "Read me".write(to: incoming.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let asset = Data([0, 255, 1, 254])
        try asset.write(to: incoming.appendingPathComponent("data/picture with spaces.bin"))
        #expect(try ProjectFiles.language(in: [incoming]) == language)
        let project = SimpleTextProject(with: "Imported_" + UUID().uuidString, sourceCodeExtension: language, importingFiles: [incoming])
        defer { try? FileManager.default.removeItem(at: project.folder) }
        #expect(project.initializationError == nil)
        #expect(try project.sourceFileURLs().map(\.lastPathComponent) == [project.name + "." + language, "A_helper." + language])
        #expect(try Data(contentsOf: project.folder.appendingPathComponent("data/picture with spaces.bin")) == asset)
        _ = try project.prepareRuntime()

        // A failed source read must not publish a half-imported project.
        try Data([0xff, 0xfe, 0xff]).write(to: incoming.appendingPathComponent("broken." + language))
        let broken = SimpleTextProject(with: "Rejected_" + UUID().uuidString, sourceCodeExtension: language, importingFiles: [incoming])
        defer { try? FileManager.default.removeItem(at: broken.folder) }
        #expect(broken.initializationError != nil)
        #expect(!FileManager.default.fileExists(atPath: broken.folder.path))
    }

    @Test func aMultiFileImportCollisionLeavesEveryExistingFileUntouched() throws {
        let fixture = try SketchFixture(language: "js", main: "const original = 1;")
        defer { fixture.remove() }
        let incoming = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let helper = incoming.appendingPathComponent("Helper.js")
        let collision = incoming.appendingPathComponent(fixture.mainName)
        try "// helper".write(to: helper, atomically: true, encoding: .utf8)
        try "// replacement".write(to: collision, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try ProjectFiles.importFiles([helper, collision], into: fixture.project.folder) }
        #expect(!FileManager.default.fileExists(atPath: fixture.project.folder.appendingPathComponent("Helper.js").path))
        #expect(try String(contentsOf: fixture.project.folder.appendingPathComponent(fixture.mainName)) == "const original = 1;")
        try ProjectFiles.importFiles([helper], into: fixture.project.folder)
        #expect(try String(contentsOf: fixture.project.folder.appendingPathComponent("Helper.js")) == "// helper")
    }

    @Test func unreadableAndEmptyProjectsFailBeforeLaunching() throws {
        let fixture = try SketchFixture(language: "js", main: "")
        defer { fixture.remove() }
        let url = fixture.project.folder.appendingPathComponent(fixture.mainName)
        try Data([0xff, 0xfe, 0xff]).write(to: url)
        #expect(throws: (any Error).self) { try fixture.project.prepareRuntime() }
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try fixture.project.prepareRuntime() }
    }
}

@MainActor
private struct SketchFixture {
    let project: SimpleTextProject
    var mainName: String { "\(project.name).\(project.sourceCodeExtension)" }

    init(language: String, main: String, helper: [String: String] = [:]) throws {
        let name = "DiagnosticTest_" + UUID().uuidString
        project = language == "pde" ? PDEProject(withProjectName: name) : P5JSProject(withProjectName: name)
        do {
            try main.write(to: project.folder.appendingPathComponent(mainName), atomically: true, encoding: .utf8)
            for (name, content) in helper {
                try content.write(to: project.folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        } catch {
            remove()
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: project.folder) }
}

@MainActor
private final class RuntimeProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var messages: [(String, [String: Any])] = []
    private var receive: ((String, [String: Any]) -> Void)?
    var errors: [[String: Any]] { messages.filter { $0.0 == "error" }.map(\.1) }
    var consoleOutput: String {
        messages.filter { $0.0 == "iosbridge" && $0.1["event"] as? String == "console" }
            .flatMap { $0.1["records"] as? [[String: Any]] ?? [] }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    init(density: Int? = nil) {
        super.init()
        let config = WKWebViewConfiguration()
        if let density {
            config.userContentController.addUserScript(WKUserScript(
                source: "Object.defineProperty(window, 'devicePixelRatio', {value: \(density)});",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(self, name: "error")
        config.userContentController.add(self, name: "iosbridge")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: config)
        webView.navigationDelegate = self
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first(where: \.isKeyWindow)?.addSubview(webView)
    }

    func load(_ program: SketchProgram, in folder: URL) throws {
        let url = folder.appendingPathComponent("test-runtime.html")
        try program.htmlPage.write(to: url, atomically: true, encoding: .utf8)
        webView.loadFileURL(url, allowingReadAccessTo: folder)
    }

    func close() {
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        receive = nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        messages.append((message.name, body))
        receive?(message.name, body)
    }

    func message(named name: String, event: String? = nil) async throws -> [String: Any] {
        func matches(_ channel: String, _ body: [String: Any]) -> Bool {
            channel == name && (event == nil || body["event"] as? String == event)
        }
        if let existing = messages.first(where: { matches($0.0, $0.1) }) { return existing.1 }
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = DispatchWorkItem { [weak self] in
                guard let self = self, self.receive != nil else { return }
                self.receive = nil
                continuation.resume(throwing: NSError(domain: "RuntimeTest", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(name). Received: \(self.messages)"]))
            }
            receive = { [weak self] channel, body in
                guard matches(channel, body) else { return }
                self?.receive = nil
                timeout.cancel()
                continuation.resume(returning: body)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        }
    }
}
