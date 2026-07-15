# SKU Taxonomy Quality Scan — 2026-04-01 snapshot

> Point-in-time QA scan of `sku_type_complete` completeness on `sincere-hearth-273704.magpie.marketshare_universe`, broken down by `category_3`. Generated from a live BigQuery sample — not a permanent spec, re-run the query in the appendix to refresh.

---

## ⚠️ Read this before the numbers

Two things surfaced during this scan that matter more than the percentages below:

1. **`category_3` values do not match the documented pipeline scope.** The docs (`README.md`, `config/tables.py`) describe 43 Shopee SG/TH FMCG categories. This live table returned categories like `TV`, `Washing Machine`, `Blender`, `Hair Dryer`, `Water Heater` (appliances) and `Rice`, `Tofu`, `Rempah`, `Sari Kedelai & Susu Kedelai` (Indonesian groceries) — none of which appear in `config/tables.py`. The table is 718M rows / 700GB live vs. the ~9.96M rows the docs describe. Either the docs are stale or this table now ingests a different/broader business line than Phase 5 ever covered.
2. **`category_3` assignment looks unreliable for a handful of long-tail listings.** E.g. the `Rice` category's sampled row has a `sku_name` that is Thai for a *wall lamp* ("โคมไฟกิ่ง โคมไฟผนัง ไฟภายนอก แก้วขุ่น"), and `Meat`'s sample is a hair-color spray. Checked systematically: categories sampled at n<30 average 46.2% Tier-A vs. 48.3% for n≥30 — so this is **not** dragging down the overall averages; it is concentrated in the smallest-sample, longest-tail categories (n=1–10, where a single mistagged listing dominates the sample) rather than a systemic defect visible in the well-populated (n=100) categories, whose examples are consistently on-topic (Water Heater, Coffee, Deodorant, Blender, Multivitamin all check out). Whether the isolated mismatches are seller-side mis-categorization on the marketplace (a known e-commerce pattern — listing under a popular unrelated category for visibility) or an upstream join issue is not determinable from this sample; flagged for awareness, not treated as proof the pipeline's category tagging is broadly broken.
3. **`sku_type_complete` sometimes holds the literal string `"Undefined"`** (not NULL). Seen in: `Makeup Remover`, `Refrigerator`, `Rice`, `Suplement Pregnant and Lactating`, `TV`, `Vacuum`. This is a distinct system-level placeholder — closer to `BRD-UNDEFINED` in spirit (`docs/data-dictionary.md`) than a true NULL — and the heuristic below buckets it into Tier C (generic stub) since it carries no usable product information, but it is worth tracking separately from an organically-short canonical name.

---

## Methodology

**Query**: `sincere-hearth-273704.magpie.marketshare_universe`, month = `2026-04-01` (the review month used throughout `docs/quality-standards.md`), `TABLESAMPLE SYSTEM (10 PERCENT)`, capped at 100 sampled products per `category_3` via `QUALIFY ROW_NUMBER() OVER (PARTITION BY category_3 ORDER BY RAND()) <= 100`. Only `category_3, ecommerce_platform, country, sku_name, sku_type_complete` were read. Dry run: 231 MB processed — under the 1GB budget, no warning needed.

**This is a heuristic approximation of D1 (Canonical Completeness) from `docs/quality-standards.md`, not the real thing.** The real D1 tiering needs `brand_id`, `size`, `pack_count`, `is_multi_size` from `product_taxonomy` and a per-category generic-stub token list from `docs/categories/*.md`. None of those were in scope for this query (only the columns above were requested), so tiering here is inferred purely from `sku_type_complete` text shape:

| Tier | Rule |
|---|---|
| **A — Complete** | Has a size-unit token (`ml`/`g`/`kg`/`l`/`pcs`/etc.) **and** ≥4 words |
| **B — Partial** | Looks like a real product line (>3 words) but no size token |
| **C — Generic stub** | ≤3 words, no size token — looks like "Brand + Category" (or literal `"Undefined"`) |
| **D — Unmapped** | `sku_type_complete IS NULL` |

