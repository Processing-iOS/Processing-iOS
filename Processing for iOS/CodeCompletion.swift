import Foundation

/// A completion belongs to one source snapshot and caret position.
struct CodeCompletion {
    let name: String
    let detail: String
    let isFunction: Bool
}

struct CodeCompletionRequest {
    let source: String
    let selection: NSRange
    let tokenRange: NSRange
    let items: [CodeCompletion]

    func edit(for item: CodeCompletion, source current: String, selection caret: NSRange) -> (range: NSRange, text: String, caret: Int)? {
        guard current == source, caret == selection, items.contains(where: { $0.name == item.name }) else { return nil }
        let text = source as NSString
        var next = NSMaxRange(tokenRange)
        while next < text.length, let scalar = UnicodeScalar(text.character(at: next)), CharacterSet.whitespacesAndNewlines.contains(scalar) { next += 1 }
        let addCall = item.isFunction && (next == text.length || text.character(at: next) != 40)
        let insertion = item.name + (addCall ? "()" : "")
        return (tokenRange, insertion, tokenRange.location + (item.name as NSString).length + (addCall ? 1 : 0))
    }
}

enum CodeCompletionEngine {
    static func request(source: String, selection: NSRange, language: String,
                        projectSymbols: [String] = [], explicit: Bool = false) -> CodeCompletionRequest? {
        let text = source as NSString
        guard selection.length == 0, selection.location >= 0, selection.location != NSNotFound, selection.location <= text.length else { return nil }
        let lexical = codeOnly(source, language: language)
        guard lexical.codePositions[selection.location] else { return nil }
        let masked = lexical.text as NSString
        var start = selection.location
        while start > 0 && isIdentifierPart(masked.character(at: start - 1)) { start -= 1 }
        var end = selection.location
        while end < text.length && isIdentifierPart(masked.character(at: end)) { end += 1 }
        let prefix = text.substring(with: NSRange(location: start, length: selection.location - start))
        guard explicit || prefix.count >= 2 else { return nil }
        guard prefix.isEmpty || isIdentifierStart(masked.character(at: start)) else { return nil }
        var previous = start
        while previous > 0, let scalar = UnicodeScalar(masked.character(at: previous - 1)), CharacterSet.whitespacesAndNewlines.contains(scalar) { previous -= 1 }
        // Global APIs are not object members; do not offer misleading dot completion.
        guard previous == 0 || masked.character(at: previous - 1) != 46 else { return nil }
        let tokenRange = NSRange(location: start, length: end - start)
        let token = text.substring(with: tokenRange)
        let builtins = catalog(language: language)
        let builtinNames = Set(builtins.map(\.name))
        let localNames = Set(symbols(in: source, language: language) + projectSymbols)
        let locals = localNames.filter { !builtinNames.contains($0) }.map {
            CodeCompletion(name: $0, detail: "Project name", isFunction: false)
        }
        let items = (locals + builtins).filter {
            ($0.name != token || selection.location < end) && $0.name.lowercased().hasPrefix(prefix.lowercased())
        }.sorted {
            let left = $0.name.hasPrefix(prefix), right = $1.name.hasPrefix(prefix)
            if left != right { return left }
            if ($0.detail == "Project name") != ($1.detail == "Project name") { return $0.detail == "Project name" }
            return $0.name < $1.name
        }
        return CodeCompletionRequest(source: source, selection: selection, tokenRange: tokenRange, items: Array(items.prefix(20)))
    }

    static func symbols(in source: String, language: String) -> [String] {
        let code = codeOnly(source, language: language).text as NSString
        var names = Set<String>()
        var index = 0
        while index < code.length {
            guard isIdentifierStart(code.character(at: index)) else { index += 1; continue }
            let start = index
            index += 1
            while index < code.length && isIdentifierPart(code.character(at: index)) { index += 1 }
            names.insert(code.substring(with: NSRange(location: start, length: index - start)))
        }
        return Array(names)
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return unit == 95 || unit == 36 || CharacterSet.letters.contains(scalar)
    }

