---
title: The Shortcuts and Menus Every Mac User Knows
impact: HIGH
impactDescription: An invented shortcut is one the user has to learn; a missing menu item is one they cannot find
tags: [native, macos, keyboard, shortcuts, menus]
paths: ["Sources/PaperDrop/**/*.swift"]
---

## The Shortcuts and Menus Every Mac User Knows

**Impact: HIGH**

Every action the user can take from a button can be taken from the menu bar,
and the common ones carry the platform's shortcut:

| Action | Shortcut |
|---|---|
| Scan Page | ⌘N; Return in the window |
| Save PDF… | ⌘S; Return in the name field |
| Cancel Scan | ⌘. and Escape |
| Search for Scanners | ⌘R |
| Undo Remove Page, Discard Pages | ⌘Z |
| Settings | ⌘, |
| Close, minimise, hide, quit | ⌘W, ⌘M, ⌘H, ⌘Q — never overridden |

A new action takes the shortcut the platform's guidelines give it, or none.
Where Apple has assigned a shortcut, use that one, and give each shortcut one
meaning. Menus are the standard set in the standard order — App, File, Edit,
View, Window, Help — with the app's items in the group they belong to: Scan
Page, Save PDF…, Cancel Scan and Discard Pages replace File › New Window,
because one window suits an app built on one scanner. The scanner and its
settings — mode, resolution, paper, orientation — are the Scanner menu, the
app's own, which SwiftUI inserts between View and Window
(/documentation/swiftui/commandmenu). The toolbar's settings menu and the
Scanner menu show the same `ScanSettingsItems`, so the two cannot drift.

**Incorrect (a menu of its own for a File item; a shortcut that already means something):**

```swift
CommandMenu("Pages") { Button("Save") { … }.keyboardShortcut("p") }   // ⌘P is Print
```

**Correct:**

```swift
CommandGroup(replacing: .newItem) {
    Button("Save PDF…") { model.savePDF() }
        .keyboardShortcut("s", modifiers: .command)
}
```

Reference: Apple Human Interface Guidelines, Keyboard and Menus.
