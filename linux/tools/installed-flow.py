#!/usr/bin/env python3
"""Take on a rule with the installed helper, keep it, and restore the backup.

The record is written only under the two absolute data directories passed in.
Nothing in the package payload is changed.
"""

import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys


def conversation(helper, environment):
    process = subprocess.Popen(
        [helper, "--normal"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, env=environment,
    )
    next_id = 0

    def ask(operation, **fields):
        nonlocal next_id
        next_id += 1
        request = {"v": 1, "id": next_id, "op": operation, **fields}
        process.stdin.write(json.dumps(request) + "\n")
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise SystemExit(f"helper ended during {operation}: {process.stderr.read()}")
        response = json.loads(line)
        if response.get("ok") is False:
            raise SystemExit(f"{operation} failed: {response}")
        if response.get("v") != 1 or response.get("id") != next_id:
            raise SystemExit(f"unexpected reply: {response}")
        return response

    return process, ask


def close(process):
    process.stdin.close()
    code = process.wait(timeout=5)
    if code != 0:
        raise SystemExit(f"helper exit {code}: {process.stderr.read()}")


def occurrence(directory, rule_id):
    database = Path(directory) / "Chotki" / "chotki.sqlite"
    connection = sqlite3.connect(database)
    row = connection.execute(
        "select date, status, completed_at from occurrence where rule_id = ?",
        (rule_id,),
    ).fetchone()
    connection.close()
    return database, row


def main():
    if len(sys.argv) != 4:
        raise SystemExit(
            "Usage: installed-flow.py /path/to/ChotkiLinuxBridge origin-data restore-data"
        )
    helper, origin, restore = sys.argv[1:]
    origin = str(Path(origin).resolve())
    restore = str(Path(restore).resolve())
    if not origin.startswith("/") or not restore.startswith("/"):
        raise SystemExit("data directories must be absolute")
    Path(origin).mkdir(parents=True, exist_ok=True)
    Path(restore).mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment["XDG_DATA_HOME"] = origin
    environment.pop("CHOTKI_LINUX_REVIEW_DIR", None)
    swift_libs = str(Path(helper).resolve().parent / "swift")
    if Path(swift_libs).is_dir():
        previous = environment.get("LD_LIBRARY_PATH", "")
        environment["LD_LIBRARY_PATH"] = swift_libs if not previous else f"{swift_libs}:{previous}"

    process, ask = conversation(helper, environment)
    version = ask("settings")["settings"]["version"]
    expected = os.environ.get("CHOTKI_EXPECT_VERSION", "")
    if expected and version != expected:
        raise SystemExit(f"version {version!r} != {expected!r}")
    ask("prepareTemplate", template="morning-prayers")
    saved = ask("saveRule", hasTime=True, hour=7, minute=0)
    morning = next(item for item in saved["entries"] if item["title"] == "Morning prayers")
    rule_id = morning["id"]
    ask("toggleKept", ruleID=rule_id)
    backup = str(Path(origin) / "backup.json")
    ask("exportBackup", path=backup)
    close(process)

    database, row = occurrence(origin, rule_id)
    if row is None or row[1] != "completed" or not row[2]:
        raise SystemExit(f"origin occurrence missing: {row}")

    restored_env = environment.copy()
    restored_env["XDG_DATA_HOME"] = restore
    process, ask = conversation(helper, restored_env)
    merged = ask("importBackup", path=backup)
    titles = [item["title"] for item in merged["entries"]]
    if titles.count("Morning prayers") != 1:
        raise SystemExit(f"restored titles: {titles}")
    close(process)
    _, restored_row = occurrence(restore, rule_id)
    if restored_row is None or restored_row[1] != "completed" or restored_row[0] != row[0]:
        raise SystemExit(f"restored occurrence: {restored_row}")

    digest = hashlib.sha256(database.read_bytes()).hexdigest()
    print(f"record {database}")
    print(f"sha256 {digest}")
    print(f"rule {rule_id}")
    print(f"date {row[0]}")
    print(f"version {version}")


if __name__ == "__main__":
    main()
