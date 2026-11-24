#!/usr/bin/env python3
"""Prepare a T3 Code database snapshot from another machine for first start here.

    python3 t3-import-db.py DB OLD_HOME NEW_HOME

Run it on a COPY of the old statev2.sqlite while T3 is NOT running against it.
Take the copy on the old machine with SQLite's backup API (not `cp`), e.g.:

    python3 -c "import sqlite3; s=sqlite3.connect('file:OLD/.t3/userdata/statev2.sqlite?mode=ro',uri=True); \
d=sqlite3.connect('snapshot.sqlite'); s.backup(d)"

What it changes (and nothing else):
  1. Drops unfinished background effects. A snapshot taken mid-conversation carries a pending
     "continue this run" effect; the new server would try to run it, i.e. start a duplicate turn
     of that conversation as soon as a provider is logged in here.
  2. Rewrites project workspace paths OLD_HOME -> NEW_HOME so projects point at this machine's clones.

Threads, messages and history are untouched. Provider sessions are not carried over, so old threads are
read-only history; start a new thread to continue work.
"""
import sqlite3
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    path, old, new = sys.argv[1:]
    c = sqlite3.connect(path)
    if c.execute("pragma integrity_check").fetchone()[0] != "ok":
        print("integrity check failed; refusing to continue")
        return 1

    n = c.execute("delete from orchestration_v2_effect_outbox where status <> 'succeeded'").rowcount
    print(f"removed {n} unfinished effect(s)")

    n = c.execute(
        "update projection_projects set workspace_root = replace(workspace_root, ?, ?), "
        "tracked_folders_json = replace(tracked_folders_json, ?, ?) "
        "where workspace_root like ? || '%' or tracked_folders_json like '%' || ? || '%'",
        (old, new, old, new, old, old),
    ).rowcount
    print(f"rewrote paths on {n} project row(s)")
    c.commit()

    live = c.execute("select count(*) from orchestration_v2_projection_threads where deleted_at is null").fetchone()[0]
    print(f"live threads: {live}")
    c.execute("pragma wal_checkpoint(TRUNCATE)")
    c.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
