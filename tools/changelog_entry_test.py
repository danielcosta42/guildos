"""The release's changelog entry in English (issue #272).

The commits are written in Portuguese and the entry was made of their subjects, so every changelog
on CurseForge and Wago came out in Portuguese. A commit now carries its line for the changelog in
English in a `Changelog:` trailer; without one, the subject is used, as before.

    python tools/changelog_entry_test.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import changelog_entry as ce  # noqa: E402


def commit(subject, body=""):
    return (subject, body)


class EntryTest(unittest.TestCase):
    def test_english_trailer_wins_over_the_portuguese_subject(self):
        out = ce.build_entry("1.11.0", "2026-11-08", [
            commit("feat: o oficial é chamado no chat (#266)",
                   "Longer text in Portuguese.\n\nChangelog: Officers get an alert when someone calls them in guild chat (#266)"),
        ])
        self.assertIn("### Added\n- Officers get an alert when someone calls them in guild chat (#266)", out)
        self.assertNotIn("oficial", out)

    def test_without_a_trailer_the_subject_stays(self):
        out = ce.build_entry("1.11.0", "2026-11-08", [commit("fix: o minimapa (#271)")])
        self.assertIn("### Fixed\n- o minimapa (#271)", out)

    def test_categories_and_header(self):
        out = ce.build_entry("1.11.0", "2026-11-08", [
            commit("feat: a", "Changelog: A"),
            commit("fix: b", "Changelog: B"),
            commit("refactor: c", "Changelog: C"),
            commit("something else"),
        ])
        self.assertTrue(out.startswith("## [1.11.0] - 2026-11-08"))
        self.assertLess(out.index("### Added"), out.index("### Fixed"))
        self.assertLess(out.index("### Fixed"), out.index("### Changed"))
        self.assertIn("### Other\n- something else", out)

    def test_housekeeping_is_left_out(self):
        out = ce.build_entry("1.11.0", "2026-11-08", [
            commit("chore: bump version to 1.10.0 [skip ci]"),
            commit("Merge pull request #264 from x/y"),
            commit("docs: o manual"),
            commit("test: um harness"),
            commit("ci: o workflow"),
            commit("fix: real", "Changelog: Real"),
        ])
        self.assertNotIn("bump", out)
        self.assertNotIn("Merge", out)
        self.assertNotIn("manual", out)
        self.assertIn("- Real", out)

    def test_every_trailer_is_a_line_and_case_does_not_matter(self):
        body = "changelog: First change\nCo-authored-by: someone\nChangelog: Second change"
        self.assertEqual(ce.english_lines("fix: x", body), ["First change", "Second change"])
        out = ce.build_entry("1.11.0", "2026-11-08", [commit("fix: várias coisas", body)])
        self.assertIn("### Fixed\n- First change\n- Second change", out)

    def test_a_trailer_inside_a_sentence_is_not_one(self):
        self.assertEqual(ce.english_lines("fix: x", "the Changelog: line is new"), ["x"])

    def test_breaking_feature_is_still_added(self):
        out = ce.build_entry("2.0.0", "2026-11-08", [commit("feat!: muda tudo", "Changelog: Everything changes")])
        self.assertIn("### Added\n- Everything changes", out)

    def test_parse_git_log_records(self):
        raw = "feat: a\x1fbody one\nChangelog: A\x1e\nfix: b\x1f\x1e\n"
        self.assertEqual(ce.parse_log(raw), [("feat: a", "body one\nChangelog: A"), ("fix: b", "")])


if __name__ == "__main__":
    unittest.main()
