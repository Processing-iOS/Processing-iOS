// Installed before either library or user code executes.
window.SketchRuntime = (function () {
    "use strict";
    var failed = false;
    var stopped = false;
    var instance = null;
    var phase = "compile";
    var projectScriptNames = Object.create(null);
    var scriptURLs = [];
    var sensorCallbacks = {
        accelerometerUpdated: 3, gyroscopeUpdated: 3, orientationUpdated: 3,
        gravityUpdated: 3, userAccelerationUpdated: 3, rotationRateUpdated: 3,
        magnetometerUpdated: 3, altimeterUpdated: 2
    };
    var sketchLanguage = "";
    var cameraViews = new Set();
    var timeouts = new Set(), intervals = new Set(), animationFrames = new Set();
    var nativeTimeout = window.setTimeout.bind(window), nativeInterval = window.setInterval.bind(window);
    var nativeClearTimeout = window.clearTimeout.bind(window), nativeClearInterval = window.clearInterval.bind(window);
    var nativeAnimationFrame = window.requestAnimationFrame.bind(window);
    var nativeCancelAnimationFrame = window.cancelAnimationFrame.bind(window);
    var disposedInstances = new WeakSet();
    var pendingImages = 0;
    var consoleRecords = [], consoleTimer = null, omittedLogs = 0;

    function printable(value, seen, depth) {
        try {
            if (typeof value === "string") return value.slice(0, 2000);
            if (value == null || typeof value !== "object") return String(value).slice(0, 2000);
            if (value instanceof Error) return value.name + ": " + value.message;
            if (seen.has(value)) return "[Circular]";
            if (depth >= 3) return "[…]";
            seen.add(value);
            var keys = Object.keys(value).slice(0, 20);
            return (Array.isArray(value) ? "[" : "{") + keys.map(function (key) {
                var descriptor = Object.getOwnPropertyDescriptor(value, key);
                var item = descriptor && "value" in descriptor ? printable(descriptor.value, seen, depth + 1) : "[Getter]";
                return (Array.isArray(value) ? "" : key + ": ") + item;
            }).join(", ").slice(0, 2000) + (Array.isArray(value) ? "]" : "}");
        } catch (_) { return "[Unreadable value]"; }
    }

    function takeConsole() {
        if (consoleTimer !== null) nativeClearTimeout(consoleTimer);
        consoleTimer = null;
        var records = consoleRecords;
        consoleRecords = [];
        if (omittedLogs) records.unshift({ level: "warn", text: omittedLogs + " earlier messages omitted (output too fast).", newline: true });
        omittedLogs = 0;
        return records;
    }

    function flushConsole() {
        var records = takeConsole();
        if (records.length) post("iosbridge", { event: "console", records: records });
    }

    function log(level, args, newline) {
        if (stopped) return;
        var text = Array.prototype.slice.call(args, 0, 20).map(function (value) {
            return printable(value, new Set(), 0);
        }).join(" ").slice(0, 2000);
        if (consoleRecords.length >= 199) { consoleRecords.shift(); omittedLogs++; }
        consoleRecords.push({ level: level, text: text, newline: newline });
        if (consoleTimer === null) consoleTimer = nativeTimeout(flushConsole, 100);
    }

    ["log", "info", "warn", "error", "debug"].forEach(function (level) {
        window.console[level] = function () { log(level, arguments, true); };
    });

    function installProcessingConsole() {
        Processing.registerLibrary("iosConsole", { attach: function (sketch) {
            sketch.print = function () { log("log", arguments, false); };
            sketch.println = function () { log("log", arguments, true); };
        } });
    }

    function saveImage(canvas, filename) {
        if (stopped) return;
        if (!canvas || typeof canvas.toDataURL !== "function") throw new Error("There is no canvas to save yet.");
        var name = String(filename || "canvas.png");
        if (!/\.[a-z0-9]+$/i.test(name)) name += ".png";
        if (!/\.(png|jpe?g)$/i.test(name) || /[\\/:]/.test(name) || name[0] === ".") {
            throw new Error("Save a PNG or JPEG filename without a folder path. Images go in the project's exports folder.");
        }
        if (canvas.width * canvas.height > 16777216 || canvas.width > 8192 || canvas.height > 8192) {
            throw new Error("The canvas is too large to export. Use at most 16 million pixels.");
        }
        if (pendingImages >= 3) throw new Error("Images are being saved faster than storage can write them. Lower frameRate() or save from a touch event.");
        var url = canvas.toDataURL(/\.png$/i.test(name) ? "image/png" : "image/jpeg", 0.95);
        var data = url.substring(url.indexOf(",") + 1);
        if (data.length > 24000000) throw new Error("The saved image is too large (maximum 18 MB). Use a smaller canvas.");
        pendingImages++;
        post("iosbridge", { event: "saveImage", name: name, data: data });
    }

    function imageSaved() { pendingImages = Math.max(0, pendingImages - 1); }

    function installP5ImageSaving() {
        p5.prototype.saveCanvas = function (canvas, filename, extension) {
            if (typeof canvas === "string" || canvas == null) {
                extension = filename; filename = canvas; canvas = this.canvas;
            } else if (canvas.elt) canvas = canvas.elt;
            filename = String(filename || "canvas");
            if (!/\.(png|jpe?g)$/i.test(filename)) filename += "." + (extension || "png");
            saveImage(canvas, filename);
        };
    }

    function trackTimer(native, collection, repeating, callback, delay, args) {
        if (stopped) return 0;
        var id = native(function () {
            if (!repeating) collection.delete(id);
            if (stopped) return;
            if (typeof callback === "function") callback.apply(window, args);
            else (0, eval)(String(callback));
        }, delay);
        collection.add(id);
        return id;
    }
    window.setTimeout = function (callback, delay) {
        return trackTimer(nativeTimeout, timeouts, false, callback, delay, Array.prototype.slice.call(arguments, 2));
    };
    window.setInterval = function (callback, delay) {
        return trackTimer(nativeInterval, intervals, true, callback, delay, Array.prototype.slice.call(arguments, 2));
    };
    window.clearTimeout = window.clearInterval = function (id) {
        timeouts.delete(id); intervals.delete(id);
        nativeClearTimeout(id); nativeClearInterval(id);
    };
    window.requestAnimationFrame = function (callback) {
        if (stopped) return 0;
        var id = nativeAnimationFrame(function (time) {
            animationFrames.delete(id);
            if (!stopped) callback(time);
        });
        animationFrames.add(id);
        return id;
    };
    window.cancelAnimationFrame = function (id) {
        animationFrames.delete(id); nativeCancelAnimationFrame(id);
    };

    function disposeInstance(sketch) {
        if (!sketch || disposedInstances.has(sketch)) return;
        disposedInstances.add(sketch);
        try {
            if (typeof sketch.noLoop === "function") sketch.noLoop();
            if (typeof sketch.remove === "function") sketch.remove();
            else if (typeof sketch.exit === "function") sketch.exit();
            if (sketch.externals && sketch.externals.canvas) sketch.externals.canvas.remove();
        } catch (_) { /* Teardown must not replace the original sketch error. */ }
    }

    function sketchCallbacks() {
        return sketchLanguage === "pde" ? instance : window;
    }

    function post(channel, body) {
        var handlers = window.webkit && window.webkit.messageHandlers;
        if (handlers && handlers[channel]) {
            handlers[channel].postMessage(body);
        }
    }

    function stop() {
        stopped = true;
        if (consoleTimer !== null) nativeClearTimeout(consoleTimer);
        consoleTimer = null;
        cameraViews.forEach(function (camera) { camera.dispose(); });
        cameraViews.clear();
        try {
            var audio = typeof window.getAudioContext === "function" ? window.getAudioContext() : null;
            disposeInstance(instance);
            if (window.p5) disposeInstance(window.p5.instance);
            if (window.Processing) {
                var sketch = window.Processing.getInstanceById("Sketch");
                disposeInstance(sketch);
            }
            document.querySelectorAll("audio,video").forEach(function (media) {
                media.pause();
                if (media.srcObject && media.srcObject.getTracks) media.srcObject.getTracks().forEach(function (track) { track.stop(); });
                media.srcObject = null;
            });
            if (audio && audio.state !== "closed") audio.close().catch(function () {});
        } catch (_) { /* Preserve the original failure if teardown also fails. */ }
        timeouts.forEach(nativeClearTimeout); timeouts.clear();
        intervals.forEach(nativeClearInterval); intervals.clear();
        animationFrames.forEach(nativeCancelAnimationFrame); animationFrames.clear();
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
        // Map the first project frame, including a project library's own code.
        // Built-in runtime frames fall through to their caller in the sketch.
        var frames = stack.split("\n"), located = false;
        for (var frame of frames) {
            for (var scriptURL of Object.keys(projectScriptNames)) {
                var escapedURL = scriptURL.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
                var match = frame.match(new RegExp(escapedURL + ":(\\d+):(\\d+)"));
                if (match) {
                    url = scriptURL;
                    line = Number(match[1]);
                    column = Number(match[2]);
                    located = true;
                    break;
                }
            }
            if (located) break;
        }
        if (projectScriptNames[url]) url = projectScriptNames[url];
        flushConsole();
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
            if (name === "sketch-source.js" || name.indexOf("libraries/") === 0) projectScriptNames[url] = name;
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

    // Capture and permission handling belong to the runtime, not every sketch.
    // Each constructor is bound to its sketch's canvas, including during setup().
    function cameraViewConstructor(contextForDrawing) {
        return function CameraView(facing, x, y, width, height) {
            if (!(this instanceof CameraView)) return new CameraView(facing, x, y, width, height);
            var view = this;
            var video = document.createElement("video");
            var stream = null, request = 0, wanted = false;
            var state = "stopped", message = "Camera is stopped.";
            var direction = facing === undefined ? "back" : facing;
            validateFacing(direction);
            view.x = x === undefined ? 0 : x;
            view.y = y === undefined ? 0 : y;
            view.width = width === undefined ? 320 : width;
            view.height = height === undefined ? 240 : height;
            validateBounds();
            video.muted = true;
            video.playsInline = true;
            video.style.display = "none";
            document.body.appendChild(video);
            var statusLabel = document.createElement("span");
            statusLabel.setAttribute("role", "status");
            statusLabel.setAttribute("aria-live", "polite");
            statusLabel.style.cssText = "position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)";
            document.body.appendChild(statusLabel);
            Object.defineProperties(view, {
                status: { get: function () { return state; } },
                message: { get: function () { return message; } },
                facing: { get: function () { return direction; } }
            });

            function validateFacing(value) {
                if (value !== "front" && value !== "back") throw new Error('CameraView facing must be "front" or "back".');
            }
            function validateBounds() {
                if (![view.x, view.y, view.width, view.height].every(Number.isFinite) || view.width < 0 || view.height < 0) {
                    throw new Error("CameraView needs finite coordinates and non-negative width and height.");
                }
            }
            function status(value, detail) {
                state = value;
                message = detail;
                statusLabel.textContent = detail;
            }
            function release(value, detail) {
                ++request;
                var previous = stream;
                stream = null;
                if (previous) previous.getTracks().forEach(function (track) { track.stop(); });
                video.pause();
                video.srcObject = null;
                status(value, detail);
            }
            async function open() {
                if (stopped || failed || !wanted || stream || state === "waiting") return;
                if (document.hidden) { status("paused", "Camera is paused."); return; }
                if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                    status("unavailable", "Camera capture is unavailable on this device.");
                    return;
                }
                var current = ++request;
                status("waiting", "Waiting for camera access…");
                try {
                    var acquired = await navigator.mediaDevices.getUserMedia({ audio: false, video: {
                        facingMode: { ideal: direction === "front" ? "user" : "environment" },
                        width: { ideal: 1280 }, height: { ideal: 720 }
                    } });
                    if (current !== request || stopped || failed || document.hidden) {
                        acquired.getTracks().forEach(function (track) { track.stop(); });
                        if (current === request) release("paused", "Camera is paused.");
                        return;
                    }
                    stream = acquired;
                    video.srcObject = acquired;
                    acquired.getVideoTracks().forEach(function (track) {
                        track.addEventListener("ended", function () {
                            if (stream === acquired) release(document.hidden ? "paused" : "error", "Camera was interrupted. Run the sketch again to retry.");
                        });
                    });
                    await video.play();
                    if (current === request) status("active", direction === "front" ? "Front camera is live." : "Back camera is live.");
                } catch (error) {
                    if (current !== request) return;
                    var value = "error", detail = "Camera could not start. Run the sketch again to retry.";
                    if (error.name === "NotAllowedError") {
                        value = "denied"; detail = "Camera access denied. Allow camera access in iOS Settings, then run the sketch again.";
                    } else if (error.name === "NotFoundError") {
                        value = "unavailable"; detail = "No camera is available on this device.";
                    } else if (error.name === "NotReadableError") {
                        detail = "Camera is busy. Run the sketch again to retry.";
                    }
                    release(value, detail);
                }
            }
            view.start = function () { wanted = true; open(); };
            view.stop = function () { wanted = false; release("stopped", "Camera is stopped."); };
            view.setFacing = function (value) {
                validateFacing(value);
                if (value === direction) return;
                direction = value;
                release("stopped", "Camera is stopped.");
                if (wanted) open();
            };
            view.draw = function (x, y, width, height) {
                if (arguments.length) {
                    view.x = x; view.y = y; view.width = width; view.height = height;
                }
                validateBounds();
                if (view.width === 0 || view.height === 0) return;
                var context = contextForDrawing();
                if (!context || typeof context.drawImage !== "function") throw new Error("CameraView.draw() requires a 2D sketch canvas.");
                context.save();
                try {
                    context.beginPath();
                    context.rect(view.x, view.y, view.width, view.height);
                    context.clip();
                    if (stream && video.readyState >= 2 && video.videoWidth > 0) {
                        // Aspect-fill without stretching; preserve the canvas's Retina transform.
                        var scale = Math.max(view.width / video.videoWidth, view.height / video.videoHeight);
                        var w = video.videoWidth * scale, h = video.videoHeight * scale;
                        context.drawImage(video, view.x + (view.width - w) / 2, view.y + (view.height - h) / 2, w, h);
                    } else {
                        context.fillStyle = "#1e2836";
                        context.fillRect(view.x, view.y, view.width, view.height);
                        context.fillStyle = "#d7e1eb";
                        context.font = "14px system-ui";
                        context.textAlign = "left";
                        context.textBaseline = "top";
                        var line = "", row = 0;
                        message.split(" ").forEach(function (word) {
                            var next = line ? line + " " + word : word;
                            if (line && context.measureText(next).width > view.width - 24) {
                                context.fillText(line, view.x + 12, view.y + 12 + row++ * 19);
                                line = word;
                            } else line = next;
                        });
                        context.fillText(line, view.x + 12, view.y + 12 + row * 19);
                    }
                } finally { context.restore(); }
            };
            cameraViews.add({
                pause: function () {
                    // Native capture shutdown can deliver track.ended before
                    // this background notification reaches JavaScript.
                    if (wanted && ["waiting", "active", "error"].indexOf(state) !== -1) release("paused", "Camera is paused.");
                },
                resume: function () { if (wanted && state === "paused") open(); },
                dispose: function () { view.stop(); video.remove(); statusLabel.remove(); }
            });
            view.start();
        };
    }

    function pauseCameras() { cameraViews.forEach(function (camera) { camera.pause(); }); }
    function resumeCameras() { cameraViews.forEach(function (camera) { camera.resume(); }); }
    document.addEventListener("visibilitychange", function () { document.hidden ? pauseCameras() : resumeCameras(); });
    window.addEventListener("pagehide", pauseCameras);
    window.addEventListener("pageshow", resumeCameras);

    function installCameraViews() {
        window.CameraView = cameraViewConstructor(function () { return window.drawingContext; });
        if (sketchLanguage === "pde") {
            // The parser uses the default scope to recognize built-in types.
            Processing.prototype.CameraView = window.CameraView;
            Processing.registerLibrary("cameraView", { attach: function (sketch) {
                sketch.CameraView = cameraViewConstructor(function () {
                    // Flush Processing's deferred pixel writes/matrix changes first.
                    sketch.pushMatrix(); sketch.popMatrix();
                    return sketch.externals.canvas.getContext("2d");
                });
            } });
        }
    }

    function installProcessingRetina() {
        var density = Math.max(1, Math.ceil(window.devicePixelRatio || 1));
        if (!Number.isFinite(density)) density = 1;
        var canvases = new WeakSet();

        function prepareCanvas(canvas) {
            if (density === 1 || canvases.has(canvas)) return;
            canvases.add(canvas);
            var context = null;
            var reset = function () {};
            var getContext = canvas.getContext.bind(canvas);
            // Processing.js predates pixelDensity(). Keep its canvas dimensions,
            // camera and input in logical pixels; only the backing store grows.
            ["width", "height"].forEach(function (name) {
                var property = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, name);
                var logical = property.get.call(canvas);
                Object.defineProperty(canvas, name, {
                    get: function () { return logical; },
                    set: function (value) {
                        logical = Math.max(0, Math.floor(Number(value) || 0));
                        property.set.call(canvas, logical * density);
                        canvas.style[name] = logical + "px";
                        reset();
                    }
                });
                canvas[name] = logical;
            });
            // The legacy touch initializer replaces the entire style attribute.
            // Without restoring these dimensions, the first touch enlarges the
            // canvas to its physical pixel size and breaks drawing alignment.
            var setAttribute = canvas.setAttribute.bind(canvas);
            canvas.setAttribute = function (name, value) {
                setAttribute(name, value);
                if (String(name).toLowerCase() === "style") {
                    canvas.style.width = canvas.width + "px";
                    canvas.style.height = canvas.height + "px";
                }
            };

            canvas.getContext = function (kind) {
                var result = getContext.apply(null, arguments);
                if (!result || context) return result;
                context = result;
                if (kind === "2d") {
                    var setTransform = context.setTransform.bind(context);
                    var drawImage = context.drawImage.bind(context);
                    var scratch = document.createElement("canvas");
                    var scratchContext = scratch.getContext("2d");
                    reset = function () { setTransform(density, 0, 0, density, 0, 0); };
                    context.setTransform = function (a, b, c, d, e, f) {
                        setTransform(a * density, b * density, c * density, d * density, e * density, f * density);
                    };
                    context.resetTransform = reset;
                    context.drawImage = function (source) {
                        var args = Array.prototype.slice.call(arguments);
                        if (canvases.has(source)) {
                            if (args.length === 3) args.push(source.width, source.height);
                            else if (args.length === 9) {
                                for (var i = 1; i <= 4; i++) args[i] *= density;
                            }
                        }
                        drawImage.apply(null, args);
                    };
                    // Preserve the legacy width*height pixels[] API. Pixel reads
                    // sample the logical image; writes expand each logical pixel.
                    // Other drawing still takes place at full Retina resolution.
                    context.getImageData = function (x, y, width, height) {
                        if (width < 0) { x += width; width = -width; }
                        if (height < 0) { y += height; height = -height; }
                        scratch.width = width;
                        scratch.height = height;
                        scratchContext.drawImage(canvas, x * density, y * density, width * density, height * density,
                            0, 0, width, height);
                        return scratchContext.getImageData(0, 0, width, height);
                    };
                    context.putImageData = function (data, x, y) {
                        // Processing only uses the three-argument form, including
                        // set(), updatePixels(), copy() and filters.
                        scratch.width = data.width;
                        scratch.height = data.height;
                        scratchContext.putImageData(data, 0, 0);
                        context.save();
                        reset();
                        context.globalAlpha = 1;
                        context.globalCompositeOperation = "source-over";
                        context.imageSmoothingEnabled = false;
                        context.clearRect(x, y, data.width, data.height);
                        drawImage(scratch, x, y);
                        context.restore();
                    };
                } else {
                    var viewport = context.viewport.bind(context);
                    var readPixels = context.readPixels.bind(context);
                    var lineWidth = context.lineWidth.bind(context);
                    var uniformLocation = context.getUniformLocation.bind(context);
                    var uniform1f = context.uniform1f.bind(context);
                    var pointSizes = new WeakSet();
                    reset = function () { viewport(0, 0, canvas.width * density, canvas.height * density); };
                    context.viewport = function (x, y, width, height) {
                        viewport(x * density, y * density, width * density, height * density);
                    };
                    context.lineWidth = function (width) { lineWidth(width * density); };
                    context.getUniformLocation = function (program, name) {
                        var location = uniformLocation(program, name);
                        if (location && name === "uPointSize") pointSizes.add(location);
                        return location;
                    };
                    context.uniform1f = function (location, value) {
                        uniform1f(location, pointSizes.has(location) ? value * density : value);
                    };
                    context.readPixels = function (x, y, width, height, format, type, pixels) {
                        if (format !== context.RGBA || type !== context.UNSIGNED_BYTE || width <= 0 || height <= 0) {
                            return readPixels.apply(null, arguments);
                        }
                        var physicalWidth = width * density;
                        var physical = new Uint8Array(physicalWidth * height * density * 4);
                        readPixels(x * density, y * density, physicalWidth, height * density, format, type, physical);
                        var center = Math.floor(density / 2);
                        for (var row = 0; row < height; row++) {
                            for (var col = 0; col < width; col++) {
                                var offset = ((row * density + center) * physicalWidth + col * density + center) * 4;
                                pixels.set(physical.subarray(offset, offset + 4), (row * width + col) * 4);
                            }
                        }
                    };
                }
                reset();
                return result;
            };
        }

        function attach(sketch) {
            prepareCanvas(sketch.externals.canvas);
            sketch.createGraphics = function (width, height, renderer) {
                // Match Processing's offscreen constructor, preparing its canvas
                // before size() creates a context or initializes WebGL shaders.
                var graphics = new Processing();
                attach(graphics);
                graphics.size(width, height, renderer);
                graphics.background(0, 0);
                // Let image() draw the full-resolution surface directly.
                Object.defineProperty(graphics, "sourceImg", { get: function () {
                    // set() buffers pixel edits until the next context operation.
                    // Flush through the public matrix API before reading the canvas.
                    graphics.pushMatrix();
                    graphics.popMatrix();
                    return graphics.externals.canvas;
                } });
                return graphics;
            };
        }
        Processing.registerLibrary("retina", { attach: attach });
    }

    async function start(program) {
        try {
            sketchLanguage = program.language;
            // WebKit successfully reads file URLs with status 0. p5's data
            // loaders require Response.ok, so normalize only successful local
            // fetches; missing files still reject and HTTP errors stay intact.
            var nativeFetch = window.fetch;
            window.fetch = function (input, options) {
                var url = new URL(typeof input === "string" || input instanceof URL ? input : input.url, document.baseURI);
                return nativeFetch.call(window, input, options).then(function (response) {
                    if (url.protocol === "file:" && response.status === 0) {
                        return new Response(response.body, { status: 200, headers: response.headers });
                    }
                    return response;
                });
            };
            for (var library of program.libraries) {
                await script(library.code, library.name);
                if (failed || stopped) return;
            }
            installCameraViews();
            if (program.language === "pde") {
                // Its DOM scanner would otherwise exit our explicitly created instance.
                Processing.disableInit();
                installProcessingRetina();
                installProcessingConsole();
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
                await new Promise(function (resolve) {
                    var onLoad = compiled.onLoad;
                    compiled.onLoad = function (sketch) {
                        onLoad.call(this, sketch);
                        // Attachment and setup finish synchronously after onLoad,
                        // including sketches that wait for preloaded images.
                        Promise.resolve().then(resolve);
                    };
                    instance = new Processing(canvas, compiled);
                });
            } else {
                installP5AssetDiagnostics();
                installP5ImageSaving();
                await script(program.code, "sketch-source.js");
                if (failed || stopped) return;
                phase = "runtime";
                await new Promise(function (resolve) {
                    var setup = window.setup;
                    window.setup = function () {
                        try { if (typeof setup === "function") setup.apply(this, arguments); }
                        catch (error) { report(error); }
                        finally { resolve(); }
                    };
                    instance = new p5();
                });
            }
            if (failed || stopped) {
                disposeInstance(instance);
            } else {
                var callbacks = sketchCallbacks();
                post("iosbridge", { event: "ready", sensors: Object.keys(sensorCallbacks).filter(function (name) {
                    return callbacks && typeof callbacks[name] === "function";
                }) });
            }
        } catch (error) {
            report(error);
        }
    }

    // Native code can detect a blocked JavaScript thread, including infinite loops.
    window.setInterval(function () {
        if (!stopped) post("iosbridge", { event: "heartbeat" });
    }, 1000);

    function motion(callback, x, y, z) {
        var readings = {};
        readings[callback] = [x, y, z];
        updateSensors({ readings: readings });
    }

    function updateSensors(packet) {
        if (failed || stopped || !packet || typeof packet !== "object") return;
        var sketch = sketchCallbacks();
        if (!sketch) return;
        try {
            var statuses = packet.statuses || {};
            var readings = packet.readings || {};
            Object.keys(sensorCallbacks).forEach(function (callback) {
                if (failed || stopped) return;
                var status = statuses[callback];
                if (["waiting", "active", "unavailable", "denied", "error"].indexOf(status) !== -1 &&
                    typeof sketch.sensorStatusUpdated === "function") sketch.sensorStatusUpdated(callback, status);
                var values = readings[callback];
                if (Array.isArray(values) && values.length === sensorCallbacks[callback] &&
                    values.every(Number.isFinite) && typeof sketch[callback] === "function") {
                    sketch[callback].apply(sketch, values);
                }
            });
        } catch (error) {
            report(error);
        }
    }

    return { start: start, stop: stop, motion: motion, updateSensors: updateSensors,
        pauseCameras: pauseCameras, resumeCameras: resumeCameras,
        saveImage: saveImage, imageSaved: imageSaved, takeConsole: takeConsole };
}());