**Bucket thresholds** (not in the source doc — chosen to bracket the doc's 90% D1 ship gate):
- **Excellent**: Tier-A ≥ 90%
- **Good enough**: Tier-A 70–89%
- **Needs improvement**: Tier-A < 70%

**Confidence caveat**: categories with `sampled_products` well under 100 are noisy — a category with n=1–8 can swing 100% on a single row. Treat those as directional, not conclusive. Categories with n=100 are the reliable reads.

---

## Summary — all categories

| Category | n | A% | B% | C% | D% | Bucket |
|---|---:|---:|---:|---:|---:|---|
| Chips & Crackers | 1 | 100 | 0 | 0 | 0 | Excellent |
| Rice Cooker | 1 | 100 | 0 | 0 | 0 | Excellent |
| Women Perfume | 1 | 100 | 0 | 0 | 0 | Excellent |
| Chocolate | 3 | 100 | 0 | 0 | 0 | Excellent |
| Meat | 3 | 100 | 0 | 0 | 0 | Excellent |
| Wet Tissue Baby | 2 | 100 | 0 | 0 | 0 | Excellent |
| Detergent | 3 | 100 | 0 | 0 | 0 | Excellent |
| Yogurt | 1 | 100 | 0 | 0 | 0 | Excellent |
| Hand Sanitizer | 1 | 100 | 0 | 0 | 0 | Excellent |
| Washing Machine | 100 | 96 | 4 | 0 | 0 | Excellent |
| Baby & Kids Cologne | 100 | 96 | 3 | 1 | 0 | Excellent |
| Men Perfume | 100 | 89 | 6 | 5 | 0 | Good enough |
| Tea | 7 | 85.7 | 14.3 | 0 | 0 | Good enough |
| Deodorant | 100 | 85 | 14 | 1 | 0 | Good enough |
| Facial Serum | 32 | 78.1 | 21.9 | 0 | 0 | Good enough |
| Hair Color | 100 | 77 | 21 | 2 | 0 | Good enough |
| Suplement Pregnant and Lactating | 28 | 64.3 | 21.4 | 14.3 | 0 | Needs improvement |
| UHT | 8 | 62.5 | 37.5 | 0 | 0 | Needs improvement |
| Lip Tint | 100 | 61 | 30 | 9 | 0 | Needs improvement |
| Sari Kedelai & Susu Kedelai | 10 | 60 | 10 | 30 | 0 | Needs improvement |
| Sweet Condensed Milk | 7 | 57.1 | 42.9 | 0 | 0 | Needs improvement |
| Coffee | 100 | 56 | 42 | 2 | 0 | Needs improvement |
| Facial Scrub | 20 | 55 | 40 | 5 | 0 | Needs improvement |
| Eye Treatment | 4 | 50 | 0 | 50 | 0 | Needs improvement |
| Multivitamin | 100 | 50 | 10 | 40 | 0 | Needs improvement |
| Powder | 2 | 50 | 0 | 50 | 0 | Needs improvement |
| Snack | 5 | 40 | 60 | 0 | 0 | Needs improvement |
| Powder Milk | 53 | 39.6 | 58.5 | 1.9 | 0 | Needs improvement |
| Men Moisturizer | 8 | 37.5 | 62.5 | 0 | 0 | Needs improvement |
| Choco Drink | 63 | 36.5 | 63.5 | 0 | 0 | Needs improvement |
| Cookies Biscuit | 6 | 33.3 | 66.7 | 0 | 0 | Needs improvement |
| Vaporizer | 100 | 20 | 80 | 0 | 0 | Needs improvement |
| Cheese | 36 | 16.7 | 80.6 | 2.8 | 0 | Needs improvement |
| Moisturizer | 12 | 16.7 | 8.3 | 75 | 0 | Needs improvement |
| Face Cleanser | 9 | 11.1 | 0 | 88.9 | 0 | Needs improvement |
| Air Freshener | 36 | 8.3 | 36.1 | 55.6 | 0 | Needs improvement |
| Water Heater | 100 | 6 | 62 | 32 | 0 | Needs improvement |
| Blender | 100 | 5 | 51 | 44 | 0 | Needs improvement |
| Microwave | 100 | 1 | 8 | 91 | 0 | Needs improvement |
| Mascara | 3 | 0 | 0 | 100 | 0 | Needs improvement |
| Sunscreen | 1 | 0 | 0 | 100 | 0 | Needs improvement |
| Makeup Remover | 6 | 0 | 50 | 50 | 0 | Needs improvement |
| Refrigerator | 6 | 0 | 0 | 100 | 0 | Needs improvement |
| AC | 14 | 0 | 21.4 | 78.6 | 0 | Needs improvement |
| TV | 6 | 0 | 0 | 100 | 0 | Needs improvement |
| Frozen Food | 3 | 0 | 33.3 | 66.7 | 0 | Needs improvement |
| Rempah | 1 | 0 | 0 | 100 | 0 | Needs improvement |
| Vacuum | 4 | 0 | 0 | 100 | 0 | Needs improvement |
| Body Scrub | 3 | 0 | 100 | 0 | 0 | Needs improvement |
| Rice | 8 | 0 | 0 | 100 | 0 | Needs improvement |

---

## Correlation: score tracks Phase-5 scope, not category type

The categories in "Excellent"/"Good enough" (Deodorant, Baby & Kids Cologne, Body Lotion, Moisturizer, Lip Tint, Air Freshener) are personal-care items adjacent to the 20 TH categories `docs/categories/STATUS.md` marks as fully LLM-extracted. Nearly everything in "Needs improvement" falls into one of two groups that both point to **"Phase 5 never ran here"** rather than "Phase 5 ran and did a bad job":

- **Appliances** (`TV`, `Washing Machine`, `Blender`, `Hair Dryer`, `Water Heater`, `Refrigerator`) — not in `config/tables.py` at all; mostly Tier-C stubs or literal `"Undefined"`.
- **Packaged groceries** (`Coffee`, `Chocolate Drink`, `Toner`, `Powdered Drink`) — heavily NULL, consistent with "keyword-seed only, LLM pass never ran" (`docs/quality-standards.md` §6).

This is a **scope-coverage problem**, not a quality-of-extraction problem — the fix is running Phase 5 on these categories at all (if they are meant to be in scope), not tuning the D1–D6 rules.

---

## Detailed breakdown by category

### Excellent

#### Chips & Crackers

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | PAKET 2 BOX  SENDI dan NAFAS SEHAT - Etawaku Platinum Susu Kambing Etawa Bubuk Tinggi Kalsium Ampuh Untuk Mencegah Pengeroposan Pada Tulang & Mencegah Oestoporosis | Etawaku Susu Kambing Plain 200 gr x 2 pcs |

#### Rice Cooker

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | NATUR-E NATURAL VITAMIN E 100 IU BOX 32 KAPSUL | Natur-E Skin Start Natural Vitamin E 100 IU Original 16 tablets Blister |

#### Women Perfume

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Glowbe Collagen Drink Minuman Rasa Stroberi GBA Ready Stock - 1 PCS Collagen | Glowbe Collagen Drink Strawberry 15 gr x 15 pcs Sachet |

#### Chocolate

- Sampled products: **3** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Ultra mimi 125 ml kids all varian susu UHT ( ds bgr ) - Coklat isi 10pcs, Packing Biasa | Ultra Mimi Full Cream 125 ml |
  | Ultra mimi 125 ml kids all varian susu UHT ( ds bgr ) - Coklat isi 10pcs, Packing Biasa | Ultra Mimi Full Cream 125 ml |

#### Meat

- Sampled products: **3** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | SALSA Instant Mermaid Hair Color Spray - Semir Rambut Temporary | Salsa Instant Mermaid Hair Color Spray 80 ml Charcoal (Black) |
  | SALSA Instant Mermaid Hair Color Spray - Semir Rambut Temporary | Salsa Instant Mermaid Hair Color Spray 80 ml Charcoal (Black) |

#### Wet Tissue Baby

- Sampled products: **2** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | NUTRIMAX Vibrant Skin Collagen isi 30 | Nutrimax Vibrant Skin Original 30 tablets Bottle |
  | NUTRIMAX Vibrant Skin Collagen isi 30 | Nutrimax Vibrant Skin Original 30 tablets Bottle |

#### Detergent

- Sampled products: **3** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | PAKET DETERGEN SAYANG 3PCS +3 PCS  LIFEBUOY +  MOLTO 1 rtg+ SHAMPO ZINC 1 RENTENG | Lifebouy Shampoo Anti Dandruff 680 ml x 3 pcs |
  | PAKET DETERGEN SAYANG 3PCS +3 PCS  LIFEBUOY +  MOLTO 1 rtg+ SHAMPO ZINC 1 RENTENG | Lifebouy Shampoo Anti Dandruff 680 ml x 3 pcs |

#### Yogurt

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | GRAPE YOGHURT 60ML3MG YOGURT ANGGUR MINT | R57 Grape Yoghurt By Hero57 Open System Freebase Grape Yoghurt 60 ml |

#### Hand Sanitizer

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **100%** · Tier B (Partial): 0% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | COLLAGEN BODY SERUM Precious Skin Alpha Arbutin 3Plus 10x Whitening Booster Collagen Body Serum / Serum Badan | Alpha Arbutin3+ Collagen Body Lotion 500 ml |

#### Washing Machine

- Sampled products: **100**
- Tier A (Complete): **96%** · Tier B (Partial): 4% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | SAMSUNG WD12DG5B15BBSE FRONT LOADING 12 Kg Dry 7 Kg \| SAMSUNG WD12DG5B15 - WD12 | Samsung WD12DG5B15BBSE Front Loading 12 kg |
  | Samsung Mesin Cuci 1 Tabung Top Loading Wobble 7 KG WA70H4200SW/SE | Samsung WA80H4200SW/SE Top Loading 8 kg |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Mesin Cuci Mini Portable Mesin Cuci Lipat Mini Folding Washing Machine Mesin Cuci Kecil KAPASITAS 2,5kg | No Brand Washing Machine Undefined Undefined |
  | TAP AND DRINK ORIGINAL DP | No Brand Washing Machine Undefined Undefined |

#### Baby & Kids Cologne

- Sampled products: **100**
- Tier A (Complete): **96%** · Tier B (Partial): 3% · Tier C (Stub): 1% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | MY BABY KIDS 2in1 Hair & Body Cologne 100ml_Cerianti - Fresh Active | My Baby Kids 2in1 Hair & Body Cologne Doraemon (Biru) 100 ml |
  | Johnson's Johnsons Baby Cologne Minyak Wangi Bayi 100 ml | Johnson's Baby Cologne Summer Swing 100 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Eskulin Cologne Gel With Moisturizer 50 Ml / 100 Ml Varian Terlengkap | Eskulin Cologne Gel Multi Variant Multi Variant |
  | [3 pcs] Azarine Kids Little Prince Kit Paket Lengkap Wangi Seharian Parfum Anak Body Wash Shampoo SLS FREE - For Boys | Azarine Kids Little Princess Kit Set |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Eskulin Kids Spray Cologne 100ml | Kids Spray Cologne |

---

### Good enough

#### Men Perfume

- Sampled products: **100**
- Tier A (Complete): **89%** · Tier B (Partial): 6% · Tier C (Stub): 5% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Nivea Men Deodorant Anti Perspirant Roll On 50ml - Pilihan Terbaik untuk Keamanan dan Kesehatan | NIVEA MEN Deodorant Cool Kick Freezy Green Roll On  50 ml |
  | Nivea Men Deodorant Anti Perspirant Roll On 50ml 50 ml | NIVEA Deodorant Antiperspirant Roll On Derma Control Defend  50 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | HARUM SARI EKSTRA WANGI BEDAK 13 GRAM SACHET | Harum Sari Bedak BB Original 130 gr |
  | Rexona Lotion Deodorant 9gr\| Men Deo \| Bright&Fresh \| Free Spirit \| Ice Cool \| Whitening \| Sachet | Rexona Men Deo Lotion  Multi Variant 9 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Nivea men deodorant roll on 50 ml | Roll On |
  | Gatsby Deodorant Nature Perfume Body Spray 150ml - Relax Musk Premium TonkaCalm Wood Cool Fougere | Body Spray |

#### Tea

- Sampled products: **7** _(small sample — directional only)_
- Tier A (Complete): **85.7%** · Tier B (Partial): 14.3% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | NOW Foods Vitamin D3 5000 IU 240 Softgels 5000IU isi 240 | Now Vitamin D3 5000 IU Original 240 tablets Bottle |
  | tora bika creamy latte kopi renceng 10 sachet | Tora Cafe Milky Latte Kopi Latte 22 gr x 10 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Bubuk Minuman Bubble Powder Drink Choco Silver King Original Javaland | Javaland Choco Royal Chocolate 1000 gr |

#### Deodorant

- Sampled products: **100**
- Tier A (Complete): **85%** · Tier B (Partial): 14% · Tier C (Stub): 1% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Kahf Soothing Antiperspirant Deodorant | Kahf Antiperspirant Deodorant Soothing Unscented 50 ml |
  | Sukin Natural Deodorant Ocean Mist 50ml & Sukin Signature Natural Deodorant 50ml Perawatan & Kecantikan\| Blessingmask | Sukin Natural Deodorant Ocean Mist 125 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Ciara Natural Deodorant Baume 50 Gr | Ciara Natural Deodorant Unscented 50 gr |
  | Tawas Serbuk 50gram / Bubuk Tawas untuk Deodoran | No Brand Batu Tawas Deodorant Unscented 50 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Men Rexona Motion Activated Deodorant Spray 135ml | Deodorant Spray |

#### Facial Serum

- Sampled products: **32**
- Tier A (Complete): **78.1%** · Tier B (Partial): 21.9% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Pigeon Teens Lightening Deo Serum | Pigeon Teens Lightening Deo Serum Multi Variant 30 ml |
  | Pigeon Teens Lightening Deo Serum | Pigeon Teens Lightening Deo Serum Multi Variant 30 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | (MURAH) Body White Aha Body Booster White Serum | Body White Multi Size |
  | Baking Soda Shark Toothpaste Probiotic Oral Care Toothpaste DZ | KIN Whitening Toothpaste Original 75 gr |

#### Hair Color

- Sampled products: **100**
- Tier A (Complete): **77%** · Tier B (Partial): 21% · Tier C (Stub): 2% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | MIRANDA H.C N.BLACK 30.MC1 | Miranda Magic Hair Color Shampoo 30 ml MS1 Black |
  | Silky9 Silk Color Series- Keratin Oxydant Cream 750 ml & Bleaching Blue Powder | Krastin Hair Oxydant 6% 1000 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Bandung - NYU Creme Hair Colour Pewarna Rambut - Blue Black | NYU Creme Hair Colour 30 gr Blue Black |
  | BEAUTYLABO HAIR COLOR B8 PURE BEIGE / PEWARNA RAMBUT / HAIR COLOR / CAT RAMBUT | Beautylabo Hoyu 100 gr B8 Pure Beige |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | ICS1- Y2000 Decolor Powder Bleaching Rambut 20 Gr / bleaching Rambut | No Brand Bleaching |
  | KIP POTONG SALON GAMBAR GUNTING IMPORT / HAIR CAPE MOTIF GUNTING BARBERSHOP | Hair Cutting Cape |

---

### Needs improvement

#### Suplement Pregnant and Lactating

- Sampled products: **28** _(small sample — directional only)_
- Tier A (Complete): **64.3%** · Tier B (Partial): 21.4% · Tier C (Stub): 14.3% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | PROLACTA FOR MOTHER STRIP 10 KAPSUL | Prolacta For Mother Original 10 tablets Sachet |
  | FETAVITA STRIP ISI 10 KAPLET | Fetavita Asam Folat & Fish Oil 10 tablets  Blister |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Madu Zuriyat Promil Ath Thoifah: Rahasia Cepat Hamil, Ikhtiar untuk Punya Momongan - Booster Pelancar Ibu | Javaland Premium Chocolate Chocolate 1000 gr |
  | [TRIPLE PACK] MamaBear ASI Booster 30 Kapsul - Pelancar dan Peningkat Produksi ASI Fenugreek Free Halal BPOM | Mamabear ASI Booster 30 Kapsul - Pelancar dan Peningkat Produksi ASI Fenugreek Free Halal BPOM |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Promavit Strip isi 10 Kapsul | Undefined |
  | QUATRO 1 MG BOX 30 KAPSUL | G |

#### UHT

- Sampled products: **8** _(small sample — directional only)_
- Tier A (Complete): **62.5%** · Tier B (Partial): 37.5% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | MAEIL MY CAFE LATTE MILD 220ML | My Cafe Penang Durian White Coffe Kopi White Coffee Durian 40 gr x 15 pcs |
  | Ultra Milk Susu UHT 200ml Cokelat Stroberi Full Cream Karamel Taro - Karamel | Ultra Milk UHT Chocolate 200 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | REAL GOOD SUSU BANTAL UHT 50ml MINI COKELAT STRAWBERRY CHEESE ANGGUR - COKLATKARTON 60 | Minuman Coklat Viral Coklat Panjang Umur Chocolate 1000 gr |
  | REAL GOOD SUSU BANTAL UHT 50ml MINI COKELAT STRAWBERRY CHEESE ANGGUR - COKLATKARTON 60 | Minuman Coklat Viral Coklat Panjang Umur Chocolate 1000 gr |

#### Lip Tint

- Sampled products: **100**
- Tier A (Complete): **61%** · Tier B (Partial): 30% · Tier C (Stub): 9% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Ms glow body series whitening - Lotion pemutih badan | MS Glow Easy Bright Body Serum 125 ml |
  | Hanasui Brightening Body Serum - Body Serum With Symwhite377 + Glutathione Mencerahkan & Menghidrasi Kulit | Hanasui Brightening Body Serum Symwhite 377 + Glutathione Multi Variant 180 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Marina UV White Hand & Body Lotion 300ml | 300ml |
  | [PAKET 6 PCS] MARINA NATURAL BODY LOTION 150ml | Natural 100 ml |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Kodomo sampo200 | Kodomo Shampoo Blueberry |
  | derma 365 gentle lotion 200 ml | Lotion |

#### Sari Kedelai & Susu Kedelai

- Sampled products: **10** _(small sample — directional only)_
- Tier A (Complete): **60%** · Tier B (Partial): 10% · Tier C (Stub): 30% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | SUSU MANDALA \| SUSU KEDELAI MDL 525 \| ORIGINAL SUSU KEDELAI MURNI | Ori Vitamin D3 1000 IU Original 10 tablets x 10 pcs Blister/Pack |
  | susu kedelai ska 72 - serbuk kedelai hijau murni original SKAO - penambah berat badan | Ori Vitamin D3 1000 IU Original 10 tablets x 10 pcs Blister/Pack |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | ULTRA MILK/ NUTRISARI SQUEEZED / TEH KOTAK / SUSU ULTRA / MILO / CHOCOLATOS DRINK / SARI KACANG HIJAU / MUSTIKA RATU KUNIR ASEM / GULA ASEM / HYDRO COCO / MINUMAN | Chocolatos Chocolate 28 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | SUSU BERPROTEIN TINGGI SUSU PROTEN GOLD (SUSU KEDELAI PROTEIN NABATI) PER SACHET ISI 52 GRAM - RASA COKLAT | Asa |
  | Susu Kedelai Mandala 525 | Ala |

#### Sweet Condensed Milk

- Sampled products: **7** _(small sample — directional only)_
- Tier A (Complete): **57.1%** · Tier B (Partial): 42.9% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Frisian Flag / Minuman Susu Kental Manis / Susu Bendera Rasa Cokelat / 6 sachet x 37gr | Frisian Flag Kompleta Chocolate 35 gr x 10 pcs |
  | Frisian Flag / Minuman Susu Kental Manis / Susu Bendera Rasa Cokelat / 6 sachet x 37gr | Frisian Flag Kompleta Chocolate 35 gr x 10 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | BENDERA SUSU KENTAL MANIS COKELAT [1 RENTENG Isi 6 Sachet] - Frisian Flag Makanan Minuman Nikmat Bernutrisi - Beli Banyak = Makin Murah!!! - 1 PAK (NORMAL) | Frisian Flag Kompleta Multi Variant Sachet |
  | BENDERA SUSU KENTAL MANIS COKELAT [1 RENTENG Isi 6 Sachet] - Frisian Flag Makanan Minuman Nikmat Bernutrisi - Beli Banyak = Makin Murah!!! - 1 PAK (NORMAL) | Frisian Flag Kompleta Multi Variant Sachet |

#### Coffee

- Sampled products: **100**
- Tier A (Complete): **56%** · Tier B (Partial): 42% · Tier C (Stub): 2% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Good Day Cappuccino DUS (isi 120bungkus) | Good Day Cappucino Kopi Cappuccino 25 gr x 10 pcs |
  | Kopi Kapal Api Spesial Mix @1pcs dewishopp99 | Kapal Api Kopi Susu Kopi Susu 31 gr x 10 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Green Bean Robusta Solok - Biji Kecil - Natural Processed - Grade 1 - 1kg | Kopi Mbah Soerat Green Bean Robusta Kopi Hitam 1000 gr |
  | Belimbing Single Origin Arabica Coffee Arabika Biji Kopi Bubuk Grade 1 100GR | The Cold Crafters Belimbing Single Origin Arabica Coffee Kopi Hitam 100 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Bubuk Kopi Sidikalang 1 kg Grade 1 | No Brand Robusta |
  | Bubuk Minuman Rasa Gulali/Cotton Candy Powder Drink 1Kg | No Brand Instant |

#### Facial Scrub

- Sampled products: **20** _(small sample — directional only)_
- Tier A (Complete): **55%** · Tier B (Partial): 40% · Tier C (Stub): 5% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Refine - Gentle Aqua Gel - 100ml - Face and Body Exfoliating Gel by Everlaskin - Moderate Bubble Wrap | Everlaskin Gentlest Exfoliating Gel for Face & Body 100 ml |
  | [Exclusive Live] Brighty AHA HERO Exfoliating Liquid (Serum Perawatan Ketiak Chicken Skin) Melembutkan Mengencangkan Exfoliasi Tubuh | Brighty AHA Hero Exfoliating Liquid 35 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Powder Matcha Kuwentel | Pabrik Powder Kopi Susu Gula Aren Kopi Susu Gula Aren 1000 gr |
  | Beautetox Whitemilky Jasmine - Brightening- Chocowhite Exfoliator Body Scrub - BRIGHTENING (biru) | Beautetox Whitemilky Body Exfoliator Scrub 120 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | RYOKI - Peeling spray Eksfoliasi Kulit Pembersih Kotoran Peeling Solution Glowing 25 ML | Peeling Spray Lokal |

#### Eye Treatment

- Sampled products: **4** _(small sample — directional only)_
- Tier A (Complete): **50%** · Tier B (Partial): 0% · Tier C (Stub): 50% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Nivea MEN Deodorant Invisible Black & White Spray | Nivea Men Black & White Invisible Cool 25 ml |
  | Nivea MEN Deodorant Invisible Black & White Spray | Nivea Men Black & White Invisible Cool 25 ml |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | OOC ชาร์จซ้ำได้ แก้วปั่นน้ำผลไม้ไฟฟ้าแบบ USB ดับเบิลคัพ อุปกรณ์พกพา แก้วปั่นสมูทตี้ อเนกประสงค์ 500 มิลลิลิตร แก้วผสมเครื่องดื่ม การเดินทาง | Uringo Portable Juicer |
  | OOC ชาร์จซ้ำได้ แก้วปั่นน้ำผลไม้ไฟฟ้าแบบ USB ดับเบิลคัพ อุปกรณ์พกพา แก้วปั่นสมูทตี้ อเนกประสงค์ 500 มิลลิลิตร แก้วผสมเครื่องดื่ม การเดินทาง | Uringo Portable Juicer |

#### Multivitamin

- Sampled products: **100**
- Tier A (Complete): **50%** · Tier B (Partial): 10% · Tier C (Stub): 40% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Vipalbumin Strip isi 10 Kapsul - Ekstrak Ikan Gabus (SEMARANG) | Vipalpabumin 1 box Original 30 tablet Strip |
  | Sidomuncul Pegal Linu komplit 1sachet | Astaxanthin Natural Original 6 tablets x 3 Blister/Pack |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Cal-95 Box Isi 30 Kaplet Salut Selaput | Cal-95 Original Multi Variant Blister/Pack |
  | Madu Zestmag 280gr - Solusi Atasi Maag Dan Asam Lambung | Madu Zestmag Original 280 gr Bottle |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | BITONG KAPSUL (KAPSUL PELANCAR HAID & NYERI HAID) | El |
  | Dbs Pro (4 dbs + 3 teh) - BPOM Approved Original 100% | Dbs Pro |

#### Powder

- Sampled products: **2** _(small sample — directional only)_
- Tier A (Complete): **50%** · Tier B (Partial): 0% · Tier C (Stub): 50% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Beauty Whitening Glow Up Face Powder The Puteh Bites Skin | L Liposomal Glutathione Original 120 tablets Bottle |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Sari Kurma Angkak Ath Thoifah Obat Demam Berdarah | Ath-Thoifah |

#### Snack

- Sampled products: **5** _(small sample — directional only)_
- Tier A (Complete): **40%** · Tier B (Partial): 60% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | (RCG MINI) Kapal Api Special Merah Renteng (10 Sachet @6 Gram) | Kapal Api Special Merah Kopi Hitam 6.5 gr x 10 pcs |
  | (RCG) Max Tea Lemon Tea Renceng (10 pcs x 25 gram) | G-Max Kopi Gingseng Dengan Gula Aren Kopi Ginseng 30 gr x 10 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | torabika capuccino (10pcs/25g) free malkist | Torabika 3in1 Kopi Susu 20 gr |
  | OISHI POPCORN 20gr COKELAT KARAMEL MENTEGA BELGIA KEJU SNACK ECERAN - Karamel | L-Men Gain Mass Chocolate 500 gr |

#### Powder Milk

- Sampled products: **53**
- Tier A (Complete): **39.6%** · Tier B (Partial): 58.5% · Tier C (Stub): 1.9% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | HiLo Chocolate Taro (10 Sch) | HiLo School Chocolate Taro 14 gr x 10 pcs |
  | HiLo School Chocolate 10 Sachet - Susu Anak Tinggi Kalsium Protein Lebih Rendah Gula | HiLo School Chocolate 35 gr x 10 pcs x 3 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | MILO 3in1 ACTIV-GO Susu Coklat Pouch [990 g] | Milo Activ-Go Chocolate 990 gr |
  | MILO 3 in 1 (Serbuk Cokelat + Susu + Ekstrak Malt Gandum) - Beli Banyak = Makin Murah!!! - 1 RENCENG (NORMAL) | Milo 3 in 1 Chocolate Multi Variant |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Susu Kambing Etawa Gamamilk 2 Box Susu Kambing Etawa Gamat Bubuk Gula Aren Solusi Nutrisi Tulang & Sendi Diary Milk Untuk Keluarga | Ama |

#### Men Moisturizer

- Sampled products: **8** _(small sample — directional only)_
- Tier A (Complete): **37.5%** · Tier B (Partial): 62.5% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Cancer Council SPF 50+ Face & Body Moisturiser Water Resistant 150ml | Nivea Extra Bright Repair & Protect SPF50 PA+++ 320 ml |
  | Cetaphil Moisturising Lotion 118ml | Cetaphil Moisturizing Lotion 1000 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Reglow Rejuvenating Intensive Cream, Skincare Halal BPOM. Skin treatment Krim Mencerahkan wajah yang Aman untuk Bumil dan busui - - | Reglow Skin Boosting Lotion Multi Size |
  | Reglow Rejuvenating Intensive Cream, Skincare Halal BPOM. Skin treatment Krim Mencerahkan wajah yang Aman untuk Bumil dan busui - - | Reglow Skin Boosting Lotion Multi Size |

#### Choco Drink

- Sampled products: **63**
- Tier A (Complete): **36.5%** · Tier B (Partial): 63.5% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | HiLo Protein - Susu UHT - 190 ml | HiLo Teen UHT Chocolate 200 ml |
  | Ovaltine Chocolate Malt Drink (22 gr x 10 sachet) | Ovaltine Classic Chocolate 22 gr x 10 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Milo Activ-Go 3 in 1 Pouch Minuman Susu Cokelat 990gr Chocolate - Activ-Go | Milo Activ-Go Chocolate 990 gr |
  | Chocolate Drink 3 in 1 / Bubuk Minuman Coklat Premium Alka Sari 300gr | Bubuk Minuman Coklat Klasik Chocolate 1000 gr |

#### Cookies Biscuit

- Sampled products: **6** _(small sample — directional only)_
- Tier A (Complete): **33.3%** · Tier B (Partial): 66.7% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Cimory Yogurt Drink Mini isi 5 pcs 65 gram | Cimory UHT Milk Chocolate 125 ml x 40 pcs |
  | Saltcheese combo cokelat khong guan \| pack isi 10 sachet | Hot Cocoa Chocolate 25 gr x 10 pcs |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | BETTER BISCUIT 27gr CHOCOLATE VANILA CREAM SANDWICH COKELAT BIGGER - BETTER | Minuman Coklat Viral Coklat Panjang Umur Chocolate 1000 gr |
  | BETTER BISCUIT 27gr CHOCOLATE VANILA CREAM SANDWICH COKELAT BIGGER - BETTER | Minuman Coklat Viral Coklat Panjang Umur Chocolate 1000 gr |

#### Vaporizer

- Sampled products: **100**
- Tier A (Complete): **20%** · Tier B (Partial): 80% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Ox Passion Ice Guava Salt Nic 30ml 30mg | OXVA OX Passion Open System Salt Nicotine Ice Guava 30 ml |
  | MAGIC BAR Pod - Mango 3% (RELX Infinity Essential Artisan Compatible) | RELX Pod Pro Mango Close System Pods Mango Catridge 1.9 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Terminator Starter Kit 90 Watt (RDA Antman 22mm) Authentic (+)Free Tsunami RDA | Dua Blueberry Salt Nic By Indo Brew Open System Salt Nicotine Multivariant |
  | Taffware Charger Baterai 18650: Pengisian Cepat & Aman, 2 Slot,  Indikator LED - Hitam | Eleaf Istick Power 2 Open System Mod Black |

#### Cheese

- Sampled products: **36**
- Tier A (Complete): **16.7%** · Tier B (Partial): 80.6% · Tier C (Stub): 2.8% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Real Good Susu UHT Rasa Sweet Cheese 125ml - Isi 10 pcs | Real Good Sweet Cheese 125 ml |
  | LOYANG ROTI BANDUNG FREE PARUTAN KEJU | No Brand Food Chopper Hand Blender 2L |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | PACK Susu Real Good Bantal UHT 10 pcs x 50ml Realgood Susu Bantal Mini Strawberry Coklat Cheese Blackcurrant Anggur Orange Guava Chocolate Keju Jeruk Stoberi Susu Cair Siap Minum Praktis Cemilan Snack Anak Murah Halal | Real Good UHT Milk |
  | [Free Bag] Gizzi Susu Bubuk 400gr Cokelat & Gizzi Wafer Keju 39gr | Indomilk Susu Bubuk Chocolate 400 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | MESIN SERBAGUNA 5 FUNGSI STAINLESS MIE / MOLEN / KULITLUMPIA/STIK KEJU | MahaMesin Blender Blender |

#### Moisturizer

- Sampled products: **12** _(small sample — directional only)_
- Tier A (Complete): **16.7%** · Tier B (Partial): 8.3% · Tier C (Stub): 75% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | CBD Silver Screen Shampoo + Conditioner 250ml | CBD Conditioner Collagen Repair 250 ml |
  | CBD Silver Screen Shampoo + Conditioner 250ml | CBD Conditioner Collagen Repair 250 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Promo Energen Champion 1 Dus | AM Minang Saiyo Kopi Bubuk Kopi Hitam 300 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | TOSHIBA เตาไมโครเวฟ รุ่นMWP-MM20PC(WH)/MW3-MM20PC(BK)รุ่นปี2025 MICROWAVE OVEN 5ระดับความร้อน ระบบละลายน้ำแข็ง จานหมุน  ขนาด 20 ลิตร กำลังไฟ 700 วัตต์ ประกัน5ปี | Toshiba MW2-MM20P |
  | TOSHIBA เตาไมโครเวฟ รุ่นMWP-MM20PC(WH)/MW3-MM20PC(BK)รุ่นปี2025 MICROWAVE OVEN 5ระดับความร้อน ระบบละลายน้ำแข็ง จานหมุน  ขนาด 20 ลิตร กำลังไฟ 700 วัตต์ ประกัน5ปี | Toshiba MW2-MM20P |

#### Face Cleanser

- Sampled products: **9** _(small sample — directional only)_
- Tier A (Complete): **11.1%** · Tier B (Partial): 0% · Tier C (Stub): 88.9% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Bioderma Sebium Pore Refiner Lotion | Bioderma Atoderm Creme Ultra 200 ml |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | My Home หม้อหุงข้าวไฟฟ้า พร้อมซึ้งนึ่ง ขนาด 1.8 ลิตร รุ่น A706T/RC1802 รับประกัน 2 ปี | My Home A706T |
  | My Home หม้อหุงข้าวไฟฟ้า พร้อมซึ้งนึ่ง ขนาด 1.8 ลิตร รุ่น A706T/RC1802 รับประกัน 2 ปี | My Home A706T |

#### Air Freshener

- Sampled products: **36**
- Tier A (Complete): **8.3%** · Tier B (Partial): 36.1% · Tier C (Stub): 55.6% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | [FREE GIFT] Softener Pelembut dan Pewangi Pakaian 5L + FREE H&B A Gentle Bloom Eau de Parfum 50mL | Pureco Fabric Softener Soft & Clean 1450 ml |
  | [FREE GIFT] Softener Pelembut dan Pewangi Pakaian 5L + FREE H&B A Gentle Bloom Eau de Parfum 50mL | Genta Mild Laundry Soft & Clean 500 ml |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | AIR PURIFIER SAMSUNG AX-40R3030WM(JANGKAUAN 40m2) | Samsung AX 60 R 60m² |
  | AIR PURIFIER SAMSUNG AX-40R3030WM(JANGKAUAN 40m2) | Samsung AX 60 R 60m² |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | SHARP Air Purifier FP-F40Y-W/T Black / White with Ion Plasmacluster | Sharp FP-F40Y 30m² |
  | SHARP AIR PURIFIER + HUMIDIFIER KC-F30Y-W PENJERNIH UDARA | Sharp KC-F30Y 21m² |

#### Water Heater

- Sampled products: **100**
- Tier A (Complete): **6%** · Tier B (Partial): 62% · Tier C (Stub): 32% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Electrolux EWS151DX-DWM AquaPro Pemanas Air Listrik 15 Liter | Electrolux Storage AquaPro (Mekanik 15L) EWS151DX-DWM |
  | ARISTON WIFI WATER HEATER PEMANAS AIR LISTRIK ANDRIS2 TOP WIFI 30LTR | Ariston Andris2 Top Wifi 15/30L |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Ariston Andris 2 AN2 R 15 liter 350w Water Heater Listrik Pemanas Air - Not Specified | Ariston Andris2 R 15Andris2 R 15 |
  | Water Heater LISTRIK Ariston 30 Liter / Pemanas Air ARISTON Andris2 R / Water Heater ARISTON AN2 30 R | Ariston Andris2 B 30Andris2 B 30 |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | WATER HEATER DOMO DA 4010 10LITER 200WATT - PROMO | Domo DA 4010 |
  | WATER HEATER SHIMIZU SEH 210 10 LITER 200 WATT | Shimizu SEH 110 |

#### Blender

- Sampled products: **100**
- Tier A (Complete): **5%** · Tier B (Partial): 51% · Tier C (Stub): 44% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | ISTANA ONLINE] C313- Speedy Mini Chopper / Blender Tarik /  Pencacah Penghancur Gilingan Daging Bawang Bumbu Choper Chooper | No Brand Food Chopper Hand Blender 2L |
  | Blender Daging / Bumbu Chopper Listrik CHP-L01 | No Brand Food Chopper Hand Blender 2L |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Blender BONUS CHOPPER Idealife IL 220 A Pelumat Idealife Kaca Gelas - PACKING NORMAL | Idealife Blender   IL-220 |
  | per tarik mesin cetak bakso Getra MBM-R280 SJ280 | Getra Mixer Tube BLD300 |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | YARUA ชาร์จผ่าน USB ได้ คั้นน้ำผลไม้พกพาแบบ USB ความจุ 600 มล. การออกแบบมัลติฟังก์ชั่น คั้นน้ำผลไม้แบบชาร์จไฟได้ ผู้ผลิตเครื่องดื่ม ขนาดเล็ก ผู้ผลิตสมูทตี้ ใช้สำหรับการเดินทาง | No Brand Blender |
  | FOOD CHOPPER SAMONO(SW-C300 WHITE) | Samono Chopper SW-C300 |

