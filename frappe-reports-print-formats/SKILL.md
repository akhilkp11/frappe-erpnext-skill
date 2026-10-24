---
name: frappe-reports-print-formats
description: Build and fix Frappe/ERPNext Script Reports, Query Reports, Report Builder views, dashboard charts, Jinja print formats, letterheads, PDFs, customer/supplier statements, and financial report reconciliation. Use whenever a report totals don't match, a filter is ignored, a print format shows blanks, PDF layout breaks, or a new report/print is requested.
---

# Reports and print formats

## Pick the report type
- **Report Builder**: no code; fine for simple lists on one DocType.
- **Query Report**: one SQL query with `%(filter)s` parameters; quick but limited and easy to get wrong with permissions.
- **Script Report**: Python `execute(filters)` + JS filters; the standard choice for anything with logic, multiple sources, charts, or totals.
Standard reports in a custom app require developer mode so the Report JSON is written into the app; commit it.

## Script Report skeleton
```python
# my_app/my_module/report/sales_by_customer/sales_by_customer.py
import frappe
from frappe import _
from frappe.utils import flt, getdate

def execute(filters=None):
    filters = frappe._dict(filters or {})
    validate(filters)
    columns = get_columns()
    data = get_data(filters)
    chart = get_chart(data)
    return columns, data, None, chart          # (columns, data, message, chart, report_summary)

def validate(filters):
    if not filters.company:
        frappe.throw(_("Company is required"))
    if getdate(filters.from_date) > getdate(filters.to_date):
        frappe.throw(_("From Date cannot be after To Date"))

def get_columns():
    return [
        {"label": _("Customer"), "fieldname": "customer", "fieldtype": "Link", "options": "Customer", "width": 180},
        {"label": _("Net Sales"), "fieldname": "net_sales", "fieldtype": "Currency", "width": 140},
    ]

def get_data(filters):
    si = frappe.qb.DocType("Sales Invoice")
    from frappe.query_builder.functions import Sum
    q = (frappe.qb.from_(si)
         .select(si.customer, Sum(si.base_net_total).as_("net_sales"))
         .where((si.docstatus == 1) & (si.company == filters.company)
                & (si.posting_date[filters.from_date:filters.to_date]))
         .groupby(si.customer))
    return q.run(as_dict=True)
```
```js
// sales_by_customer.js
frappe.query_reports["Sales By Customer"] = {
  filters: [
    { fieldname: "company", label: __("Company"), fieldtype: "Link", options: "Company",
      default: frappe.defaults.get_user_default("Company"), reqd: 1 },
    { fieldname: "from_date", label: __("From Date"), fieldtype: "Date", reqd: 1,
      default: frappe.datetime.add_months(frappe.datetime.get_today(), -1) },
    { fieldname: "to_date", label: __("To Date"), fieldtype: "Date", reqd: 1,
      default: frappe.datetime.get_today() },
  ],
};
```
Syntax details of the query builder (date slicing, joins) differ slightly between versions: check an existing standard report in the installed `erpnext/accounts/report` for the idiom the version uses.

## Correctness rules
1. Define what the number *means* first: net vs gross, base vs transaction currency, posting date vs due date, submitted only (`docstatus = 1`) vs including drafts.
2. Preserve filter semantics (company, cost center, territory, customer group, GSTIN, dimensions) for every sub-query; a missing company filter is the classic cause of cross-company totals.
3. Returns/credit notes (`is_return`) carry negative signs; cancelled and amended documents must not double count.
4. Financial reports: reconcile against the standard report for the same filters (General Ledger, Accounts Receivable, Trial Balance, Stock Balance, "Stock and Account Value Comparison"). A report that cannot be reconciled is not finished.
5. Respect permissions: raw SQL ignores user permissions; if the report is not admin-only, apply them (use `get_list`-style APIs or add the conditions) and test as a restricted user.
6. Avoid N+1 queries and unbounded result sets (`frappe-performance`); paginate or require tight filters. Heavy reports can be "Prepared Reports" (background) via the report settings.
7. Totals: `add_total_row` in the Report settings, or an explicit total row; keep columns numeric so totals compute.

## Jinja print formats
```jinja
<table class="table table-bordered">
{% for row in doc.items %}
  <tr>
    <td>{{ loop.index }}</td>
    <td>{{ row.item_name }}</td>
    <td class="text-right">{{ row.get_formatted("qty") }}</td>
    <td class="text-right">{{ row.get_formatted("amount", doc) }}</td>
  </tr>
{% endfor %}
</table>
<p>{{ doc.in_words }}</p>
{% set addr = frappe.db.get_value("Address", doc.customer_address, ["address_line1", "city"], as_dict=True) %}
```
- Know where a value lives: parent (`doc.x`), child row (`row.x`), linked doc (`frappe.db.get_value`/`frappe.get_doc`), or a custom field (check the exact fieldname in Customize Form).
- Format money/dates with `get_formatted` / `frappe.utils.fmt_money`, not string concatenation.
- Do not run queries inside long loops; prepare data once with a server-side `print_format` helper or a `{% set %}` map.
- Escape user content; avoid `|safe` unless the HTML is yours.
- PDF engines are limited CSS renderers: prefer tables over flex/grid, test page breaks with long item lists, repeating headers (`thead`), multiple addresses/contacts, missing values, and the PDF output itself (not only the browser preview). Check Print Settings for the PDF generator available in the installed version.
- Copy a standard format ("Customize" > duplicate) rather than editing the standard one so upgrades do not overwrite it.

## Delivery
Provide the full code, file path or Desk location, filters, sample expected output, deployment steps (`bench migrate`/`bench build`, clear cache), and the reconciliation test you ran or that the user should run.
