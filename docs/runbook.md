# Operational Runbook

Step-by-step guide for running each pipeline stage. Run stages in order.

---

## Prerequisites (every session)

```bash
# 1. Copy credentials — /tmp clears on reboot
cp "/Users/magpie/Downloads/Magpie OpenClaw.json" /tmp/brand_audit_creds.json

# 2. Set working directory
cd /Users/magpie/marketshare-universe

# 3. Verify BQ access
/Users/magpie/google-cloud-sdk/bin/bq query \
  --project_id=sincere-hearth-273704 --nouse_legacy_sql \
  "SELECT COUNT(*) FROM \`sincere-hearth-273704.master_clean_niq.shopee_sg_shampoo\`"
```

**Python:** always use `/Users/magpie/.pyenv/versions/3.8.12/bin/python3` (has google-auth, pandas, BQ client)

**Working Sheet:** https://docs.google.com/spreadsheets/d/1MvJdpoccc63AMs8D0qShI7PhKZ2BrrJJP-kwvDbh40M
Tabs: `niq_category_mapping`, `brand_audit`, `brand_review`

---

## Stage 01 — Brand Audit

**Purpose:** Aggregate all 43 source tables into a ranked brand-per-category view. Output written to the `brand_audit` Sheet tab. Used as input for duplicate detection.

**When to re-run:** when source data is refreshed (new month added to master_clean_niq).

```bash
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 -u \
  pipeline/01_brand_audit/brand_audit.py 2>&1 | tee /tmp/brand_audit.log

# Takes ~10–12 minutes. Queries all 43 tables.
```

**Output:** `brand_audit` tab — columns: `country | magpie_cat_1 | magpie_cat_2 | end_category | rank | brand | raw_variants | avg_monthly_gmv | gmv_pct | cum_gmv_pct | products`

---

## Stage 02 — Taxonomy Build

**Purpose:** Detect duplicate brand names and build `magpie_reference.brand_dict`.

### Step 2a — Duplicate detection

Reads `brand_audit` tab, detects duplicate groups, writes decisions to BQ + Sheet.

```bash
# All 94 categories (default) — writes to BQ brand_review + Sheet brand_review tab
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/02_taxonomy_build/detect_duplicates.py

# Single category (for testing)
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/02_taxonomy_build/detect_duplicates.py --category "Body Lotion"

# Skip BQ write (print only)
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/02_taxonomy_build/detect_duplicates.py --no-bq --no-sheet
```

**Auto-decisions (no human needed):**
- `AUTO-RED` → same brand after full normalization → `MERGE`
- `AUTO-YELLOW` (fuzzy ratio ≥ 0.90) → near-identical → `MERGE`

**Human review needed:**
- `NEEDS-REVIEW` rows written to `brand_review` Sheet tab
- Reviewer fills `merge_decision` = `MERGE` or `SKIP`, and corrects `final_canonical` if needed

**Decision source flags:**
```
AUTO-RED        fuzzy_ratio = 1.0   always MERGE
AUTO-YELLOW     fuzzy_ratio ≥ 0.90  always MERGE
NEEDS-REVIEW    fuzzy_ratio 0.82–0.89  human decides
PATTERN-SKIP    known false-positive pattern  always SKIP
```

### Step 2b — Build brand_dict

After review decisions are saved in the Sheet, run:

```bash
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/02_taxonomy_build/build_brand_dict.py
```

**What it does:**
1. Loads brand_audit (all unique brand names per country)
2. Loads all MERGE decisions from BQ brand_review (AUTO) + Sheet brand_review (manual)
3. Builds merge map: every raw variant → one canonical_name
4. Assigns brand_ids: `BRD-GLOBAL-*`, `BRD-SG-*`, `BRD-TH-*` (sorted by GMV desc)
5. Adds reserved entries: `BRD-UNDEFINED`, `BRD-UNBRANDED`
6. Writes to `magpie_reference.brand_dict` (full replace)

**Output:** `magpie_reference.brand_dict` (~19,700 rows as of Jun 2026)
**Local backup:** `pipeline/02_taxonomy_build/brand_dict.csv`

---

## Stage 03 — Product Mapping

**Purpose:** Map every unique product across all 43 source tables to a `brand_id`. Writes to `magpie_reference.product_brand_map`.

```bash
# All 43 tables
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/03_product_mapping/build_product_brand_map.py

# Single table (test or re-run one)
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/03_product_mapping/build_product_brand_map.py \
  --table shopee_sg_hand_and_body_moisturiser

# Dry run — no BQ writes, prints stats only
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/03_product_mapping/build_product_brand_map.py \
  --table shopee_sg_hand_and_body_moisturiser --dry-run
```

**Takes ~2–3 hours for all 43 tables.** Script is idempotent — re-running a table deletes its existing rows and reinserts.

**If interrupted — resume from a specific table:**
```bash
# Check which tables are done
/Users/magpie/google-cloud-sdk/bin/bq query --nouse_legacy_sql \
  --project_id=sincere-hearth-273704 \
  "SELECT master_table, COUNT(*) AS n FROM \`sincere-hearth-273704.magpie_reference.product_brand_map\` GROUP BY 1 ORDER BY 1"

# Run remaining tables (safe — idempotent per table)
for t in shopee_sg_shampoo shopee_th_body_wash; do
  /Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
    pipeline/03_product_mapping/build_product_brand_map.py --table "$t"
done
```