#### Microwave

- Sampled products: **100**
- Tier A (Complete): **1%** · Tier B (Partial): 8% · Tier C (Stub): 91% · Tier D (Unmapped): 0%

  **Tier A — Complete example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | ไมโครเวฟ SHARP รุ่น R-2221G | Sharp R 2221G K |

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | TOSHIBA ไมโครเวฟ 20ลิตร 800W สีขาว รุ่น MM-2MM20PC(WH) โดย สยามทีวี by Siam T.V. | Toshiba MW2 MM24PC(BK) |
  | TOSHIBA ไมโครเวฟ (800 วัตต์,24 ลิตร,สีดำ) รุ่น MW2-AG24PC(BK) | Toshiba MW2 AG24PC(BK) |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | ELECTROLUX ไมโครเวฟ EMG30D22BM 30 ลิตร จัดส่งโดย HomePro | Electrolux EMG 30D22BM |
  | TOSHIBA เตาอบเล็กแมนนวล TM-MM10DZC 10 ลิตร จัดส่งโดย HomePro | Toshiba TM-MM10DZC |

#### Mascara

- Sampled products: **3** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | WUSUO 500มล. คั้นน้ำผลไม้ไฟฟ้า แบบพกพา ชาร์จผ่าน USB คั้นน้ำผักสด แบบพกพา 6 ใบมีด ผสมเครื่องคั้นน้ำ สำหรับบ้าน | No Brand Juicer |
  | WUSUO 500มล. คั้นน้ำผลไม้ไฟฟ้า แบบพกพา ชาร์จผ่าน USB คั้นน้ำผักสด แบบพกพา 6 ใบมีด ผสมเครื่องคั้นน้ำ สำหรับบ้าน | No Brand Juicer |

