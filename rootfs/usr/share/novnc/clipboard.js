// Browser clipboard <-> VNC clipboard, so Ctrl+C / Ctrl+V just work.
// The Clipboard API exists only in secure contexts (HTTPS, localhost);
// elsewhere noVNC's clipboard panel is the only way.
import UI from "./app/ui.js";

const clip = window.isSecureContext && navigator.clipboard;

if (clip) {
    // UI.rfb is replaced on every (re)connect
    let rfb = null;
    setInterval(() => {
        if (UI.rfb === rfb) return;
        rfb = UI.rfb;
        if (!rfb) return;
        // VNC -> browser: whatever was copied in WinBox
        rfb.addEventListener("clipboard", (e) => {
            clip.writeText(e.detail.text).catch(() => {});
        });
    }, 500);

    // browser -> VNC
    const pushLocal = async () => {
        const text = await clip.readText();
        if (rfb && text) rfb.clipboardPasteFrom(text);
    };

    // Once reading is allowed (Chromium asks once), sync when coming back to the
    // tab, so pasting from WinBox's own menus gets the fresh text too
    window.addEventListener("focus", async () => {
        try {
            const perm = await navigator.permissions.query({ name: "clipboard-read" });
            if (perm.state === "granted") await pushLocal();
        } catch {
            // no such permission (Firefox): the paste keys below still work
        }
    });

    // Modifiers as they are now, the paste key below goes out later
    const held = { ctrl: false, shift: false };
    const track = (e) => {
        held.ctrl = e.ctrlKey;
        held.shift = e.shiftKey;
    };
    window.addEventListener("keydown", track, true);
    window.addEventListener("keyup", track, true);

    // Press the modifiers the paste needs but the user already let go of
    const sendWith = (mods, keysym, code) => {
        const missing = [];
        if (mods.ctrl && !held.ctrl) missing.push([0xffe3, "ControlLeft"]);
        if (mods.shift && !held.shift) missing.push([0xffe1, "ShiftLeft"]);
        for (const [sym, c] of missing) rfb.sendKey(sym, c, true);
        rfb.sendKey(keysym, code);
        for (const [sym, c] of missing.reverse()) rfb.sendKey(sym, c, false);
    };

    // Ctrl+V, Ctrl+Shift+V, Shift+Insert: hold the key back until the browser
    // clipboard is on the server, then send it
    let swallowUp = null;
    window.addEventListener("keydown", (e) => {
        const paste = (e.ctrlKey && !e.altKey && e.code === "KeyV") ||
                      (e.shiftKey && !e.ctrlKey && e.code === "Insert");
        if (!paste || !rfb || ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        // On Windows noVNC holds ControlLeft back for up to 100 ms (AltGr
        // detection) and releases it on the next key, which it won't see here
        rfb._keyboard?._interruptAltGrSequence?.();
        swallowUp = e.code;
        const mods = { ctrl: e.ctrlKey, shift: e.shiftKey };
        const keysym = e.code === "Insert" ? 0xff63 : (e.shiftKey ? 0x56 : 0x76);
        const code = e.code;
        pushLocal().catch(() => {}).finally(() => sendWith(mods, keysym, code));
    }, true);
    window.addEventListener("keyup", (e) => {
        if (e.code !== swallowUp) return;
        swallowUp = null;
        e.preventDefault();
        e.stopImmediatePropagation();
    }, true);
}