    private static func isIdentifierPart(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return isIdentifierStart(unit) || CharacterSet.decimalDigits.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar)
    }

    /// Preserve UTF-16 offsets while masking comments, strings, templates and JS regex literals.
    static func codeOnly(_ source: String, language: String) -> (text: String, codePositions: [Bool], spans: [(range: NSRange, comment: Bool)]) {
        let units = Array(source.utf16)
        var masked = units
        var positions = Array(repeating: true, count: units.count + 1)
        var i = 0
        var allowsRegex = true
        var spans: [(range: NSRange, comment: Bool)] = []
        func hide(_ start: Int, _ end: Int, closed: Bool, comment: Bool = false) {
            spans.append((NSRange(location: start, length: end - start), comment))
            for j in start..<end where units[j] != 10 && units[j] != 13 { masked[j] = 32 }
            if end > start {
                for j in (start + 1)...end { positions[j] = false }
            }
            if closed { positions[end] = true }
        }
        while i < units.count {
            let c = units[i], next: UInt16 = i + 1 < units.count ? units[i + 1] : 0
            if c == 47 && next == 47 {
                let start = i
                while i < units.count && units[i] != 10 && units[i] != 13 { i += 1 }
                hide(start, i, closed: false, comment: true)
                continue
            }
            if c == 47 && next == 42 {
                let start = i
                i += 2
                while i < units.count && !(units[i] == 42 && i + 1 < units.count && units[i + 1] == 47) { i += 1 }
                let closed = i < units.count
                if closed { i += 2 }
                hide(start, i, closed: closed, comment: true)
                continue
            }
            if c == 34 || c == 39 || (language == "js" && c == 96) || (language == "js" && c == 47 && allowsRegex) {
                let start = i, delimiter = c
                var inClass = false
                i += 1
                var closed = false
                while i < units.count {
                    if units[i] == 92 { i = min(i + 2, units.count); continue }
                    if delimiter == 47 && units[i] == 91 { inClass = true }
                    if delimiter == 47 && units[i] == 93 { inClass = false }
                    if units[i] == delimiter && !inClass { i += 1; closed = true; break }
                    if delimiter != 96 && (units[i] == 10 || units[i] == 13) { break }
                    i += 1
                }
                hide(start, i, closed: closed)
                allowsRegex = false
                continue
            }
            if isIdentifierStart(c) {
                let start = i
                i += 1
                while i < units.count && isIdentifierPart(units[i]) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                allowsRegex = ["return", "throw", "case", "typeof", "void", "delete", "new", "yield", "await"].contains(word)
                continue
            }
            if c == 10 || c == 13 { positions[i + 1] = true }
            if let scalar = UnicodeScalar(c), !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                allowsRegex = [40, 91, 123, 44, 59, 58, 61, 33, 38, 124, 63, 43, 45, 42, 37].contains(c)
            }
            i += 1
        }
        return (String(decoding: masked, as: UTF16.self), positions, spans)
    }

    private static let commonFunctions = [
        "background(color)", "fill(color)", "noFill()", "stroke(color)", "noStroke()", "strokeWeight(weight)",
        "rect(x, y, width, height)", "ellipse(x, y, width, height)", "circle(x, y, diameter)", "square(x, y, size)", "line(x1, y1, x2, y2)",
        "point(x, y)", "triangle(x1, y1, x2, y2, x3, y3)", "quad(x1, y1, x2, y2, x3, y3, x4, y4)",
        "arc(x, y, width, height, start, stop)", "bezier(x1, y1, cx1, cy1, cx2, cy2, x2, y2)",
        "rectMode(mode)", "ellipseMode(mode)", "colorMode(mode)", "color(value)", "lerpColor(from, to, amount)",
        "beginShape()", "endShape()", "vertex(x, y)", "curveVertex(x, y)", "bezierVertex(cx1, cy1, cx2, cy2, x, y)",
        "translate(x, y)", "rotate(angle)", "scale(amount)", "resetMatrix()",
        "text(value, x, y)", "textSize(size)", "textAlign(horizontal, vertical)", "textFont(font)", "textWidth(value)",
        "image(img, x, y)", "imageMode(mode)", "loadImage(path)", "loadFont(path)", "CameraView(facing)",
        "loadPixels()", "updatePixels()", "get(x, y)", "set(x, y, color)", "filter(kind)",
        "random(max)", "randomSeed(seed)", "noise(x)", "noiseSeed(seed)", "map(value, start1, stop1, start2, stop2)",
        "constrain(value, low, high)", "dist(x1, y1, x2, y2)", "lerp(start, stop, amount)",
        "sin(angle)", "cos(angle)", "tan(angle)", "atan2(y, x)", "radians(degrees)", "degrees(radians)",
        "abs(value)", "ceil(value)", "floor(value)", "round(value)", "sqrt(value)", "pow(value, exponent)", "min(a, b)", "max(a, b)",
        "frameRate(rate)", "noLoop()", "loop()", "redraw()", "millis()", "second()", "minute()", "hour()",
        "setup()", "draw()", "mouseClicked()", "mouseDragged()", "mouseMoved()", "mouseReleased()", "keyTyped()", "keyReleased()",
        "accelerometerUpdated(x, y, z)", "gyroscopeUpdated(x, y, z)", "orientationUpdated(roll, pitch, yaw)",
        "gravityUpdated(x, y, z)", "userAccelerationUpdated(x, y, z)", "rotationRateUpdated(x, y, z)",
        "magnetometerUpdated(x, y, z)", "altimeterUpdated(relativeAltitude, pressure)", "sensorStatusUpdated(sensor, status)"
    ]
    private static let pdeFunctions = ["size(width, height)", "fullScreen(renderer)", "smooth()", "noSmooth()", "pushMatrix()", "popMatrix()", "pushStyle()", "popStyle()", "println(value)", "print(value)", "saveFrame(filename)", "createImage(width, height, format)"]
    private static let jsFunctions = ["createCanvas(width, height)", "resizeCanvas(width, height)", "createVector(x, y)", "push()", "pop()", "clear()", "pixelDensity(density)", "loadJSON(path)", "loadStrings(path)", "loadSound(path)", "saveCanvas(filename)", "preload()", "windowResized()", "mousePressed()", "keyPressed()", "touchStarted()", "touchMoved()", "touchEnded()"]

    static func catalog(language: String) -> [CodeCompletion] {
        let functions = commonFunctions + (language == "js" ? jsFunctions : pdeFunctions)
        let variables = "width height mouseX mouseY pmouseX pmouseY mouseButton key keyCode frameCount pixels PI TWO_PI HALF_PI QUARTER_PI CENTER CORNER CORNERS RADIUS LEFT RIGHT TOP BOTTOM RGB HSB CLOSE POINTS LINES TRIANGLES TRIANGLE_STRIP TRIANGLE_FAN QUADS QUAD_STRIP"
            + (language == "js" ? " windowWidth windowHeight deltaTime touches mouseIsPressed keyIsPressed DEGREES RADIANS" : " screenWidth screenHeight displayWidth displayHeight mousePressed keyPressed PImage PFont PVector StringList P2D P3D")
        let keywords = "if else for while do switch case break continue return class new true false"
            + (language == "js" ? " function let const var null undefined async await" : " void int float double boolean char String color byte long final public private import null")
        let functionItems = functions.map {
            let name = String($0.prefix { $0 != "(" })
            // Processing also uses the constructor name in type declarations.
            return CodeCompletion(name: name, detail: $0, isFunction: language == "js" || name != "CameraView")
        }
        let functionNames = Set(functionItems.map(\.name))
        return functionItems + Set((variables + " " + keywords).split(separator: " ").map(String.init)).filter { !functionNames.contains($0) }.map {
            CodeCompletion(name: String($0), detail: "Name / keyword", isFunction: false)
        }
    }
}