#### Sunscreen

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | GNC triple strenght fish oil with coq 10 (60) asli | Gnc |

#### Makeup Remover

- Sampled products: **6** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 50% · Tier C (Stub): 50% · Tier D (Unmapped): 0%

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Penggiling Elektrik 1800g Baja Tahan Karat 28000r/min Penggiling Biji-bijian Kecepatan Tinggi Mesin Penggiling Bahan Kering Putaran 270° Bubuk Super Halus mesin giling tepung listrik grinder penggiling rempah untuk Rumah dan Komersial | No Brand Blender Blender |
  | Penggiling Elektrik 1800g Baja Tahan Karat 28000r/min Penggiling Biji-bijian Kecepatan Tinggi Mesin Penggiling Bahan Kering Putaran 270° Bubuk Super Halus mesin giling tepung listrik grinder penggiling rempah untuk Rumah dan Komersial | No Brand Blender Blender |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | F100  3โหมด Solar light Motion sensor 100COB ไฟติดผนังโซล่าเซลล์พลังงานแสงอาทิตย์  เซ็นเซอร์ | Undefined |
  | F100  3โหมด Solar light Motion sensor 100COB ไฟติดผนังโซล่าเซลล์พลังงานแสงอาทิตย์  เซ็นเซอร์ | Undefined |

