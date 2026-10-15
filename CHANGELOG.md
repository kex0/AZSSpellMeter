# Changelog

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
