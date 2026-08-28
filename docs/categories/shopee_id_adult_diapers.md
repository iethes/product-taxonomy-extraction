# shopee_id_adult_diapers — Category Context

> First-run Full Rebuild session, 2026-08-21. Month reviewed: 2026-06 (latest available;
> table has data through 2026-06-01, back to 2025-09-01).

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (7 official-store brand batches) |
| LLM Pass 2 | ✅ Complete (7 reseller-routing batches: 4 no-official-store brands + Lifree/Confidence/remaining-brand reseller top-ups) |
| GMV Coverage | 89.1% overall (41.10B / 46.13B IDR, GWP-zeroed), 89.9% on the Rule-A in-scope set (1,199/1,498 products) — both exceed the ≥85% Pass-2 target in `docs/quality-standards.md` §6 |
| Last run | 2026-08-21 |
| Current MAX taxonomy_id | SKU-346564 (650 taxonomy rows created in this session, range SKU-344804–SKU-346564, block SKU-344804–SKU-346803 remains ACTIVE with ~240 unused slots) |

**Note on ARCHITECTURE.md/data-dictionary.md:** both docs describe `master_clean_niq` as "Shopee SG+TH" only
and `brand_dict.country_scope` as `SG`/`TH`/`GLOBAL` only. Both are stale — `master_clean_niq.shopee_id_*`
tables exist and are populated (this table: 1,123,602 rows across 2025-09 to 2026-06), and `brand_dict` has
8,765 `ID`-scoped rows. Confirmed live 2026-08-21, not guessed.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-344804–345053 (250) | Pass 1: Lifree/Certainty/CHARM (Unicharm parent stores) — 88 entries used |
| SKU-345054–345153 (100) | Pass 1: Confidence — 54 entries used |
| SKU-345154–345253 (100) | Pass 1: Oto/BP — 34 entries used |
| SKU-345254–345303 (50) | Pass 1: Popoku — 27 entries used |
| SKU-345304–345353 (50) | Pass 1: Wings Care / Happily — 6 entries used |
| SKU-345354–345403 (50) | Pass 1+2: Lively (official store + reseller) — 30 entries used |
| SKU-345404–345453 (50) | Pass 1: PARENTY — 12 entries used |
| SKU-345454–345603 (150) | Pass 2: Ideal + HAPPILY resellers — 11 entries used |
| SKU-345604–345753 (150) | Pass 2: Starcare + SENSI resellers — 20 entries used |
| SKU-345754–345903 (150) | Pass 2: TOP + Mom & Dad resellers — 50 entries used |
| SKU-345904–346053 (150) | Pass 2: Wecare + ANDLOVE resellers — 14 entries used |
| SKU-346054–346353 (300) | Pass 2 top-up: Lifree resellers — 114 entries used |
| SKU-346354–346553 (200) | Pass 2 top-up: Confidence resellers — 182 entries used |
| SKU-346554–346803 (250) | Pass 2 top-up: Oto/BP/Popoku/Wings/PARENTY resellers — 11 entries used |

Block SKU-344804–346803 (2000 slots) status: **ACTIVE**, ~240 slots unused, safe to reuse for a future top-up
session on this category (per `docs/headless-runbook.md`, no "COMPLETE" status transition exists for a
successful run — only `FAILED_QA` on failure).

---

## Brand Scope (GMV threshold 95%, GWP-zeroed, month 2026-06)

**Method:** ranked all distinct `brand` values by `SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)`,
with three token-level normalizations applied first (confirmed via sku_name inspection, not assumed):
- `Oto Pants` → merged into `Oto` (it's Oto's pants/celana product line, not a separate brand)
- `Bulk Pack` → merged into `BP` (same OTO-Diapers-store budget sub-brand; `BP` already exists in
  `brand_dict` as `BRD-GLOBAL-01093`, `Bulk Pack` is just an inconsistent raw-text variant of it)
- `We Care` → merged into `Wecare` (spacing variant of the same brand)

