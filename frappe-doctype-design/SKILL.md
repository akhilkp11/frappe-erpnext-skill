---
name: frappe-doctype-design
description: Design or change Frappe DocTypes - fields, naming series, child tables, Link vs Dynamic Link, submittable documents, permissions per role/permlevel, Custom Fields vs Property Setters vs Customize Form, renaming or retyping fields safely. Use when creating a new DocType, adding fields to ERPNext doctypes, planning a data model, or asking "should this be a custom field or a new doctype".
---

# DocType design

## Decide the mechanism first
| Situation | Use |
|---|---|
| Extra field on a standard ERPNext/HRMS DocType | **Custom Field** (ship via fixtures, filtered by app module) |
| Change a property of a standard field (label, mandatory, options, hidden) | **Property Setter** (Customize Form creates it) |
| New business entity or process | **New DocType** in your custom app (developer mode) |
| Repeating rows inside one document | **Child table** (`istable`) |
| One global configuration record | **Single** DocType |
| Hierarchy (departments, territories) | **Tree** DocType (`is_tree`, NestedSet) |
| Data from an external system, not stored locally | **Virtual** DocType (controller supplies data) |

Prefix custom fields on standard doctypes (`custom_` is added by Customize Form on recent versions; follow whatever convention the project already uses) so they never collide with future upstream fields.

## Naming
Pick `autoname` deliberately; it is hard to change once documents exist and other records link to the names.
- `naming_series:` for human-friendly document numbers (add a `naming_series` Select field; options like `INV-.YYYY.-.####`). Series are per company/fiscal-year when you include them in the pattern.
- `field:fieldname` when a business key is unique and stable (item code); `format:` for composed patterns; `hash` for opaque ids; `Prompt` for user-entered names.
- Customizing a name in code: implement `autoname(self)` and set `self.name`. Do not generate numbers with `select max()+1` (race conditions); use `frappe.model.naming.make_autoname` / series.

## Field choices that cause long-term trouble
- Money: `Currency` with an `options` pointing to a currency field; quantities/rates: `Float` with explicit precision. Compare with `frappe.utils.flt(value, precision)`, never `==` on floats.
- `Link` stores a name and enforces existence; `Dynamic Link` needs a companion Link-to-DocType field. `Select` options are a hard-coded list: if the list changes by business decision, use a Link to a small master instead.
- `fetch_from` copies on selection only; it does not keep data in sync. Decide whether you need a snapshot (fine) or live lookup (query it).
- Add `search_index` only for fields that are filtered/sorted on at scale; `unique` for business keys (it also creates an index).
- `Table MultiSelect` stores links in a child table; use it for small many-to-many selections, not for ledgers.
- `Long Text`/`Text Editor` fields cannot be indexed usefully; do not filter on them.

## Document behavior flags
`is_submittable` (adds docstatus 0/1/2 and `amended_from`), `track_changes` (version history), `allow_import`, `allow_rename`, `quick_entry`, `title_field`/`show_title_field_in_link`, `sort_field`. Make something submittable only if it needs the immutable-after-submit lifecycle; fields editable after submit need `allow_on_submit`, and changes there run `on_update_after_submit`.

## Permissions model
Roles are granted per DocType in the permission table with a **permlevel** (0 for normal fields, higher levels for restricted fields such as cost or salary). Add rows only for roles that need them; avoid `System Manager`-only shortcuts that become the de facto rule. Row-level restriction is a different layer (User Permissions, hooks): see `frappe-security-permissions`.

## Changing an existing DocType safely
1. Work in developer mode on a development site so the JSON in the app is rewritten; commit the JSON.
2. Renaming a field: add a patch using `frappe.model.utils.rename_field` (in `pre_model_sync`) so data moves; otherwise the old column's data is orphaned.
3. Changing field type: check data compatibility first (text to int, Data to Link). Add a patch to clean values before the schema change.
4. Removing a field: stop writing it, deploy, then remove in a later release; custom reports, print formats and scripts may reference it.
5. Run `bench --site SITE migrate`; verify in `bench --site SITE console` with `frappe.get_meta("DocType").get_field("x")`.
6. Child-table schema changes affect every parent form, API payloads, and print formats; search the repo for the child DocType name first.

## Review checklist
Is there already a standard DocType/field for this? Are names stable? Are links valid for archived records? Are permission rows minimal? Are there indexes for the list/report filters? Will import/export and API consumers survive the change?
