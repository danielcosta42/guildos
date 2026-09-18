# Beta build: one package that loads on Forever, outside the stores

Issue: danielcosta42/guildos#11 · Epic: #4 · Depends on #6, #7, #9 · ADR-0017

Condensed spec + plan + tasks.

> **Read with #20 (ADR-0021).** Two premises below expired: the stores now have the Forever flavour, and the
> packager knows it from commit `e50a250f` on. So the committed TOC carries `20506, 16001`, `publish.yml` names
> no flavour and one upload serves both clients, and `beta.yml` no longer stamps interfaces — it refuses a TOC
> that lost Forever's. What still holds: a `-beta.N` tag is a GitHub pre-release, built with `-d`, with no store
> credentials anywhere near it.

## 1. Problem

- **The stores cannot carry it yet.** CurseForge, Wago and WoWInterface have no WoW: Forever flavour.
- **Publishing would mislabel Anniversary.** The BigWigs packager tags an interface it does not know as retail. Putting Forever's interface in the committed TOC and running `publish.yml` (`-g bcc`) risks mislabelling the Anniversary release.
- **Testers still need a build.** They need one zip that loads on the beta when it opens.
- **Forever's interface number is unknown.** Its internal build line is 1.60.x, which gives 16000 or 16001 by the `%d%02d%02d` rule.

## 2. Design

### 2.1 What exists today (read from the workflows)
- `release.yml`:
  - runs on pushes to `main` and on pull requests;
  - finds the latest tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$`, in both the version bump and the changelog;
  - bumps the version, commits, tags `vX.Y.Z` and dispatches `publish.yml` for that tag.
- `publish.yml` runs on `workflow_dispatch` only. It runs the BigWigs packager with `-g bcc` and uploads to CurseForge and Wago.
- `.pkgmeta` packages as `GuildOS` and keeps `tools`, `.github` and every `*.md` out of the zip.
- A `vX.Y.Z-beta.N` tag is invisible to both workflows:
  - `release.yml` never runs on a tag, and its tag regex skips a `-beta` suffix;
  - `publish.yml` runs only when dispatched: by `release.yml` for the store tag it made, or by hand from the Actions page.

### 2.2 `.github/workflows/beta.yml`
- **Trigger:** a pushed tag matching `v*.*.*-beta.*`, and nothing else: no branch, pull request or manual dispatch.
- **Permissions:** `contents: write`, at the workflow level only.
- **Stamp (in its own checkout only):**
  - the TOC interface line keeps the committed Anniversary interface first and appends `16000, 16001` (today
    `## Interface: 20506, 16000, 16001`), so a client patch bump carries over;
  - a committed interface line it cannot extend (two numbers, a trailing space) fails the step;
  - `## Version` and `GuildOS.VERSION` take the tag's version without the `v`, so `/guildos probe` records the beta build;
  - `GuildOS.VERSION` keeps its trailing comment;
  - the step prints the stamped lines.
- **Checkout:** the tagged commit with its history, and `persist-credentials: false`, so the job token never lands in `.git/config` where a later step could push with it.
- **Package:** the BigWigs packager in `-d` mode, which uploads nowhere, with no store credentials. It is pinned to the commit its `v2` tag pointed to (`6d50adb`), not to the movable tag.
- **Release:** `gh release create "$GITHUB_REF_NAME" .release/GuildOS-*.zip --prerelease` with the job's `GITHUB_TOKEN`.
- **Never touched:** `git push`, `git commit`, the store workflows and the committed TOC.

Multi-interface TOC lines are already common among the addons installed on this Anniversary client, so the 2.5.6 client reads the list.

