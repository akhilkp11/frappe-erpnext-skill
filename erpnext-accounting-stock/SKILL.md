---
name: erpnext-accounting-stock
description: Analyze and customize ERPNext accounting and inventory - GL Entry, Payment Ledger, Payment Entry and reconciliation, outstanding amounts, taxes and rounding, multi-currency, credit notes/returns, cost centers and dimensions, Stock Ledger Entry, valuation (FIFO/Moving Average), Serial/Batch bundles, Repost Item Valuation, stock vs GL mismatches, and financial report discrepancies. Use for any ledger, tax-total, stock value, or "report doesn't match" problem, or when a customization could change posted entries.
---

# ERPNext accounting and stock integrity

Behavior changes between ERPNext releases (v15 vs v16 especially around payment ledger, reposting, and stock bundles). Read the installed controllers before asserting how something posts.

## Trace the full effect
Source document -> submit/cancel -> GL Entry (`make_gl_entries`) -> Payment Ledger Entry (party outstanding) -> Stock Ledger Entry (`update_stock_ledger`) -> valuation -> reports.
- Cancelled vouchers keep their ledger rows with `is_cancelled = 1` (and reversing entries); filter `is_cancelled = 0` in custom SQL, or you will double count.
- Separate: item net amount, base net amount, taxes, grand total, rounded total and rounding adjustment, outstanding amount, valuation rate, stock value.
- Verify company, currency and exchange rate, posting date **and time** (stock), cost center, project, warehouse, accounting dimensions, inventory dimensions, item tax template.
- Returns/credit notes: `is_return`, `return_against`, signs, `update_stock`, whether outstanding is applied against the original or standalone.
- Payment Entry: inspect the `references` child rows (allocated amounts), `unallocated_amount`, deductions/write-offs, and exchange gain/loss. "Fully paid" documents can still differ across reports because of report filters (posting date vs due date, party vs account, `Show Cancelled`).
- Payment/Journal reconciliation tools (Payment Reconciliation, unreconcile) change ledger links; never emulate them with SQL.

## Never fix ledgers with SQL
GL Entry, Stock Ledger Entry, Payment Ledger Entry and outstanding fields are derived data. Supported corrections:
- Cancel and amend the source document (respect period closing and `frozen_date` settings).
- **Repost Item Valuation** to recompute stock ledger values/GL after backdated changes or valuation bugs; **Repost Accounting Ledger** to regenerate GL for vouchers.
- Stock Reconciliation for quantity/valuation corrections, Journal Entry for pure accounting corrections.
If SQL is truly unavoidable (last resort), require: verified backup, rehearsal on a restored copy, a read-only query proving the affected set, an approved written plan, and before/after Trial Balance and Stock Balance comparison.

## Reconciliation toolbox (read-only)
- Standard reports: General Ledger, Trial Balance, Accounts Receivable/Payable (with and without "Group by"), Stock Balance, Stock Ledger, **Stock and Account Value Comparison**, Purchase/Sales Register.
- Voucher-level GL vs SLE check (adjust accounts and filters; run via `bench --site SITE mariadb` read-only or Desk report):
```sql
SELECT gl.voucher_type, gl.voucher_no,
       SUM(gl.debit - gl.credit) AS gl_stock_amount,
       (SELECT IFNULL(SUM(sle.stock_value_difference), 0)
          FROM `tabStock Ledger Entry` sle
         WHERE sle.voucher_type = gl.voucher_type AND sle.voucher_no = gl.voucher_no
           AND sle.is_cancelled = 0) AS sle_value
FROM `tabGL Entry` gl
WHERE gl.is_cancelled = 0 AND gl.company = %(company)s
  AND gl.account IN (SELECT name FROM `tabAccount` WHERE account_type = 'Stock' AND company = %(company)s)
  AND gl.posting_date BETWEEN %(from_date)s AND %(to_date)s
GROUP BY gl.voucher_type, gl.voucher_no
HAVING ABS(gl_stock_amount - sle_value) > 0.01;
```
Differences usually trace to backdated entries, negative stock, valuation settings, landed cost vouchers, or a failed/queued repost.

## Stock and valuation
- Valuation method (FIFO / Moving Average, and any other the version offers) is per item/settings; changing it after transactions exist needs a plan, not a toggle.
- Perpetual inventory creates stock GL entries; without it, only SLE exist. Know which the company uses.
- Serial and Batch Bundles (v15+) replaced inline serial/batch fields on stock transactions; custom code that reads old fields breaks.
- Backdated entries trigger repost of later entries (queued); check Repost Item Valuation status before judging numbers.
- Negative stock, reserved stock, and inventory dimensions change what "available" means.

## Taxes and withholding
- Do not reimplement tax calculation: customize through Tax Templates, Item Tax Templates, Tax Rules, or hooks around the standard `calculate_taxes_and_totals`.
- Tax withholding (TDS/TCS): Tax Withholding Category with per-fiscal-year rate and threshold rows, party setting, and invoice-level apply flag; verify category, section, rate, cumulative threshold, and add/deduct semantics against the standard path. India-specific setup: `erpnext-india-gst`.
- Rounding: use `flt(value, precision)` with the field's precision; compare totals after rounding; remember "Disable Rounded Total" and the rounding adjustment account.

## Customization discipline
- Do not override a controller before checking hooks of all apps (`frappe-testing-debugging/scripts/hooks_audit.py`).
- A custom discount/credit-note automation must reuse supported documents (Payment Entry deductions, Credit Note via return) and be idempotent, so retries and cancels do not create duplicates.
- Test: invoice and credit-note paths, partial/full payments, multiple items and cost centers, multi-currency, rounding, cancel/amend, backdated posting, and period-closed behavior. Reconcile against standard reports and source ledger rows.
- State the risk to historical data, require a backup and staging validation before production, and describe the rollback.
