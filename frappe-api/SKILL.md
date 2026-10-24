---
name: frappe-api
description: Design, implement, secure, and debug Frappe/ERPNext APIs - @frappe.whitelist methods, /api/method and /api/resource REST calls, JSON request bodies, token/session auth, mobile app endpoints, webhooks, error codes, idempotency, pagination. Use for any endpoint, integration, "API returns 417/403/500", or Postman/curl testing task.
---

# Frappe API development

## Define the contract first
HTTP method, URL, auth mode, request schema, success schema, error format, and who may call it. Provide a concrete request/response example and a curl line.

URLs: `/api/method/<dotted.path.to.function>` calls a whitelisted function; `/api/resource/<DocType>[/<name>]` is the generic CRUD layer (it enforces DocType permissions and runs document hooks). Newer versions also ship a v2 API under `/api/v2/...`; check the installed version before promising it.

## Skeleton
```python
import frappe
from frappe import _
from frappe.rate_limiter import rate_limit

@frappe.whitelist(methods=["POST"])           # restrict methods; default allows more than you think
@rate_limit(limit=30, seconds=60)             # for expensive or abuse-prone endpoints
def create_visit():
    payload = frappe.request.get_json(silent=True)
    if not isinstance(payload, dict):
        frappe.throw(_("Request body must be a JSON object"), frappe.ValidationError)

    customer = payload.get("customer")
    if not customer or not frappe.db.exists("Customer", customer):
        frappe.throw(_("Valid customer is required"), frappe.ValidationError)

    frappe.has_permission("Customer", "read", customer, throw=True)   # authorization, not just authentication

    request_id = payload.get("request_id")        # idempotency key from the client
    if request_id:
        existing = frappe.db.get_value("Visit", {"custom_request_id": request_id}, "name")
        if existing:
            return {"name": existing, "duplicate": True}

    doc = frappe.get_doc({"doctype": "Visit", "customer": customer,
                          "custom_request_id": request_id}).insert()   # runs validation + permissions
    return {"name": doc.name}
```
Form-encoded and JSON arguments are also merged into `frappe.form_dict`/function kwargs; verify in the installed `frappe/app.py` which one your clients use and keep one convention.

## Responses and errors
- A returned value is wrapped as `{"message": ...}`. Return dicts/lists with stable keys, not raw documents (documents leak internal fields).
- `frappe.throw` raises `ValidationError` (HTTP 417 by default); `frappe.PermissionError` -> 403; `frappe.DoesNotExistError` -> 404. For a specific status: `frappe.local.response["http_status_code"] = 400` then return the error body.
- Never return tracebacks. Log with `frappe.log_error(title=..., message=frappe.get_traceback())` and return a safe message.

## Authentication
Token header `Authorization: token <api_key>:<api_secret>` (generated per User), session cookie for browser clients, OAuth for third parties. Give integration users the minimum roles; one integration user per consumer so access can be revoked and audited. `allow_guest=True` makes the method public: validate everything, rate-limit, and never return private data.

## Server-side rules
- Never trust client-sent prices, totals, taxes, statuses, owners, or companies. Recompute server-side or let document validation do it.
- Use document methods (`insert`, `submit`) when business rules must run; avoid `ignore_permissions=True` unless the endpoint itself authorizes the caller by another mechanism (for example a verified webhook signature).
- Lists: use `frappe.get_list` for permission-aware reads, select only needed fields, and paginate (`limit_start`, `limit_page_length`). If the requirement forbids pagination, discuss filters, field selection, hard limits, and payload size instead of returning an unbounded table.
- Avoid N+1: fetch related rows in one query and map by key (see `frappe-performance`).
- Concurrency/retries: make creates idempotent (unique `request_id` field with a unique index protects against races that `exists()` checks alone cannot). Keep work in one transaction; do not `frappe.db.commit()` midway.

## Webhooks (inbound)
Verify a signature or shared secret with `hmac.compare_digest` before touching data, respond quickly, and do heavy work via `frappe.enqueue` (see `frappe-background-jobs`). Log the raw payload (without secrets) for replay.

## Test it
```bash
curl -X POST "https://SITE/api/method/my_app.api.create_visit" \
  -H "Authorization: token KEY:SECRET" -H "Content-Type: application/json" \
  -d '{"customer":"CUST-0001","request_id":"abc-123"}'
```
Cover: missing/invalid JSON, wrong types, unknown ids, unauthorized user (real low-privilege user, not Administrator), duplicate request, empty results, large payload, and the target Frappe version. Include path, method, headers, sample request/response, and the test commands in your answer.