### 2.3 README: "Testing on the Forever beta"
Placed right after Installation. In order:
1. Point the Guild OS companion at the `_anniversary_` folder before installing the beta.
2. Download the latest `GuildOS-vX.Y.Z-beta.N.zip` from the GitHub pre-releases. The section says it is never on CurseForge or Wago.
   **Revised 2026-09-17:** how the beta build ships is not decided. If CurseForge and Wago add a WoW: Forever flavour
   it ships there; if not, as a direct download (this workflow's pre-release is that fallback). The README says so and
   points at the GuildOS Discord, where the build is announced.
3. Install into the beta client's own `Interface/AddOns`, not into `_anniversary_`.
4. Tick **Load out of date AddOns** if the beta's interface is newer than the build lists.
5. Run `/guildos probe`, then `/reload` to write the result to disk.
6. Send back `WTF/Account/<account>/SavedVariables/GuildOS.lua`. It holds Guild OS's saved data, including guild members' character names, officer notes and chat messages; share it only with the maintainers.

### 2.4 Risks
- **The interface list is a guess.** Until the beta shows its real number, Forever may need "Load out of date AddOns". The first beta that reveals the number replaces `16000, 16001` in `beta.yml`.
- **The packager is unproven here.** How it treats a TOC listing interfaces it does not know is proven only by the first beta tag. If it refuses, the fallback is a `zip` of the checkout that honours the `.pkgmeta` ignore list.

## 3. Tests
- `tools/beta-workflow.py` (Python with PyYAML, bash and git; 102 checks). It parses the three workflows and, for two tags (`v0.54.0-beta.1` and `v1.2.3-beta.10`), runs the beta stamp step for real under bash on LF copies of `GuildOS.toc` and `Core/Config.lua` committed in a temporary git repository (what a CI checkout has), runs the release step under bash with a stub `gh` that records every call and then with one that fails, and reads `.pkgmeta` and the README. It covers:
  - **Beta trigger:** pushed tags only.
  - **Tag pattern:** `v0.54.0-beta.1` and `v1.0.0-beta.12` match; `v0.54.0`, `v0.54.0-rc.1`, `main` and `v0.54.0-beta` do not.
  - **Permissions:** `contents: write` only, and the job does not widen them.
  - **Shape:** nothing else at the top level; a job with no condition, environment or permissions of its own; a
    checkout of exactly `actions/checkout@v4` with `fetch-depth: 0` and `persist-credentials: false`; the
    steps in order (checkout, stamp, package, release), none with a condition, shell, working directory or error
    override.
  - **Packager and release:** the packager pinned to a commit, in `-d`, without credentials; with `GITHUB_TOKEN`, `gh` is called exactly
    once, as `release create <tag> .release/GuildOS-<tag>.zip --prerelease --title … --notes …`, so a draft, a
    `--prerelease=false`, a broken continuation or a later `gh release edit` all fail; and when `gh` fails, the step fails.
  - **Never used:** `git push`, `git commit`, CurseForge or Wago secrets, workflow dispatch or `-g bcc`.
  - **Stamp:**
    - it runs cleanly, in a git repository with both files committed, so a revert through git would show;
    - every TOC line is kept, and only the interface and version lines change: to the committed interface plus
      `16000, 16001`, and to the tag's version; a committed `20599` becomes `20599, 16000, 16001`;
    - a committed `20506, 20507` or `20506 ` (trailing space) fails the step instead of shipping without Forever's interfaces;
    - `GuildOS.VERSION` takes the version and keeps its comment;
    - the step prints what it stamped.
  - **Store flow unchanged:**
    - the committed TOC declares one interface, Anniversary's (`205xx`);
    - `release.yml` runs on `main` and pull requests, never on a tag;
    - both of its tag regexes see store tags and skip beta tags, every `LATEST=` lookup goes through that regex
      and its fallback is a store version, and it dispatches `publish.yml` only for its own tag;
    - `publish.yml` runs only when dispatched, still with `-g bcc`.
  - **Zip:** it packages as `GuildOS`, makes one zip only (no no-lib copy), and leaves out `tools`, `.github` and
    `*.md`.
  - **README:** the section sits right after Installation, carries every item from the acceptance criteria, and puts the companion step before installing.
- **Mutation check:** 59 hand-written mutants of `beta.yml`, `release.yml`, `publish.yml`, the TOC, `.pkgmeta` and the README; the test kills all 59.
  - **Review round 1:** the packager moved before the stamp; a condition, a shell with `continue-on-error` or a
    working directory on the stamp step; `if: false` on the packager, the release or the job; a no-lib second zip;
    a latest-tag lookup that reads any tag; the warning without officer notes.
  - **Review round 2:** a draft release, `--prerelease=false`, the release command cut at its continuation, a
    `gh release edit` after it, a checkout of `main` or into a subfolder, a `git checkout` undoing the stamp.
  - **Review round 3:** the token left in `.git/config`, the packager back on its movable tag, a swallowed `gh`
    failure, the stamp reverted through git called by path, the install step pointed at `_anniversary_`.
  - **Review round 4:** the version, the release tag, the zip name or the title copied from one tag instead of
    read from `GITHUB_REF_NAME`.
  - **Review round 5:** the Anniversary interface written as a literal, or matched only as `20506`, instead of carried
    over from the committed TOC.
  - **Review round 6:** a stamp that silently leaves an interface line it cannot extend.
  - **`beta.yml` trigger and access:** any tag, `main`, manual dispatch, wider or job permissions, not a pre-release, the packager uploading or holding credentials, a push to `main`, a wider zip glob.
  - **`beta.yml` stamp:** interface order, a missing 16001, a version not stamped or keeping its `v`, `GuildOS.VERSION` not stamped or losing its comment, a silent stamp.
  - **Store flow:** `release.yml` reading beta tags or running on tags, `publish.yml` running on tags or losing its flavour, the committed TOC listing Forever.
  - **Zip:** a renamed zip, shipped harnesses.
  - **README:** each required item removed.
- Still passing: every Lua harness. `luacheck` is clean apart from the known `Inbox.lua:5` warning.
- **Manual, needs the maintainer** (pushing a tag publishes):
  1. Push `vX.Y.Z-beta.1`.
  2. Confirm one pre-release with one zip appears, no store upload runs, and `main` gets no commit.
  3. Install the zip on Anniversary and confirm it loads with no out-of-date warning.

## 4. Tasks
- [x] `.github/workflows/beta.yml`
- [x] README section "Testing on the Forever beta"
- [x] `tools/beta-workflow.py`; ADR-0017
- [ ] Manual: the first beta tag, and the install check on Anniversary (maintainer)
