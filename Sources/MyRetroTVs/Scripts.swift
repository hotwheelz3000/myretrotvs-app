/// JavaScript injected into the MyRetroTVs pages.
enum Scripts {
    /// Lets the app press the site's keyboard shortcuts (the site is driven by the
    /// keyboard: Space = power, arrows = channel, -/+ = volume, H = menu...).
    ///
    /// Runs at document start, before the site's own scripts, and notes which key
    /// events the page listens for (keydown, keyup or keypress) so the app sends the
    /// kind the site actually handles. `window.__retroKey('ArrowUp')` presses a key.
    static let keyBridge = #"""
        (function () {
          if (window.__retroKey) return;
          var seen = { keydown: 0, keyup: 0, keypress: 0 };
          var originalAdd = EventTarget.prototype.addEventListener;
          EventTarget.prototype.addEventListener = function (type, listener, options) {
            if (Object.prototype.hasOwnProperty.call(seen, type)) seen[type]++;
            return originalAdd.call(this, type, listener, options);
          };
          var NAMED = {
            ' ': ['Space', 32],
            ArrowUp: ['ArrowUp', 38],
            ArrowDown: ['ArrowDown', 40],
            ArrowLeft: ['ArrowLeft', 37],
            ArrowRight: ['ArrowRight', 39],
            '+': ['Equal', 187],
            '-': ['Minus', 189],
            Escape: ['Escape', 27]
          };
          function describe(key) {
            if (NAMED[key]) return { key: key, code: NAMED[key][0], keyCode: NAMED[key][1] };
            if (/^[0-9]$/.test(key)) return { key: key, code: 'Digit' + key, keyCode: 48 + Number(key) };
            var upper = key.toUpperCase();
            return { key: key, code: 'Key' + upper, keyCode: upper.charCodeAt(0) };
          }
          function fire(type, d) {
            var legacy = type === 'keypress' ? d.key.charCodeAt(0) : d.keyCode;
            var event = new KeyboardEvent(type, {
              key: d.key,
              code: d.code,
              keyCode: legacy,
              which: legacy,
              charCode: type === 'keypress' ? legacy : 0,
              shiftKey: d.key === '+',
              bubbles: true,
              cancelable: true,
              view: window
            });
            if (event.keyCode !== legacy) {
              try {
                Object.defineProperty(event, 'keyCode', { get: function () { return legacy; } });
                Object.defineProperty(event, 'which', { get: function () { return legacy; } });
              } catch (e) {}
            }
            var target = document.body || document.documentElement || document;
            target.dispatchEvent(event);
          }
          function hasInline(name) {
            return typeof document[name] === 'function' || typeof window[name] === 'function' ||
              (document.body && typeof document.body[name] === 'function');
          }
          window.__retroKey = function (key) {
            var d = describe(key);
            var down = seen.keydown > 0 || hasInline('onkeydown');
            var press = seen.keypress > 0 || hasInline('onkeypress');
            var up = seen.keyup > 0 || hasInline('onkeyup');
            if (down || (!press && !up)) fire('keydown', d);
            if (press && !down && d.key.length === 1) fire('keypress', d);
            fire('keyup', d);
            return true;
          };
        })();
        """#

    /// Makes the page behave like part of an app: no tap flashes, no long-press
    /// menus on the TV, no pinch zoom, no rubber-band bounce.
    static let appPolish = #"""
        (function () {
          var style = document.createElement('style');
          style.textContent = [
            'html, body { -webkit-tap-highlight-color: transparent !important; overscroll-behavior: none; }',
            'body, img, a, button { -webkit-touch-callout: none; -webkit-user-select: none; user-select: none; }',
            'input, textarea, select { -webkit-user-select: text; user-select: text; }'
          ].join('\n');
          (document.head || document.documentElement).appendChild(style);
          var metas = document.querySelectorAll('meta[name="viewport"]');
          var content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
          if (metas.length) {
            metas.forEach(function (meta) { meta.setAttribute('content', content); });
          } else {
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = content;
            (document.head || document.documentElement).appendChild(meta);
          }
        })();
        """#
}
