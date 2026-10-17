# Changelog

## 1.20

- Damage, Healing, Boss, and Taken sit under the title bar. Damage is selected until you pick another. The highlighted button is the view you are on.
- Healing is the game's Healing Done meter. Overhealing is left out. Kills stay tracked, and they are not shown on this view.
- Boss is the last boss fight. Bosses up together count as one fight. The kills column is hidden there too.
- Taken splits the damage you took by what hit you: boss melee, boss spells, elites, mobs, and ground. When you die, one chat line names the biggest source.
- Reset clears only the view you are looking at. Resetting healing, boss damage, or damage taken does not clear kills.
- The title bar shows your class icon and class name. The window has rounded corners.
- A thin bar under a spell icon is that spell's cooldown. Green means it is ready.
- Hover the total for the build behind the numbers: damage, crit, crit damage, cooldown, extra targets, area, and echo.
- Leech, worn items such as Onyxia Tooth Pendant, and the Taken rows use their own icons. A proc button shows the proc's icon.

## 1.19

- The window can no longer be left off the screen. If a saved position is already off screen, it is moved back on login.
- `/azsm resetpos` puts the window back in the top-left. Reinstalling the addon does not clear a saved position, so use this instead of deleting the saved file.

## 1.18

- Fixed the chat error that appeared while the meter looked up spell icons. Relog to load it.

## 1.17

- Damage, DPS, and each spell's share are read from the game's own meter, so they match Damage Done.
- Each spell shows how many kills it landed. A proc keeps the kills of the spell it actually casts.
- That proc is grouped onto the spell. Blast Wave shows a proc button for Pyroclasm, instead of a separate Pyroclasm row. The button's tooltip has the proc's damage, DPS, kills, and icon.
- Reset starts this window over. The built-in meter keeps its numbers.
- Resizing the window clips the list, so the last spell can be partly visible. Scroll with the mouse wheel.
- Tooltips follow the cursor and update while you keep the pointer there. A spell's share of the damage is in the tooltip.
- The header is a compact title bar. The minus button collapses the window to a bubble sitting on that button. Click the bubble to open it again.

## 1.8

- Tighter header. The total and DPS sit on the title line, and the kill count sits with the column labels.
- Removed the Total/Actual switch. The meter always counts the full hit. Accurate "actual" damage is not available to an addon.
