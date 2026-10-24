---
name: frappe-testing-debugging
description: Diagnose Frappe/ERPNext errors and write tests - read tracebacks, find hook and controller-override conflicts across apps, use bench console/execute/mariadb, Error Log and logs, write IntegrationTestCase/UnitTestCase tests, run bench run-tests, and build regression tests for ledger and permission behavior. Use whenever there is a traceback, a "works on one site not another" issue, a flaky test, or a request to add tests.
---

# Testing and debugging

## Diagnose before editing
1. Get the **full traceback**, exact versions of frappe/erpnext/custom apps (`frappe-dev-workflow/scripts/detect_env.sh`), the DocType, the action (save/submit/cancel/job/report/API), and whether it reproduces for every user and site.
2. Read the failing frames in the installed source and all callers. Do not guess from the last line only; the frame that **calls** into your code usually shows intent.
3. Audit overrides across **all** apps: `python scripts/hooks_audit.py /path/to/bench` lists duplicate `doc_events`, multiple `override_doctype_class`/`extend_doctype_class`, and `override_whitelisted_methods` for the same target. Hook conflicts explain many "only after installing app X" bugs.
4. Check data/config: Custom Fields, Property Setters, Client/Server Scripts, Workflow states, permissions, `docstatus`, site-specific settings, and fixtures that differ between sites.
5. Confirm the root cause with a reproduction. Separate **verified** facts, **likely** causes, and **open questions**.

## Tools
- `bench --site SITE console` (IPython with `frappe` loaded): inspect docs/meta, run queries read-only first.
- `bench --site SITE execute dotted.path --kwargs "{...}"`: run one function reproducibly.
- `bench --site SITE mariadb`: SQL shell (read-only discipline on production).
- Desk: Error Log, Scheduled Job Log, RQ Job, Recorder, Activity/Version log of the document, Audit Trail.
- Files: `logs/web.error.log`, `logs/worker.error.log`, `logs/scheduler.log`, `logs/frappe.log` (list `logs/` for the actual names).
- Browser: console and Network tab for client/API issues (status code and response body).
- `frappe.log_error(title=..., message=frappe.get_traceback())` for server-side diagnostics that must survive a rollback.

## Writing tests (current framework)
In recent Frappe versions the base classes are in `frappe.tests`: `UnitTestCase` (no DB, fast) and `IntegrationTestCase` (DB connection, test-record loading, rollback after each test). `FrappeTestCase` (from `frappe.tests.utils`) still works but is **deprecated**; use it only when the installed version predates the new classes.
```python
import frappe
from frappe.tests import IntegrationTestCase, change_settings   # verify names in the installed version

class TestInvoiceRounding(IntegrationTestCase):
    def test_return_reverses_gl(self):
        si = make_sales_invoice(qty=3, rate=100)                    # helper from erpnext tests or your own factory
        ret = make_return(si)
        gl = frappe.get_all("GL Entry", filters={"voucher_no": ret.name, "is_cancelled": 0},
                            fields=["sum(debit) as debit", "sum(credit) as credit"])[0]
        self.assertEqual(gl.debit, gl.credit)

    @change_settings("Accounts Settings", {"over_billing_allowance": 0})
    def test_over_billing_blocked(self):
        ...
```
Useful helpers (check availability): `assertQueryCount`, `assertDocumentEqual`, context managers for `set_user` and frozen time, `change_settings`. Run:
```bash
bench --site test_site set-config allow_tests true     # test sites only
bench --site test_site run-tests --app my_app
bench --site test_site run-tests --doctype "My DocType"
bench --site test_site run-tests --module my_app.my_module.doctype.thing.test_thing
```
(Flags vary slightly by version; run `bench run-tests --help`.)

Test design: valid, invalid, empty, boundary, permission-denied (use a real restricted user), duplicate execution, and cancellation. For transactions: draft/save/submit/cancel/amend/return and the resulting GL/stock ledger. Keep test data isolated; rely on rollback or clean up explicitly; never run destructive test commands against a production site (`allow_tests` stays off there). Always add a regression test for the reported bug that fails before the fix and passes after.

## Reporting
State the confirmed cause only when evidence supports it. Never say a test passed unless it was executed and the result observed; if you cannot run it, say "not run" and give the exact command.
