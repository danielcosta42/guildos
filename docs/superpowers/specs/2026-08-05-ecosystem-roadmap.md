# Ecosystem roadmap — from Phase 1 to a product that pays for itself

Working thesis: Blizzard will not backport retail's modern conveniences (armory, in-game performance
analysis, cross-realm group finder, coaching) to the old clients — Classic Era, TBC/WotLK/Cata
Anniversary, SoD, Hardcore. The players on those clients want them anyway. That gap is the terrain.

Our unique asset is **not any single feature** — it is the **closed loop** nobody else has assembled:

```
  addon (structured in-game data)  ──►  companion (SavedVariables + LIVE combat log)  ──►  web + DB
        ▲                                                                                    │
        └────────────────────────  Discord bot (identity + cross-server signup)  ◄──────────┘
```

Every feature below composes on that loop, so each one is cheaper to add than the last and widens the
moat. Competitors are point solutions: Warcraft Logs (analysis, no addon/signup, retail-first),
Raid-Helper (signup only, no data), Raidify (closest, no rich addon). Our wedge is the loop **plus**
Classic-specific *prescriptive* coaching (feasible because old-client rotations are well-defined) and
**cross-guild data network effects**.

This roadmap is deliberately post-Phase 1 (Phase 1 = web + companion + single-server bot, see
`2026-08-05-webapp-phase1-design.md`). Sequencing is value-first: ship the viral hook before the
paywall.

---

## The three features that make it pay (bet on these)

1. **Auto Raid Recap → Discord.** After each raid the bot posts a recap: kills, loot (with an equity
   note), top performers, and **one concrete coaching tip per player who needs it**, plus attendance.
   Combat log + addon data → deterministic metrics → LLM writes the narrative. It's *viral* (shared in
   Discord, seen by every member every raid night), it's *retention* (people come back for their
   card), and it's the free showcase for the paid guru. Cheap once combat-log ingestion exists.

2. **Raid Guru — prescriptive per-player coaching.** Not "here are your numbers" (that's Warcraft
   Logs) but "here is the *one thing* to change." e.g. *"Warrior: Heroic Strike uptime 82% while
   rage-capping 14% of the fight — stop queuing HS below 30 rage."* Old-client rotations are simple
   enough that a **deterministic rules engine per class/spec** can be authoritative; the LLM only
   phrases it. This is the paid centerpiece and genuinely hard to copy well.

3. **Cross-guild benchmarking.** Because we aggregate combat logs across many guilds and servers, we
   can tell a player *"your warlock is p62 vs the median warlock at your gear level on this boss"* —
   without depending on Warcraft Logs. **Data network effect:** more guilds → better benchmarks →
   more valuable → more guilds. This compounds and is the real long-term moat.

Recap is the hook (free), Guru + benchmarking are the paid tier. That's the business.

---

## Phased roadmap

### Phase 2 — Live combat log + the viral hook
Unlocks everything analysis-related.
- **Companion combat-log leg**: tail `WoWCombatLog.txt` live; a mini-addon auto-runs `/combatlog` on
  raid entry (required on old clients even with advanced logging on). Stream fights to the web.
- **Per-fight metrics** (deterministic): DPS/HPS, buff/debuff uptime, deaths, interrupts, dispels,
  consumable use, rage/energy/mana waste, downtime.
