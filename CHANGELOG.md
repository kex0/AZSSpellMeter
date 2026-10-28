# Changelog

## 1.32

Tested with game 0.113.3.

- Each spell alone lists every spell, talent, and item on its own row, as Damage Done does.
- A proc in that list has no kill count, because a proc is the spell it casts.
- Settings are split into Window, DPS, Rows, Columns, and Colors.

## 1.31

Tested with game 0.113.3.

- An icon after a spell name no longer covers that spell's kill count.
- Damage from your only summon, such as a Water Elemental, uses that summon's name and icon.
- Wolf, Raptor, Treant, and Spirit Wolf have icons.

## 1.30

Tested with game 0.113.3.

- Another hero's strongest spell is named in your language.
- A spell keeps its icon when a co-op partner's game is in another language.
- A talent groups under the spell it casts even when a partner's spell names are not in English.
- The same talent no longer shows twice under one spell when a partner's game is in another language.
- Hovering another hero's strongest spell shows what that spell does.
- The tip for another hero's strongest spell does not include your own damage bonuses.
- The tip for another hero's strongest spell does not say you have not learned that spell.
- Divine Storm has an icon beside a hero's name.
- Imp, Felhunter, Succubus, and Pit Lord have icons beside a hero's name.
- Choker of the Fire Lord has an icon beside a hero's name.
- Pendant of the Plague: Moonfire shows Moonfire's icon.
- A spell or item that was missing its picture now has one.

## 1.27

Tested with game 0.113.1.

- Share shows each spell's part of the total.
- Kills, Damage, Share, and DPS can each be hidden.
- Under the spell adds an arrow that opens the talents grouped into a spell.
- Sweeping Strikes shows on Cleave, Mortal Strike, and Execute.
- An item that adds to a spell is grouped into that spell.
- A pet's attacks use the pet's name.
- Infernal, Doomguard, and Felguard have icons.
- Hover a spell to see its hits, crits, and crit chance.
- Columns widen just enough for a long number, and they stop shifting as DPS changes.
- Wrap names splits a long name onto a second line. It is off until you turn it on.
- An item's icon stays after a reload, once the meter has seen it.
- Party shows each hero's damage while you are in co-op.
- The Party tab is hidden when you play alone.
- Each hero's strongest spell sits beside their name.

## 1.26

Tested with game 0.107.0.

- You can choose how far back DPS looks. It still starts at 10 seconds, from 5 seconds up to 2 minutes.
- Since the start shows the average for the whole run.

## 1.25

Tested with game 0.107.0.

- Talents that trigger a spell, such as Flurry and Rampage, now show on that spell instead of as their own row.
- Hovering one of those talents no longer lists kills.

## 1.24

Tested with game 0.105.0.

- DPS is the last 10 seconds of the run, not the average since the start. Healing, boss damage, and damage taken use the same window. It still pauses while the run is paused.
- A kill from the English combat log is added to the translated spell row when the icon matches one spell on the meter.
- Fixed the error `table index is nil` that repeated while the main window was open.

## 1.23

Tested with game 0.104.0.

- A gear on the title bar opens settings. Right-click the bubble, or type `/azsm settings`, for the same window.
- Scale changes the main window, the bubble, and any extra windows together. Each one grows from its own top-left corner.
- Opacity fades the whole window. Background fades only the panel fill, so the text can stay readable.
- Colors cover the window, its border, and each view's title, bars, and numbers.
- Cooldown bars under spell icons can be turned off. Lock stops the windows from being dragged.
- Reset settings puts those back. Numbers and where the windows sit are kept.
- Windows, including ones that open beside the main window, stay on the screen. Tooltips stay on screen and sit next to the cursor.
- The total, DPS, and Reset on an extra window have the same tooltips as the main window.
- Drag the title, or the damage and DPS numbers, to move a window.

## 1.22

Tested with game 0.102.2.

- Fixed the load error after the latest game update: `too many upvalues (limit=32)`. Relog to load it.
- Tooltips show again on hover. The anchor name had been rewritten into something the game rejects.
- The close and minimize marks sit in the middle of their buttons. Text uses a centered outline instead of a drop shadow.
- Windows can sit against the right edge of the screen. Tooltips follow the cursor there too.
- Resizing an extra window lets go when the mouse button does.
- The title bar takes the color of the view it is showing.
- Damage, Healing, Boss, and Taken stretch across the full width of the window.

## 1.21

- Right-click Damage, Healing, Boss, or Taken to open that view in its own window. The button stays on the main window, dimmed.
- Click the dimmed button, or the x on the extra window, to put the view back. The main window switches to it.
- Each view is only shown in one place. An extra window has its own size, position, scroll, and Reset.
- Opening the view the main window is showing switches the main window to another view. The last view on the main window stays there.
- The built-in meter stays hidden while the main window, its bubble, or an extra window is open.

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