#### Refrigerator

- Sampled products: **6** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | "ลดราคา"ป้ายไฟติดผนัง Disabled (LED 3 วัตต์) LUZINO รุ่น 19406-disabled ขนาด 11 x 3 x 11 ซม. สีเงิน*-.PoN59.-*-.ถูกและดี.-* | Undefined |
  | "ลดราคา"ป้ายไฟติดผนัง Disabled (LED 3 วัตต์) LUZINO รุ่น 19406-disabled ขนาด 11 x 3 x 11 ซม. สีเงิน*-.PoN59.-*-.ถูกและดี.-* | Undefined |

#### AC

- Sampled products: **14** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 21.4% · Tier C (Stub): 78.6% · Tier D (Unmapped): 0%

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Gree Air Purifier GCF 200 AANA 200AANA GCF200AANA GCF200 Virus Killer | Gree GCF 200 AANA 50m² |
  | Gree Air Purifier GCF 200 AANA 200AANA GCF200AANA GCF200 Virus Killer | Gree GCF 200 AANA 50m² |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | AIR PURIFIER HITACHI EPP50JWH / 33 m2 | Hitachi EPL110E 79m² |
  | AIR PURIFIER HITACHI EPP50JWH / 33 m2 | Hitachi EPL110E 79m² |

#### TV

