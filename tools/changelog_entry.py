"""The changelog entry of a release, from the commits since the last tag (issue #272).

Commits are written in Portuguese; the stores' readers are not. A commit carries its changelog line in
English in `Changelog:` trailers at the start of body lines, each one a line of the entry; a commit without
one keeps its subject, as the entry always did. Housekeeping (version bumps, merges, chore/ci/docs/test)
is left out.

    python3 tools/changelog_entry.py <version> [<since tag>]

prints the entry. release.yml prepends it to CHANGELOG.md and writes it alone to RELEASE_NOTES.md,
which is what CurseForge and Wago show. Tested by tools/changelog_entry_test.py.
"""
import datetime
import re
import subprocess
import sys

TRAILER = re.compile(r"^changelog:\s*(.+?)\s*$", re.IGNORECASE)
TYPE = re.compile(r"^(\w+)(\([^)]*\))?(!)?:\s*")
SKIP = re.compile(r"^\s*(chore: bump version|Merge)")
QUIET = {"chore", "ci", "docs", "test"}
SECTIONS = [("Added", {"feat"}), ("Fixed", {"fix"}), ("Changed", {"refactor", "perf", "style"})]


def english_lines(subject, body):
    """Every `Changelog:` trailer's text, one line each (a commit may close several issues), else
    the subject without its type."""
    lines, said = [], False
    for row in (body or "").splitlines():
        m = TRAILER.match(row.strip())
        if m:
            said = True
            # `Changelog: none`: nothing for the players, e.g. a fix to code not released yet.
            if m.group(1).lower() not in ("none", "-"):
                lines.append(m.group(1))
    if said:
        return lines
    return [TYPE.sub("", subject, count=1)]


def build_entry(version, date, commits):
    """commits: [(subject, body)]. The markdown entry, sections in a fixed order."""
    groups = {name: [] for name, _ in SECTIONS}
    other = []
    for subject, body in commits:
        if not subject or SKIP.match(subject):
            continue
        m = TYPE.match(subject)
        kind = m.group(1).lower() if m else None
        if kind in QUIET:
            continue
        for name, kinds in SECTIONS:
            if kind in kinds:
                groups[name].extend(english_lines(subject, body))
                break
        else:
            other.extend(english_lines(subject, body))
    out = "## [%s] - %s" % (version, date)
    for name, _ in SECTIONS:
        if groups[name]:
            out += "\n\n### %s\n" % name + "\n".join("- " + line for line in groups[name])
    if other:
        out += "\n\n### Other\n" + "\n".join("- " + line for line in other)
    return out


def parse_log(raw):
    """`git log --pretty=format:%s%x1f%b%x1e` into [(subject, body)]."""
    out = []
    for record in raw.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        subject, _, body = record.partition("\x1f")
        out.append((subject.strip(), body.strip()))
    return out


def main(argv):
    # CI's lint runs every tools/*.py with no arguments, and a failure there stops the release.
    if len(argv) < 2:
        print("usage: python3 tools/changelog_entry.py <version> [<since tag>]")
        return
    version = argv[1]
    since = argv[2] if len(argv) > 2 and argv[2] else None
    rng = ["%s..HEAD" % since] if since else []
    raw = subprocess.run(["git", "log", *rng, "--pretty=format:%s%x1f%b%x1e"],
                         check=True, capture_output=True, text=True, encoding="utf-8").stdout
    print(build_entry(version, datetime.date.today().isoformat(), parse_log(raw)))


if __name__ == "__main__":
    main(sys.argv)
