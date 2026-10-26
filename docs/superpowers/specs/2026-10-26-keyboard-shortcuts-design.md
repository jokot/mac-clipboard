# Keyboard shortcuts in every window

Design canvas: "MaClip Keyboard Shortcuts" (https://claude.ai/artifact/5zPufnQ6tmTPvgVwCtgsdU).

## Goal

A person can use every MaClip window with the keyboard only: move, run every action, and close each window.
Each window shows its own keys in a panel. Press ⌘/ to open the panel.

## One list of keys for each window

Each window has one table of key bindings. The key handling and the ⌘/ panel read the same table.
A unit test fails when two actions in one table use the same key.

## Clip window

The clip window has two sides: the list and the preview. Only one side has focus.
The clip window stays the key window. MaClip sends each key to the side with focus.

- Space opens the preview. The list keeps focus.
- → moves focus to the preview. ← moves focus back to the list.
- A 2 pt accent ring shows the side with focus while the preview is open.
- A click on a side gives focus to that side.
- In the search field, ← → switch sides only when the field is empty.
  When the field has text, ← → move the text cursor.

Esc goes back one step at a time:

1. End the edit.
2. Close the preview. The list gets focus.
3. Clear the search.
4. Close the window.

### List keys

| Group | Action | Key |
|---|---|---|
| Move | Select a clip | ↑ ↓ |
| Move | First or last clip | ⌘↑ ⌘↓ (also Home, End) |
| Move | Page up or down | fn↑ fn↓ |
| Move | Search | ⌘F |
| Move | Filter by typing | a–z |
| Move | List or preview | ← → |
| Move | Back, then close | esc |
| Clip | Paste | ↩ |
| Clip | Paste clip 1 to 9 | ⌘1–9 |
| Clip | Copy only | ⌘C |
| Clip | Preview | space |
| Clip | Edit | ⌘E |
| Clip | All actions | ⌘K |
| Clip | Delete | ⌘⌫ |
| Clip | Don’t save from app… | ⌥⌘⌫ |
| Clip | Show concealed clip | ⌘U |
| Links and files | Open | ⌘O |
| Links and files | Reveal in Finder | ⌘R |
| Links and files | Copy path | ⌥⌘C |
| Images | Extract text | ⌘T |
| Images | Extract code | ⌘B |
| Window | Settings | ⌘, |
| Window | About MaClip | ⌘I |
| Window | Clear history… | ⇧⌘⌫ |
| Window | Close window | ⌘W |
| Window | Quit MaClip | ⌘Q |
| Window | This list | ⌘/ |

The panel also shows the 3 global keys from Settings.

### Preview keys (the preview has focus)

| Action | Key |
|---|---|
| Scroll | ↑ ↓ |
| Page up or down | fn↑ fn↓ |
| Top or bottom | ⌘↑ ⌘↓ |
| Back to the list | ← |
| Close preview | space, esc |

Every clip key of the list also works, on the clip in the preview.

### Edit mode

| Action | Key |
|---|---|
| Save | ⌘↩, ⌘S |
| Cancel | esc |

Text keys work as in any Mac text field.

## Image editor

| Action | Key |
|---|---|
| Crop, Arrow, Rectangle, Oval, Text, Pen, Redact | C A R O T P X |
| Color 1 to 8 | 1–8 |
| Thinner or thicker line | [ ] |
| Rotate left or right | ⌘L ⌘R |
| Undo, Redo | ⌘Z ⇧⌘Z |
| Save | ↩ ⌘S |
| Save as new clip | ⇧⌘S |
| Cancel | esc ⌘W |

Tool, color and width keys are off while the text tool has a text field open.

## Settings, About, Accessibility prompt

- Settings: ⌘1–⌘4 select the tabs. esc, ⌘W and ⌘, close. ⌫ removes the selected app in Privacy.
- About: ↩ checks for updates. esc, ⌘W and ⌘I close.
- Accessibility prompt: ↩ runs the main button. esc and ⌘W run Not Now.

Each window also has a keyboard button that opens its panel.

## Panel

The panel is a card on top of its window. ⌘/ or esc closes it. A click outside the card closes it.
While the panel is open, the window behind it does not take keys.
