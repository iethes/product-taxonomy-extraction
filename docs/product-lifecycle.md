# Product Lifecycle — From Raw Listing to Canonical Taxonomy

> How a single Shopee product travels through the pipeline: what data we read, in
> what order, how we decide its brand and its canonical product entry, and how we
> decide whether to **match an existing taxonomy entry or create a new one**.
>
> Read this after [README.md](../README.md) and [ARCHITECTURE.md](../ARCHITECTURE.md).
> This document is the "what happens to one product" narrative; ARCHITECTURE.md is
> the "what tables exist" reference; [llm-extraction-rules.md](llm-extraction-rules.md)
> is the rulebook the LLM follows at each decision point.

---

## 1. The inputs — what we have about one product

Every Shopee product (`product_id`) arrives with the following raw signals. They are
listed in **trust order** — the order we consult them when extracting an attribute.

| # | Signal | Source column / asset | Trust | Why this rank |
|---|--------|-----------------------|-------|---------------|
| 1 | **Product title** | `master_clean_niq.sku_name` | Highest for *text-stated* facts | Seller types size/pack explicitly here far more often than anywhere else |
| 2 | **Product image** | image URL (LLM multimodal reads it) | Highest for *visual* facts | The pack shot is ground truth for brand, product line, variant, and bundle count |
| 3 | **Option / variant list** | model rows under the product | Authoritative for multi-variant | Distinguishes "5 sizes to choose" from "5-pack" |
| 4 | **Product specification** | `raw_niq_history.product_specification` | Fallback | Structured but inconsistently filled by sellers |
| 5 | **Product description** | `raw_niq_history.product_description` | Last resort | Free text, marketing-heavy, lowest signal |

**Key rule (size & pack extraction priority):**

```
sku_name text  →  product image  →  product_specification  →  product_description
```

We never override a size that is clearly stated in `sku_name` with a guess from the
image. We only descend to `product_specification` / `product_description` when the
higher-trust signals are silent or ambiguous. Full rules in
[llm-extraction-rules.md §2 (Size)](llm-extraction-rules.md) and
[§1 (Pack Count)](llm-extraction-rules.md).

