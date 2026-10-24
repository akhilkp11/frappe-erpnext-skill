---
name: frappe-core
description: Write and debug Frappe Framework server-side code (v15/v16) - controllers, doc_events, hooks.py, override_doctype_class / extend_doctype_class, frappe.get_doc/get_all/db/qb queries, fixtures, patches, flags, transactions. Use whenever the task involves Python in a Frappe app, a DocType controller, a hook, a query, or "how do I do X in Frappe", even if ERPNext is not mentioned.
---

# Frappe Framework core (server side)

Verify version-sensitive behavior in the installed `apps/frappe` source; this skill gives the patterns and the traps.

## Choosing the extension point
| Need | Use | Notes |
|---|---|---|
| Logic on a DocType you own | Controller method (`validate`, `on_submit`, ...) | Always call `super()` when overriding a parent method. |
| Add a step to someone else's DocType | `doc_events` in hooks.py | Several apps may register the same event; order follows app install order. |
| Replace a controller class | `override_doctype_class` | Only one app can win (last wins). Fragile with multiple apps. |
| Add methods/mixins to a controller | `extend_doctype_class` (**v16**; check it exists in the installed version) | Extensions stack, so prefer it over override on v16. |
| Replace a whitelisted endpoint | `override_whitelisted_methods` | Keep the same signature and return shape. |
| Periodic work | `scheduler_events` | See `frappe-background-jobs`. |
| Row filter for list views | `permission_query_conditions` / `has_permission` | See `frappe-security-permissions`. |

```python
# hooks.py
doc_events = {
    "Sales Invoice": {
        "validate": "my_app.overrides.sales_invoice.validate",
        "on_submit": "my_app.overrides.sales_invoice.on_submit",
    }
}

# my_app/overrides/sales_invoice.py
def validate(doc, method=None):
    ...
```
Lifecycle order and which events fire on insert, save, submit, cancel: `references/lifecycle-and-hooks.md`.

## Reading data
```python
frappe.get_doc("Customer", name)                 # full doc incl. children; runs no permission check by itself
frappe.get_cached_doc("Company", company)        # read-mostly masters; never mutate and save it casually
frappe.db.get_value("Customer", name, ["customer_name", "territory"], as_dict=True)
frappe.db.exists("Item", {"item_code": code})
rows = frappe.get_all("Sales Invoice",
        filters={"docstatus": 1, "posting_date": ["between", [start, end]]},
        fields=["name", "customer", "grand_total"], order_by="posting_date asc")
names = frappe.get_all("Item", filters={"disabled": 0}, pluck="name")
```
- `frappe.get_list` applies the session user's permissions; `frappe.get_all` bypasses them. Using `get_all` inside a whitelisted method silently removes row-level security.
- `get_list` defaults to a page limit (20 rows) while `get_all` returns everything unless limited. Always pass `limit_page_length` deliberately in APIs.
- Joins and aggregates: use the query builder, not string SQL.
```python
from frappe.query_builder.functions import Sum
si, sii = frappe.qb.DocType("Sales Invoice"), frappe.qb.DocType("Sales Invoice Item")
rows = (frappe.qb.from_(si).join(sii).on(sii.parent == si.name)
        .select(si.customer, Sum(sii.base_net_amount).as_("amount"))
        .where((si.docstatus == 1) & (si.company == company))
        .groupby(si.customer)).run(as_dict=True)
```
- Raw SQL is last resort and **must** be parameterized: `frappe.db.sql("select name from tabItem where item_group=%s", (group,), as_dict=True)`. Never build SQL with f-strings.

## Writing data
- Prefer `doc.insert()` / `doc.save()` / `doc.submit()` so validations, naming, permissions, versions and hooks run.
- `frappe.db.set_value` and `doc.db_set` skip validation and controller hooks; they update `modified` unless `update_modified=False`. Fine for flags/status markers, wrong for business data that affects ledgers.
- Flags: `doc.flags.ignore_permissions`, `ignore_validate`, `ignore_mandatory`, `ignore_links`. Each one removes a safety net; justify it in a comment and keep the scope narrow.
- Children: `doc.append("items", {...})`, `doc.set("items", [])`; rows need `parentfield`/`parenttype` handled by `append`, not by hand.
- Never call `frappe.db.commit()` inside controllers, hooks, or whitelisted methods; Frappe commits at the end of a successful request and rolls back on exception. Commits are acceptable in patches and in long-running background jobs that work in batches. Use `frappe.db.after_commit.add(fn)` for side effects (emails, enqueues) that must happen only if the transaction succeeds.
- Do not call `doc.save()` on the same doc from its own `on_update`/`validate` (recursion). Use `doc.db_set` for post-save markers.

## Errors, messages, translation
`frappe.throw(_("..."))` stops and rolls back; `frappe.msgprint` only informs. Wrap user-facing strings in `_()` with positional format args (`_("Row {0}: ...").format(idx)`), not f-strings, so translations work.

## Fixtures
Export only what the app owns, with a filter, otherwise you ship site-specific config:
```python
fixtures = [
    {"dt": "Custom Field", "filters": [["module", "=", "My App"]]},
    {"dt": "Property Setter", "filters": [["module", "=", "My App"]]},
    {"dt": "Role", "filters": [["name", "in", ["My Manager"]]]},
]
```
Run `bench --site SITE export-fixtures`, then review the JSON diff before committing. Custom Fields and Property Setters only get a `module` value when created with the app's module set (developer mode); verify the filter returns what you expect.

## Patches
```
# patches.txt
[pre_model_sync]
my_app.patches.v1_0.rename_old_field
[post_model_sync]
my_app.patches.v1_0.backfill_new_field
```
A patch is `execute()` in a module. Make it idempotent (check before you change), batch large updates, never destroy user data, and prefer `post_model_sync` unless you must act before the schema changes. See `frappe-data-migration-patches`.

## Debugging checklist
Capture the full traceback; check hooks of **all** installed apps for the same DocType; check Custom Fields, Property Setters, Client/Server Scripts, workflow states and `docstatus`; reproduce on a disposable site. Separate observed facts from guesses.

## Expected answer
Root cause, exact files, complete code, commands (`bench --site SITE migrate`, `bench build`, restart) with their impact, test steps, rollback. State any version uncertainty.
