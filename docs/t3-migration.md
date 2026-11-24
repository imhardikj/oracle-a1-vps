# Bringing T3 Code thread history from another machine

Goal: read old threads on the new VM. Not goal: resuming old provider sessions. Threads arrive as read-only history;
start a new thread (and let the agent read the old one) to continue work.

Tested once, between two Linux VMs on the same T3 nightly build (database schema must match, or the target be newer).

## What carries over and what does not

| Carries over | Does not |
|---|---|
| Threads, messages, runs, plans, checkpoints (`~/.t3/userdata/statev2.sqlite`) | Provider sessions (`~/.codex`, `~/.claude`, ...), so no resume |
| Projects (paths rewritten) | Worktrees, T3 `secrets/`, provider logins |
| Settled / archived / deleted flags | Anything created on the old machine after the snapshot |

The new machine gets its **own environment id**, so a client app shows old and new as two environments. Threads appear
once under each until you remove the old environment from the app.

## Procedure

1. Settle the threads you care about on the old machine. Soft-deleted threads stay hidden.
2. On the old machine take a consistent snapshot (do **not** `cp` a live database; it uses WAL):

   ```bash
   python3 -c "import sqlite3; s=sqlite3.connect('file:$HOME/.t3/userdata/statev2.sqlite?mode=ro',uri=True); d=sqlite3.connect('snapshot.sqlite'); s.backup(d)"
   ```
3. Copy `snapshot.sqlite` to the new machine and run `scripts/t3-import-db.py snapshot.sqlite /home/OLD /home/NEW`.
4. Put it at `~/.t3/userdata/statev2.sqlite` **before** T3 has ever started there (or with the service stopped).
5. Install and start T3: `t3 up --lan --no-connect` (tailnet access with pairing codes; add `--connect` for T3 Connect).
   Optional, for a browser-friendly HTTPS address on the tailnet (needs "HTTPS Certificates" enabled in the Tailscale
   admin console, and the login user allowed to manage Tailscale Serve):

   ```bash
   sudo tailscale set --operator=$USER
   t3 pair --tailscale --ttl 2m --label serve-setup   # configures Tailscale Serve; persists across restarts
   # -> https://<machine>.<tailnet>.ts.net/  (tailnet only; the pairing code is still the lock)
   ```

   Primary/backup routes are a client-side choice: T3 Connect (`t3 up --connect`, needs a one-time sign-in) as the
   primary route, and the tailnet HTTPS address as the second route in the app.
6. Check: no failed effects at startup, then `t3 thread list --project <path>`.
7. **Do not log in to any provider (claude, codex, ...) before step 6 is clean** (see below).
8. Pair a client: `t3 pair --label <name>` on the VM, then add the environment in the app (`http://<tailnet-name>:3773`).

## The hazard this guards against

A snapshot taken while a conversation is running contains an unfinished background effect ("continue this run"). When
T3 starts on the new machine it retries it; once a provider is logged in there, that would start a **duplicate turn of
that conversation**, acting on the new machine. `t3-import-db.py` deletes unfinished effects from the copy. On first
start, T3 also cancels the interrupted run and queues a *new* continuation. If startup logs "Orchestration effect
execution failed", stop the service, delete rows where `status <> 'succeeded'` in `orchestration_v2_effect_outbox`, start
again, and confirm the log is clean before logging in to any provider.
