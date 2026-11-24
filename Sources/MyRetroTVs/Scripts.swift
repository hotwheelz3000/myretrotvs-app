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

    /// The app's own full screen: stretches the YouTube player to fill the whole page,
    /// without relying on the site's F key. `window.__retroFull(true/false)`.
    /// Ancestors of the player lose any transform/filter while it's on, since those
    /// would trap a fixed-position element inside the TV graphic.
    static let fullScreen = #"""
        (function () {
          if (window.__retroFull) return;
          var on = false;
          var style = document.createElement('style');
          style.textContent = [
            'html.retro-full, html.retro-full body { background: #000 !important; overflow: hidden !important; }',
            '[data-retro-anc] { transform: none !important; filter: none !important; perspective: none !important;',
            '  contain: none !important; will-change: auto !important; }',
            '[data-retro-player] { position: fixed !important; inset: 0 !important; width: 100vw !important;',
            '  height: 100vh !important; max-width: none !important; max-height: none !important;',
            '  margin: 0 !important; z-index: 2147483647 !important; background: #000 !important; }'
          ].join('\n');
          function player() {
            var frames = document.querySelectorAll('iframe');
            var best = null, bestArea = 0;
            for (var i = 0; i < frames.length; i++) {
              var f = frames[i];
              var src = f.src || '';
              var r = f.getBoundingClientRect();
              var area = r.width * r.height;
              if (/youtube|youtu\.be/.test(src)) area += 1e9;
              if (area > bestArea) { best = f; bestArea = area; }
            }
            return best || document.querySelector('video');
          }
          function clear() {
            document.querySelectorAll('[data-retro-anc]').forEach(function (el) { el.removeAttribute('data-retro-anc'); });
            document.querySelectorAll('[data-retro-player]').forEach(function (el) { el.removeAttribute('data-retro-player'); });
          }
          function apply() {
            if (!on) return;
            var p = player();
            if (!p) return;
            if (!p.hasAttribute('data-retro-player')) {
              clear();
              p.setAttribute('data-retro-player', '');
              for (var el = p.parentElement; el && el !== document.documentElement; el = el.parentElement) {
                el.setAttribute('data-retro-anc', '');
              }
            }
          }
          var pending = false;
          new MutationObserver(function () {
            if (!on || pending) return;
            pending = true;
            setTimeout(function () { pending = false; apply(); }, 150);
          }).observe(document.documentElement, { childList: true, subtree: true });
          window.__retroFull = function (value) {
            if (!style.parentNode) (document.head || document.documentElement).appendChild(style);
            on = !!value;
            document.documentElement.classList.toggle('retro-full', on);
            if (on) apply(); else clear();
            return on;
          };
        })();
        """#
}
