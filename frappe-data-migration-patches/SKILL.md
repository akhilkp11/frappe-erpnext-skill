---
name: frappe-data-migration-patches
description: Safely change or load data in Frappe/ERPNext - writing patches (pre_model_sync/post_model_sync), bulk updates, renaming fields/docs, Data Import, opening balances (Opening Invoice Creation Tool, Opening Stock via Stock Reconciliation), migrating from Tally/Excel, dry runs, reposting, and verifying totals afterward. Use for "fix wrong data in 5,000 records", cleanup scripts, go-live loads, and bench execute/console data fixes.
---

# Data migration, fixes, and patches

Data changes are the highest-risk work in an ERP: they bypass the validations that normally protect ledgers. Work in the order below.

## 1. Protocol for any bulk change
1. **Backup**: `bench --site SITE backup --with-files` (confirm it completed and note the path). Production changes need explicit user approval.
2. **Rehearse** on a restored copy (see `frappe-devops` for restore, including the `encryption_key` caveat).
3. **Read-only investigation**: write the SELECT that defines the affected set; record count, sample rows, and totals (amounts, quantities) before.
4. **Dry run**: run the logic and `frappe.db.rollback()` at the end, printing what would change.
5. **Execute** in batches, logging changed names to a file/Error Log for rollback and audit.
6. **Verify**: counts, totals, Trial Balance / General Ledger / Stock Balance as relevant, plus a spot check in the UI.

## 2. Choosing the write method
| Method | Runs validation/hooks | Updates `modified` | Use for |
|---|---|---|---|
| `doc.save()` / `submit()` | yes | yes | Business data; slow on large sets |
| `frappe.db.set_value(dt, name, field, val, update_modified=False)` | no | optional | Status markers, backfills of non-ledger fields |
| `frappe.db.sql("UPDATE ... WHERE ... %s")` | no | no | Mass backfills with verified WHERE clause |
| Cancel/amend, Repost Item Valuation / Repost Accounting Ledger | yes (supported flows) | yes | Anything touching GL, stock, outstanding |
Never UPDATE or DELETE rows in GL Entry, Stock Ledger Entry, Payment Ledger Entry directly; use supported reposting/cancellation (see `erpnext-accounting-stock`).

## 3. Patch template
```python
# patches.txt -> [post_model_sync] my_app.patches.v1_1.backfill_region
import frappe

def execute():
    if not frappe.db.has_column("Customer", "custom_region"):
        return                                           # schema not there; nothing to do
    names = frappe.get_all("Customer", filters={"custom_region": ["is", "not set"]}, pluck="name")
    for i in range(0, len(names), 500):
        for name in names[i:i + 500]:
            territory = frappe.db.get_value("Customer", name, "territory")
            frappe.db.set_value("Customer", name, "custom_region", map_region(territory),
                                update_modified=False)
        frappe.db.commit()                               # batch commit is acceptable in patches
```
- Idempotent (re-running changes nothing more), restartable, and logged.
- `pre_model_sync` runs before DocType JSON is applied (use for renames/cleanup that the new schema would break; call `frappe.reload_doc(module, "doctype", name)` if you need the new schema in a pre patch). `post_model_sync` runs after (default choice).
- Renames: `frappe.model.utils.rename_field(doctype, old, new)` for fields; `frappe.rename_doc(doctype, old, new, merge=False)` for documents (updates links; slow on large sets).
- New indexes: `frappe.db.add_index(doctype, fields)` in a patch for large existing tables.
- Test the patch twice on a copy of production data; the second run must be a no-op.

## 4. Loading data
- **Data Import** (Desk) with the downloaded template: choose Insert vs Update, run "Start Import" after the dry-run validation passes. Fix source data rather than disabling mandatory/link checks. CLI exists as `bench --site SITE data-import` (verify flags in the installed bench).
- **Masters first**: Company, Chart of Accounts, Warehouses, Item Groups, Items, Parties, Addresses/Contacts, Price Lists, then transactions.
- **Opening balances**: receivables/payables via **Opening Invoice Creation Tool**; bank/other accounts via a Journal Entry using a temporary opening account (**Temporary Opening**) that must net to zero; stock via **Stock Reconciliation** with purpose Opening Stock (dated before go-live).
- **From Tally/Excel**: normalise IDs and GSTINs, split addresses, map ledgers to accounts, and keep a mapping table (source id -> ERPNext name) for re-runs and audit.
- After load: Trial Balance matches source, AR/AP ageing totals match, Stock Balance matches physical/source valuation, document counts match.

## 5. One-off scripts
`bench --site SITE execute my_app.scripts.fix.run --kwargs "{'dry_run': 1}"` keeps scripts in Git with a dry-run switch. Avoid pasting long scripts into `bench console` on production; if you must, keep the exact text in the ticket.

## 6. Anti-patterns
Looping `frappe.get_doc(...).save()` over thousands of rows without batching; changing docstatus by SQL; deleting "wrong" ledger rows; patches that assume a field exists; running the same patch under two names; changing data without a count/total check before and after.
