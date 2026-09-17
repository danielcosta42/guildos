"""Beta build (issue #11): the workflow that turns a vX.Y.Z-beta.N tag into a GitHub
pre-release, checked against the store flow it has to stay out of.

The three workflows are parsed as YAML. The beta job's stamp step runs for real, under
bash, on LF copies of GuildOS.toc and Core/Config.lua committed in a temporary git
repository (what a CI checkout has); its release step runs against a stub gh. The
README section and .pkgmeta are checked for what testers and the zip rely on.

    python tools/beta-workflow.py

Needs PyYAML, bash and git. Exits 1 on the first failed check.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
check([s.get("name") for s in job["steps"]] == ["Checkout", "Stamp the beta version and interfaces",
      "Package without uploading anywhere", "Create the GitHub pre-release"],
      "the steps run in this order: checkout, stamp, package, release")
for s in job["steps"]:
    check(set(s) <= {"name", "uses", "with", "run", "env"},
          "step %r has no condition, shell, working directory or error override" % s.get("name"))
check(job["steps"][0] == {"name": "Checkout", "uses": "actions/checkout@v4",
                          "with": {"fetch-depth": 0, "persist-credentials": False}},
      "the checkout is the tagged commit, in the workspace root, with its history, and stores no token in .git/config")
packager = step(job, "Package without uploading anywhere")
check(packager and packager.get("uses") == "BigWigsMods/packager@6d50adb6e8517eefef63f4afb16a6518166a6b28"
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
stamp = step(job, "Stamp the beta version and interfaces")
check(stamp is not None and "run" in stamp, "the beta job stamps the version and interfaces")
toc_before = read("GuildOS.toc")
config_before = read("Core", "Config.lua")
ANNIVERSARY = toc_before.split("\n", 1)[0]  # the committed interface line, "## Interface: 20506" today
check(re.fullmatch(r"## Interface: 205\d\d", ANNIVERSARY) is not None,
      "the committed TOC declares one interface, Anniversary's: %s" % ANNIVERSARY)
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
    check([a for _, a in changed] == [ANNIVERSARY + ", 16000, 16001", "## Version: " + version],
          "%s: the zip's TOC lists Anniversary first, then 16000 and 16001, and carries the tag's version: %r"
          % (tag, changed))
    check(changed[0][0] == ANNIVERSARY and changed[1][0].startswith("## Version: "),
          "%s: only the interface and version lines change" % tag)
    cb, ca = config_before.split("\n"), config_after.split("\n")
    cchanged = [(b, a) for b, a in zip(cb, ca) if b != a]
    check(len(cb) == len(ca) and len(cchanged) == 1 and cchanged[0][0].startswith("GuildOS.VERSION")
          and ('"%s"' % version) in cchanged[0][1]
          and cchanged[0][1].endswith("-- kept in sync with GuildOS.toc by the release workflow"),
          "%s: GuildOS.VERSION takes the tag's version, so /guildos probe records the beta build; its comment stays"
          % tag)
    check("16000" in done.stdout and version in done.stdout, "%s: the step prints what it stamped" % tag)

    ran, calls = run_release(tag, 0)
    check(ran.returncode == 0, "%s: the release step runs cleanly: %s" % (tag, ran.stderr.strip()))
    check(calls == [["release", "create", tag, ".release/GuildOS-%s.zip" % tag, "--prerelease",
                     "--title", "GuildOS %s (WoW: Forever beta)" % tag, "--notes", NOTES]],
          "%s: gh is called once, to create a pre-release for the tag with its one zip, titled and noted: %r"
          % (tag, calls))
    failed, _ = run_release(tag, 1)
    check(failed.returncode != 0,
          "%s: a failing gh release create fails the step, so the job never goes green without a release" % tag)

# A client patch bumps Anniversary's interface in the committed TOC: the beta zip has to follow it.
done, toc_after, _ = run_stamp("v0.54.0-beta.1", toc_before.replace(ANNIVERSARY, "## Interface: 20599", 1))
check(done.returncode == 0 and toc_after.split("\n", 1)[0] == "## Interface: 20599, 16000, 16001",
      "the stamp keeps whatever Anniversary interface the committed TOC has, so a patch bump reaches the beta zip")
# An interface line the stamp cannot extend fails the step, rather than shipping a zip without Forever's interfaces.
for line in ("## Interface: 20506, 20507", "## Interface: 20506 "):
    done, _, _ = run_stamp("v0.54.0-beta.1", toc_before.replace(ANNIVERSARY, line, 1))
    check(done.returncode != 0, "a committed %r fails the stamp step instead of shipping without 16000, 16001" % line)

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
check("args: -g bcc" in pub_text, "and still publishes the Anniversary flavour")

# ── The zip and the README ──────────────────────────────────────────────
pkgmeta = yaml.safe_load(read(".pkgmeta"))
check(pkgmeta.get("package-as") == "GuildOS", "the packager names the zip GuildOS-<tag>.zip, as the release step expects")
check(pkgmeta.get("enable-nolib-creation") is False, "and makes one zip only, so the pre-release gets exactly one")
for kept_out in ("tools", ".github", "*.md"):
    check(kept_out in pkgmeta.get("ignore", []), "the zip leaves out %s" % kept_out)

readme = read("README.md")
headings = re.findall(r"^## (.+)$", readme, re.M)
check("Testing on the Forever beta" in headings, "README has a Testing on the Forever beta section")
check(headings.index("Testing on the Forever beta") == headings.index("Installation") + 1,
      "right after Installation")
section = readme.split("## Testing on the Forever beta", 1)[1].split("\n## ", 1)[0]
for needle, what in (
    # How the beta build ships is not decided yet (2026-09-17): the stores if they add a Forever flavour,
    # a direct download if not. The section says so rather than promising either.
    ("is not settled yet", "that the distribution is not decided yet"),
    ("CurseForge and Wago", "the stores it ships through if they add Forever"),
    ("direct download", "the fallback when they don't"),
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
