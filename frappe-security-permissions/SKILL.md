---
name: frappe-security-permissions
description: Frappe/ERPNext authorization and application security - roles and permlevels, User Permissions, sharing, has_permission and permission_query_conditions hooks, get_list vs get_all, ignore_permissions risks, SQL injection, XSS in Jinja/JS, guest endpoints, private files, secrets and Password fields. Use when someone "can see too much", when reviewing an endpoint or report, or when adding row-level restrictions.
---

# Security and permissions

## Permission layers (outermost to innermost)
1. **Authentication**: session, API key/secret, OAuth. Disabled users and expired sessions fail here.
2. **Role permissions per DocType** (read/write/create/delete/submit/cancel/amend/report/export/import/share/print/email), optionally `if_owner`, and **permlevels** that gate individual fields.
3. **User Permissions**: restrict a user to specific linked records (a Company, Warehouse, Territory...). They apply to Link fields and to list queries on the restricted DocType; check "Apply to all document types" and per-field "Ignore User Permissions" settings when results surprise you.
4. **Document sharing** (Share) and **Workflow** state conditions.
5. **App hooks**: `has_permission` (decide per document) and `permission_query_conditions` (SQL condition appended to list queries).

## Enforcing in code
```python
frappe.has_permission("Sales Invoice", "read", doc=name, throw=True)
doc = frappe.get_doc("Sales Invoice", name); doc.check_permission("write")
frappe.only_for(["System Manager", "Accounts Manager"])      # role gate for admin-only methods
rows = frappe.get_list("Task", fields=[...])                 # permission-aware
rows = frappe.get_all("Task", fields=[...])                  # BYPASSES permissions; justify every use
```
`@frappe.whitelist()` only exposes the function; it grants nothing and checks nothing. Every endpoint must authorize explicitly.

## Row-level hooks
```python
# hooks.py
permission_query_conditions = {"Sales Invoice": "my_app.permissions.si_query"}
has_permission = {"Sales Invoice": "my_app.permissions.si_has_permission"}

# my_app/permissions.py
def si_query(user=None):
    user = user or frappe.session.user
    if "System Manager" in frappe.get_roles(user):
        return ""
    return f"`tabSales Invoice`.owner = {frappe.db.escape(user)}"   # always escape

def si_has_permission(doc, user=None, permission_type=None):
    user = user or frappe.session.user
    return doc.owner == user or "Accounts Manager" in frappe.get_roles(user)
```
`permission_query_conditions` affects `get_list`/reports/link searches, not `get_all` or raw SQL. Keep both hooks consistent, or users will see records in a list that they cannot open (or the reverse).

## Common vulnerabilities and fixes
- **SQL injection**: f-strings/`%`/`.format` into `frappe.db.sql`, or into `order_by`/`fields`/`filters` taken from the client. Use parameters, the query builder, and whitelist sortable columns.
- **XSS**: Jinja auto-escapes `{{ }}`, but `|safe`, `frappe.render_template` with raw HTML, `innerHTML`, and `frappe.msgprint(html_from_user)` do not. Escape with `frappe.utils.escape_html` or render text with `.text()`.
- **Over-fetching**: returning whole documents or `SELECT *` leaks fields restricted by permlevel. Select explicit fields.
- **Guest endpoints**: `allow_guest=True` plus `ignore_permissions=True` is effectively an unauthenticated database writer. Require a signature/token and validate input strictly.
- **Files**: attachments default to private only if the field/upload says so; set `is_private=1` for anything sensitive, and use `frappe.get_doc("File", ...)` checks before exposing paths.
- **Secrets**: use `Password` fields and `get_decrypted_password`, never plain Data fields; keep keys out of Git, fixtures, logs, and error messages. Do not paste `site_config.json` or `bench show-config` output into chats.
- **Server Scripts / Client Scripts** are code with power: restrict who can edit them (System Manager only) and review them like app code.
- **Path/command injection**: validate filenames; never pass user input into `subprocess` or `os.system`.

## Reviewing a permission complaint
Reproduce as the actual user (`frappe.set_user`, or Desk "Switch user" with a test account), check role rows incl. permlevel, User Permissions on every linked field, workflow state, sharing, and hooks from every app. Use `frappe.permissions.get_doc_permissions` or the Role Permissions Manager to see what the framework thinks.

## Tests to add
A user without the role gets `PermissionError`; a user restricted to company A cannot read company B; guest cannot call the endpoint; list and detail views agree.
