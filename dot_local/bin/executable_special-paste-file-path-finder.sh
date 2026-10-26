#!/bin/sh

# @raycast.schemaVersion 1
# @raycast.title Paste File Path as Text
# @raycast.mode silent
# @raycast.packageName File Paths
# @raycast.icon 📋
# @raycast.description Paste the absolute paths of normally copied Finder files or folders as text.

# macOS supplies osascript and the native clipboard/keyboard APIs used below.
# --print checks the copied paths without changing the clipboard or pasting.
exec /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('AppKit');
ObjC.import('ApplicationServices');

function run(args) {
    const clipboard = $.NSPasteboard.generalPasteboard;
    const options = $.NSDictionary.dictionaryWithObjectForKey(
        $(true), $.NSPasteboardURLReadingFileURLsOnlyKey
    );
    const urls = clipboard.readObjectsForClassesOptions($([$.NSURL]), options);
    if (!urls || !Number(urls.count)) {
        throw new Error('Copy a file or folder in Finder first (Command+C).');
    }

    const paths = [];
    for (let i = 0; i < urls.count; i++) {
        paths.push(ObjC.unwrap(urls.objectAtIndex(i).path));
    }
    const text = paths.join('\n');
    if (args.indexOf('--print') !== -1) return text;
    if (!$.AXIsProcessTrusted()) {
        throw new Error('Allow Raycast in System Settings > Privacy & Security > Accessibility.');
    }

    // Preserve the copied file references, so a later normal paste still works.
    const saved = [];
    const items = clipboard.pasteboardItems;
    for (let i = 0; i < items.count; i++) {
        const original = items.objectAtIndex(i);
        const copy = $.NSPasteboardItem.alloc.init;
        const types = original.types;
        for (let j = 0; j < types.count; j++) {
            const type = types.objectAtIndex(j);
            copy.setDataForType(original.dataForType(type), type);
        }
        saved.push(copy);
    }

    const down = $.CGEventCreateKeyboardEvent(null, 9, true);
    const up = $.CGEventCreateKeyboardEvent(null, 9, false);
    $.CGEventSetFlags(down, 1 << 20); // Command+V
    $.CGEventSetFlags(up, 1 << 20);
    clipboard.clearContents;
    clipboard.setStringForType($(text), $.NSPasteboardTypeString);
    const pasteChange = Number(clipboard.changeCount);
    try {
        $.CGEventPost($.kCGHIDEventTap, down);
        $.CGEventPost($.kCGHIDEventTap, up);
        $.NSThread.sleepForTimeInterval(0.5);
    } finally {
        // Leave a newer clipboard copy alone if the user copied during the paste.
        if (Number(clipboard.changeCount) === pasteChange) {
            clipboard.clearContents;
            clipboard.writeObjects($(saved));
        }
    }
}
JXA
