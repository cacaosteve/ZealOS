#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src_dir=$(CDPATH= cd -- "$script_dir/../src" && pwd)

python3 - "$src_dir/Misc/OSInstall.ZC" "$src_dir/Misc/Auto/AutoInstall.ZC" <<'PY'
import pathlib
import re
import sys

failed = []

for filename in sys.argv[1:]:
    path = pathlib.Path(filename)
    source = path.read_text(encoding="ascii")
    match = re.search(
        r"Bool\s+VMPartDisk\([^)]*\)\s*\{(.*?)\n\}\n\nU0\s+VMInstallDrive",
        source,
        re.DOTALL,
    )
    if match is None:
        failed.append(f"{path}: VMPartDisk function not found")
        continue

    body = match.group(1)
    submit = body.find("XTalkWait(task")
    wait = body.find("TaskWait(task, TRUE);", submit)
    success = body.find("return TRUE;", submit)

    if submit < 0 or success < 0 or not submit < wait < success:
        failed.append(
            f"{path}: VMPartDisk must wait for the command-line prompt "
            "after submitting DiskPart"
        )

if failed:
    for failure in failed:
        print(f"FAIL: {failure}", file=sys.stderr)
    raise SystemExit(1)

print("OK: VM installers wait for DiskPart to finish before copying files")
PY
