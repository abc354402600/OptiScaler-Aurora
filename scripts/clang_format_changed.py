"""Read-only clang-format check of changed lines, without historical tree-wide debt.

PR: merge base to head. Push: before to after. New branch: default branch merge
base to head. Renames are new files; deletion-only hunks contain no new code.
Format the full file, but fail only replacements touching added/modified lines.
"""
import argparse
import bisect
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def git(*args, data=None):
    return subprocess.run(["git", *args], input=data, check=True, stdout=subprocess.PIPE).stdout


def commit(ref):
    return git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}").decode().strip()


def event_base(event, head):
    if "pull_request" in event:
        base = commit(event["pull_request"]["base"]["sha"])
        return git("merge-base", base, head).decode().strip()
    before = event.get("before", "")
    if before and before != "0" * 40:
        return commit(before)
    default = event.get("repository", {}).get("default_branch")
    if default:
        base = commit("refs/remotes/origin/" + default)
        return git("merge-base", base, head).decode().strip()
    raise ValueError("No comparison base: use --base explicitly outside GitHub Actions")


def eligible(name):
    path = PurePosixPath(name)
    return (path.parts[0] == "OptiScaler" and "external" not in path.parts
            and path.parts[:2] != ("OptiScaler", "include")
            and path.suffix.lower() in {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"})


def changed_ranges(diff):
    ranges = []
    for line in diff.splitlines():
        match = re.match(rb"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if match:
            start = int(match[1])
            count = int(match[2]) if match[2] is not None else 1
            if count:
                ranges.append((start, start + count - 1))
    return ranges


def violations(source, xml, ranges):
    root = ET.fromstring(xml)
    if root.get("incomplete_format") == "true":
        raise ValueError("clang-format could not completely parse the file")
    starts = [0] + [i + 1 for i, char in enumerate(source) if char == 10]
    result = []
    for item in root.findall("replacement"):
        offset, length = int(item.attrib["offset"]), int(item.attrib["length"])
        if offset < 0 or length < 0 or offset + length > len(source):
            raise ValueError("Invalid formatter replacement range")
        first = bisect.bisect_right(starts, offset)
        last = bisect.bisect_right(starts, offset + max(0, length - 1))
        if any(first <= end and last >= start for start, end in ranges):
            result.append(first)
    return sorted(set(result))


def check(base, head, formatter):
    names = git("diff", "--no-renames", "--name-only", "--diff-filter=AM", "-z", base, head, "--")
    failures = 0
    checked = 0
    for raw in names.split(b"\0"):
        if not raw:
            continue
        name = os.fsdecode(raw)
        if not eligible(name):
            continue
        diff = git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--unified=0", base, head, "--", name)
        ranges = changed_ranges(diff)
        if not ranges:
            continue
        source = git("show", head + ":" + name)
        output = subprocess.run([formatter, "--style=file", "--fallback-style=none",
                                 "--assume-filename=" + name, "--output-replacements-xml"],
                                input=source, check=True, stdout=subprocess.PIPE).stdout
        checked += 1
        for line in violations(source, output, ranges):
            # repr prevents filenames with control characters from injecting CI commands.
            print(f"{name!r}:{line}: formatting change required on edited lines")
            failures += 1
    print(f"Checked {checked} changed C/C++ files; {failures} edited-line violations")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--formatter", default="clang-format")
    args = parser.parse_args()
    head = commit(args.head)
    if args.base:
        base = commit(args.base)
    else:
        event_path = os.environ.get("GITHUB_EVENT_PATH")
        event = json.loads(Path(event_path).read_text(encoding="utf-8")) if event_path else {}
        base = event_base(event, head)
    return check(base, head, args.formatter)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        print(f"Formatting check failed: {error}", file=sys.stderr)
        sys.exit(2)