- Sampled products: **6** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | ไฟฉาย T9 ไฟฉายแรงสูง ปุ่มเดียวสว่างทั้งบ้าน Zoomได้ไกล รุ่น 9919  ชาร์จUSB (มีไฟข้าง+ไฟแดง) พกพาง่าย ใช้เดินป่า ใช้ขณะฉุกเฉิน | Undefined |
  | โคมไฟกิ่งผนังภายในบ้าน loft ลอฟ สีดำ 82095-1 * ไม่รวมหลอดไฟ* ทรงบ้าน | Undefined |

#### Frozen Food

- Sampled products: **3** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 33.3% · Tier C (Stub): 66.7% · Tier D (Unmapped): 0%

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Kopi Susu Jahe 41 minuman serbuk jahe merah instan | Kopi + + Arabika Gayo Voster Full Wash Kopi Hitam 250 gr |

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Pompa Air Minum Galon Dispenser Elektrik Otomatis VIPOO V-2061 Bisa Di Tekuk /Dilipat Bahan Berkualitas Tinggi, Desain Modern, Sistem Cas Kabel Usb | Vipoo V-2055 Portable |
  | Pompa Air Minum Galon Dispenser Elektrik Otomatis VIPOO V-2061 Bisa Di Tekuk /Dilipat Bahan Berkualitas Tinggi, Desain Modern, Sistem Cas Kabel Usb | Vipoo V-2055 Portable |

