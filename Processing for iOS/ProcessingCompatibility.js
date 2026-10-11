// Compatibility additions for the bundled Processing.js 1.6.6 runtime.
(function () {
    "use strict";
    function StringList(values) {
        this.items = Array.isArray(values) ? values.slice() : [];
    }
    function index(list, i) {
        if (!Number.isInteger(i) || i < 0 || i >= list.items.length) throw new RangeError("StringList index " + i + " is outside the list.");
    }
    StringList.prototype.size = function () { return this.items.length; };
    StringList.prototype.clear = function () { this.items.length = 0; };
    StringList.prototype.get = function (i) { index(this, i); return this.items[i]; };
    StringList.prototype.set = function (i, value) {
        if (!Number.isInteger(i) || i < 0) throw new RangeError("StringList index must be nonnegative.");
        while (this.items.length <= i) this.items.push(null);
        this.items[i] = value == null ? null : String(value);
    };
    StringList.prototype.append = function (value) {
        if (value instanceof StringList) value = value.items;
        if (Array.isArray(value)) this.items.push.apply(this.items, value);
        else this.items.push(value == null ? null : String(value));
    };
    StringList.prototype.remove = function (i) { index(this, i); return this.items.splice(i, 1)[0]; };
    StringList.prototype.hasValue = function (value) { return this.items.indexOf(value) !== -1; };
    StringList.prototype.sort = function () {
        this.items.sort(function (a, b) {
            if (a == null) return b == null ? 0 : 1;
            if (b == null) return -1;
            a = a.toLowerCase(); b = b.toLowerCase();
            return a < b ? -1 : a > b ? 1 : 0;
        });
    };
    StringList.prototype.sortReverse = function () { this.sort(); this.reverse(); };
    StringList.prototype.reverse = function () { this.items.reverse(); };
    StringList.prototype.shuffle = function () {
        for (var i = this.items.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var value = this.items[i]; this.items[i] = this.items[j]; this.items[j] = value;
        }
    };
    StringList.prototype.lower = function () { this.items = this.items.map(function (s) { return s == null ? null : s.toLowerCase(); }); };
    StringList.prototype.upper = function () { this.items = this.items.map(function (s) { return s == null ? null : s.toUpperCase(); }); };
    StringList.prototype.array = StringList.prototype.toArray = function () { return this.items.slice(); };
    StringList.prototype.copy = function () { return new StringList(this.items); };
    StringList.prototype.join = function (separator) { return this.items.join(separator); };
    StringList.prototype.toString = function () { return "[" + this.items.join(", ") + "]"; };
    StringList.prototype.iterator = function () {
        var list = this, i = 0;
        return { hasNext: function () { return i < list.items.length; },
            next: function () { return list.get(i++); } };
    };

    Processing.prototype.StringList = StringList;
    Processing.registerLibrary("iosCompatibility", {
        exports: ["StringList", "circle", "square", "displayWidth", "displayHeight", "fullScreen"],
        attach: function (sketch) {
            sketch.StringList = StringList;
            sketch.circle = function (x, y, extent) { sketch.ellipse(x, y, extent, extent); };
            sketch.square = function (x, y, extent) { sketch.rect(x, y, extent, extent); };
            Object.defineProperty(sketch, "displayWidth", { get: function () { return window.innerWidth; } });
            Object.defineProperty(sketch, "displayHeight", { get: function () { return window.innerHeight; } });
            sketch.fullScreen = function (renderer) { sketch.size(window.innerWidth, window.innerHeight, renderer || sketch.P2D); };
            sketch.saveFrame = function (filename) {
                var name = String(filename || "screen-####.png").replace(/#+/g, function (hashes) {
                    return String(sketch.frameCount).padStart(hashes.length, "0");
                });
                // Flush deferred Processing pixel writes before reading the canvas.
                sketch.pushMatrix(); sketch.popMatrix();
                window.SketchRuntime.saveImage(sketch.externals.canvas, name);
            };
        }
    });
}());
