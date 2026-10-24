---
name: frappe-client-scripts
description: Write and debug Frappe Desk form JavaScript and Client Scripts - frappe.ui.form.on events, frm.set_query link filters (parent and child tables), custom buttons, set_value/set_df_property, child-table events, frappe.call and frappe.db.get_value, list view settings, and doctype_js/app_include_js. Use for any browser-side Desk customization or "filter doesn't apply / button duplicates / value gets overwritten" bug.
---

# Client scripts and form JavaScript

## Where the code lives
- **Client Script DocType**: quick, site-local, editable in Desk; fine for small tweaks and on Frappe Cloud without a custom app.
- **App JS** (`doctype_js` or `app_include_js` in hooks.py): versioned, reviewable, testable; use for anything business-critical. Needs `bench build` (or developer-mode watcher) and a hard refresh.
State which location you chose and why.

## Skeleton
```js
frappe.ui.form.on("Sales Invoice", {
  setup(frm) {
    // runs once per form load: register queries here
    frm.set_query("cost_center", () => ({ filters: { company: frm.doc.company, is_group: 0 } }));
    frm.set_query("item_code", "items", (doc, cdt, cdn) => ({ filters: { disabled: 0, is_sales_item: 1 } }));
  },

  refresh(frm) {
    // runs on every refresh: must be idempotent
    frm.clear_custom_buttons();
    if (frm.doc.docstatus === 1) {
      frm.add_custom_button(__("Send Reminder"), () => send_reminder(frm), __("Actions"));
    }
  },

  customer(frm) {                       // field-change handler (same name as fieldname)
    if (!frm.doc.customer) return;
    frappe.db.get_value("Customer", frm.doc.customer, ["territory", "customer_group"]).then(r => {
      const v = r.message || {};
      frm.set_value("territory", v.territory);
    });
  },

  validate(frm) {                       // client-side convenience only; the server must re-validate
    if (!frm.doc.items?.length) frappe.throw(__("Add at least one item"));
  },
});

frappe.ui.form.on("Sales Invoice Item", {   // child DocType events: (frm, cdt, cdn)
  item_code(frm, cdt, cdn) {
    const row = locals[cdt][cdn];
    frappe.model.set_value(cdt, cdn, "description", row.item_name);
  },
  qty(frm, cdt, cdn) { recalc_row(frm, cdt, cdn); },
  items_add(frm, cdt, cdn) {},
  items_remove(frm) { frm.trigger("recalculate"); },
});

function send_reminder(frm) {
  frappe.call({
    method: "my_app.api.send_reminder",
    args: { invoice: frm.doc.name },
    freeze: true, freeze_message: __("Sending..."),
  }).then(r => { frappe.show_alert({ message: __("Sent"), indicator: "green" }); frm.reload_doc(); });
}
```

## Rules that prevent the usual bugs
- `set_query` belongs in `setup` (or `onload`), is evaluated lazily per open dropdown, and must return `{filters: ...}` or `{query: "dotted.path", filters: ...}`. For a child table pass the table fieldname as the second argument. The fieldname must be the link field on **that** DocType.
- Use `frm.set_value` / `frappe.model.set_value`, not `frm.doc.x = ...`; direct assignment skips change triggers and form state. `await frm.set_value(...)` when later logic depends on the result.
- Change handlers can trigger each other. Guard against loops (`if (frm.doc.x === new) return;`) and avoid calling `set_value` inside `validate`.
- `refresh` fires often; buttons, banners (`frm.dashboard.add_comment`, `frm.set_intro`) and event bindings added there must be cleared or conditional.
- `frm.is_new()` for unsaved docs; check `frm.doc.docstatus` and `frm.doc.__islocal` before enabling edits. Read-only submitted forms need `allow_on_submit` for editable fields.
- Visibility/required: `frm.toggle_display`, `frm.toggle_reqd`, `frm.set_df_property(field, "read_only", 1)`; for child grids use `frm.fields_dict.items.grid.update_docfield_property(...)` or `grid.toggle_reqd`.
- Handlers for the same DocType from multiple scripts/apps all run; order is load order. Do not assume yours is last.
- Context correctness: company, party, warehouse, cost center, price list, and item-tax filters must read from the right document (parent `frm.doc` vs the child row).
- `frappe.call` for anything authoritative; never treat client checks as security. Debounce server calls on frequently firing events; cache lookups per value.
- ERPNext standard forms already set many queries/fetches (`erpnext.queries.*`, controller JS under `erpnext/public/js/controllers`); read them before overriding, and extend by registering extra handlers instead of replacing prototypes.

## Quick patterns
- Confirm: `frappe.confirm(__("Proceed?"), () => {...})`; prompt: `frappe.prompt([...], (values) => {...}, __("Title"))`.
- Open a mapped document: `frappe.model.open_mapped_doc({ method: "...make_x", frm })`.
- List view: `frappe.listview_settings["Sales Invoice"] = { add_fields: [...], get_indicator(doc) {...} };`
- Realtime: `frappe.realtime.on("event", cb)` and `frappe.publish_realtime` server side.

## Testing
New doc, existing draft, submitted (read-only), cancelled, empty values, changing the link field after rows exist, multiple rows, copy/duplicate document, and mobile width. After deploying JS: `bench build --app my_app`, clear cache, hard refresh. Check the browser console and Network tab.