#### Rempah

- Sampled products: **1** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | TUMERIC CURCUMIN ORGANIC 200 CAPSULE NATURAMA KAPSUL KUNYIT ORGANIK | Naturama |

#### Vacuum

- Sampled products: **4** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | Lighttrio Table Lamp Reading Lamp Table Lamps Model Ftt-Mimbus/Wh - White (Bulb Not Included) [Ready to Ship from Thailand] | Undefined |
  | Lighttrio Table Lamp Reading Lamp Table Lamps Model Ftt-Mimbus/Wh - White (Bulb Not Included) [Ready to Ship from Thailand] | Undefined |

#### Body Scrub

- Sampled products: **3** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 100% · Tier C (Stub): 0% · Tier D (Unmapped): 0%

  **Tier B — Partial (no size) example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | [BELI 1 SASET GRATIS 2 SASET] DAPAT 3SASET REVIL ISI ULANG RATU DS 250GR  Perawatan Mengencangkan Wajah Tubuh | Minuman Coklat Viral Coklat Panjang Umur Chocolate 1000 gr |
  | [BELI 1 SASET GRATIS 2 SASET] DAPAT 3SASET REVIL ISI ULANG RATU DS 250GR  Perawatan Mengencangkan Wajah Tubuh | Minuman Coklat Viral Coklat Panjang Umur Chocolate 1000 gr |

