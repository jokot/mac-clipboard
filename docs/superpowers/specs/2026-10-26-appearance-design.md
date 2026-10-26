# Settings → Appearance

Design canvas: "MaClip Redesign" (https://claude.ai/artifact/REhTjHvSy9VkLAUrrGrAgS), artboards "Settings — Appearance", "Accent colors" and "Appearance — custom color picker".

## Tabs

General, Appearance, Shortcuts, Storage, Privacy. ⌘1 to ⌘5 select them. Theme moves from General to Appearance.

## Accent color

- 10 presets: Indigo #5E5CE6 (default), Blue #0A84FF, Purple #BF5AF2, Pink #FF375F, Red #FF453A, Orange #FF9F0A, Yellow #FFD60A, Green #30D158, Teal #40C8E0, Graphite #98989D.
- Custom: a popover with a color field, a hue slider, a hex field, an eyedropper and the 4 newest custom colors.
  The app shows the color under the knob at once. Done or ↩ keeps it. Cancel or esc goes back. A click outside keeps it.
- Saved in `settings.accentColor` as a preset name or "#RRGGBB". A bad value gives Indigo.

## Readable colors

- Button text is white when white has 3:1 contrast with the accent, else #1C1C1E.
- Colored text (links, "← List", group titles) gets lighter in dark mode or darker in light mode until it has 4.5:1 contrast.
- The selected clip uses the accent at 22% in dark mode and 16% in light mode.
- Warnings stay orange. The app icon and the menu bar icon do not change.
- Controls that macOS draws, such as the segmented Theme control, keep the macOS accent color.

## Preview

A switcher shows the clip window, the preview, controls or the shortcuts panel. The preview uses the selected theme.

## Keyboard

- The swatches are one focus stop. ← → step through the presets and Custom. Space on Custom opens the picker.
- In the picker, ⇥ moves between the color field, the hue slider, the hex field and the eyedropper. The arrow keys move the knob 1% a step, 10% with ⇧.

## Restore Defaults

On General. It resets the theme, the accent, pasting, the clip window, the shortcuts, auto clean, the list of apps, the MaClip switch and concealed clips.
It keeps the clips, the clip limit and encryption.
