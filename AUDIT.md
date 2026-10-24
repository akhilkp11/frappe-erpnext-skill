# Audit of the original pack, and what changed

## Original pack: findings
| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | `install.sh` moved old skills to `~/.claude/skills/<name>.backup-<stamp>`, i.e. **inside** the skills folder. Those copies still contain `SKILL.md`, so they can be loaded as duplicate skills. | High | Backups now go to `~/.claude/skills-backup/<stamp>/`. Added `--project`, `--dry-run`, `--only`; argument validation. Tested. |
| 2 | `frappe-testing-debugging` told users to use `FrappeTestCase`. Current Frappe documents it as deprecated in favor of `IntegrationTestCase` / `UnitTestCase` (from `frappe.tests`). | High | Rewritten; old class mentioned only as legacy. Lint rule F010 flags it. |
| 3 | README said "8 skills" but listed and shipped 9. | Low | README rewritten and counts match. |
| 4 | Skills were mostly generic cautions ("inspect the source", "test carefully") with almost no code, commands, queries, or version facts. They repeated the same safety bullets in every file. | High (value) | Each skill now has concrete patterns, snippets, tables, and failure modes; shared safety rules live in `CLAUDE.md.example`. |
| 5 | Descriptions were passive; Claude tends to under-trigger skills. | Medium | Descriptions now name concrete triggers (symptoms, doctypes, commands). |
| 6 | No v15 vs v16 facts (Python/Node/MariaDB, hook options, test classes). | Medium | Added with "verify in installed source" markers. |
| 7 | No coverage of security/permissions, background jobs, DocType design, data migration, India GST/TDS, app structure, or code review; no scripts. | Gap | 8 new skills and 4 helper scripts. |
| 8 | `frappe-performance` said `frappe.db.get_list` without noting `get_list`/`get_all` default limits differ. | Low | Clarified in `frappe-core`. |

## Verified against current sources (web, Oct 2026)
- `IntegrationTestCase`/`UnitTestCase` import from `frappe.tests`; `FrappeTestCase` deprecated (Frappe framework docs, testing overview and integration testing pages).
- Frappe v16 requirements: Python 3.14, Node 24, MariaDB 11.8 recommended; v15 supports Python 3.10-3.13; bench installed via `uv` (Frappe framework installation docs).
- GST, e-invoice, e-way bill, TDS and GST returns come from the India Compliance app; GSTR-1 is a snapshot needing regeneration/Reset; unfiltered reports combine all GSTINs; GSTR-3B uses an ITC Claim Period; GSTR-9/6/7 are not generated; new Tax Withholding Categories arrive by updating India Compliance (ERPNext docs pages `india-gst-help`, `gstr-1-missing-or-mismatch`, `gst-wrong-on-invoice`).

## Based on secondary sources or memory (flagged "verify" in the skills)
- `extend_doctype_class` as a v16 hook (seen in third-party skill packs; confirm in installed Frappe).
- `frappe.enqueue(job_id=..., deduplicate=True)`, `frappe.rate_limiter.rate_limit`, `/api/v2`, `frappe.cache` vs `frappe.cache()`, Print Settings PDF generator options, `bench` flag names, default queue timeouts.
- Document event order (from the structure of `frappe/model/document.py`); India Compliance exact field names; Frappe Cloud capabilities per plan.
- The query-builder date slice idiom in the report skeleton.

## Testing performed
- All 17 `SKILL.md` frontmatters validated (name matches folder, lengths, no angle brackets).
- `frappe_lint.py`: run on a synthetic app with 13 planted issues (all detected; safe code and patch commits not flagged).
- `hooks_audit.py`: run on a synthetic 3-app bench (duplicate `doc_events`, override conflicts, wildcard, non-literal hooks all reported).
- `detect_env.sh`: run on a synthetic bench; secret values confirmed absent from output (found and fixed a bug where the config sections printed nothing).
- `backup_status.sh`: run on synthetic backups (found and fixed a public/private file pattern overlap).
- `install.sh`: fresh install, reinstall with backup location, `--only`, `--dry-run`, `--project`, bad argument.

## Not tested
Nothing was run against a live Frappe/ERPNext bench, and the skills were not trial-run through Claude Code task evaluations. Treat code snippets as patterns to confirm on a development site for your exact versions.