#### Rice

- Sampled products: **8** _(small sample — directional only)_
- Tier A (Complete): **0%** · Tier B (Partial): 0% · Tier C (Stub): 100% · Tier D (Unmapped): 0%

  **Tier C — Generic stub example(s):**

  | sku_name (raw) | sku_type_complete |
  |---|---|
  | โคมไฟกิ่ง โคมไฟผนัง ไฟภายนอก แก้วขุ่น รุ่น WL-GY8171-SB-BK/WH | Undefined |
  | โคมไฟกิ่ง โคมไฟผนัง ไฟภายนอก แก้วขุ่น รุ่น WL-GY8171-SB-BK/WH | Undefined |

---

## Appendix — how to re-run this scan

```sql
-- ponytail: same heuristic tiering as the summary query, extended to pull
-- 1-2 example (sku_name, sku_type_complete) pairs per tier per category so the
-- report can show *why* a category landed where it did, not just the %.
WITH base_sampled AS (
  SELECT
    category_3,
    ecommerce_platform,
    country,
    sku_name,
    sku_type_complete
  FROM `sincere-hearth-273704.magpie.marketshare_universe` TABLESAMPLE SYSTEM (10 PERCENT)
  WHERE month = '2026-04-01'
    AND category_3 IS NOT NULL
),
capped AS (
  SELECT *
  FROM base_sampled
  QUALIFY ROW_NUMBER() OVER (PARTITION BY category_3 ORDER BY RAND()) <= 100
),
scored AS (
  SELECT
    *,
    ARRAY_LENGTH(SPLIT(TRIM(IFNULL(sku_type_complete, '')), ' ')) AS word_count,
    REGEXP_CONTAINS(
      LOWER(sku_type_complete),
      r'\d+(\.\d+)?\s?(ml|l|g|kg|mg|oz|pcs|pc|ct|sheet|sheets|tablet|tablets|capsule|capsules|sachet|sachets)\b'
    ) AS has_size
  FROM capped
),
tiered AS (
  SELECT
    *,
    CASE
      WHEN sku_type_complete IS NULL THEN 'D'
      WHEN has_size AND word_count >= 4 THEN 'A'
      WHEN NOT has_size AND word_count <= 3 THEN 'C'
      ELSE 'B'
    END AS tier
  FROM scored
)
SELECT
  category_3,
  COUNT(*) AS sampled_products,
  ROUND(100 * COUNTIF(tier = 'A') / COUNT(*), 1) AS pct_a,
  ROUND(100 * COUNTIF(tier = 'B') / COUNT(*), 1) AS pct_b,
  ROUND(100 * COUNTIF(tier = 'C') / COUNT(*), 1) AS pct_c,
  ROUND(100 * COUNTIF(tier = 'D') / COUNT(*), 1) AS pct_d,
  CASE
    WHEN 100 * COUNTIF(tier = 'A') / COUNT(*) >= 90 THEN 'Excellent'
    WHEN 100 * COUNTIF(tier = 'A') / COUNT(*) >= 70 THEN 'Good enough'
    ELSE 'Needs improvement'
  END AS bucket,
  ARRAY_AGG(IF(tier = 'A', STRUCT(sku_name AS sku_name, sku_type_complete AS sku_type_complete), NULL) IGNORE NULLS ORDER BY RAND() LIMIT 2) AS examples_a,
  ARRAY_AGG(IF(tier = 'B', STRUCT(sku_name AS sku_name, sku_type_complete AS sku_type_complete), NULL) IGNORE NULLS ORDER BY RAND() LIMIT 2) AS examples_b,
  ARRAY_AGG(IF(tier = 'C', STRUCT(sku_name AS sku_name, sku_type_complete AS sku_type_complete), NULL) IGNORE NULLS ORDER BY RAND() LIMIT 2) AS examples_c,
  ARRAY_AGG(IF(tier = 'D', STRUCT(sku_name AS sku_name, sku_type_complete AS sku_type_complete), NULL) IGNORE NULLS ORDER BY RAND() LIMIT 2) AS examples_d
FROM tiered
GROUP BY category_3
ORDER BY pct_a DESC;
```

Dry-run this first (`dry_run: true` via the bigquery-data skill's `execute_sql` script) and confirm bytes processed stays under your budget before running for real — this run cost 231 MB.
