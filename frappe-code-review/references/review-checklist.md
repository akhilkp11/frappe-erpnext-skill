# Frappe review checklist

## Data integrity
- Does any code write GL Entry / Stock Ledger Entry / Payment Ledger Entry / outstanding fields directly? (Should use supported flows.)
- Are float comparisons done with `flt(x, precision)`? Are rounding and currency (base vs transaction) handled?
- Are submitted documents changed with `db_set`/SQL? Is cancel/amend or reposting used instead?
- Hooks that create or modify other documents: can they double-fire (retry, amend, import)? Are they idempotent?
- Does a change duplicate standard calculations (taxes, totals, outstanding, valuation) instead of reusing them?

## Security
- Each `@frappe.whitelist` function: who may call it, is that checked, and does it avoid returning more than needed?
- `allow_guest`, `ignore_permissions`, `get_all` inside user-facing code: justified?
- SQL: parameterized; user-controlled `order_by`, `fields`, `filters` validated?
- HTML: any `|safe`, `innerHTML`, or `msgprint` with user data?
- Secrets: nothing in Git, fixtures, logs, or error text; Password fields used.

## Correctness
- Correct event for the logic (validate vs before_submit vs on_submit vs on_update)? Interaction with amend, return, import, and `flags`?
- Version-specific APIs verified against the installed Frappe/ERPNext/India Compliance version?
- Hooks from other apps for the same DocType considered (`hooks_audit.py`)?
- Timezones/dates: `getdate`, `nowdate`, month boundaries, fiscal year?
- Child tables: row index handling, deletes during iteration, `parentfield` correctness.

## Performance
- Queries inside loops, `get_doc` for single fields, unbounded `get_all`, missing limits on API/report outputs.
- Work in request that should be queued; hook cost on hot DocTypes; indexes for new filters.

## Operability
- Errors logged with context (`frappe.log_error`) and re-raised when the caller must know.
- Jobs: queue/timeout, `enqueue_after_commit`, idempotency, rerun path.
- Migration impact: patches idempotent, fixtures narrow, `after_migrate` safe to rerun, rollback plan.

## Tests
- New behavior and the bug are covered; permissions and cancellation paths tested; tests do not depend on production data or execution order.