- **Auto Raid Recap** (killer #1) posted to Discord.
- **Personal parse history & trend** on the web character page.
- Monetization: still free — this is adoption fuel.

### Phase 3 — Turn the analysis into a product (paywall on)
- **Raid Guru** (killer #2): per-class/spec rules engine → prescriptive cards, per player, per fight.
- **Cross-guild benchmarking** (killer #3): percentile vs gear-bracketed cohort.
- **Guild performance dashboard**: raid-over-raid trends, who's improving, roster weak spots.
- **Guild Pro subscription** launches here (officer/guild pays — see Monetization).

### Phase 4 — Network effects & growth
- **Cross-server signup network** (the original differentiator): one raid, signups fanned across N
  host communities, web as source of truth. Two-sided; premium for host communities / featured slots.
- **Recruitment marketplace with verified data**: applicants arrive with *verified* gear/attunement/
  parse (our own data), not screenshots. Guilds pay to post/search. Two-sided.
- **Character Passport**: portable identity — gear, parses, attunements, alts, reputation — across
  guilds and the network. Raises switching cost; underpins recruitment and pug trust.

### Phase 5 — Deepen guild lock-in
- **Loot Council Cockpit**: one screen with wishlist + loot equity + attendance + "BiS-for-whom",
  decide, and (write-back leg) push the award into the game.
- **Raid Readiness pre-check**: pre-pull, bot shows who's missing consumables/enchants/attunement/
  world buffs + bench suggestions. The addon already computes most of this — cheap, high value.
- **Comp Optimizer**: with alts tracked, suggest the optimal raid comp (buff coverage, roles) from
  who actually signed.
- **Season/gearing planner**: "to clear SSC you need 3 more Kara-attuned; here's who's closest."
- **API / embeds** for guild websites — roster, logs, signup widgets. Sticky.

---

## More features on the shelf (compose freely, sequence by pull)

**AI-native (hard to copy):**
- **Natural-language queries** over guild data: "who's missing Kara attunement and is a healer?",
  "DPS trend for our warlocks last month". LLM over structured data — numbers stay deterministic.
- **Wipe post-mortem**: "why did we wipe on Vashj p2" → timeline of deaths/mistakes from the log.
- **Recruitment matching**: "you need a resto shaman with SSC attune" → matched against the pool.

**Guild management SaaS:**
- **Public guild page** (armory-like) — old clients have no armory; shareable, recruitment-friendly.
- **Applicant pipeline**: apply on web, officers review with logs/gear attached.
- **Guild health analytics**: retention, raid consistency, roster gaps, burnout signals.
- **Loot equity / DKP / EPGP on web** (addon already tracks equity).

**Player-facing / retention:**
- **Milestones, streaks, personal bests, "most improved"** — the recap feeds these.
- **Discord DM reminders** for signup, missing consumables, expiring world buffs.
- **Mobile-friendly** everything (signup, passport, recap).

**Economy (careful, but large):**
- **Soft-res / MS>OS on web**, imported to game (write-back leg).
- **BiS / loot-path tracker** per raider (the addon already has TMB integration).

---

## Monetization

Keep the **addon 100% free** — it is the distribution channel and the data moat. Monetize the web /
analysis layer.

| Tier | Who pays | What they get |
| --- | --- | --- |
| **Free** | individual players | character passport, sign up to raids, view own recap card, light coaching |
| **Guild Pro** (subscription) | an officer/GM, for the guild | full Raid Guru for the roster, cross-guild benchmarking, guild dashboard, auto-recaps, loot cockpit, recruitment tools, longer history retention |
| **Network / Community** | large communities | cross-server signup hosting, featured recruitment, multi-guild dashboards, benchmarking pro |

- Anchor: a guild splitting a small monthly fee is trivial (compare Warcraft Logs subscription,
  Raid-Helper premium, everyone already pays for a Discord boost). The *guild*, not the player, is the
  natural payer — one officer covers 25–40 people.
- **LLM cost control** (this is the main variable cost): numbers come from a deterministic engine, the
  LLM only writes narrative; cache recaps; gate LLM features behind Guild Pro; use cheaper models for
  bulk and reserve the strongest model for the guru's coaching text. Make cost scale with paying
  seats, not free ones.

---

## Risks & guardrails (be honest early)

- **ToS.** Reading `WoWCombatLog.txt` / SavedVariables and analyzing on the web is established, safe
  territory (Warcraft Logs precedent). The line we never cross: automating the game client (input
  injection, memory reads, botting). The companion stays 100% file-on-disk.
- **Reputation / "pug blacklist" features are a trap.** Public performance shaming or shared ban lists
  invite defamation and brigading — the addon *already dropped* shared ban lists for exactly this
  reason (`alliance-design.md`). If we do pug reputation, keep it objective (no-show counts), private
  to officers, and disputable — never public shaming.
- **LLM cost** can outrun revenue if guru/recaps are free at scale — hence the gating above.
- **Privacy / LGPD** duty multiplies as we aggregate cross-guild personal data: consent, delete,
  regional hosting (São Paulo helps), and be explicit about benchmarking anonymization.
- **Combat-log reliability**: needs `/combatlog` on (mini-addon auto-enables) and advanced logging for
  positional data; some metrics simply won't exist without it — surface that honestly rather than
  guessing.
- **Defensibility**: Warcraft Logs could bolt on signup; Raidify exists. Our protection is *speed on
  the closed loop* + the Classic-prescriptive coaching + the cross-server data network effect. Ship
  the loop and the benchmarking data flywheel before anyone else assembles it.

---

## One-line summary

Phase 1 proves the loop. Phase 2's **Raid Recap** makes it spread. Phase 3's **Guru + benchmarking**
makes it pay. Phase 4's **cross-server network + verified recruitment** makes it hard to leave.
Everything monetizes the web layer while the addon stays free to protect distribution and data.
