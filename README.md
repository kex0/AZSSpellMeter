# AZS Spell Meter

Per-spell damage for [Azeroth Survivors](https://wow.aethus.pl/). Damage, DPS, and each spell's share come from the game's own meter, so they match **Damage Done**. Kills are counted on top of that, and a proc is shown on the spell it actually casts.

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

Requires Azeroth Survivors 0.87 or newer, for `AZS_GetMeter`. Healing, Boss, and Taken need a current game build.

## Use

Drag the bronze title bar to move the window. Drag the corner to resize it. If the list is longer than the window, the last spell sits partly in view. Scroll with the mouse wheel.

Damage, Healing, Boss, and Taken are the buttons under the title. Damage includes kills per spell. Healing is health actually restored. Boss is the last boss fight, and it stays up until the next boss. Taken is the damage you took, split by what hit you. A thin bar under a spell icon is its cooldown. Hover the total for your build stats.

Right-click a button to open that view in its own window. The button stays, dimmed. Click it, or the x on the extra window, to bring the view back. Each view is only in one place. The extra window has its own size, position, and Reset.

| Command | |
|---|---|
| `/azsm` | Show or hide. If the window is off screen, this brings it back |
| `/azsm reset` | Start this window over |
| `/azsm resetpos` | Put the window back on screen |
| `/azsm lock` | Lock or unlock dragging |
| `/spellmeter` | Same as `/azsm` |

While the main window, its bubble, or an extra window is open, the built-in Damage Done meter is hidden. It comes back when all of them are closed, if it was on before.

The window position is remembered across updates. Deleting the addon folder does not clear it. If the window is missing, type `/azsm resetpos`.

## Changelog

### 1.21

- Right-click Damage, Healing, Boss, or Taken to open that view in its own window. The button stays, dimmed.
- Click the dimmed button, or the x on the extra window, to bring the view back.
- Each view is only shown in one place. An extra window has its own size, position, and Reset.
- The built-in meter stays hidden while any of these windows is open.

### 1.20

- Damage, Healing, Boss, and Taken are the buttons under the title. Damage stays selected until you pick another.
- Healing matches Healing Done. Kills keep counting, and they are not listed on that view.
- Boss matches the last boss fight. The kills column is hidden there too.
- Taken splits damage you took by source. On death, one chat line names the biggest source.
- Reset clears only the view you are looking at.
- The title shows your class. Spell cooldowns sit under the icon, and the total's tooltip lists your build.
- Leech, items, and the Taken rows have their own icons.

### 1.19

- The window stays on screen. A position saved off screen is moved back on login.
- `/azsm resetpos` puts the window back in the top-left without wiping the meter.

### 1.18

- Fixed the chat error that appeared while the meter looked up spell icons.

### 1.17

- Damage, DPS, and share are read from the game's meter. They match Damage Done.
- Kills per spell. A proc's kills stay with the spell it casts.
- Procs are grouped under that spell, with a button for the proc's own numbers and icon.
- Reset clears this window only. The built-in meter is unchanged.
- The list clips to the window, so resizing can leave a spell half visible.
- Tooltips sit above the cursor, follow it, and update while you hover. Share is shown there.
- Compact title bar. Minimize collapses the window to a bubble on that button.
