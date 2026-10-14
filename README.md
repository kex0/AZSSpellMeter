# AZS Spell Meter

Per-spell damage for [Azeroth Survivors](https://github.com/samwhosung/benilla). Damage, DPS, and each spell's share come from the game's own meter, so they match **Damage Done**. Kills are counted on top of that, and a proc is shown on the spell it actually casts.

![AZS Spell Meter](preview.png)

## Why use this instead of Damage Done

The built-in meter is the right tally. This one reads those same numbers and adds the things it doesn't show.

- **Kills per spell.** The kill column is how many creatures that spell finished.
- **The spell that was actually cast.** Pyroclasm's explosion is Blast Wave. Damage Done lists Pyroclasm on its own. This meter puts that damage on Blast Wave and leaves a proc button beside it. Upgrading Blast Wave is what upgrades the proc, and the row makes that obvious. Hover the button for the proc's own damage, DPS, kills, and icon.
- **Sortable columns.** Click Kills, Damage, or DPS. Click again to reverse the order.
- **A reset that is yours.** Reset starts this window over. The built-in meter keeps its own numbers, so you can measure a stretch of the run without wiping the game's tally.
- **It gets out of the way.** The minus button collapses the window onto a small bubble. Click the bubble to open it again.

## Install

1. In game, open **Options → AddOns → Open AddOns Folder**.
2. Put this folder there, so the path ends in `AddOns/AZSSpellMeter/AZSSpellMeter.toc`.
3. Relog. Addons only load at login.

Requires Azeroth Survivors 0.87 or newer, for `AZS_GetMeter`.

## Use

Drag the bronze title bar to move the window. Drag the corner to resize it. If the list is longer than the window, the last spell sits partly in view. Scroll with the mouse wheel.

| Command | |
|---|---|
| `/azsm` | Show or hide |
| `/azsm reset` | Start this window over |
| `/azsm lock` | Lock or unlock dragging |
| `/spellmeter` | Same as `/azsm` |

While this window is open, the built-in Damage Done meter is hidden. Hiding this addon puts it back, if it was on before.

## Changelog

### 1.17

- Damage, DPS, and share are read from the game's meter. They match Damage Done.
- Kills per spell. A proc's kills stay with the spell it casts.
- Procs are grouped under that spell, with a button for the proc's own numbers and icon.
- Reset clears this window only. The built-in meter is unchanged.
- The list clips to the window, so resizing can leave a spell half visible.
- Tooltips sit above the cursor, follow it, and update while you hover. Share is shown there.
- Compact title bar. Minimize collapses the window to a bubble on that button.
