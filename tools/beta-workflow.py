"""Beta build (issue #11): the workflow that turns a vX.Y.Z-beta.N tag into a GitHub
pre-release, checked against the store flow it has to stay out of.

The three workflows are parsed as YAML. The beta job's stamp step runs for real, under
bash, on LF copies of GuildOS.toc and Core/Config.lua committed in a temporary git
repository (what a CI checkout has); its release step runs against a stub gh. The
README section and .pkgmeta are checked for what testers and the zip rely on.

The stable GitHub Release that the desktop companion installs from (the site's specs/070)
lives in publish.yml beside the store upload, so it is checked here as well: its step runs
for real against real zips and the same stub gh, and the store job has to come out of it
exactly as it went in.

    python tools/beta-workflow.py

Needs PyYAML, bash, git and unzip. Exits 1 on the first failed check.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The packager both workflows pin, by commit and not by tag: this is third-party code that runs with
# the store keys in publish.yml. The commit is what `v2` points at, and the first one that knows the
# forever flavour — the one before it called interface 16001 retail (#20).
PIN = "e50a250f8705041e40f2fa1ddcb280a686d65aa0"
checks = 0


def check(cond, what):
    global checks
    checks += 1
    if not cond:
        sys.stderr.write("FAIL: %s\n" % what)
        sys.exit(1)


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as fh:
        return fh.read().replace("\r\n", "\n")


def workflow(name):
    text = read(".github", "workflows", name)
    data = yaml.safe_load(text)
    # YAML 1.1 reads the bare key `on` as the boolean true.
    data["on"] = data.pop(True, data.get("on"))
    return text, data


def github_glob(pattern, ref):
    # GitHub filter patterns: * is any run of characters except '/'; the rest is literal here.
    rx = "^" + "".join("[^/]*" if c == "*" else re.escape(c) for c in pattern) + "$"
    return re.match(rx, ref) is not None


def step(job, name):
    for s in job["steps"]:
        if s.get("name") == name:
            return s
    return None


# ── beta.yml: a beta tag, a pre-release, nothing else ────────────────────
beta_text, beta = workflow("beta.yml")
check(set(beta["on"]) == {"push"} and set(beta["on"]["push"]) == {"tags"},
      "the beta workflow runs on pushed tags only: no branches, pull requests or manual dispatch")
tags = beta["on"]["push"]["tags"]
check(tags == ["v*.*.*-beta.*"], "and only on vX.Y.Z-beta.N tags")
for ref in ("v0.54.0-beta.1", "v1.0.0-beta.12"):
    check(github_glob(tags[0], ref), "%s triggers the beta build" % ref)
for ref in ("v0.54.0", "v0.54.0-rc.1", "main", "v0.54.0-beta"):
    check(not github_glob(tags[0], ref), "%s does not trigger the beta build" % ref)
check(beta.get("permissions") == {"contents": "write"}, "it can write releases and nothing more")

check(list(beta["jobs"]) == ["beta"], "one job")
job = beta["jobs"]["beta"]
check("permissions" not in job, "which does not widen its permissions")
check(set(beta) == {"name", "on", "permissions", "jobs"}, "the workflow sets nothing else at its top level")
check(set(job) == {"name", "runs-on", "steps"}, "the job has no condition, environment or permissions of its own")
check([s.get("name") for s in job["steps"]] == ["Checkout", "Stamp the beta version",
      "Package without uploading anywhere", "Create the GitHub pre-release"],
      "the steps run in this order: checkout, stamp, package, release")
for s in job["steps"]:
    check(set(s) <= {"name", "uses", "with", "run", "env"},
          "step %r has no condition, shell, working directory or error override" % s.get("name"))
check(job["steps"][0] == {"name": "Checkout", "uses": "actions/checkout@v4",
                          "with": {"fetch-depth": 0, "persist-credentials": False}},
      "the checkout is the tagged commit, in the workspace root, with its history, and stores no token in .git/config")
packager = step(job, "Package without uploading anywhere")
check(packager and packager.get("uses") == "BigWigsMods/packager@" + PIN
      and packager.get("with") == {"args": "-d"} and "env" not in packager,
      "it packages with the BigWigs packager pinned to the commit of its v2 tag, in -d mode, with no store credentials")
release = step(job, "Create the GitHub pre-release")
run = release and release.get("run", "")
check(release and 'gh release create "$GITHUB_REF_NAME" .release/GuildOS-*.zip' in run and "--prerelease" in run
      and release.get("env") == {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}"},
      "and attaches the zip to a GitHub pre-release for the tag")
for forbidden in ("git push", "git commit", "CF_API_KEY", "WAGO_API_TOKEN", "createWorkflowDispatch", "-g bcc"):
    check(forbidden not in beta_text, "the beta workflow never uses %r" % forbidden)

# ── The stamp and release steps, run for real ───────────────────────────
# Both run under bash, as on the runner, for two tags: a value copied from one tag
# instead of read from GITHUB_REF_NAME fails on the other.
stamp = step(job, "Stamp the beta version")
check(stamp is not None and "run" in stamp, "the beta job stamps the version")
toc_before = read("GuildOS.toc")
config_before = read("Core", "Config.lua")
INTERFACES = toc_before.split("\n", 1)[0]  # "## Interface: 20506, 16001, 120105" today
# Anniversary first so it shows no out-of-date warning there, then Forever's 16001 (#20), then
# retail's (#168). All three are committed: the stamp step adds none, and what is published is read
# from this line.
check(re.fullmatch(r"## Interface: 205\d\d, 16001, 1\d{5}", INTERFACES) is not None,
      "the committed TOC declares Anniversary's interface, Forever's and retail's: %s" % INTERFACES)
bash = shutil.which("bash")
check(bash is not None, "bash is available to run the steps")
git = shutil.which("git")
check(git is not None, "git is available to build the checkout")
NOTES = ('Beta build for testing on the WoW: Forever beta. Not published to CurseForge or Wago. '
         'Install and test steps: README, "Testing on the Forever beta".')


def run_stamp(tag, toc=None):
    work = tempfile.mkdtemp(prefix="guildos-beta-")
    try:
        os.makedirs(os.path.join(work, "Core"))
        for rel, text in (("GuildOS.toc", toc or toc_before), (os.path.join("Core", "Config.lua"), config_before)):
            with open(os.path.join(work, rel), "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
        # Both files committed, as in the CI checkout, so a step that reverts them through git
        # really reverts them here and the content checks see it.
        for args in (["init", "-q"], ["config", "core.autocrlf", "false"], ["add", "-A"],
                     ["-c", "user.name=test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                      "commit", "-q", "-m", "checkout"]):
            check(subprocess.run([git] + args, cwd=work, capture_output=True).returncode == 0,
                  "the temporary checkout builds: git %s" % " ".join(args))
        done = subprocess.run([bash, "-e", "-c", stamp["run"]], cwd=work, env=dict(os.environ, GITHUB_REF_NAME=tag),
                              capture_output=True, text=True)
        with open(os.path.join(work, "GuildOS.toc"), encoding="utf-8", newline="") as fh:
            toc_after = fh.read()
        with open(os.path.join(work, "Core", "Config.lua"), encoding="utf-8", newline="") as fh:
            config_after = fh.read()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return done, toc_after, config_after


def run_release(tag, gh_exit):
    # A gh first on PATH that records every call and exits with gh_exit.
    work = tempfile.mkdtemp(prefix="guildos-release-")
    try:
        os.makedirs(os.path.join(work, ".release"))
        os.makedirs(os.path.join(work, "bin"))
        open(os.path.join(work, ".release", "GuildOS-%s.zip" % tag), "wb").close()
        log = os.path.join(work, "gh.log")
        with open(os.path.join(work, "bin", "gh"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write('#!/usr/bin/env bash\nprintf \'%s\\n\' "$@" @@ >> "$GH_LOG"\nexit "${GH_EXIT:-0}"\n')
        os.chmod(os.path.join(work, "bin", "gh"), 0o755)
        env = dict(os.environ, GITHUB_REF_NAME=tag, GH_LOG=log, GH_TOKEN="test", GH_EXIT=str(gh_exit))
        env["PATH"] = os.path.join(work, "bin") + os.pathsep + env.get("PATH", "")
        ran = subprocess.run([bash, "-e", "-c", release["run"]], cwd=work, env=env, capture_output=True, text=True)
        calls = []
        if os.path.exists(log):
            with open(log, encoding="utf-8") as fh:
                calls = [c.strip("\n").split("\n") for c in fh.read().split("@@\n") if c.strip("\n")]
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return ran, calls


for tag in ("v0.54.0-beta.1", "v1.2.3-beta.10"):
    version = tag[1:]
    done, toc_after, config_after = run_stamp(tag)
    check(done.returncode == 0, "%s: the stamp step runs cleanly: %s" % (tag, done.stderr.strip()))
    before, after = toc_before.split("\n"), toc_after.split("\n")
    check(len(before) == len(after), "%s: the stamped TOC keeps every line" % tag)
    changed = [(b, a) for b, a in zip(before, after) if b != a]
    check([a for _, a in changed] == ["## Version: " + version],
          "%s: the version is the only line the zip's TOC changes: %r" % (tag, changed))
    check(after[0] == INTERFACES, "%s: and the interfaces are the committed ones, untouched" % tag)
    cb, ca = config_before.split("\n"), config_after.split("\n")
    cchanged = [(b, a) for b, a in zip(cb, ca) if b != a]
    check(len(cb) == len(ca) and len(cchanged) == 1 and cchanged[0][0].startswith("GuildOS.VERSION")
          and ('"%s"' % version) in cchanged[0][1]
          and cchanged[0][1].endswith("-- kept in sync with GuildOS.toc by the release workflow"),
          "%s: GuildOS.VERSION takes the tag's version, so /guildos probe records the beta build; its comment stays"
          % tag)
    check("16001" in done.stdout and version in done.stdout, "%s: the step prints what it stamped" % tag)

    ran, calls = run_release(tag, 0)
    check(ran.returncode == 0, "%s: the release step runs cleanly: %s" % (tag, ran.stderr.strip()))
    check(calls == [["release", "create", tag, ".release/GuildOS-%s.zip" % tag, "--prerelease",
                     "--title", "GuildOS %s (WoW: Forever beta)" % tag, "--notes", NOTES]],
          "%s: gh is called once, to create a pre-release for the tag with its one zip, titled and noted: %r"
          % (tag, calls))
    failed, _ = run_release(tag, 1)
    check(failed.returncode != 0,
          "%s: a failing gh release create fails the step, so the job never goes green without a release" % tag)

# A client patch bumps Anniversary's interface in the committed TOC: the beta zip carries it as committed.
for bumped in ("## Interface: 20599, 16001, 120105", "## Interface: 20506, 16001, 120107", "## Interface: 20506, 16001"):
    done, toc_after, _ = run_stamp("v0.54.0-beta.1", toc_before.replace(INTERFACES, bumped, 1))
    check(done.returncode == 0 and toc_after.split("\n", 1)[0] == bumped,
          "the stamp keeps whatever interfaces the committed TOC has, so a patch bump reaches the beta zip: %s" % bumped)
# Forever's interface dropped from the committed TOC fails the step, rather than shipping a zip the beta
# client will not load — which is the one thing in this pipeline nothing else would notice.
for line in ("## Interface: 20506", "## Interface: 20506, 16000", "## Interface: 20506,16001",
             "## Interface: 20506, 120105", "## Interface: 20506, 16000, 120105"):
    done, _, _ = run_stamp("v0.54.0-beta.1", toc_before.replace(INTERFACES, line, 1))
    check(done.returncode != 0, "a committed %r fails the stamp step instead of shipping without 16001" % line)

# ── The store flow stays as it was ──────────────────────────────────────
rel_text, rel = workflow("release.yml")
check(set(rel["on"]) == {"push", "pull_request"} and set(rel["on"]["push"]) == {"branches"}
      and rel["on"]["push"]["branches"] == ["main"], "release.yml runs on main and pull requests, never on a tag")
patterns = re.findall(r"grep -E '(\^v\[0-9\]\+[^']*)'", rel_text)
check(len(patterns) == 2, "release.yml reads the latest tag in two places: the version bump and the changelog")
for p in patterns:
    check(re.match(p, "v0.54.0") and not re.match(p, "v0.54.0-beta.1"),
          "each of them sees store tags and skips beta tags (%s)" % p)
latest = re.findall(r"LATEST=(\S.*)", rel_text)
check(len(latest) == 3, "release.yml sets the latest tag in three places: two lookups and the fallback")
for value in latest:
    value = value.strip()
    if value.startswith("$("):
        check("grep -E '^v[0-9]+\\.[0-9]+\\.[0-9]+$'" in value, "every latest-tag lookup skips beta tags: %s" % value)
    else:
        check(re.fullmatch(r'"v\d+\.\d+\.\d+"', value) is not None, "and the fallback is a store version: %s" % value)
check(rel_text.count("createWorkflowDispatch") == 1 and "ref: 'v${{ steps.version.outputs.next }}'" in rel_text,
      "release.yml dispatches publish.yml only for the store tag it just made")
pub_text, pub = workflow("publish.yml")
check(set(pub["on"]) == {"workflow_dispatch"}, "publish.yml runs only when dispatched")
pub_steps = pub["jobs"]["publish"]["steps"]
pub_packager = [x for x in pub_steps if str(x.get("uses", "")).startswith("BigWigsMods/packager")]
check(len(pub_packager) == 1 and pub_packager[0]["uses"] == "BigWigsMods/packager@" + PIN,
      "it publishes with the same pinned packager as the beta job, not a tag that moves under the store keys")
# No -g: the flavours come from the TOC's own interface line, so one upload is marked for both clients
# (#20). A flavour named here publishes to that one and drops the other without saying so.
check(pub_packager[0].get("with", {}).get("args", "") == "" and "-g " not in pub_text,
      "and names no flavour, so the game versions come from the TOC")
check(pub_steps[0].get("with", {}).get("persist-credentials") is False,
      "and its checkout stores no token in .git/config either")

# ── The stable GitHub Release the companion installs from ───────────────
# It must not be able to break the stores. So it is a job of its own that starts after them, and the
# store job, which is what actually ships the addon, is checked to be exactly what it was.
store = pub["jobs"]["publish"]
check(list(pub["jobs"]) == ["publish", "github-release"], "publish.yml is the store job and the GitHub Release job")
check([s.get("name") for s in store["steps"]] == ["Checkout", "Package and publish to CurseForge & Wago"],
      "the store job is the two steps it always was")
check(set(store) == {"name", "runs-on", "steps"}, "with no permissions, condition or dependency added to it")
for s, keys in zip(store["steps"], ({"name", "uses", "with"}, {"name", "uses", "with", "env"})):
    check(set(s) == keys, "step %r keeps its keys: a continue-on-error would call a failed upload a success" % s.get("name"))
check(set(pub) == {"name", "on", "jobs"}, "and no token widened over the whole workflow")
check(pub_packager[0].get("env") == {"CF_API_KEY": "${{ secrets.CF_API_KEY }}",
                                     "WAGO_API_TOKEN": "${{ secrets.WAGO_API_TOKEN }}"},
      "its upload is given the store keys it always had")

ghjob = pub["jobs"]["github-release"]
check(ghjob.get("needs") == "publish", "the GitHub Release starts after the stores, never beside them")
check(ghjob.get("permissions") == {"contents": "write"}, "and its token can write releases and nothing more")
check(ghjob.get("if") == "startsWith(github.ref, 'refs/tags/v') && !contains(github.ref_name, '-')",
      "and it is skipped for anything but a tag with no pre-release suffix: a beta never becomes the latest release")
check([s.get("name") for s in ghjob["steps"]] == ["Checkout", "Package without uploading anywhere", "Create the GitHub release"],
      "it checks out, packages and releases")
ghtext = yaml.safe_dump(ghjob)
for key in ("CF_API_KEY", "WAGO_API_TOKEN"):
    check(key not in ghtext, "the job with the write token never sees %s" % key)
check(ghjob["steps"][0].get("with", {}).get("persist-credentials") is False,
      "and keeps it out of .git/config, away from the packager")
ghpack = step(ghjob, "Package without uploading anywhere")
check(ghpack.get("uses") == "BigWigsMods/packager@" + PIN and ghpack.get("with") == {"args": "-d"} and "env" not in ghpack,
      "the same pinned packager, in -d mode, with no store credentials: nothing here can upload to a store")
ghstep = step(ghjob, "Create the GitHub release")
check(ghstep.get("env") == {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}"}, "the release step alone holds the token")
STABLE_NOTES = ("Stable build, the same version as on CurseForge and Wago. "
                "The GuildOS companion installs and updates the addon from this release.")
GOOD_ZIP = {"GuildOS/GuildOS.toc": "## Version: 1.4.0\n", "GuildOS/Core/Core.lua": "-- core\n"}


def run_stable(tag, zips, gh_exit=0):
    """The release step under bash, as on the runner, over `zips`: {file name: entries, or raw bytes}."""
    work = tempfile.mkdtemp(prefix="guildos-stable-")
    try:
        os.makedirs(os.path.join(work, ".release"))
        os.makedirs(os.path.join(work, "bin"))
        for name, content in zips.items():
            path = os.path.join(work, ".release", name)
            if isinstance(content, bytes):
                with open(path, "wb") as fh:
                    fh.write(content)
            else:
                with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
                    for entry, text in content.items():
                        z.writestr(entry, text)
        log = os.path.join(work, "gh.log")
        with open(os.path.join(work, "bin", "gh"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write('#!/usr/bin/env bash\nprintf \'%s\\n\' "$@" @@ >> "$GH_LOG"\nexit "${GH_EXIT:-0}"\n')
        os.chmod(os.path.join(work, "bin", "gh"), 0o755)
        env = dict(os.environ, GITHUB_REF_NAME=tag, GH_LOG=log, GH_TOKEN="test", GH_EXIT=str(gh_exit))
        env["PATH"] = os.path.join(work, "bin") + os.pathsep + env.get("PATH", "")
        ran = subprocess.run([bash, "-e", "-c", ghstep["run"]], cwd=work, env=env, capture_output=True, text=True)
        calls = []
        if os.path.exists(log):
            with open(log, encoding="utf-8") as fh:
                calls = [c.strip("\n").split("\n") for c in fh.read().split("@@\n") if c.strip("\n")]
        made = {}
        for name in os.listdir(work):
            if name.startswith("GuildOS-"):
                with open(os.path.join(work, name), "rb") as fh:
                    made[name] = fh.read()
        source = None
        if len(zips) == 1:
            with open(os.path.join(work, ".release", next(iter(zips))), "rb") as fh:
                source = fh.read()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return ran, calls, made, source


for tag in ("v1.4.0", "v12.30.7"):
    ran, calls, made, source = run_stable(tag, {"GuildOS-%s.zip" % tag: GOOD_ZIP})
    zip_name, sha_name = "GuildOS-%s.zip" % tag, "GuildOS-%s.zip.sha256" % tag
    check(ran.returncode == 0, "%s: the release step runs cleanly: %s" % (tag, ran.stderr.strip()))
    check(calls == [["release", "create", tag, zip_name, sha_name, "--verify-tag",
                     "--title", "GuildOS %s" % tag, "--notes", STABLE_NOTES]],
          "%s: gh creates one normal release for the tag that exists, with the two assets, named exactly: %r" % (tag, calls))
    check(set(made) == {zip_name, sha_name}, "%s: the two files are the assets, named by the tag: %r" % (tag, sorted(made)))
    check(made[zip_name] == source, "%s: the zip is the packager's, byte for byte" % tag)
    check(made[sha_name] == hashlib.sha256(source).hexdigest().encode("ascii"),
          "%s: the .sha256 is the zip's hash in hex and nothing else, no name and no newline: %r" % (tag, made[sha_name]))
    failed, _, _, _ = run_stable(tag, {"GuildOS-%s.zip" % tag: GOOD_ZIP}, gh_exit=1)
    check(failed.returncode != 0, "%s: a failing gh fails the step, so a missing release shows in the run" % tag)

# Named by the tag, whatever the packager called its file: a flavour suffix in the file name must not
# reach the asset the companion looks for.
ran, calls, made, _ = run_stable("v1.4.0", {"GuildOS-v1.4.0-forever.zip": GOOD_ZIP})
check(ran.returncode == 0 and "GuildOS-v1.4.0.zip" in calls[0] and set(made) == {"GuildOS-v1.4.0.zip", "GuildOS-v1.4.0.zip.sha256"},
      "the asset is named by the tag, not by the packager")

# Nothing goes out wrong. Each of these reaches gh not at all: the companion would refuse the zip, or a
# beta would become the latest release.
outside = dict(GOOD_ZIP, **{"Other/evil.lua": "x"})
for tag, zips, what in (
    ("v1.4.0-beta.1", {"GuildOS-v1.4.0-beta.1.zip": GOOD_ZIP}, "a beta tag"),
    ("v1.4.0-rc.1", {"GuildOS-v1.4.0-rc.1.zip": GOOD_ZIP}, "a release candidate"),
    ("main", {"GuildOS-main.zip": GOOD_ZIP}, "a branch"),
    ("v1.4", {"GuildOS-v1.4.zip": GOOD_ZIP}, "a tag that is not X.Y.Z"),
    ("v1.4.0", {}, "no zip"),
    ("v1.4.0", {"GuildOS-a.zip": GOOD_ZIP, "GuildOS-b.zip": GOOD_ZIP}, "two zips"),
    ("v1.4.0", {"GuildOS-v1.4.0.zip": b""}, "an empty file"),
    ("v1.4.0", {"GuildOS-v1.4.0.zip": b"not a zip"}, "a file that is no zip"),
    ("v1.4.0", {"GuildOS-v1.4.0.zip": outside}, "an entry outside GuildOS/"),
    ("v1.4.0", {"GuildOS-v1.4.0.zip": {"GuildOS-extra/x.lua": "x", "GuildOS/GuildOS.toc": "x"}}, "a folder that only starts like GuildOS"),
    ("v1.4.0", {"GuildOS-v1.4.0.zip": {"GuildOS.toc": "x"}}, "a zip with no GuildOS folder"),
    ("v1.4.0", {"GuildOS-v1.4.0.zip": {"GuildOS/Core/Core.lua": "x"}}, "a GuildOS folder with no TOC"),
):
    ran, calls, _, _ = run_stable(tag, zips)
    check(ran.returncode != 0 and calls == [], "%s fails the step before gh: rc=%s, calls=%r" % (what, ran.returncode, calls))

# ── The zip and the README ──────────────────────────────────────────────
pkgmeta = yaml.safe_load(read(".pkgmeta"))
check(pkgmeta.get("package-as") == "GuildOS", "the packager names the zip GuildOS-<tag>.zip, as the release step expects")
check(pkgmeta.get("enable-nolib-creation") is False, "and makes one zip only, so the pre-release gets exactly one")
for kept_out in ("tools", ".github", "*.md"):
    check(kept_out in pkgmeta.get("ignore", []), "the zip leaves out %s" % kept_out)

readme = read("README.md")
check("16001" in readme, "the README names the interface the one build carries for Forever")
headings = re.findall(r"^## (.+)$", readme, re.M)
check("Testing on the Forever beta" in headings, "README has a Testing on the Forever beta section")
check(headings.index("Testing on the Forever beta") == headings.index("Installation") + 1,
      "right after Installation")
section = readme.split("## Testing on the Forever beta", 1)[1].split("\n## ", 1)[0]
for needle, what in (
    # One build serves both clients: the stores carry it under Forever's flavour too (#20).
    ("one build for both clients", "that one build serves both clients"),
    ("CurseForge and Wago", "the stores it ships through"),
    ("pre-release", "where the builds between releases go"),
    ("discord.gg/8XA6gmNjja", "where the build is announced"),
    ("into the beta client's own `Interface/AddOns` folder, not into `_anniversary_`",
     "to install into the beta client's own AddOns folder, not Anniversary's"),
    ("Load out of date AddOns", "how to load it when the interface is newer"),
    ("/guildos probe", "how to run the probe"),
    ("/reload", "that /reload writes it to disk"),
    ("WTF/Account/<account>/SavedVariables/GuildOS.lua", "where the SavedVariables file is"),
    ("character names", "that it contains character names"),
    ("officer notes", "that it contains officer notes"),
    ("chat messages", "and chat messages"),
    ("_anniversary_", "to point the companion at the Anniversary folder first"),
):
    check(needle in section, "the section says %s" % what)
check(section.index("_anniversary_") < section.index("Install"), "the companion step comes before installing")

print("beta-workflow: %d checks passed" % checks)