**The raw `brand` column is unreliable for this category** — 9.4% of category GMV sits under blank/`-`
brand values (the `(unresolved)` row below). Sampling those rows shows real, already-in-scope brands
(mostly Lifree) whose sellers simply left the brand field empty; per `llm-extraction-rules.md` §9's phonetic-
brand precedent and the softdrink changelog's "taxonomy mapping does not require brand_id consistency with
product_brand_map" rule, these products still get extracted and routed to the correct taxonomy entry by
reading `sku_name`/image — the raw brand column is a ranking input only, never a scope filter (see
`llm-extraction-rules.md` §8, "keyword gate... must never be used to decide whether an individual product
gets extracted").

**16 real brands reach the 95% cumulative threshold** (the `(unresolved)` bucket is excluded from this
enumeration — it isn't a brand — and is documented separately):

| Rank | Brand | brand_id (brand_dict) | GMV (IDR) | Cumulative |
|---|---|---|---|---|
| 1 | **Lifree** | `BRD-GLOBAL-00024` | 8.52B | 18.5% |
| 2 | **Confidence** | `BRD-TH-03303` ⚠️ TH-scoped, likely needs an ID-scope entry — see below | 8.43B | 36.7% |
| 3 | **Ideal** | *not found in brand_dict* | 6.91B | 51.7% |
| — | *(unresolved / blank brand field)* | — | 4.38B | 61.2% — **not a brand, see note above** |
| 4 | **Lively** | *not found in brand_dict* | 2.66B | 67.0% |
| 5 | **HAPPILY** | *not found in brand_dict* | 2.05B | 71.4% |
| 6 | **Oto** (incl. "Oto Pants") | *not found in brand_dict as "Oto"* | 1.98B | 75.7% |
| 7 | **Starcare** | *not found in brand_dict* | 1.55B | 79.1% |
| 8 | **BP** (incl. "Bulk Pack") | `BRD-GLOBAL-01093` | 1.34B | 82.0% |
| 9 | **SENSI** | `BRD-ID-08616` (ID) — note `BRD-TH-00243` also exists, TH scope, do not use | 1.31B | 84.8% |
| 10 | **PARENTY** | *not found in brand_dict* | 1.23B | 87.5% |
| 11 | **Wings Care** | `BRD-ID-05611` | 1.10B | 89.9% |
| 12 | **TOP** | `BRD-SG-14514` (SG scope) or `BRD-SG-00709` (status=GARBAGE, do not use) — no ID entry | 684M | 91.4% |
| 13 | **Mom & Dad** | *not found in brand_dict* | 674M | 92.8% |
| 14 | **Popoku** | `BRD-ID-08619` | 538M | 94.0% |
| 15 | **Wecare** (incl. "We Care") | *not found in brand_dict* | 455M | 95.0% |
| 16 | **ANDLOVE** | `BRD-TH-00016` (TH scope) — no ID entry | 451M | 96.0% |

**Finding for a human/future session (RESOLVED 2026-08-21 — see below):** 10 of these 16 brands had no
`brand_dict` entry at all, and 3 more (`Confidence`, `TOP`, `ANDLOVE`) only existed under the wrong country
scope (TH/SG instead of ID). This mirrors the `brand_dict` gap pattern already on record for other ID
categories (see `alatmusik_id` memory precedent). At the time this session was first run, taxonomy entries
were left with `brand_id = BRD-UNDEFINED` under the reasoning that `product_taxonomy_map` doesn't require
`brand_id` agreement with `product_brand_map`/`brand_dict`, citing the softdrink Coke/Fanta precedent — **that
reasoning doesn't actually apply here**: the softdrink precedent is about `product_brand_map`'s per-product
brand assignment being `BRD-UNDEFINED` while its `product_taxonomy` entry still correctly resolves to a real
Coca-Cola/Fanta `brand_id`. Here it was `product_taxonomy.brand_id` itself sitting at `BRD-UNDEFINED` — the
taxonomy entry (the shared record every mapped product routes through) had no real brand identity, which
also weakens `docs/product-lifecycle.md` §4.2's brand-gate matching (multiple genuinely different brands
sharing the literal string `BRD-UNDEFINED` can't be told apart by that gate). See "Brand backfill" below for
the fix.

**Brands below the 95% tail (not in scope):** ONEMED (96.5%), Certainty (96.9%), Pamperindo (97.4%),
unicharm-as-raw-brand-string (97.7%, note: Unicharm *is* in scope as the parent-company official store for
Lifree/Certainty/CHARM — see Official Store Allowlist), Laurier (98.0%, also see Scope §, these are
menstrual pads not adult diapers), and ~110 smaller brands/tail values below that.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` for month 2026-06, then
matching against the 16 in-scope brands and manually excluding multi-brand retailers.

**This category's Mall-badged pool is dominated by multi-brand pharmacy/reseller chains** — the ID
equivalent of the TH/SG Watsons/Boots/BigC exclusion list in `llm-extraction-rules.md` §4. 6,418 Mall-badged
rows / 5,909 distinct products exist, but only **613 distinct products** sit under a genuine single-brand or
parent-company official store. **Pass 1 must scope to the allowlist below only, not the full 5,909-product
Mall-badged pool** — the raw pool is ~10x over-inclusive.

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Lifree | `BRD-GLOBAL-00024` | `Lifree Official Store` |
| Lifree / Certainty / CHARM (parent co.) | — | `Unicharm Official Shop`, `Unicharm Authorized Partner Jawa Tengah`, `Unicharm Authorized Partner Jawa Barat`, `Unicharm Authorized Partner Jawa Timur` |
| Confidence | `BRD-TH-03303` (scope caveat above) | `Confidence Official Shop` |
| Oto (incl. BP sub-line) | — | `OTO ADULT DIAPERS OFFICIAL` |
| Popoku | `BRD-ID-08619` | `Popoku Official Shop` |
| Wings Care (parent: Wings) | `BRD-ID-05611` | `Wings Official Shop` |
| Lively | — | `Lively Popok Dewasa` |
| PARENTY | — | `Parenty Official Store` |

**Excluded multi-brand retailers (never Pass 1, regardless of Mall badge)** — confirmed by sampling each
store's `brand` column and finding 2+ unrelated in-scope brands, or by chain-name recognition:
- **Pharmacy chains:** every `Apotek *` store (dozens — Alpro, K-24, Farmaku, Vita Farma, Mandjur, etc.),
  every `Century *` / `Century Authorized Store *` location (major ID pharmacy chain, ID's Watsons/Guardian
  analogue), `Viva Apotek *`
- **Grocery/hypermarket chains:** `Hypermart *`, `Yogya Online Supermarket Official Shop`, `Segari - *`
  (multiple locations), `Foodmart Basko Padang`, `Supermarket Instant Cempaka Putih`, `KLiK INDOMARET *`
- **Multi-brand baby/health resellers (badged "Official" but sell 3+ unrelated brands):** `Raja Susu
  Official *` (multiple cities — sells HAPPILY/Confidence/PARENTY/SENSI/Oto interchangeably), `NM Baby Shop
  Official Store`, `Mommy n Me Official Shop`, `Fluffy Official Shop`, `MBJCARE Official Store`,
  `FOODIESHOP Official Store`, `Sehati Healthcare`, `Halodoc Official Shop`, `KlikDokter Official Shop`,
  `Cici Sehat Official Store`, `Montalk Official Store`, `Heneco Beauty Official Store`, `Claires Baby
  Indonesia`, `KedaiMart Official Shop`

**Brands with no official store found (Pass 2 only):** Ideal, HAPPILY, Starcare, SENSI, TOP, Mom & Dad,
Wecare, ANDLOVE. Verified — each appears only inside the multi-brand stores excluded above, never under a
single-brand or parent-company store name.

---

## Scale

- Total rows (month 2026-06): 28,808
- Distinct products (month 2026-06): 16,261
- **Rule A in-scope set (top-95%-cumulative-GMV products, GWP-zeroed):** 1,498 products — this is the real
  per-product review denominator, not the raw 16,261.
- Raw Mall-badged rows/products: 6,418 / 5,909 — **do not use this as Pass 1 scope directly**, see above.
- Official Store Allowlist distinct products: 613 — this is the actual Pass 1 scope.
- Existing `product_taxonomy_map` rows for this table: **0** (confirmed live, both `HUMAN` and `LLM` — this
  is a genuine first LLM pass with no prior keyword-seed coverage at all, unusual for this pipeline but
  confirmed, not assumed).

---

## Scope — What's In vs Out

**In scope:**
- Adult diapers, both form factors: `celana`/`pants` (pull-up) and `perekat`/`tape` (taped/wrap style) —
  these are a real product-line-level split within a brand, not interchangeable (e.g. Lifree sells both;
  structure `product_line` around this distinction, not collapsed).
- Underpads / bed pads (`perlak`, `alas`, `underpad`) sold under adult-diaper-focused brands (Sensi, Onemed,
  Lively, OTO, Dr J) — same buyer need (incontinence/bed protection), consistently appears in this category's
  source data grouped with diapers.
- Multi-size buyer-choice listings (`Size M L XL XXL` selectable in one listing) — very common in this
  category. Set `is_multi_size=TRUE`. **canonical_name must never contain "Multiple Sizes"/"All Sizes"** —
  the placeholder-leak QA gate hard-fails on that phrase even with the flag correctly set. Use brand + line
  only, no size suffix.

**Out of scope (leave NULL, or route to `category_scope_exceptions` once confirmed):**
- Menstrual/feminine hygiene pads (`pembalut` when the product is explicitly for menstruation, e.g. Laurier
  "Relax Night Pembalut Malam" — a night-time menstrual pad, not an incontinence product). Confirmed live:
  `Kao Official Shop` sells Laurier menstrual pads inside this table's data — wrong category, not a diaper
  or underpad.
- Incontinence/urine pads (e.g. "CharmNap Urine Dry Pembalut Urine") are a genuine edge case — read the
  product image/description; if marketed for urine incontinence (adult care) treat as in-scope, if marketed
  for menstruation treat as out-of-scope. Do not default either way from the word `pembalut` alone.

**Edge cases:**
- `Oto Pants` / `Bulk Pack` / `We Care` in the raw `brand` column are not real distinct brands — see Brand
  Scope normalization above.
- Products with blank/`-` brand field: do not skip. Read `sku_name` — many are legitimate Lifree/other
  in-scope-brand listings the seller just didn't tag.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Split by form factor first: `{Brand} Pants` vs `{Brand} Perekat/Tape` (or the brand's own on-label line
  name if more specific, e.g. "Lifree Pants Sachet Renceng").
- Indonesian pack/size vocabulary (this category has no existing Thai-style §9 equivalent in
  `llm-extraction-rules.md` — first ID session to need one):
  - `isi N pcs` / `isi N` = contains N pieces → pack_count = N (only when there is no separate inner-bag
    layer — see the karton rule below when there is)
  - `renceng` / `sachet renceng` = individual sachet strip packaging (not a multiplier itself, describes
    packaging format)
  - `1 karton` / `dus` = one carton/box — **see "Karton / bulk-pack rule" below, do not just read this as
    a fixed multiplier**
  - `lusin` = dozen = 12
  - `beli 1 gratis 1` / `gratis` = "buy 1 get 1 free" — same GWP-vs-genuine-multipack logic as Thai `แถม`:
    same product free = pack_count includes the free unit; different product free = flag_GWP, pack_count
    unaffected
  - `per pack` = per pack (packaging descriptor, not itself a count — read the actual N)

**Karton / bulk-pack rule (category-scoped exception to `llm-extraction-rules.md`'s universal
`x{TOTAL}` rule — see pointer added to that file's changelog).** Corrected 2026-08-21 after a real
example: `SKU-345622` was `Sensi Underpad L x120 Karton`, derived from `"SENSI SUREPAD KARTON L10x12"` —
size L, 10 pcs per box, 12 boxes per karton. The listing text often has two layers: a per-bag/per-box
piece count, and an outer karton/dus multiplier (bags per karton). Rule:
- `pack_count` (the canonical name's `x{N}` suffix) = **the outer multiplier only** — how many bags/boxes/
  packs are in the karton (`12` in the example above), **never** the grand total pieces (`120`). A karton
  of 12 bags is `x12`, not `x120`, even though each bag itself holds 10 pieces.
- `size` stays the plain garment size (`S`/`M`/`L`/`XL`/`XXL`) or physical dimension (underpads, e.g.
  `60x90cm`) — **do not** glue the per-bag piece count onto it (not `"L10"`, not `"XL6"`). Per an explicit
  ruling from the category owner (2026-08-21): the per-bag/per-box piece count is **not tracked** as its
  own field on this schema (`size` + `pack_count` is all there is) — when a listing states it (e.g. "XL6",
  "10pcs"), that number is dropped rather than folded into `size` or `pack_count`. This is a known,
  accepted information loss for this category, not a bug to work around.
  Canonical formula stays `{Brand} {Product Line} {Sub-line} {Variant} {Size} x{N}` — `N` = outer
  multiplier, nothing else.
- `variant` must never be set to `"Karton"` (or `"Dus"`/`"Kartonan"`/similar packaging-format words) — that
  is not a product variant, it is Shopee reseller packaging noise. Leave `variant` NULL unless there is a
  real on-label variant (scent, formula, etc.). 4 of the 7 rows fixed below had `variant = 'Karton'` sitting
  unused in the column (didn't leak into `canonical_name` except on SKU-345622, but still wrong data).
- When the listing states only a single total with no separable inner-bag layer (e.g. `"21 pcs - EC
  Karton"`, no "X bag/pack" wording), that total is not a bulk-pack case — `pack_count` = the stated
  number as-is, same as the universal default. Only apply the outer-multiplier rule when the text actually
  states two layers (a per-bag count *and* a bag/pack count, e.g. `"isi 12 Bag"`, `"L 7 x 3 PACK"`).

**Known difficult products:**
- Products with blank/`-` brand and generic titles like `"pempers dewasa celana dan perekat/popok dewasa isi 20"`
  (merchant `aiswapopok`) — genuinely ambiguous which named brand, if any; route to a generic-brand catch-all
  entry rather than guessing a specific brand, or leave NULL if the image doesn't clarify.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-08-21 | Pre-run research | Raw `brand` column unreliable (9.4% GMV under blank/`-`); 10/16 in-scope brands missing from `brand_dict`, 3 more under wrong country scope | Documented above; taxonomy writes proceed with `BRD-UNDEFINED` where no real brand_id exists, per softdrink precedent — not a blocker |
| 2026-08-21 | Pre-run research | Mall-badged pool (5,909 products) is ~10x over-inclusive vs. real single-brand allowlist (613 products) — dominated by pharmacy/grocery/multi-brand-reseller chains | Official Store Allowlist scoped to 613 products across 8 real single-brand/parent-company stores |
| 2026-08-21 | Pass 1 (parallel batches) | `product_taxonomy_map.confidence` is a STRING column, not FLOAT as `data-dictionary.md` documents — a plain float literal INSERT fails without an explicit cast/string literal | Flagged to all subsequent batches; all writes used string literals (`'0.75'` etc.) |
| 2026-08-21 | Pass 1→2 orchestration gap | Initial batch plan gave Lifree/Confidence/Oto/BP/Popoku/Wings/PARENTY only Pass-1 (official-store) coverage, no Pass-2 reseller routing — left Rule-A coverage at 52.8% after the first 11 batches, with the two largest brands (Lifree 18.5% GMV, Confidence 18.5% GMV) almost entirely unreseller-routed | 3 follow-up batches (Lifree resellers, Confidence resellers, remaining-5-brands resellers) closed the gap to 89.9% Rule-A / 89.1% overall GMV coverage |
| 2026-08-21 | Reconciliation | 795 products (12,772→10,238 rows) had race-condition duplicate `product_taxonomy_map` rows from concurrent parallel batches — all confirmed same-`taxonomy_id` duplicates, not real routing conflicts (G1 gate) | Deduped via staging table (keep latest `mapped_at` per `product_id`), delete+reinsert; verified 0 dual-mapped after |
| 2026-08-21 | Reconciliation | 206 confirmed out-of-scope products found across batches: 123 menstrual/feminine-hygiene pads (Laurier, Softex, generic "menstruasi" listings), 81 "Blood Maximum Panty Pads" (menstrual line), 1 Pro Plan pet food, 1 vitamin C supplement — all wrong product type/category, not adult diapers | Bulk-inserted into `category_scope_exceptions` so they stop re-entering future sessions' coverage-gap counts |
| 2026-08-21 | QA gates (STEP 7) | All hard gates checked post-dedup: dual-mapped (LLM)=0, NULL platform=0, NULL country=0, HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields-NULL%=6% (well under 50% threshold) | All gates passed, no blockers |

---

## Targeted QA Fix Brief

**2026-08-21 — Karton/bulk-pack `pack_count` correction (partial, session done same-day as the Full
Rebuild above).** See "Karton / bulk-pack rule" under Taxonomy Design Notes for the rule. A sweep of all
`product_taxonomy_map` rows whose source `sku_name` contains `karton`/`dus isi`/`per dus`, cross-checked
against an explicit `"isi N bag/pack/ball/box"` or `"{size}{pcs} x N PACK"` pattern in that text, found 8
rows where the stored `pack_count` didn't match the explicit outer-multiplier number in the text. 7 fixed
directly (high-confidence, explicit multiplier text; `_meta` reset to unreviewed on each):

| taxonomy_id | Old canonical_name / pack_count | New canonical_name / pack_count |
|---|---|---|
| SKU-345359 | Lively Adult Diapers Perekat XL x72 | Lively Adult Diapers Perekat XL x12 |
| SKU-345361 | Lively Adult Diapers Celana M x80 | Lively Adult Diapers Celana M x8 |
| SKU-345370 | Lively Adult Diapers Celana XL x56 | Lively Adult Diapers Celana XL x8 |
| SKU-345382 | Lively Adult Diapers Underpad 60x90cm x120 | Lively Adult Diapers Underpad 60x90cm x12 |
| SKU-345622 | Sensi Underpad L x120 Karton | Sensi Underpad L x12 |
| SKU-345754 | TOP Adult Pants, pack_count=20 | TOP Adult Pants, pack_count=6 (canonical_name unchanged — see duplicate-name finding below) |
| SKU-345914 | Wecare Adult Diapers Celana L16 | Wecare Adult Diapers Celana L x6 |

1 skipped as genuinely ambiguous, needs a future session with image/human judgment, not a blind regex fix:
- **SKU-345414** "Parenty Adult Diapers Celana Trial Pack", stored `pack_count=2`, source text `"[ PAKET 1
  DUS isi 32 PACK ] PARENTY Adult Pants M/L/XL MINIPACK isi 2pcs"` — unclear whether `pack_count` should be
  `32` (dus multiplier) or stay `2` (the "MINIPACK isi 2pcs" the listing is actually selling one of).

**Known pre-existing issue found during this sweep, not fixed (out of scope for a pack_count-only pass):**
`SKU-345754`/`SKU-345755`/`SKU-345757` all share the literal `canonical_name` `"TOP Adult Pants"` with
different `pack_count` (6/22/11) as the only distinguishing field — a duplicate-canonical-name situation
worth a dedicated naming pass later (not a G1 dual-mapping violation, just confusing/collision-prone
naming).

**Not yet swept:** the karton/bulk-pack regex above only matched rows whose text had an explicit
`"isi N bag/pack"` phrase. Other `karton`/`dus`-mentioning rows in this category (dozens more, see the
Brand/Official-Store sections above) may carry the same total-vs-multiplier confusion in less regular
phrasing (e.g. `"1 Dus isi 48 pcs"` single-layer sachet listings are probably fine per the rule above, but
weren't individually verified) — a full pass through every `karton`/`dus` row is future work, not done
here.

**2026-08-21 — `brand_id = BRD-UNDEFINED` backfill (resolves the Brand Scope "Finding" above).** 159 of 672
`product_taxonomy` rows (3,833 of 10,630 `product_taxonomy_map` rows — the undefined-brand entries are
disproportionately high-mapping) sat at `brand_id = 'BRD-UNDEFINED'`. In every case but one, the real brand
was already correctly captured as the leading word(s) of `canonical_name` (and, for official-store products,
`merchant_name`) — `brand_dict` just had no matching ID-scoped entry. `brand_from_image` was empty for every
affected row (Pass 2 bulk-text-matched these; no image was read because sku_name text was unambiguous), so
the backfill used `canonical_name` + `merchant_name` corroboration, per `alatmusik_id`'s established method.

16 new `brand_dict` rows minted (`BRD-ID-08772`–`BRD-ID-08787`, `country_scope='ID'`, checked for name
collisions against existing `brand_dict` entries first — none found except `Andlove`/`TOP`, which already
had TH/SG-scoped entries; minted separate ID-scoped entries for those too per this brief's own
recommendation above, not reused cross-country): Andlove, Arwana, BIGred, Dr. Kang, Elvasense, Ideal,
Lively, Meliz, Mom & Dad, Oto, Pamperindo, Parenty, Sofcare, Starcare, TOP, Wecare. 157 taxonomy rows
repointed to these; 6 rows whose `canonical_name` says `(Unbranded)` repointed to `BRD-UNBRANDED` instead
(genuinely generic/no-brand listings, not a data gap). `_meta` reset to unreviewed on every touched row.

**1 row deliberately left `BRD-UNDEFINED`, not backfilled:** `SKU-346575` "GOPANTS Celana" — `sku_name`
("GOPANTS Popok Dewasa(Celana) M.15+3/L.12+2/XL.9+2-SUSUMURAH") has no real brand signal; "GOPANTS" is
very likely Sensi's own on-label product line name ("GoPants" — see `SKU-345619` "Sensi Celana GoPants
Reguler", already correctly attributed to Sensi `brand_id`), meaning this is probably a mis-extracted
duplicate that should be **rerouted** to the Sensi GoPants taxonomy entry, not a new brand. Needs a source
listing/image check before acting — not done here, flagged for a future session.

---

## Scripts

*(none yet — extraction performed directly in this session, no pipeline scripts written for this category)*

---

## Map Row Counts (as of last run, 2026-08-21)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 10,238 | Pass 1 (7 official-store batches) + Pass 2 (7 reseller batches), deduped post-run |
| HUMAN | 0 | This category had no prior keyword-seed coverage — genuine first LLM pass |
| NULL (unmapped) | ~6,023 of 16,261 distinct products | Below GMV scope, generic/unbranded long-tail resellers, or the 206 confirmed out-of-scope rows in `category_scope_exceptions` |

**Remaining gap (for a future top-up session, per `docs/headless-runbook.md`'s top-up scenario):** ~11% of
category GMV, concentrated in generic/unbranded reseller listings with no clear brand signal in text (e.g.
`"popok dewasa non kemasan 1karton isi 100 pcs"`), a residual Lifree/Confidence reseller long tail (~12% of
each brand's own GMV), and Onemed underpads (Onemed is below the 16-brand 95% threshold so has no dedicated
batch, but individual high-GMV Onemed products are still Rule-A eligible).
