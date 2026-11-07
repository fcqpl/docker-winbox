// Browser clipboard <-> VNC clipboard, so Ctrl+C / Ctrl+V just work.
import UI from "./app/ui.js";

// UI.rfb is replaced on every (re)connect
let rfb = null;
setInterval(() => {
    if (UI.rfb === rfb) return;
    rfb = UI.rfb;
    // VNC -> browser: whatever was copied in WinBox. The Clipboard API is
    // there on secure pages only (HTTPS, localhost)
    if (rfb && window.isSecureContext && navigator.clipboard) {
        rfb.addEventListener("clipboard", (e) => {
            navigator.clipboard.writeText(e.detail.text).catch(() => {});
        });
    }
}, 500);

// Browser -> VNC: on a paste key the focus jumps to a hidden textarea, the
// browser pastes into it (no clipboard permission needed), the text goes to
// the VNC clipboard and only then the key goes on to WinBox
const sink = document.createElement("textarea");
sink.setAttribute("aria-hidden", "true");
sink.tabIndex = -1;
sink.style.cssText = "position:fixed;top:0;left:-100px;width:1px;height:1px;opacity:0";
document.body.appendChild(sink);

// Modifiers as they are now, the paste key goes out a moment later
const held = { ctrl: false, shift: false };
const track = (e) => {
    held.ctrl = e.ctrlKey;
    held.shift = e.shiftKey;
};
window.addEventListener("keydown", track, true);
window.addEventListener("keyup", track, true);

let pending = null;
let swallowUp = null;

const finish = () => {
    if (!pending) return;
    const { mods, keysym, code } = pending;
    pending = null;
    rfb.focus({ preventScroll: true });
    // Press the modifiers the paste needs but the user already let go of
    const missing = [];
    if (mods.ctrl && !held.ctrl) missing.push([0xffe3, "ControlLeft"]);
    if (mods.shift && !held.shift) missing.push([0xffe1, "ShiftLeft"]);
    for (const [sym, c] of missing) rfb.sendKey(sym, c, true);
    rfb.sendKey(keysym, code);
    for (const [sym, c] of missing.reverse()) rfb.sendKey(sym, c, false);
};

// Ctrl+V, Ctrl+Shift+V, Shift+Insert
window.addEventListener("keydown", (e) => {
    const paste = (e.ctrlKey && !e.altKey && e.code === "KeyV") ||
                  (e.shiftKey && !e.ctrlKey && e.code === "Insert");
    if (!paste || !rfb || pending || ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return;
    // Keep noVNC away from it, but not the browser: its paste is what we want
    e.stopImmediatePropagation();
    // On Windows noVNC holds ControlLeft back for up to 100 ms (AltGr
    // detection) and releases it on the next key, which it won't see here
    rfb._keyboard?._interruptAltGrSequence?.();
    swallowUp = e.code;
    pending = {
        mods: { ctrl: e.ctrlKey, shift: e.shiftKey },
        keysym: e.code === "Insert" ? 0xff63 : (e.shiftKey ? 0x56 : 0x76),
        code: e.code,
    };
    sink.value = "";
    sink.focus({ preventScroll: true });
    // No paste event (empty or non-text clipboard): send the key anyway
    setTimeout(finish, 50);
}, true);

sink.addEventListener("paste", (e) => {
    e.preventDefault();
    const text = e.clipboardData && e.clipboardData.getData("text/plain");
    if (text && rfb) rfb.clipboardPasteFrom(text);
    finish();
});

window.addEventListener("keyup", (e) => {
    if (e.code !== swallowUp) return;
    swallowUp = null;
    e.preventDefault();
    e.stopImmediatePropagation();
}, true);
