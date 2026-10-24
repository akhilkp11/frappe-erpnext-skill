# Document lifecycle and hook reference

Verified against the structure of `frappe/model/document.py` (`insert`, `save`, `submit`, `cancel`, `run_before_save_methods`, `run_post_save_methods`). Re-check in the installed version before relying on fine detail.

## Event order (typical)
**Insert (new doc):** `before_insert` -> naming (`before_naming`, `autoname`) -> `before_validate` -> `validate` -> `before_save` -> (framework validations: mandatory, links, permissions on fields) -> DB insert -> `after_insert` -> `on_update` -> `on_change`

**Save (existing draft):** `before_validate` -> `validate` -> `before_save` -> DB update -> `on_update` -> `on_change`

**Submit:** `before_validate` -> `validate` -> `before_submit` -> DB update (docstatus 1) -> `on_update` -> `on_submit` -> `on_change`. Note `before_save` does not run on submit; `on_update` does.

**Cancel:** `before_cancel` -> DB update (docstatus 2) -> `on_cancel` -> `on_change`

**Edit after submit (allow_on_submit fields):** `before_update_after_submit` -> `on_update_after_submit` -> `on_change`

**Delete:** `on_trash` -> (DB delete) -> `after_delete`

Other useful: `before_rename`/`after_rename`, `validate_links`, `on_update_after_submit`, `before_print`, `get_feed`.

## Consequences
- Put validation that must block saving in `validate` (or `before_submit` for submit-only rules); it runs before the framework's own mandatory/link validation, so values you set there are validated afterward.
- Side effects (create other docs, call external services, send mail) belong in `on_submit`/`after_insert`/`on_update`, ideally via `frappe.enqueue` or `frappe.db.after_commit`.
- `on_update` fires on every save and on submit; guard with `doc.docstatus` or `doc.has_value_changed("field")` when needed. `doc.get_doc_before_save()` returns the previous version inside `validate`/`on_update`.
- `doc_events` handlers receive `(doc, method=None)`. Wildcard key `"*"` runs for every DocType, so keep it cheap.

## Multiple apps, same event
Handlers from different apps all run, in app install order; one app raising aborts the transaction. If order matters, resolve it in code (explicit dependency/guard), not by hoping for an order. For controller replacement, only one `override_doctype_class` wins.

## hooks.py snippets
```python
required_apps = ["frappe", "erpnext"]          # also gates install order
doctype_js = {"Sales Invoice": "public/js/sales_invoice.js"}
override_whitelisted_methods = {"erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice": "my_app.api.make_sales_invoice"}
scheduler_events = {"daily": ["my_app.tasks.daily"], "cron": {"0 9 * * 1-5": ["my_app.tasks.weekday_9am"]}}
after_install = "my_app.setup.after_install"
after_migrate = ["my_app.setup.after_migrate"]
permission_query_conditions = {"Task": "my_app.permissions.task_query"}
has_permission = {"Task": "my_app.permissions.task_has_permission"}
```
Changing hooks.py requires a worker/web restart (or `bench restart`); changing doctype JSON requires `bench migrate`; JS/CSS requires `bench build` (or developer-mode watch).
