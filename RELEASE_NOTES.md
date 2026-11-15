## [1.23.0] - 2026-11-15

### Added
- Loot rules: every loot system is now built from the same blocks (who may ask, how to ask, the order between candidates, who decides, what an award costs, per-item exceptions), for the guild or for each raid core (Raid Cores > Config), which can also just follow the guild's.
- The Master Loot window now lists rollers in exactly the order the winner is picked, and the winner line says what decided (officer priority, fewer items received, attendance) when it was not the roll.
- Loot rolls can now be answered by a button in the roll popup, with the roll drawn by the loot master's addon, so WoW: Forever raids no longer depend on /roll lines in chat. The loot master can type in the answer of a raider without the addon.
- Officers can edit the roll popup's answers in Settings > Loot: rename the buttons, add or remove answers, choose whether each asks for a roll or a bid, what share of the item's price it pays, and how long raiders have to answer.
- New loot systems: MS > OS +1 with a counter that resets each raid night, DKP bidding (open, or sealed at second price), Suicide Kings, Karma, SR+, zero-sum DKP, a weighted score, and a loot council that votes in a GuildOS window, by guild rank or by name, optionally anonymous.
- DKP gets a points cap, named reasons to earn with weekly caps, decay rounding and a cost to enter a roll with a partial refund for whoever loses. Awards for being on time, staying to the end and attending the raid are paid once an officer switches them on in Settings > Loot.
- EPGP is now a loot system of its own, with GP per item by slot and item level, EP/GP priority, minimum EP and decay on both sides.
- Loot rules can have per-item exceptions: send recipes, mounts, bind-on-equip items or unclaimed items straight to a bank character or the disenchanter, or give specific items, bosses or raids their own order.
- A raid's loot rule set on guildos.me applies in game for that raid night.
- Every award now records why the winner got the item (the candidates in order, what decided, the council's votes), and the record goes to the site with the loot history.
- A raider's first roll for an item now stands: rolling again no longer changes the number.
- The disenchant button no longer charges points to anyone.
- Fixed a freeze when the addon read data from the website containing a very small number.
