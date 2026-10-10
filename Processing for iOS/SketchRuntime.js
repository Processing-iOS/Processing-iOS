// Installed before either library or user code executes.
window.SketchRuntime = (function () {
    "use strict";
    var failed = false;
    var stopped = false;
    var instance = null;
    var phase = "compile";
    var sourceURL = "";
    var scriptURLs = [];

    function post(channel, body) {
        var handlers = window.webkit && window.webkit.messageHandlers;
        if (handlers && handlers[channel]) {
            handlers[channel].postMessage(body);
        }
    }

    function stop() {
        stopped = true;
        try {
            if (instance && typeof instance.noLoop === "function") instance.noLoop();
            if (window.p5 && window.p5.instance) window.p5.instance.noLoop();
            if (window.Processing) {
                var sketch = window.Processing.getInstanceById("Sketch");
                if (sketch) sketch.noLoop();
            }
        } catch (_) { /* Preserve the original failure if teardown also fails. */ }
        scriptURLs.forEach(function (url) { URL.revokeObjectURL(url); });
        scriptURLs = [];
        // Prevent p5's automatic global startup after a failed top-level script.
        window.setup = undefined;
        window.draw = undefined;
        window.preload = undefined;
    }

    function report(error, fallback, url, line, column) {
        if (failed || stopped) return;
        failed = true;
        var message;
        try {
            message = error instanceof Error ? error.name + ": " + error.message :
                (error == null ? String(fallback || "Unknown sketch error") : String(error));
        } catch (_) {
            message = "The sketch threw an unreadable error.";
        }
        if (!message.trim()) message = "The sketch threw an empty error.";
        var stack = "";
        try { if (error && typeof error.stack === "string") stack = error.stack; } catch (_) {}
        // Errors thrown by a library often retain a caller in the original sketch.
        if (sourceURL) {
            var escapedURL = sourceURL.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            var frame = stack.match(new RegExp(escapedURL + ":(\\d+):(\\d+)"));
            if (frame) {
                url = sourceURL;
                line = Number(frame[1]);
                column = Number(frame[2]);
            }
            if (url === sourceURL) url = "sketch-source.js";
        }
        post("error", {
            message: message.slice(0, 4000),
            phase: phase,
            url: typeof url === "string" ? url : "",
            line: Number.isFinite(line) ? line : 0,
            column: Number.isFinite(column) ? column : 0,
            stack: stack.slice(0, 8000)
        });
        stop();
    }

    window.addEventListener("error", function (event) {
        if (event instanceof ErrorEvent) {
            report(event.error, event.message, event.filename, event.lineno, event.colno);
        } else {
            var target = event.target;
            var url = target && (target.src || target.href);
            if (url) report(null, "Could not load resource: " + url);
        }
    }, true);

    window.addEventListener("unhandledrejection", function (event) {
        report(event.reason, "Unhandled promise rejection");
        event.preventDefault();
    });

    function script(code, name) {
        return new Promise(function (resolve, reject) {
            var element = document.createElement("script");
            var url = URL.createObjectURL(new Blob([code], { type: "text/javascript" }));
            scriptURLs.push(url);
            if (name === "sketch-source.js") sourceURL = url;
            element.src = url;
            element.onload = function () { element.remove(); resolve(); };
            element.onerror = function () { element.remove(); reject(new Error("Cannot load " + name)); };
            document.head.appendChild(element);
        });
    }

    function installP5AssetDiagnostics() {
        // These loaders log and swallow failures when no error callback is supplied.
        // Preserve explicitly handled failures, while surfacing otherwise silent ones.
        ["loadImage", "loadFont", "loadSound"].forEach(function (name) {
            var original = p5.prototype[name];
            if (typeof original !== "function") return;
            p5.prototype[name] = function () {
                var args = Array.prototype.slice.call(arguments);
                if (typeof args[2] !== "function") {
                    var failure = new Error("Could not load resource: " + args[0]);
                    args[2] = function () { report(failure); };
                }
                return original.apply(this, args);
            };
        });
    }

    async function start(program) {
        try {
            for (var library of program.libraries) {
                await script(library.code, library.name);
                if (failed) return;
            }
            if (program.language === "pde") {
                // Its DOM scanner would otherwise exit our explicitly created instance.
                Processing.disableInit();
                var canvas = document.createElement("canvas");
                canvas.id = "Sketch";
                document.body.appendChild(canvas);
                window.getProcessingSketchID = function () { return "Sketch"; };
                // Compile explicitly so parser errors cannot disappear in library auto-start.
                var compiled = Processing.compile(program.code);
                Object.keys(compiled.imageCache.images).forEach(function (path) {
                    var image = compiled.imageCache.images[path];
                    if (image && image.addEventListener) {
                        image.addEventListener("error", function () {
                            report(null, "Could not load resource: " + path);
                        });
                    }
                });
                compiled.attachFunction = new Function(
                    "return (" + compiled.sourceCode + "\n);\n//# sourceURL=processing-generated.js"
                )();
                phase = "runtime";
                instance = new Processing(canvas, compiled);
            } else {
                installP5AssetDiagnostics();
                await script(program.code, "sketch-source.js");
                if (failed) return;
                phase = "runtime";
                instance = new p5();
            }
            if (!failed) post("iosbridge", { event: "ready" });
        } catch (error) {
            report(error);
        }
    }

    // Native code can detect a blocked JavaScript thread, including infinite loops.
    window.setInterval(function () {
        if (!stopped) post("iosbridge", { event: "heartbeat" });
    }, 1000);

    function motion(callback, x, y, z) {
        if (failed || stopped || !window.Processing) return;
        var sketch = Processing.getInstanceById("Sketch");
        if (!sketch || typeof sketch[callback] !== "function") return;
        try {
            sketch[callback](x, y, z);
        } catch (error) {
            report(error);
        }
    }

    return { start: start, stop: stop, motion: motion };
}());
