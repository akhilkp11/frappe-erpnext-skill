---
name: erpnext-customization
description: Customize ERPNext/HRMS business logic safely - Sales, Purchase, Stock, Manufacturing, HR, Projects and Tasks; document mapping (make_* / get_mapped_doc), workflows, notifications, assignment rules, Auto Repeat, escalations and reminders, custom fields on transactions, and extending standard controllers. Use when a change affects how ERPNext transactions behave, e.g. "copy this field to the invoice", "block submit unless...", "auto-assign tasks", "send overdue reminders".
---

# ERPNext business logic customization

Preserve standard validation, permissions, accounting, stock, tax and lifecycle behavior. Read the installed ERPNext controller before changing it; ERPNext logic lives mostly in `erpnext/controllers/` (`accounts_controller`, `selling_controller`, `buying_controller`, `stock_controller`) plus each DocType's own controller.

## Choose the lowest-risk mechanism
1. **Configuration**: Customize Form, Workflow, Notification, Assignment Rule, Auto Repeat, Email Alert, Property Setter, Accounts/Stock/Selling Settings. Try these first.
2. **Custom Field + fetch_from/mapping** for extra data that must travel between documents.
3. **doc_events / extend_doctype_class** in your app for validation or side effects (`frappe-core`).
4. **override_whitelisted_methods** for the `make_*` mapping functions when the standard copy logic is wrong.
5. **Controller override** only when nothing above fits, and always call `super()`.

## Transaction analysis (before writing code)
For Sales Invoice, Purchase Invoice, Orders, Quotation, Delivery Note, Purchase Receipt, Stock Entry, Payment Entry, Journal Entry and returns:
1. Where is the field set and recalculated? (`calculate_taxes_and_totals`, `set_missing_values`, client scripts, fetch rules.) A value you set in `validate` may be overwritten by a later recalculation.
2. What does submit/cancel create downstream: GL Entry, Stock Ledger Entry, Payment Ledger, outstanding amounts, linked-document status updates (`update_prevdoc_status`, per-billed/delivered percentages).
3. Returns and credit notes: `is_return`, negative quantities/amounts, `return_against`, stock behavior.
4. Currency, company, cost center, warehouse, item tax template, discount, rounding.
5. Amend/cancel/copy/duplicate/import paths: custom fields are copied on amend and duplicate unless `no_copy` is set.
6. Avoid duplicate tax rows, double GL postings, double stock updates, and recalculations that overwrite custom values.

## Mapping between documents
Standard `make_sales_invoice`, `make_delivery_note`, etc. use `frappe.model.mapper.get_mapped_doc` with field maps and post-processing. To carry a custom field: add the same-named custom field on both DocTypes (same-name fields map automatically) or extend the mapping through an override of the `make_*` function that calls the original, then adjusts the result. Keep the override signature identical and test the "Create" button flow from Desk and the API.

## Workflows
- A Workflow controls `workflow_state` and allowed transitions per role; it does not replace permissions. Check state-to-`docstatus` mapping (submit happens on the transition to a state with docstatus 1).
- Conditions on transitions are Python expressions evaluated server-side; keep them simple and tested.
- Bypassing a workflow with `db_set`/SQL breaks audit and state consistency; use `frappe.model.workflow.apply_workflow` in code.
- Test each role's view: buttons, transitions, self-approval rules, and what happens on amend.

## Tasks, Projects, reminders, escalations
- Make scheduled logic **idempotent**: store what was sent (an escalation level, last-sent timestamp, or a log DocType) and compare before sending. Reruns after downtime must not spam.
```python
def escalate_overdue_tasks():
    today = frappe.utils.getdate()
    for t in frappe.get_all("Task", filters={"status": ["not in", ["Completed", "Cancelled"]],
                                             "exp_end_date": ["<", today]},
                            fields=["name", "custom_escalation_level", "exp_end_date"]):
        level = days_overdue_to_level((today - t.exp_end_date).days)
        if level > (t.custom_escalation_level or 0):
            notify(t.name, level)
            frappe.db.set_value("Task", t.name, "custom_escalation_level", level, update_modified=False)
```
- Define overdue consistently (date vs datetime, site timezone, working days vs calendar days) and test at midnight and month ends.
- Auto Repeat: read the installed implementation; verify how the next date is derived and what happens on holidays and failed generation; each generated document must carry the original's relevant custom values.
- Prevent duplicate ToDos/assignments when hooks fire twice (check existing open ToDo for the same reference before creating one).
- Notifications: avoid sending on every save; use condition + "value changed" semantics and test with multiple recipients and missing emails.

## HR notes
Payroll and attendance logic is sensitive (salary slips, leave ledger, tax). Treat Salary Slip, Leave Ledger Entry and Additional Salary like ledgers: no direct SQL, and test with multiple periods and mid-month joins/exits.

## Response format
Explain the standard behavior first, then the safest customization point, complete code, migration/deploy steps, tests (draft, save, submit, cancel, amend, return, import, API), and any impact on accounting or stock ledgers.
