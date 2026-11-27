"""Data/ReleaseNotes.lua from a release's changelog entry: what the game's What's new shows at the first
login with that release (Modules/Onboarding.lua, O:Notes / O:NoteCards).

    python3 tools/changelog_entry.py <version> <since> | python3 tools/release_notes_lua.py <version>

writes Data/ReleaseNotes.lua. release.yml runs it next to RELEASE_NOTES.md. With no argument (CI runs every
tools/*.py so) it checks itself.
"""
import re
import sys

OUT = "Data/ReleaseNotes.lua"
HEADER = """----------------------------------------------------------------------
-- Guild OS - this release's notes, written by the release workflow (tools/release_notes_lua.py).
-- What's new opens with them at the first login with this version (Modules/Onboarding.lua).
----------------------------------------------------------------------
"""


def lua_string(text):
    out = []
    for ch in text:
        if ch in '\\"':
            out.append("\\" + ch)
        elif ch == "\n":
            out.append(" ")
        elif ord(ch) < 32:
            continue
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def note_lines(entry):
    """The entry's bullet lines, without markdown: the game draws them as they are."""
    lines = []
    for row in entry.splitlines():
        m = re.match(r"^\s*-\s+(.+?)\s*$", row)
        if not m:
            continue
        text = m.group(1).replace("`", "")
        text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
        text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
        lines.append(text)
    return lines


def render(version, entry):
    body = ",\n".join("        " + lua_string(line) for line in note_lines(entry))
    return HEADER + "GuildOS.RELEASE_NOTES = {\n    version = %s,\n    lines = {\n%s%s    },\n}\n" % (
        lua_string(version), body, "\n" if body else "")


def selftest():
    entry = "## [2.0.1] - 2026-11-28\n\n### Fixed\n- `/gos lm` reopens \"it\"\n- A [link](https://x) and **bold**\n"
    out = render("2.0.1", entry)
    assert 'version = "2.0.1"' in out, out
    assert '"/gos lm reopens \\"it\\""' in out, out
    assert '"A link and bold"' in out, out
    assert render("2.0.2", "## [2.0.2]\n").count("lines = {\n    }") == 1
    print("release_notes_lua: ok")


def main(argv):
    if len(argv) < 2:
        return selftest()
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(argv[1], sys.stdin.read()))


if __name__ == "__main__":
    main(sys.argv)
