import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "clang_format_changed.py"
spec = importlib.util.spec_from_file_location("checker", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class SelectionTests(unittest.TestCase):
    def test_scope(self):
        for name in ("OptiScaler/a.cpp", "OptiScaler/space name/中文.HPP"):
            self.assertTrue(checker.eligible(name))
        for name in ("dist/a.cpp", "OptiScaler/include/a.h", "OptiScaler/external/a.c", "OptiScaler/a.ps1"):
            self.assertFalse(checker.eligible(name))

    def test_hunks(self):
        self.assertEqual(checker.changed_ranges(b"@@ -1,2 +1,0 @@\n@@ -9 +8,2 @@\n@@ -20 +20 @@"), [(8, 9), (20, 20)])

    def test_utf8_offsets_and_insertions(self):
        data = "// 中文\nint a;\nint b;\n".encode()
        xml = f'<replacements><replacement offset="{data.index(b"int b")}" length="0"> </replacement></replacements>'
        self.assertEqual(checker.violations(data, xml, [(2, 2)]), [])
        self.assertEqual(checker.violations(data, xml, [(3, 3)]), [3])

    def test_bad_formatter_output(self):
        for xml in ('<replacements incomplete_format="true"/>', '<replacements><replacement offset="999" length="1"/></replacements>'):
            with self.assertRaises(ValueError):
                checker.violations(b"x", xml, [(1, 1)])

    def test_event_selection(self):
        with patch.object(checker, "commit", side_effect=lambda x: x), patch.object(checker, "git", return_value=b"mergebase\n") as run:
            self.assertEqual(checker.event_base({"before": "old"}, "new"), "old")
            self.assertEqual(checker.event_base({"pull_request": {"base": {"sha": "base"}}}, "new"), "mergebase")
            self.assertEqual(checker.event_base({"before": "0" * 40, "repository": {"default_branch": "main"}}, "new"), "mergebase")
            run.assert_called_with("merge-base", "refs/remotes/origin/main", "new")
        with self.assertRaises(ValueError):
            checker.event_base({}, "new")


class RealFormatterTests(unittest.TestCase):
    def test_committed_changes(self):
        formatter = os.environ.get("AURORA_CLANG_FORMAT") or shutil.which("clang-format")
        self.assertIsNotNone(formatter, "Install pinned clang-format 20.1.8 to run integration tests")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root).decode().strip()
            def write(name, text):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            def save():
                git("add", ".")
                git("-c", "user.name=Fixture", "-c", "user.email=fixture@invalid", "commit", "-qm", "fixture")
                return git("rev-parse", "HEAD")
            def check(base):
                return subprocess.run([os.sys.executable, str(SCRIPT), "--base", base, "--formatter", formatter], cwd=root, capture_output=True).returncode
            git("init", "-q")
            write(".clang-format", "BasedOnStyle: LLVM\n")
            name = "OptiScaler/space 中文.cpp"
            write(name, "int  old_bad;\n" + "// spacer\n" * 10 + "int clean;\n")
            base = save()
            write(name, "int  old_bad;\n" + "// spacer\n" * 10 + "int changed;\n")
            clean = save()
            self.assertEqual(check(base), 0, "Inherited debt outside changed lines is ignored")
            write(name, "int  old_bad;\n" + "// spacer\n" * 10 + "int  changed_bad;\n")
            bad = save()
            self.assertEqual(check(clean), 1, "New violation must fail")
            write("notes.txt", "installer-only change")
            save()
            self.assertEqual(check(bad), 0, "No C++ edits must pass despite existing debt")
            before_delete = git("rev-parse", "HEAD")
            (root / name).unlink()
            save()
            self.assertEqual(check(before_delete), 0, "Deleted files are not formatted")
            before_new = git("rev-parse", "HEAD")
            write("OptiScaler/new.cpp", "int  new_bad;\n")
            save()
            self.assertEqual(check(before_new), 1, "Entire new file is checked")
            self.assertEqual(check("not-a-real-ref"), 2, "Missing base cannot silently pass")


if __name__ == "__main__":
    unittest.main()