> **Note on grain:** the source is at *model/variant* grain
> `(product_id, model_id, month)`. A single `product_id` may have many model rows
> (one per size/colour). We resolve taxonomy at the **product** level
> `(product_id, master_table)` — one canonical entry per listing. See
> [ARCHITECTURE.md → Data Granularity](../ARCHITECTURE.md#data-granularity).

---

## 2. The two outputs — what we produce

A product ends up described by **two independent resolutions**, written to two tables:

| Resolution | Question it answers | Table | Key output |
|------------|--------------------|-------|-----------|
| **Brand** | "Who makes this?" | `product_brand_map` | `brand_id` → `brand_dict.canonical_name` |
| **Taxonomy** | "Exactly which product is this?" | `product_taxonomy_map` | `taxonomy_id` → `product_taxonomy.canonical_name` |

These are deliberately separate. Brand is resolved first, at scale, by string
matching (Stages 02–03). Taxonomy is resolved later, per category, by LLM
multimodal extraction (Stage 05 / Phase 5). The taxonomy step can also **correct**
a wrong brand it discovers by reading the image (see §6).

Both are finally stamped onto `marketshare_universe`, the table analysts query.

---

## 3. Stage flow for one product

```
                      ┌─────────────────────────────────────────┐
   RAW LISTING        │ product_id, sku_name, brand(maybe blank),│
   (master_clean_niq) │ image, gmv, merchant_name, merchant_badge│
                      └───────────────────┬─────────────────────┘
                                          │
        ┌─────────────────────────────────┴──────────────────────────────┐
        │                                                                  │
        ▼ STAGE 02–03  (brand resolution, all categories, string-based)    │
  ┌──────────────────────────┐                                            │
  │ Match brand string against│   source = BRAND_FIELD       (best)        │
  │ brand_dict:               │          | PRODUCT_NAME_SCAN              │
  │  - Shopee brand field?    │          | FALLBACK → BRD-UNDEFINED       │
  │  - else scan sku_name?    │                                            │
  │  - else BRD-UNDEFINED     │   → writes product_brand_map row           │
  └──────────────────────────┘                                            │
        │                                                                  │
        ▼ STAGE 05 / PHASE 5  (taxonomy resolution, per category, LLM)     │
  ┌──────────────────────────────────────────────────────────────────┐   │
  │ PASS 1 — Official stores      |   PASS 2 — Resellers (95% GMV)     │   │
  │ Read image + sku_name → extract: brand_from_image, product_line,   │   │
  │ size, pack_count, variant flags                                    │   │
  │                                                                    │   │
  │            ┌──────────── MATCH-OR-CREATE (see §4) ───────────┐     │   │
  │            │ Does an entry exist for this exact              │     │   │
  │            │ brand × product_line × size × pack_count?       │     │   │
  │            │   YES → reuse taxonomy_id                       │     │   │
  │            │   NO  → mint new SKU-XXXXXX, insert into        │     │   │
  │            │         product_taxonomy                        │     │   │
  │            └────────────────────────────────────────────────┘     │   │
  │                                                                    │   │
  │ → writes product_taxonomy_map row (source=LLM, brand_from_image,   │   │
  │   brand_mismatch flag)                                             │   │
  └──────────────────────────────────────────────────────────────────┘   │
        │                                                                  │
        ▼ UNIVERSE REFRESH (targeted DML UPDATE)                           │
  ┌──────────────────────────────────────────────────────────────────┐   │
  │ Join product_taxonomy_map → product_taxonomy → niq_category_mapping │◄─┘
  │ → product_brand_map → brand_dict                                   │
  │ Stamp onto marketshare_universe: taxonomy_id, sku_type_complete,   │
  │ brand, taxonomy_source/confidence/meta_agent                       │
  │ (LLM beats HUMAN; lower taxonomy_id breaks ties)                   │
  └──────────────────────────────────────────────────────────────────┘
```

---

## 4. The match-or-create decision (the heart of Phase 5)

For each product, after the LLM has extracted `{brand_from_image, product_line,
size, pack_count, variant flags}`, it must decide: **does this map to a taxonomy
entry that already exists, or do we mint a new one?**

### 4.1 The matching key

A taxonomy entry is uniquely identified, conceptually, by:

```
brand_id  ×  product_line  ×  sub-line/variant  ×  size  ×  pack_count
```

Two products map to the **same** `taxonomy_id` only if **all five** agree. A
difference in *any* component is a different product and needs its own entry:

- `Vaseline Gluta-Hya Serum Burst 400ml` ≠ `...400ml x2` (pack differs)
- `Vaseline Gluta-Hya Serum Burst 400ml` ≠ `...330ml` (size differs)
- `Enfalac Stage 2 400g` ≠ `Enfagrow Stage 2 400g` (brand/line differs — **never** merge)

### 4.2 Decision procedure

```
1. BRAND GATE (hard).
   Resolve brand_id from brand_from_image. Only consider existing taxonomy
   entries with the SAME brand_id. Never match across brands by similarity
   of line/size alone. (Decision 19 — formula milk taught us this.)

2. CATEGORY GATE (hard).
   Only consider entries that belong to THIS category. Never route a face
   moisturizer to a shampoo entry even if brand matches. (Origin: 1,802
   cross-category contamination rows found in moisturizer_for_face.)

3. TYPE GATE (hard, where the category has product types).
   wet food ≠ dry food; lotion ≠ oil; toothpaste ≠ mouthwash. A type
   mismatch is never a match. (Decision 17 / 18.)

4. SPECIFICITY MATCH (ordered).
   Among surviving candidates, match the MOST SPECIFIC phrase first, then
   fall back to generic. "Oil Control Gel Cream" before "Oil Control".
   (Decision 12.)

5. SIZE + PACK MATCH.
   Require size AND pack_count to match. If the brand+line entry exists but
   not at this size/pack, that is a CREATE, not a match.

6. RESULT:
   - All gates pass + exact size/pack found  → REUSE taxonomy_id
   - Brand+line+category+type OK but size/pack absent → CREATE new entry
   - No entry for this brand+line at all → CREATE new entry
   - Cannot confidently read brand or line → UNRESOLVED (see §5)
```

### 4.3 When to CREATE a new entry

Create a new `SKU-XXXXXX` when **any** of these is true:

- No entry exists for this `brand_id` in this category.
- An entry exists for the brand+line but **not at this size** (e.g. taxonomy has
  `400g` but the product is `800g`).
- An entry exists for the brand+line+size but **not at this pack_count** (e.g.
  taxonomy has the single, product is `x12` bulk case).
- A new **flavor/variant** appears that has no entry (e.g. Pepsi Zero Sugar when
  only Pepsi Cola exists — silent fallback to the wrong flavor is a known failure
  mode; create the variant).

> **Better a new entry than a wrong match.** A correct-but-granular taxonomy is
> fixable by merging later; a product silently routed to the wrong entry corrupts
> every brand/size/pack analysis downstream and is invisible until QA. This is why
> `UNRESOLVED` and "create new" are always preferred over nearest-match.

### 4.4 Reuse rules to avoid duplicate entries

Before minting a new SKU:

- **Query `MAX(taxonomy_id)` from BigQuery immediately before the first insert** —
  not from notes, which may be stale if a parallel session ran. Assign
  non-overlapping 1,000-slot blocks per category. (Decision 16 — we have hit real
  collisions, e.g. drinking-water vs toothpaste both grabbing `SKU-045000`.)
- **Dedup within the run:** the same `product_id` can appear as several model rows;
  keep exactly one map row (most specific entry wins). One product = one
  `product_taxonomy_map` row.
- Pass 2 routes to entries Pass 1 already created before creating its own
  catch-alls — official-store extraction is more reliable, so it seeds the
  taxonomy first.

---

## 5. UNRESOLVED — the valid "I don't know" output

If the LLM cannot confidently determine the product's **brand** or **product
line** (unreadable label, ambiguous multi-product listing, mystery box), the
correct output is **UNRESOLVED** — leave the product unmapped (`taxonomy_id`
stays NULL in the universe). We do **not** force it into a catch-all of a
different type or brand.

UNRESOLVED is not a failure; it is a signal that either (a) the listing genuinely
can't be resolved from available data, or (b) a new taxonomy entry is needed. It
keeps the dataset honest: a NULL is a known gap; a wrong mapping is a hidden
error.

---

## 6. Brand correction during taxonomy (the feedback loop)

Phase 5 reads the product image, so it sees the *actual* brand on the pack. If
that disagrees with the brand we assigned in Stage 03:

```
IF brand_from_image ≠ brand_dict.canonical_name(product_brand_map.brand_id)
   AND product_brand_map.source IN ('PRODUCT_NAME_SCAN', 'FALLBACK')   -- low-trust
THEN flag brand_mismatch = TRUE on the product_taxonomy_map row
```

We do **not** silently auto-rewrite the brand. Mismatches are flagged for review;
confirmed ones trigger a `brand_dict` / `product_brand_map` update and a partial
universe re-run. If the original brand source is `BRAND_FIELD` or `HUMAN` (high
trust), we keep it and skip the check.

Real examples caught this way: a *Vaseline* official store listing *Citra*
products; a *Banana Boat* listing selling *Sunplay*. See
[docs/categories/th_suncare.md](categories/th_suncare.md).

---

## 7. Worked example — one product, end to end

**Raw listing** (in `master_clean_niq.shopee_th_body_wash`):

```
product_id     : 27472551988
sku_name       : "Shokubutsu Monogatari Vacation Series ครีมอาบน้ำ 500ml [แพ็คคู่ x2]"
brand          : ""                       ← blank in Shopee field
merchant_name  : "Lion Shop Online"       ← multi-brand official store
merchant_badge : "Shopee Mall"
image          : <pack shot of two green Shokubutsu bottles>
```

**Stage 03 — brand resolution (string-based):**
- Shopee `brand` field is blank → can't use BRAND_FIELD.
- Scan `sku_name` → "Shokubutsu" matches `brand_dict` → `brand_id = BRD-...` (Shokubutsu), `source = PRODUCT_NAME_SCAN`, lower confidence.
- Row written to `product_brand_map`.

**Stage 05 — taxonomy extraction (Pass 1, official store):**
1. **Read image + sku_name.** `brand_from_image = "Shokubutsu"` → matches the
   PRODUCT_NAME_SCAN brand, so `brand_mismatch = FALSE`. (Lion Shop is multi-brand,
   so this confirmation matters — see §6.)
2. **Extract attributes** (priority order, §1): size `500ml` (stated in
   `sku_name`), pack_count `2` (`[แพ็คคู่ x2]` — square-bracket form is always a
   genuine pack, not a selector), product_line `Vacation Series`.
3. **Match-or-create (§4):**
   - Brand gate → consider only Shokubutsu entries.
   - Category gate → only body_wash entries.
   - Specificity → `Vacation Series` line.
   - Size+pack → is there a `Shokubutsu Vacation Series 500ml x2`? **No** — only a
     single `500ml` exists. → **CREATE** `SKU-036021` =
     `"Shokubutsu Vacation Series Shower Cream 500ml x2"`.
4. **Write `product_taxonomy_map`** row: `product_id 27472551988 → SKU-036021`,
   `source = LLM`, `brand_from_image = Shokubutsu`, `meta_agent = CLAUDE_CODE`.

**Universe refresh:**
- DML UPDATE stamps `marketshare_universe`:
  `taxonomy_id = SKU-036021`,
  `sku_type_complete = "Shokubutsu Vacation Series Shower Cream 500ml x2"`,
  `brand = "Shokubutsu"`, `taxonomy_source = LLM`.

Analysts can now see this listing's true size and that it is a **2-pack** — which
doubles its effective unit volume in any price-per-ml or units-sold analysis.

---

## 8. Where each rule lives (so you can go deeper)

| You want to know… | Read |
|-------------------|------|
| The exact attribute-extraction rules (pack, size, GWP, false positives) | [docs/llm-extraction-rules.md](llm-extraction-rules.md) |
| Per-category brand scope, official-store allowlist, edge cases | [docs/categories/](categories/) (one file per category) |
| Table schemas and column definitions | [ARCHITECTURE.md → Table Schemas](../ARCHITECTURE.md#table-schemas) |
| Why two-pass / why LLM / why GMV threshold | [docs/decisions/ADR-005](decisions/ADR-005-product-taxonomy-architecture.md) |
| How to actually run a category extraction | [docs/runbook.md](runbook.md) |
| What's done vs pending, SKU range map | [docs/categories/STATUS.md](categories/STATUS.md) |
| QA gates that must pass before universe refresh | [docs/quality-standards.md](quality-standards.md) |
