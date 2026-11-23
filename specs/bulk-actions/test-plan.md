# Bulk actions: in-game test (issue #420)

Automated: `luajit -e 'ADDON="."' tools/bulk-actions.lua` (rules, eligibility, queue, skips, log, typed
mode, retail press/release). In game, an officer with the rights to promote, demote and remove, and a
test guild with a few low-rank alts:

1. **Rules.** Leadership > Bulk actions, Promote, rank = the lowest, Preview: only those members; yourself
   and officers never listed. No rule set: Preview says "Set at least one rule."
2. **Promote by click.** Start, then Next: the alt is promoted one step, the chat says "Sent /gpromote …",
   the row turns "done" after the roster update, and Audit Log shows one "Promoted" line.
3. **Macro.** Make a macro `/click GuildOSBulkNext`, press it: the next member is promoted.
4. **Skips.** With a queue running, promote one of its members by hand in the game's panel, or have one
   leave: Next skips them ("rank changed", "left the guild").
5. **Remove.** Remove, Offline at least 1 day, Start: the confirmation lists the names; Cancel starts
   nothing; Start, then Next removes one per click.
6. **Permission.** On a rank without the right: Preview and Start are disabled, the tab says so.
7. **Combat.** In combat Next does nothing and says "Not during combat."; closing the window in combat
   raises no "Interface action failed" error.
8. **Retail.** With "Cast on key down" on and off, one click promotes exactly one member.
9. **WoW: Forever.** Next prints "Type /gpromote Name in chat…"; typing it promotes, the next click goes on.
   **Open question:** a member with a surname ("Chehul Druida") gets `/gpromote Chehul-Druida`, the form `/w`
   takes on Forever (GuildOS:WhisperTarget). Whether the game's /gpromote takes that form is not verified:
   check it, and try `/gpromote Chehul Druida` if it does not.
10. **Key-down option.** With "Cast on key down" on, the panel shows `/click GuildOSBulkNext LeftButton 1`;
    off, `/click GuildOSBulkNext`. Each press of either macro acts on one member.
11. **Not confirmed.** Click Next for a member the game refuses (e.g. one above your rank by then): 15 s
    later the row reads "not confirmed, check it", and no click sends them again.
