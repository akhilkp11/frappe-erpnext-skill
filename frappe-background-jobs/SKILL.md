---
name: frappe-background-jobs
description: Run work outside the request in Frappe - frappe.enqueue, queues (short/default/long), scheduler_events (daily/hourly/cron), Scheduled Job Type, RQ workers, retries, deduplication, progress/realtime updates, idempotent jobs, and diagnosing jobs that never run or run twice. Use for reminders, escalations, bulk processing, integrations, imports, or "scheduler not running / job stuck / duplicate emails".
---

# Background jobs and scheduler

## Choosing how to run work
| Work | Approach |
|---|---|
| Must finish before the response (small, deterministic) | Inline |
| Slow, retryable, or external call | `frappe.enqueue` |
| Time-based (daily digest, escalation) | `scheduler_events` (cron string for exact times) |
| Triggered by a document event | enqueue from the hook, after commit |

## Enqueue
```python
frappe.enqueue(
    "my_app.tasks.sync_invoice",       # dotted path string is safest across versions
    queue="long",                      # short | default | long; pick by expected duration
    timeout=1800,
    enqueue_after_commit=True,         # do not start before the triggering transaction is committed
    job_id=f"sync-invoice-{name}", deduplicate=True,   # supported in current versions; verify in installed source
    invoice=name,                      # kwargs for the function
)
```
- Without `enqueue_after_commit`, a worker may start before the row exists or after a rollback.
- Pass identifiers, not documents; reload inside the job so it works with current data.
- `frappe.enqueue_doc("DocType", name, "method", **kwargs)` runs a controller method.
- In tests and with `now=True` jobs run synchronously; do not rely on that behavior in production reasoning.

## Writing the job
```python
def sync_invoice(invoice):
    frappe.set_user("Administrator")          # jobs run as the user who enqueued unless you change it; choose deliberately
    doc = frappe.get_doc("Sales Invoice", invoice)
    if doc.get("custom_synced"):              # idempotency guard
        return
    try:
        push_to_service(doc)
        doc.db_set("custom_synced", 1, update_modified=False)
    except Exception:
        frappe.log_error(title=f"Sync failed: {invoice}", message=frappe.get_traceback())
        raise                                 # let RQ record the failure
```
Design for at-least-once: a job may run twice (retry, duplicate enqueue, worker restart). Use natural idempotency keys, check-before-write, and unique indexes. For large loops, process in batches and `frappe.db.commit()` per batch inside the job (acceptable here, not in request handlers); make the batch resumable.

Progress: `frappe.publish_progress(percent, title=..., description=...)` or `frappe.publish_realtime` for UI updates.

## Scheduler
```python
scheduler_events = {
    "all": [],                                   # every tick; avoid
    "hourly": ["my_app.tasks.hourly"],
    "daily": ["my_app.tasks.send_overdue_reminders"],
    "daily_long": ["my_app.tasks.rebuild_cache"],   # long queue for heavy daily work
    "cron": {"30 8 * * 1-5": ["my_app.tasks.weekday_digest"]},
}
```
After changing scheduler hooks run `bench --site SITE migrate` (registers Scheduled Job Types) or equivalent sync. Job time is in the **system timezone** of the site; be explicit when computing "today" (`frappe.utils.nowdate()`, `getdate`) and test month/day boundaries.

Escalations/reminders must record what was already sent (a level, timestamp, or log row) so reruns and backfills do not resend. Check workflow state and the `docstatus`/status before acting.

## Diagnosing
Read-only first:
- `bench --site SITE scheduler status` and `bench doctor` (scheduler enabled? workers alive? queue lengths?).
- Desk: Scheduled Job Log, Error Log, RQ Job / Background Jobs page.
- Logs: `logs/worker.log`, `logs/worker.error.log`, `logs/scheduler.log` (names can vary; list `logs/`).
- Site config: `pause_scheduler`, `maintenance_mode` stop jobs; `bench --site SITE enable-scheduler` re-enables (changes state; confirm first).
- Production: workers are Supervisor/systemd processes per queue; a missing `long` worker means long jobs never run. Check `supervisorctl status` (see `frappe-devops`).
- Jobs "stuck": expired timeouts, killed workers, Redis queue backlog, or an exception swallowed by `except: pass`.

## Review checklist
Right queue and timeout? `enqueue_after_commit`? Idempotent? Retries safe? Errors logged with context? Does it run as the intended user? Does it avoid loading unbounded rows? Is there a way to rerun for one record?