**Mapping method priority:**
1. `BRAND_FIELD` (HIGH) — brand column filled, matched in brand_dict
2. `PRODUCT_NAME_SCAN` HIGH — brand found at start of sku_name
3. `PRODUCT_NAME_SCAN` MEDIUM — brand found anywhere in sku_name
4. `FALLBACK` (UNRESOLVED) — BRD-UNDEFINED or BRD-UNBRANDED

**Expected coverage (per table):**
- BRAND_FIELD: 30–45%
- SCAN: 45–60%
- FALLBACK: 5–10%

**Output:** `magpie_reference.product_brand_map`

---

## Stage 04 — Universe Append

**Purpose:** Join source data with brand and category mappings → write to `magpie.marketshare_universe`.

**Grain:** product-month level (model variants collapsed — GMV summed, variant count kept).
**Confidence:** all rows included (HIGH + MEDIUM + UNRESOLVED). Filter at query time.
**Idempotent:** DELETE month partition, then INSERT. Safe to re-run.

```bash
# Dry run first — estimates row count and cost, no writes
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/04_universe_append/build_marketshare_universe.py --dry-run

# Full run — Apr 2026 (default)
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 -u \
  pipeline/04_universe_append/build_marketshare_universe.py 2>&1 | tee /tmp/universe_append.log

# Different month
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/04_universe_append/build_marketshare_universe.py --month 2026-02

# Re-run same month without re-uploading category mapping (faster)
/Users/magpie/.pyenv/versions/3.8.12/bin/python3 \
  pipeline/04_universe_append/build_marketshare_universe.py --skip-cat-upload
```

**Takes ~2–3 minutes** (single BQ query — all joins done in BQ, not Python).

**Estimated cost:** ~$0.005 per month run (0.86 GB scan, same as brand_audit_resolved).

**What it does:**
1. Loads `niq_category_mapping` from Sheets, pre-expands for partial-key fallbacks, uploads to `magpie_reference.niq_category_mapping`
2. `CREATE TABLE IF NOT EXISTS magpie.marketshare_universe` (partitioned by month, clustered by country/magpie_category_3/brand_id)
3. `DELETE` existing rows for target month
4. `INSERT INTO ... SELECT` — single BQ query doing all 4 joins

**Output:** `sincere-hearth-273704.magpie.marketshare_universe_niq` (staging table for review)
15 columns: `month, country, master_table, product_id, sku_name, brand_raw, brand_id, brand_canonical, brand_confidence, brand_source, magpie_category_1, magpie_category_2, magpie_category_3, gmv, model_count`

**Review queries after running:**
```sql
-- 1. Category mapping sanity check — do all categories map correctly?
SELECT magpie_category_1, magpie_category_2, magpie_category_3,
       COUNT(*) AS products, ROUND(SUM(gmv)/1e6, 2) AS gmv_m
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
WHERE month = '2026-04-01' AND country = 'SG'
GROUP BY 1, 2, 3 ORDER BY 5 DESC;

-- 2. Brand confidence breakdown — is coverage acceptable?
SELECT brand_confidence, brand_source, COUNT(*) AS products
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
WHERE month = '2026-04-01'
GROUP BY 1, 2 ORDER BY 1, 2;

-- 3. Spot-check a category
SELECT brand_canonical, brand_id, brand_confidence, SUM(gmv) AS gmv
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
WHERE month = '2026-04-01' AND country = 'SG' AND magpie_category_3 = 'Shampoo'
GROUP BY 1, 2, 3 ORDER BY 4 DESC LIMIT 20;
```

Once satisfied with the review, promote to the final table:
```sql
-- Promote: copy staging → production
INSERT INTO `sincere-hearth-273704.magpie.marketshare_universe`
SELECT * FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
WHERE month = '2026-04-01';
```

---

## Troubleshooting

### `/tmp` credentials missing
```bash
cp "/Users/magpie/Downloads/Magpie OpenClaw.json" /tmp/brand_audit_creds.json
```
`/tmp` clears on reboot. Always copy credentials at session start.

### `bq` not found
```bash
export PATH="/Users/magpie/google-cloud-sdk/bin:$PATH"
# Or use full path: /Users/magpie/google-cloud-sdk/bin/bq
```

### Wrong Python (missing google libs)
```bash
/Users/magpie/.pyenv/versions/3.8.12/bin/python3  # correct
/usr/bin/python3                                    # wrong
```

### Stage 03 slow / killed — check progress
```bash
/Users/magpie/google-cloud-sdk/bin/bq query --nouse_legacy_sql \
  --project_id=sincere-hearth-273704 \
  "SELECT COUNT(DISTINCT master_table) AS done, COUNT(*) AS rows
   FROM \`sincere-hearth-273704.magpie_reference.product_brand_map\`"
```

### BQ 403 Forbidden on magpie_reference
Service account `openclaw@magpie-openclaw.iam.gserviceaccount.com` needs WRITER access on the dataset:
```bash
# Grant access (run once, as project owner)
/Users/magpie/google-cloud-sdk/bin/bq update --source /dev/stdin \
  sincere-hearth-273704:magpie_reference << 'EOF'
{"access": [
  {"role": "OWNER", "specialGroup": "projectOwners"},
  {"role": "WRITER", "specialGroup": "projectWriters"},
  {"role": "READER", "specialGroup": "projectReaders"},
  {"role": "WRITER", "userByEmail": "openclaw@magpie-openclaw.iam.gserviceaccount.com"}
]}
EOF
```

### brand_review Sheet — service account access
Sheet must be shared with `openclaw@magpie-openclaw.iam.gserviceaccount.com` (Editor).
Current working Sheet: https://docs.google.com/spreadsheets/d/1MvJdpoccc63AMs8D0qShI7PhKZ2BrrJJP-kwvDbh40M
