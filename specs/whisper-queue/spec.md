# One queue for every whisper on WoW: Forever (issue #393, after #392)

## Why
On WoW: Forever the server answers a client that whispers about thirty times a minute with "You
are doing that too fast" (`ERR_GENERIC_THROTTLE`). The player sees it, every other addon is
throttled with them, and the whispers that came too fast are refused. A player measured GuildOS
at about 28 `ChehulRecruit` whispers a minute for hours in the evening. Two causes:

- **The realm bus.** Addon YELL is refused on Forever, so `LibChehulMesh` whispers every realm
  item to `REALM_FANOUT = 3` names, up to `YELL_PER_FLUSH = 4` items every 25 s, and
  `RecruitBeacon:RelayTick` refills its queue with four ads every 30 s: 12 to 24 whispers every
  25 s. The library is shared by the Chehul family (`chehulnet.lock`, `tools/chehulnet-lock.sh`)
  and is not changed here.
- **The gossip (#392).** A round's allowance counted payloads, while AceComm splits a payload over
  255 bytes into parts of 254: one 2 KB CR3 ad is nine whispers.

## What
- `Core/WhisperQueue.lua` (`GuildOS.WhisperQueue`): a bucket of parts. `BURST = 4` parts may leave
  back to back after a quiet spell, then one every `INTERVAL = 4` s (15 a minute, half what drew
  the error). A payload pays its AceComm parts. Only on WoW: Forever; elsewhere everything goes at
  once, as before.
- **Back-off.** `UI_ERROR_MESSAGE` carrying `ERR_GENERIC_THROTTLE` doubles the interval (up to
  `MAX_INTERVAL = 64` s) and empties the bucket; each `RECOVER_SECONDS = 60` without another
  halves it, back to `INTERVAL`.
- **Priority.** `high` (a join request and its answer, a loot vote or sealed bid, the whisper
  test) goes first and is never dropped. `normal` (sync answers, alliance ops) after it, dropped
  only to make room for a `high` when the queue (`QUEUE_MAX = 60`) is full. `low` (gossip,
  CraftNet's answer) last; it makes room for the others and is stale past `LOW_TTL = 90` s,
  because the next round says it again.
- **The realm bus.** GuildOS hands the mesh's `:Realm` its items through `WhisperQueue:Realm`.
  Where YELL is dead an item goes in only when nothing of ours waits and both the bucket and a
  slower one of its own (`REALM_PER_MINUTE = 6` parts) can pay for every whisper the mesh will
  send for it (`REALM_FANOUT` times its parts plus the relay envelope). What does not fit is not
  queued: the next relay tick offers it again. Where YELL lives the mesh paces itself and the item
  goes straight in.
- **The gossip.** A round's allowance is `ROUND_PARTS = 10` parts (it was 10 payloads), digests
  included, and every gossip whisper goes through the queue.
- **Chat lines.** `Push` queues a chat whisper; where the game drops a chat line an addon sends
  from a timer (#61), a waiting one leaves on the next click (`Release`, or any whisper from a
  click). A whisper the player's own click sends (a warning, *Whisper next*) goes at once through
  `SendNow` and is paid for, so what waits behind it waits longer.

- **A message in chunks is one unit.** CommSystem cuts a whisper over 250 bytes into chunks, each
  a whisper; on Forever they go in through `PushAddonGroup`: all of them or none (a full queue
  refuses the message, not its last chunk), and when one makes way, or the game will not send one,
  the rest of that message goes with it. The receiver waits for a whisper's next chunk
  `WHISPER_CHUNK_SECONDS = 128` s (two of the queue's slowest steps), renewed at each chunk, so a
  message of any length completes at the queue's pace; over GUILD it stays `CHUNK_SECONDS = 30`.

API, for other modules (the reminders of #422 among them):

```lua
GuildOS.WhisperQueue:Push(target, text, prio)            -- chat; "sent" | "queued" | false
GuildOS.WhisperQueue:SendNow(target, text)               -- chat from a click; true when it went
GuildOS.WhisperQueue:PushAddon(prefix, payload, target, prio, send)  -- send() returns false when nothing went
GuildOS.WhisperQueue:PushAddonGroup(prefix, payloads, target, prio, send)  -- one message's parts, all or none
GuildOS.WhisperQueue:Realm(prefix, payload, key)         -- true when it went into the mesh's queue
GuildOS.WhisperQueue:Release()                           -- from a click
```

Through it: CommSystem's targeted messages, the gossip (and so JoinRequests), Alliance:Send (and
so AllianceSync), CraftNet's answer and realm query, RecruitBeacon's realm ads, the loot council's
vote and the loot master's sealed bid, the warning whisper, the recruit scanner's *Whisper next*.

## Outside it
What `Libs/LibChehulMesh.lua` and `Modules/ChehulNet.lua` whisper on their own (the peer exchange,
about 4 a minute; the relay's forwards, under the library's own `RELAY_BUDGET`; ChehulNet's hello
and ping answers, about 1 a minute) cannot be routed without changing the shared copies. The
issue's diff for the library (`REALM_WHISPER_BUDGET`, `Spend` with a cost) belongs in
danielcosta42/chehulnet, followed by its `tools/sync.sh`.

## Acceptance
- [x] Every whisper GuildOS sends itself on Forever goes through one queue at a safe pace.
- [x] `ERR_GENERIC_THROTTLE` doubles the interval and it comes back slowly.
- [x] A `high` message is never dropped; only `low` ones go stale.
- [x] The realm bus's whispers are paid for before an item reaches the mesh.
- [x] `tools/whisper-queue.lua`: an hour of the issue's load against a server that refuses past
  30 a minute draws no error (the same load without the queue draws 320), and the worst minute
  stays at 18.
- [x] A whisper of 40 chunks, sent while the server throttles, reaches the other side whole; a full
  queue takes a message's chunks all or none.
