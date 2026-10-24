---
name: erpnext-india-gst
description: Configure, troubleshoot, and customize India GST and TDS in ERPNext with the India Compliance app - GST Settings, GSTIN/GST Category/Place of Supply, HSN/SAC, Item Tax Templates, Sales/Purchase tax templates, CGST/SGST/IGST mistakes, reverse charge, SEZ/export, e-invoice (IRN), e-way bill, GSTR-1/GSTR-3B mismatches, ITC, Tax Withholding Category (TDS/TCS). Use for any Indian tax, GST report, e-invoice failure, or "GST is wrong on the invoice" problem.
---

# India GST and TDS in ERPNext

GST, e-invoice, e-way bill, TDS and the GST returns in ERPNext are provided by the **India Compliance** app (`india_compliance`), not by ERPNext core. Confirm it is installed (`bench --site SITE list-apps`) and that its branch matches ERPNext/Frappe (`version-15` with v15, `version-16` with v16); mismatched versions cause TypeErrors after updates. Official references: ERPNext docs "India GST, e-invoice and e-way bill: find your answer" (docs.frappe.io/erpnext/india-gst-help) and docs.indiacompliance.app. Check them for current behavior; rules and portal APIs change.

## Data that drives GST
- **Company**: GSTIN(s) via Company address (multiple branches use multiple GSTINs: filter every report by GSTIN or totals combine them).
- **Party**: GST Category (Registered Regular/Composition, Unregistered, SEZ, Overseas, UIN holders, etc.) and GSTIN on the party/address.
- **Document**: Place of Supply (state) compared with the company's state decides IGST vs CGST+SGST; company/billing/shipping GSTIN fields; reverse-charge flag; e-invoice/e-way bill fields (`irn`, `ewaybill`).
- **Item**: HSN/SAC code, GST Treatment (taxable, nil-rated, exempted, non-GST), tax rate via **Item Tax Template**.
- **GST Settings**: accounts per tax type (output, input, reverse charge), HSN validation, e-invoice/e-way bill switches and API credentials, SEZ/overseas switch.
List the exact fields installed (names vary by release):
```python
# bench --site SITE console
[f.fieldname for f in frappe.get_meta("Sales Invoice").fields
 if "gst" in f.fieldname or f.fieldname in ("irn", "ewaybill", "place_of_supply")]
```

## Diagnosing "GST is wrong, missing, or a few paisa off"
Check in this order: (1) Place of Supply and company/party states, (2) GST Category of the party, (3) GST accounts configured in GST Settings for the company, (4) the Item Tax Template and the template-related setting that India Compliance expects (see the ERPNext docs pages *Item Tax Template* and *Why is GST wrong or missing on my invoice?*; one setting there must be off for India Compliance), (5) item HSN/GST Treatment, (6) rounding settings and whether taxes are inclusive. Reselect the tax template after fixing masters; stale taxes on an existing document do not recalc by themselves.

## Returns and reconciliation
- **GSTR-1**: GST Sales Register is the one-line-per-invoice view with the GSTR-1 section; GSTR-1 data is a snapshot from when it was generated: after changing invoices, regenerate or Reset. Totals differing from the sales register often come from combining GSTINs, wrong period (posting date), cancelled/amended invoices, credit notes, or invoices categorized into a section you did not expect. Compare per invoice, not just totals.
- **GSTR-3B / ITC**: India Compliance uses an ITC Claim Period and blocks edits to periods already filed; fix by following its amendment flow, not by unlocking.
- **GSTR-2A/2B**: Purchase Reconciliation tooling exists; IMS is supported in newer releases. GSTR-9, GSTR-6, GSTR-7 are not generated; use the GST reports as the base and file on the portal.
- Reverse charge (RCM), ineligible ITC, advances, SEZ/export, nil-rated, and ISD each have dedicated setup in the India Compliance docs; do not emulate them with custom tax rows.

## e-Invoice and e-way bill
Enable API features and credentials in GST Settings (sandbox first). Typical failures: invalid or missing party GSTIN/address/PIN/HSN, API credit exhaustion, portal downtime, IRN already generated, cancelling after the portal's time window (the e-invoice can no longer be cancelled after 24 hours; follow the credit-note route), and Part-B/vehicle updates for e-way bills. Log the portal's error text (without credentials) before changing data.

## TDS / TCS
Tax Withholding Categories (sections, rates per fiscal year, thresholds) come from India Compliance; update the app to receive new section sets (for example the categories introduced for the Income Tax Act 2025), then select them on suppliers. Verify the threshold type (single vs cumulative), section, rate, and addition/deduction semantics against the standard calculation; do not duplicate it.

## Customization rules
- Do not hand-edit generated GST tax rows or bypass `india_compliance` hooks; run `frappe-testing-debugging/scripts/hooks_audit.py` and read the app's source for the document you touch.
- Add rules through supported extension points (`frappe-core`) and keep them idempotent with respect to e-invoice/e-way bill generation.
- Never change posted invoices in SQL; for historical errors use cancel/amend (if the period and e-invoice state allow), credit/debit notes, or Journal Entries as the compliance process requires, and involve the finance owner.
- GST rules are legal obligations: flag decisions that need a CA/tax professional instead of guessing.

## Test matrix
Intra-state (CGST+SGST) and inter-state (IGST), unregistered B2C, registered B2B, SEZ with/without payment, export, RCM purchase, nil-rated + taxable mixed items, discounts, inclusive tax, credit note against an e-invoiced invoice, multi-GSTIN company, backdated posting into a filed month, and GSTR-1 regeneration after a correction.
