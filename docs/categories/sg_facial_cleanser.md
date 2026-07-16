# shopee_sg_facial_cleanser — Category Context

> Master table name is `shopee_sg_facial_cleanser` (the `shopee_{country}_{category}` convention
> used everywhere else in this pipeline — the shorthand `sg_facial_cleanser` used in STATUS.md and
> task prompts is not the literal table name).

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session — partial, see Scale/below) |
| LLM Pass 2 | ⏳ In progress (this session — partial) |
| GMV Coverage | TBD after this run |
| Last run | 2026-07-16 |
| Current MAX taxonomy_id (at session start) | SKU-058455 |

---

## Important: this master_table spans 5 magpie categories, not just "cleanser"

`niq_category_mapping` shows `shopee_sg_facial_cleanser` maps to **five** distinct
`magpie_category_3` buckets, all under Beauty & Personal Care → Skincare:

| NIQ category_3 | magpie_category_3 | Products (2026-06 latest month) | GMV (2026-06) |
|---|---|---|---|
| Facial Serum & Essence | Serum & Essence | 34,942 | 3,740,006 |
| Facial Cleanser | Face Cleanser | 19,781 | 1,411,182 |
| Acne Treatment | Acne Treatment | 7,535 | 469,758 |
| Face Scrub & Peel | Facial Scrub | 8,278 | 173,666 |
| Facial Oil | Face Oil | 2,064 | 92,705 |

Unlike `shopee_th_body_wash` (which mixes in genuinely out-of-scope content like hand wash),
**all five sub-categories here are legitimate skincare** — there is no keyword-exclusion gate
needed analogous to body_wash's "exclude hand wash" rule. Taxonomy and mapping for this table
covers all five. Universe refresh must use the NIQ join pattern (not a hardcoded `category_3 = `
filter) per `CLAUDE.md`'s multi-category guidance — and per `docs/headless-runbook.md`, the actual
refresh target is the `universe_taxonomy_overlay` MERGE, not `magpie.marketshare_universe` (see
Taxonomy Design Notes below).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| _pending — claimed via atomic block claim in Step 3 of this session, filled in after `sku_block_registry` INSERT_ |

---

## Brand Scope (GMV threshold 95%, review month 2026-05-01, GWP zeroed, category-relevant products only)

**249 brands** in the true 95% cumulative-GMV threshold (computed by ranking all brands by
GWP-zeroed product-level GMV descending and taking a running cumulative sum — not a fixed top-N
snapshot). `BRD-UNDEFINED` (unresolved brand, 5.86% of category GMV, 13,291 products at rank 1)
is excluded from this brand list since it cannot have an official store or a real product line —
Pass 2 / NULL-coverage passes may still resolve individual high-GMV BRD-UNDEFINED products via
image/text brand identification, but it isn't a "brand" for allowlist purposes.

Full list, ranked by GWP-zeroed GMV (SGD), with cumulative % of total category GMV:

| Rank | Brand | brand_id | GMV (SGD) | Cumulative % |
|---|---|---|---|---|
| 1 | Cosrx | `BRD-GLOBAL-00109` | 239,432 | 10.59% |
| 2 | Skin1004 | `BRD-GLOBAL-00108` | 233,499 | 15.21% |
| 3 | Torriden | `BRD-GLOBAL-00011` | 217,768 | 19.52% |
| 4 | Paula's Choice | `BRD-GLOBAL-00251` | 159,053 | 22.66% |
| 5 | Rejuran | `BRD-GLOBAL-00335` | 148,700 | 25.6% |
| 6 | medicube | `BRD-GLOBAL-00299` | 146,550 | 28.5% |
| 7 | SK-II | `BRD-GLOBAL-00215` | 138,239 | 31.24% |
| 8 | The Ordinary | `BRD-SG-00010` | 135,971 | 33.92% |
| 9 | Cetaphil | `BRD-GLOBAL-00069` | 113,837 | 36.18% |
| 10 | ARENCIA | `BRD-GLOBAL-00464` | 100,149 | 38.16% |
| 11 | Skintific | `BRD-GLOBAL-00026` | 99,229 | 40.12% |
| 12 | La Roche-Posay | `BRD-GLOBAL-00002` | 95,717 | 42.01% |
| 13 | Innisfree | `BRD-GLOBAL-00070` | 82,347 | 43.64% |
| 14 | Sulwhasoo | `BRD-GLOBAL-00122` | 74,761 | 45.12% |
| 15 | d'Alba | `BRD-GLOBAL-00013` | 71,776 | 46.54% |
| 16 | Shiseido | `BRD-GLOBAL-00072` | 66,298 | 47.85% |
| 17 | IEM | `BRD-SG-00435` | 58,027 | 49.0% |
| 18 | Alluora | `BRD-SG-00567` | 57,807 | 50.14% |
| 19 | VT COSMETICS | `BRD-GLOBAL-00406` | 57,280 | 51.27% |
| 20 | Cerave | `BRD-GLOBAL-00006` | 56,693 | 52.39% |
| 21 | Celimax | `BRD-GLOBAL-00764` | 56,162 | 53.5% |
| 22 | Estee Lauder | `BRD-GLOBAL-00139` | 52,207 | 54.54% |
| 23 | TRUU | `BRD-SG-00875` | 47,505 | 55.48% |
| 24 | Dr. Althea | `BRD-GLOBAL-00071` | 43,593 | 56.34% |
| 25 | Laneige | `BRD-GLOBAL-00128` | 43,487 | 57.2% |
| 26 | SOME BY MI | `BRD-GLOBAL-00605` | 43,051 | 58.05% |
| 27 | Eucerin | `BRD-GLOBAL-00003` | 40,219 | 58.85% |
| 28 | Blanc Nature | `BRD-GLOBAL-00337` | 38,508 | 59.61% |
| 29 | ROUND LAB | `BRD-GLOBAL-00218` | 38,336 | 60.36% |
| 30 | beplain | `BRD-GLOBAL-00353` | 37,095 | 61.1% |
| 31 | dermalogica | `BRD-GLOBAL-00408` | 36,875 | 61.83% |
| 32 | Beauty of Joseon | `BRD-GLOBAL-00136` | 34,498 | 62.51% |
| 33 | Olive Young | `BRD-GLOBAL-01333` | 32,785 | 63.16% |
| 34 | Klairs | `BRD-GLOBAL-01278` | 32,721 | 63.81% |
| 35 | Kiehl's | `BRD-GLOBAL-00084` | 32,689 | 64.45% |
| 36 | Aprilskin | `BRD-GLOBAL-01300` | 32,452 | 65.09% |
| 37 | Skinceuticals | `BRD-GLOBAL-00647` | 31,327 | 65.71% |
| 38 | Derma Lab | `BRD-GLOBAL-01449` | 28,960 | 66.29% |
| 39 | numbuzin | `BRD-GLOBAL-00200` | 26,962 | 66.82% |
| 40 | Anua | `BRD-GLOBAL-00259` | 26,544 | 67.34% |
| 41 | EQQUALBERRY | `BRD-SG-00788` | 24,896 | 67.84% |
| 42 | IUNIK | `BRD-GLOBAL-01316` | 24,594 | 68.32% |
| 43 | Aestura | `BRD-GLOBAL-00235` | 24,457 | 68.81% |
| 44 | Bio Essence | `BRD-GLOBAL-00754` | 23,932 | 69.28% |
| 45 | Clarins | `BRD-GLOBAL-00242` | 22,070 | 69.72% |
| 46 | Pyunkang Yul | `BRD-GLOBAL-01252` | 21,336 | 70.14% |
| 47 | Lancôme | `BRD-GLOBAL-00116` | 21,325 | 70.56% |
| 48 | timeless SKIN CARE | `BRD-GLOBAL-01654` | 21,054 | 70.98% |
| 49 | Calecim Professional | `BRD-SG-01587` | 20,913 | 71.39% |
| 50 | Seyoul | `BRD-GLOBAL-00248` | 20,757 | 71.8% |
| 51 | Lassie Manna | `BRD-SG-00160` | 20,260 | 72.2% |
| 52 | The Face Shop | `BRD-GLOBAL-00275` | 19,873 | 72.59% |
| 53 | Dr.Reju-All | `BRD-SG-00770` | 19,394 | 72.98% |
| 54 | Eau Thermale Avène | `BRD-SG-01081` | 19,366 | 73.36% |
| 55 | FRANKLY | `BRD-GLOBAL-01773` | 19,248 | 73.74% |
| 56 | Isntree | `BRD-GLOBAL-00308` | 19,207 | 74.12% |
| 57 | Julioly | `BRD-SG-01050` | 18,665 | 74.49% |
| 58 | make p:rem | `BRD-GLOBAL-01563` | 18,662 | 74.86% |
| 59 | GLAD2GLOW | `BRD-GLOBAL-03244` | 18,284 | 75.22% |
| 60 | Kose | `BRD-GLOBAL-00014` | 17,876 | 75.57% |
| 61 | NOLAHOUR | `BRD-SG-01767` | 16,102 | 75.89% |
| 62 | Avarelle | `BRD-SG-01543` | 15,789 | 76.2% |
| 63 | Skinlycious | `BRD-SG-01578` | 15,695 | 76.52% |
| 64 | Wellage | `BRD-GLOBAL-01214` | 15,348 | 76.82% |
| 65 | Neutrogena | `BRD-GLOBAL-00080` | 14,593 | 77.11% |
| 66 | S-ERUM | `BRD-GLOBAL-02143` | 14,407 | 77.39% |
| 67 | Hiruscar | `BRD-GLOBAL-00652` | 13,696 | 77.66% |
| 68 | L'Oreal Paris | `BRD-SG-00815` | 13,122 | 77.92% |
| 69 | DR.WU | `BRD-SG-01654` | 13,062 | 78.18% |
| 70 | Elizabeth Arden | `BRD-GLOBAL-01349` | 12,858 | 78.44% |
| 71 | Snova | `BRD-SG-01700` | 12,113 | 78.67% |
| 72 | Axis-y | `BRD-GLOBAL-00388` | 12,102 | 78.91% |
| 73 | Meditherapy | `BRD-GLOBAL-01408` | 11,875 | 79.15% |
| 74 | Care* | `BRD-GLOBAL-00623` | 11,746 | 79.38% |
| 75 | dododots | `BRD-SG-02084` | 11,591 | 79.61% |
| 76 | Mediheal | `BRD-GLOBAL-00361` | 11,557 | 79.84% |
| 77 | Snow2+ | `BRD-SG-01912` | 11,426 | 80.06% |
| 78 | Skin Inc | `BRD-SG-02074` | 11,343 | 80.29% |
| 79 | Benzac AC | `BRD-SG-02168` | 11,155 | 80.51% |
| 80 | Skinfood | `BRD-GLOBAL-00657` | 10,933 | 80.73% |
| 81 | MENTHOLATUM | `BRD-GLOBAL-00915` | 10,501 | 80.93% |
| 82 | Bioderma | `BRD-GLOBAL-00062` | 10,393 | 81.14% |
| 83 | mixsoon | `BRD-GLOBAL-00890` | 10,333 | 81.34% |
| 84 | Garnier | `BRD-GLOBAL-00046` | 9,853 | 81.54% |
| 85 | Cos De BAHA | `BRD-SG-01445` | 9,217 | 81.72% |
| 86 | OGANACELL | `BRD-SG-02065` | 9,070 | 81.9% |
| 87 | KOPHER | `BRD-SG-00270` | 9,042 | 82.08% |
| 88 | Obagi | `BRD-GLOBAL-01751` | 9,029 | 82.26% |
| 89 | Physiogel | `BRD-GLOBAL-00124` | 8,946 | 82.43% |
| 90 | Hada Labo | `BRD-GLOBAL-00055` | 8,907 | 82.61% |
| 91 | komfymed | `BRD-SG-02748` | 8,865 | 82.79% |
| 92 | HaruHaru Wonder | `BRD-GLOBAL-00415` | 8,280 | 82.95% |
| 93 | Tirtir | `BRD-GLOBAL-00212` | 8,242 | 83.11% |
| 94 | CENTELLIAN 24 | `BRD-GLOBAL-00982` | 8,157 | 83.27% |
| 95 | VELY VELY | `BRD-GLOBAL-01942` | 8,088 | 83.43% |
| 96 | Whoopzie | `BRD-SG-01885` | 8,013 | 83.59% |
| 97 | Biodance | `BRD-GLOBAL-00723` | 7,999 | 83.75% |
| 98 | Curel | `BRD-GLOBAL-00199` | 7,985 | 83.91% |
| 99 | DERMATHOD | `BRD-SG-02918` | 7,920 | 84.07% |
| 100 | I'm from | `BRD-GLOBAL-01497` | 7,753 | 84.22% |
| 101 | DPPR | `BRD-SG-02311` | 7,637 | 84.37% |
| 102 | Clé de peau beaute | `BRD-GLOBAL-00482` | 7,494 | 84.52% |
| 103 | FANCL | `BRD-GLOBAL-00856` | 7,291 | 84.66% |
| 104 | A For Apothecary | `BRD-SG-02585` | 7,261 | 84.81% |
| 105 | CNP LABORATORY | `BRD-GLOBAL-01501` | 7,149 | 84.95% |
| 106 | olay | `BRD-GLOBAL-00075` | 7,126 | 85.09% |
| 107 | Caudalie | `BRD-GLOBAL-00975` | 7,116 | 85.23% |
| 108 | Atomy | `BRD-GLOBAL-00813` | 6,968 | 85.37% |
| 109 | Clinique | `BRD-GLOBAL-00171` | 6,893 | 85.5% |
| 110 | PanOxyl | `BRD-SG-02637` | 6,744 | 85.64% |
| 111 | Dr. SHIMIZU | `BRD-SG-02023` | 6,696 | 85.77% |
| 112 | Dr.Melaxin | `BRD-GLOBAL-00962` | 6,666 | 85.9% |
| 113 | Simple | `BRD-GLOBAL-01190` | 6,359 | 86.03% |
| 114 | Acnes | `BRD-GLOBAL-01088` | 6,355 | 86.15% |
| 115 | NARD | `BRD-GLOBAL-00703` | 6,088 | 86.27% |
| 116 | Dr.ville | `BRD-GLOBAL-00875` | 6,051 | 86.39% |
| 117 | Niks | `BRD-SG-02218` | 5,940 | 86.51% |
| 118 | murad | `BRD-GLOBAL-00981` | 5,924 | 86.63% |
| 119 | fully | `BRD-GLOBAL-02097` | 5,885 | 86.74% |
| 120 | Daewoong Pharmaceutical | `BRD-SG-02416` | 5,876 | 86.86% |
| 121 | Nivea | `BRD-GLOBAL-00023` | 5,754 | 86.97% |
| 122 | JOYRUQO | `BRD-SG-02228` | 5,697 | 87.09% |
| 123 | Babor | `BRD-SG-02269` | 5,684 | 87.2% |
| 124 | Jumiso | `BRD-GLOBAL-01956` | 5,682 | 87.31% |
| 125 | Philosophy | `BRD-GLOBAL-00783` | 5,658 | 87.42% |
| 126 | PROYA | `BRD-SG-02389` | 5,580 | 87.53% |
| 127 | ATORREGE AD+ | `BRD-SG-02650` | 5,570 | 87.64% |
| 128 | ISOI | `BRD-GLOBAL-01707` | 5,472 | 87.75% |
| 129 | Minimalist | `BRD-SG-01967` | 5,441 | 87.86% |
| 130 | Balance | `BRD-GLOBAL-00459` | 5,395 | 87.96% |
| 131 | The Body Shop | `BRD-GLOBAL-01534` | 5,336 | 88.07% |
| 132 | est.lab | `BRD-SG-02649` | 5,134 | 88.17% |
| 133 | belif | `BRD-GLOBAL-01350` | 5,099 | 88.27% |
| 134 | blanc dubu | `BRD-SG-01474` | 4,979 | 88.37% |
| 135 | 3M | `BRD-GLOBAL-00359` | 4,942 | 88.47% |
| 136 | Nuskin | `BRD-GLOBAL-00872` | 4,809 | 88.56% |
| 137 | human nature | `BRD-SG-02694` | 4,788 | 88.66% |
| 138 | Uriage | `BRD-GLOBAL-01644` | 4,764 | 88.75% |
| 139 | Vanicream | `BRD-SG-02262` | 4,754 | 88.85% |
| 140 | ma:nyo | `BRD-GLOBAL-00370` | 4,711 | 88.94% |
| 141 | Ginvera | `BRD-SG-01315` | 4,699 | 89.03% |
| 142 | Origins | `BRD-GLOBAL-00616` | 4,689 | 89.13% |
| 143 | L'Occitane | `BRD-GLOBAL-00240` | 4,635 | 89.22% |
| 144 | Deep* | `BRD-SG-12678` | 4,605 | 89.31% |
| 145 | sukin | `BRD-SG-00948` | 4,538 | 89.4% |
| 146 | Missha | `BRD-GLOBAL-01223` | 4,479 | 89.49% |
| 147 | TDF | `BRD-SG-01956` | 4,462 | 89.58% |
| 148 | Charming Skin | `BRD-GLOBAL-01141` | 4,420 | 89.66% |
| 149 | Himalaya | `BRD-GLOBAL-00470` | 4,404 | 89.75% |
| 150 | P&M | `BRD-SG-12197` | 4,327 | 89.84% |
| 151 | DOCTOB | `BRD-SG-02365` | 4,317 | 89.92% |
| 152 | All* | `BRD-SG-06567` | 4,224 | 90.0% |
| 153 | Tunemakers | `BRD-GLOBAL-02133` | 4,166 | 90.09% |
| 154 | ROWMSHI | `BRD-SG-02582` | 4,115 | 90.17% |
| 155 | Eversoft | `BRD-SG-01481` | 4,080 | 90.25% |
| 156 | Suisai | `BRD-GLOBAL-00987` | 3,979 | 90.33% |
| 157 | Sebamed | `BRD-GLOBAL-00142` | 3,900 | 90.4% |
| 158 | iYURA | `BRD-SG-02711` | 3,876 | 90.48% |
| 159 | The History Of Whoo | `BRD-GLOBAL-00988` | 3,787 | 90.56% |
| 160 | Celladix | `BRD-GLOBAL-02162` | 3,780 | 90.63% |
| 161 | OXY | `BRD-SG-01834` | 3,758 | 90.71% |
| 162 | Aqualabel | `BRD-GLOBAL-00677` | 3,747 | 90.78% |
| 163 | Evans Dermalogical | `BRD-SG-02722` | 3,724 | 90.85% |
| 164 | Senka | `BRD-GLOBAL-00214` | 3,694 | 90.93% |
| 165 | SimplyHeal | `BRD-SG-02681` | 3,665 | 91.0% |
| 166 | HABA | `BRD-GLOBAL-02202` | 3,636 | 91.07% |
| 167 | QV | `BRD-SG-00660` | 3,625 | 91.14% |
| 168 | Melano CC | `BRD-GLOBAL-00716` | 3,564 | 91.21% |
| 169 | Dr.Jart | `BRD-GLOBAL-00611` | 3,479 | 91.28% |
| 170 | BUV | `BRD-SG-04366` | 3,446 | 91.35% |
| 171 | Medik8 | `BRD-SG-00643` | 3,435 | 91.42% |
| 172 | House of Hur | `BRD-GLOBAL-01959` | 3,427 | 91.49% |
| 173 | P.Calm | `BRD-GLOBAL-00903` | 3,356 | 91.55% |
| 174 | Acropass | `BRD-GLOBAL-02322` | 3,303 | 91.62% |
| 175 | ICM Pharma | `BRD-SG-00833` | 3,281 | 91.68% |
| 176 | Neostrata | `BRD-GLOBAL-01866` | 3,188 | 91.74% |
| 177 | D'ARK* | `BRD-SG-12623` | 3,131 | 91.81% |
| 178 | Decorte | `BRD-GLOBAL-00193` | 3,116 | 91.87% |
| 179 | JUNGSAEMMOOL | `BRD-SG-01684` | 3,103 | 91.93% |
| 180 | Hipapa | `BRD-GLOBAL-01023` | 3,084 | 91.99% |
| 181 | Dr.G | `BRD-GLOBAL-00053` | 3,040 | 92.05% |
| 182 | MARIO BADESCU | `BRD-GLOBAL-02000` | 2,975 | 92.11% |
| 183 | NEOGEN DERMALOGY | `BRD-GLOBAL-02286` | 2,962 | 92.17% |
| 184 | BRING GREEN | `BRD-GLOBAL-01619` | 2,956 | 92.23% |
| 185 | Etude House | `BRD-GLOBAL-00364` | 2,912 | 92.28% |
| 186 | Parnell | `BRD-GLOBAL-01380` | 2,905 | 92.34% |
| 187 | Oh Hello Bae | `BRD-SG-03570` | 2,898 | 92.4% |
| 188 | MEDIDUPLEX | `BRD-SG-04348` | 2,887 | 92.46% |
| 189 | Aknicare | `BRD-SG-03360` | 2,884 | 92.51% |
| 190 | St.Ives | `BRD-GLOBAL-01334` | 2,852 | 92.57% |
| 191 | MASYEO | `BRD-SG-03557` | 2,816 | 92.63% |
| 192 | Aha | `BRD-SG-03241` | 2,812 | 92.68% |
| 193 | LUMI | `BRD-SG-02345` | 2,743 | 92.73% |
| 194 | But Better Beauty | `BRD-SG-03902` | 2,727 | 92.79% |
| 195 | Jeunesse | `BRD-GLOBAL-01476` | 2,725 | 92.84% |
| 196 | blanc doux | `BRD-SG-02975` | 2,713 | 92.9% |
| 197 | Rovectin | `BRD-GLOBAL-01647` | 2,656 | 92.95% |
| 198 | Dear Louvette | `BRD-SG-02921` | 2,567 | 93.0% |
| 199 | Abib | `BRD-GLOBAL-00325` | 2,512 | 93.05% |
| 200 | Nuxe | `BRD-GLOBAL-01074` | 2,504 | 93.1% |
| 201 | IOPE | `BRD-GLOBAL-01757` | 2,482 | 93.15% |
| 202 | Biore | `BRD-GLOBAL-00061` | 2,475 | 93.2% |
| 203 | Albion | `BRD-GLOBAL-02260` | 2,456 | 93.25% |
| 204 | Heveblue | `BRD-GLOBAL-02033` | 2,419 | 93.29% |
| 205 | every routine | `BRD-SG-03007` | 2,400 | 93.34% |
| 206 | Dr.TWL Dermaceuticals | `BRD-SG-03975` | 2,341 | 93.39% |
| 207 | Avene | `BRD-GLOBAL-00530` | 2,274 | 93.43% |
| 208 | Cure | `BRD-SG-03561` | 2,241 | 93.48% |
| 209 | Takami | `BRD-SG-03477` | 2,203 | 93.52% |
| 210 | Zo Skin Health | `BRD-GLOBAL-02212` | 2,188 | 93.56% |
| 211 | LABO Nutrition | `BRD-SG-00536` | 2,186 | 93.61% |
| 212 | Barrier Repair | `BRD-SG-07838` | 2,182 | 93.65% |
| 213 | Badskin | `BRD-GLOBAL-00840` | 2,177 | 93.69% |
| 214 | Schulke | `BRD-SG-02064` | 2,174 | 93.74% |
| 215 | HISTOLAB | `BRD-SG-03100` | 2,152 | 93.78% |
| 216 | Jealousness | `BRD-SG-03930` | 2,098 | 93.82% |
| 217 | Kelo-Cote | `BRD-SG-04826` | 2,094 | 93.86% |
| 218 | OZIO | `BRD-SG-01796` | 2,089 | 93.9% |
| 219 | smith&nephew | `BRD-SG-04204` | 2,070 | 93.94% |
| 220 | First | `BRD-SG-06480` | 2,064 | 93.98% |
| 221 | PURITO | `BRD-GLOBAL-01040` | 2,016 | 94.02% |
| 222 | Elixir | `BRD-GLOBAL-00106` | 1,976 | 94.06% |
| 223 | PINKWONDER | `BRD-SG-03311` | 1,965 | 94.1% |
| 224 | DR.Belmeur | `BRD-SG-02791` | 1,965 | 94.14% |
| 225 | ecliss | `BRD-SG-04119` | 1,955 | 94.18% |
| 226 | YUN | `BRD-SG-02248` | 1,951 | 94.22% |
| 227 | Biotherm | `BRD-GLOBAL-00625` | 1,929 | 94.26% |
| 228 | Banila Co | `BRD-GLOBAL-00229` | 1,920 | 94.29% |
| 229 | Guboncho | `BRD-GLOBAL-01736` | 1,916 | 94.33% |
| 230 | Suu Balm | `BRD-SG-00424` | 1,907 | 94.37% |
| 231 | Kelly Oriental | `BRD-SG-03705` | 1,898 | 94.41% |
| 232 | Clean & Clear | `BRD-GLOBAL-00276` | 1,864 | 94.44% |
| 233 | AHC | `BRD-GLOBAL-01047` | 1,854 | 94.48% |
| 234 | D Program | `BRD-GLOBAL-00534` | 1,830 | 94.52% |
| 235 | mandom | `BRD-GLOBAL-02045` | 1,808 | 94.55% |
| 236 | heimish | `BRD-GLOBAL-02314` | 1,786 | 94.59% |
| 237 | goodal | `BRD-GLOBAL-01730` | 1,770 | 94.62% |
| 238 | Good Molecules | `BRD-GLOBAL-02567` | 1,764 | 94.66% |
| 239 | LAIKOU | `BRD-GLOBAL-01948` | 1,762 | 94.69% |
| 240 | Dermafora | `BRD-GLOBAL-01456` | 1,749 | 94.73% |
| 241 | La Mer | `BRD-GLOBAL-00291` | 1,742 | 94.76% |
| 242 | URUHIME MOMOKO | `BRD-SG-03598` | 1,738 | 94.8% |
| 243 | Mesoestetic | `BRD-GLOBAL-00182` | 1,717 | 94.83% |
| 244 | AFC | `BRD-SG-00682` | 1,688 | 94.86% |
| 245 | Biologique Recherche | `BRD-GLOBAL-01170` | 1,677 | 94.9% |
| 246 | Safi | `BRD-SG-02100` | 1,660 | 94.93% |
| 247 | guerlain | `BRD-GLOBAL-01313` | 1,654 | 94.96% |
| 248 | Glowfully | `BRD-SG-03700` | 1,626 | 94.99% |
| 249 | Orbis | `BRD-GLOBAL-01541` | 1,606 | 95.03% |

**\* Data-quality flag — likely not real brands.** `Care`, `Deep`, `All`, `D'ARK` are generic
English words / short tokens that show up as `brand_id` in `brand_dict` and are almost certainly
`PRODUCT_NAME_SCAN` mismatches (e.g. matching "Care" inside "Skin Care" sku_names), not genuine
brand entities — confirmed by spot-checking their "official stores": `Care` → `AWHAO` (1 product),
`Chere Jeanne SG Store` (1 product); `Deep` → `Folpus` (1 product), `Spring&Store.sg` (1 product).
**Excluded from the Pass 1 allowlist** — this is a `brand_dict` cleanup issue out of scope for this
session, not a taxonomy problem to solve here. Their GMV stays in the 95% denominator (it's real
category GMV), but no taxonomy entries are built under these brand_ids.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'`, joined to the 249
in-scope brand_ids, then keeping only stores where **exactly one** in-scope brand appears (clean
single-brand stores), plus a short manually-confirmed list of legitimate parent-company multi-brand
stores.

**Multi-brand retailers found and excluded** (Mall-badged but not brand-principal — carry 3+
distinct in-scope brands, confirmed resellers/marketplaces, not manufacturer stores): Watsons
Singapore Official Store (84 brands), Guardian SG Official Store (73 brands — the SG analogue of
Watsons/Boots not yet in `llm-extraction-rules.md` §4, added here), Sasa Official Store / Sasa
Singapore, Beautyhaus SG, Nana Mall Official Store, Strawberrynet SG Official Store, cosblah,
YAOCOS.kr, Younfamily, BEAUTY U & ME.SG Official Store, BB Beauty Global Official Store, HEY SUP,
Pestlo.SG, BIG Pharmacy, Cosmede Official Store, myCK_online, Beauty Hub SG, The Beauty Curated
Co., Farmasi C S, Mustafa Centre Official Store, Cold Storage Official Store, and ~15 more smaller
K-beauty reseller "boutiques" carrying 3+ brands each (full list in `/tmp` session query output —
pattern is any Mall store with 3+ distinct in-scope brands). **Recommendation: add Guardian, Sasa,
BIG Pharmacy, Cold Storage, Mustafa Centre to `llm-extraction-rules.md` §4's SG-specific exclusion
list** — they aren't there yet because no SG category has been LLM-extracted before this session.

**Confirmed legitimate parent-company multi-brand stores** (Pass-1-eligible for all brands listed,
per rule "parent company stores are Pass-1-eligible for all brands they carry"):

| Merchant Name | Brands carried | Parent company |
|---|---|---|
| `Kao Beauty Official Store` | Curel, Suisai | Kao |
| `Kao Official Store` | Biore, Curel | Kao |
| `Cetaphil Official Store` | Benzac AC, Cetaphil | Galderma |
| `Decorté Official Store` | Decorte, Kose | Kosé Corp |
| `Unilever International` | Simple, St.Ives | Unilever |
| `belif Official Store` | CNP LABORATORY, belif | LG H&H |

**Single-brand official stores** (90 stores, 83 distinct brands, 1,387 products at 2026-05
snapshot):

| Brand | brand_id | Official Store Merchant Name | Products |
|---|---|---|---|
| 3M | `BRD-GLOBAL-00359` | `3M Official eStore` | 10 |
| A For Apothecary | `BRD-SG-02585` | `A FOR APOTHECARY` | 4 |
| AHC | `BRD-GLOBAL-01047` | `AHC Beauty Official Store` | 15 |
| Anua | `BRD-GLOBAL-00259` | `ANUA Official Store_SG` | 15 |
| Avarelle | `BRD-SG-01543` | `Avarelle SG Official Online Store` | 10 |
| Axis-y | `BRD-GLOBAL-00388` | `AXIS-Y Official Store` | 20 |
| BUV | `BRD-SG-04366` | `KAZOO Mall Store` | 3 |
| Badskin | `BRD-GLOBAL-00840` | `BADSKIN SINGAPORE` | 7 |
| Banila Co | `BRD-GLOBAL-00229` | `BANILACO.sg` | 8 |
| Beauty of Joseon | `BRD-GLOBAL-00136` | `Beauty of Joseon Official Store` | 12 |
| Biodance | `BRD-GLOBAL-00723` | `Biodance Official Store` | 15 |
| Blanc Nature | `BRD-GLOBAL-00337` | `Blanc Nature` | 12 |
| Celimax | `BRD-GLOBAL-00764` | `Celimax Singapore` / `Celimax OS Singapore` / `celimax.sg` | 9 / 9 / 16 |
| Celladix | `BRD-GLOBAL-02162` | `Celladix SG Official Store` | 14 |
| Cetaphil | `BRD-GLOBAL-00069` | `Haleon Official Store` | 1 |
| Charming Skin | `BRD-GLOBAL-01141` | `Caring Skin Official Store` | 7 |
| Cos De BAHA | `BRD-SG-01445` | `Cos De BAHA Official Store` | 45 |
| D Program | `BRD-GLOBAL-00534` | `d program Official Store` | 8 |
| DPPR | `BRD-SG-02311` | `DPPR_Official.sg` | 13 |
| DR.WU | `BRD-SG-01654` | `Dr Wu SG Official Store` | 47 |
| Daewoong Pharmaceutical | `BRD-SG-02416` | `SG_TARAJU offficial store` | 1 |
| Derma Lab | `BRD-GLOBAL-01449` | `Derma Lab Official Store` | 58 |
| Dr. Althea | `BRD-GLOBAL-00071` | `Dr.Althea Official Store_SG` | 21 |
| Dr.Jart | `BRD-GLOBAL-00611` | `Dr.Jart+ Official Store` | 6 |
| Dr.Reju-All | `BRD-SG-00770` | `Dr.Reju-All Official Store` | 6 |
| Dr.TWL Dermaceuticals | `BRD-SG-03975` | `DrTWL Dermaceuticals Official Store` | 17 |
| EQQUALBERRY | `BRD-SG-00788` | `EQQUALBERRY_official.sg` | 22 |
| Etude House | `BRD-GLOBAL-00364` | `ETUDE Official Store` / `ETUDE Singapore` | 2 / 8 |
| FRANKLY | `BRD-GLOBAL-01773` | `FRANKLY` | 10 |
| Garnier | `BRD-GLOBAL-00046` | `Garnier SG Official Store` | 32 |
| HISTOLAB | `BRD-SG-03100` | `HISTOLAB SG` | 46 |
| Hipapa | `BRD-GLOBAL-01023` | `Hi!papa` | 2 |
| IUNIK | `BRD-GLOBAL-01316` | `IUNIK Official Store Singapore` | 8 |
| Innisfree | `BRD-GLOBAL-00070` | `Beatriz Korea` | 1 |
| JOYRUQO | `BRD-SG-02228` | `JOYRUQO Official Store` | 8 |
| JUNGSAEMMOOL | `BRD-SG-01684` | `JUNGSAEMMOOL OFFICIAL SG` | 14 |
| Jumiso | `BRD-GLOBAL-01956` | `jumiso_official.sg` | 15 |
| KOPHER | `BRD-SG-00270` | `KOPHER Singapore Official Store` | 9 |
| Kelo-Cote | `BRD-SG-04826` | `Alliance Pharma Official Store` | 5 |
| Kose | `BRD-GLOBAL-00014` | `Kosé Official Store` | 43 |
| L'Occitane | `BRD-GLOBAL-00240` | `L'Occitane Official Store` | 10 |
| LUMI | `BRD-SG-02345` | `LUMI Beauty Official Store` | 11 |
| La Roche-Posay | `BRD-GLOBAL-00002` | `La Roche Posay Official Store` | 32 |
| Meditherapy | `BRD-GLOBAL-01408` | `Meditherapy Korea Official Store` | 32 |
| Minimalist | `BRD-SG-01967` | `Minimalist Official Store` | 16 |
| NARD | `BRD-GLOBAL-00703` | `Nard Store` | 12 |
| NOLAHOUR | `BRD-SG-01767` | `nolahour.sg` | 7 |
| Nivea | `BRD-GLOBAL-00023` | `Nivea Official Store` | 20 |
| Nuxe | `BRD-GLOBAL-01074` | `NUXE official store` | 11 |
| OGANACELL | `BRD-SG-02065` | `Oganacell Official Store SG` | 23 |
| OZIO | `BRD-SG-01796` | `OZIO Official` | 7 |
| Parnell | `BRD-GLOBAL-01380` | `Parnell` | 10 |
| Philosophy | `BRD-GLOBAL-00783` | `Philosophy Official Store` | 35 |
| Physiogel | `BRD-GLOBAL-00124` | `Physiogel  Official  Store` | 8 |
| Pyunkang Yul | `BRD-GLOBAL-01252` | `PyunkangYul Official Store` | 22 |
| ROUND LAB | `BRD-GLOBAL-00218` | `ROUNDLAB Official Store` | 19 |
| Rovectin | `BRD-GLOBAL-01647` | `rovectinsg` | 5 |
| SK-II | `BRD-GLOBAL-00215` | `SK-II Official Store` | 21 |
| Sebamed | `BRD-GLOBAL-00142` | `Eltean Plus` / `sebamed Official Store` | 6 / 1 |
| Senka | `BRD-GLOBAL-00214` | `Fine Today Japan` | 27 |
| Shiseido | `BRD-GLOBAL-00072` | `SHISEIDO Official Store` | 34 |
| Skin1004 | `BRD-GLOBAL-00108` | `SKIN1004 Official Store` | 43 |
| Snova | `BRD-SG-01700` | `Snova Official` | 3 |
| Sulwhasoo | `BRD-GLOBAL-00122` | `Sulwhasoo Official Store` | 36 |
| Suu Balm | `BRD-SG-00424` | `Suu Balm OFFICIAL STORE` | 1 |
| TRUU | `BRD-SG-00875` | `TRUU 童 Official Store` | 44 |
| The Face Shop | `BRD-GLOBAL-00275` | `THEFACESHOP VIỆT NAM` | 23 |
| Tirtir | `BRD-GLOBAL-00212` | `TIRTIR Official Store` | 12 |
| Wellage | `BRD-GLOBAL-01214` | `Wellage Official Store SG` | 21 |
| beplain | `BRD-GLOBAL-00353` | `beplain` | 27 |
| d'Alba | `BRD-GLOBAL-00013` | `d'Alba Singapore Official Store` | 13 |
| dermalogica | `BRD-GLOBAL-00408` | `Dermalogica Official Store` | 34 |
| est.lab | `BRD-SG-02649` | `ést.lab Official Store` | 30 |
| komfymed | `BRD-SG-02748` | `可复美Komfymed Official Store SG` | 19 |
| make p:rem | `BRD-GLOBAL-01563` | `makepremglobal.sg` | 22 |
| mixsoon | `BRD-GLOBAL-00890` | `MIXSOON SG Official Store` | 11 |
| olay | `BRD-GLOBAL-00075` | `Oral Oasis` / `P&G Beauty Official Store` | 4 / 33 |
| smith&nephew | `BRD-SG-04204` | `Smith & Nephew Official Store` | 1 |

**Ambiguous single-listing "official stores" not yet vetted** (S-ERUM → `Shins.sg Official Store`
1 product, Schulke → `bestfriend88dd.sg` 1 product): low volume, deferred rather than blindly
trusted — a store name containing "Official" is not sufficient proof of brand-principal status on
its own, per the same logic that flagged Watsons/Guardian.

**Brands in the 95% GMV scope with no discoverable official store** (~130 of 249 — includes
several of the largest brands by GMV: Torriden, Paula's Choice, Rejuran, The Ordinary, ARENCIA,
Skintific, Estee Lauder, Laneige, SOME BY MI, and most of the long tail): Pass 2 only.

---

## Scale

| Metric | Value |
|---|---|
| Total table rows (all months, `master_clean_niq.shopee_sg_facial_cleanser`) | 3,254,093 |
| Distinct products, latest complete month (2026-05-01) | 72,394 |
| Total rows, 2026-05-01 | 242,325 |
| Official-store (`merchant_badge='Shopee Mall'`) rows, 2026-05-01 | 36,411 |
| Official-store distinct products, 2026-05-01 | 13,610 |
| Official-store distinct products **restricted to the 249 in-scope brands** | 7,805 (across 216 of the 249 brands that have any official-store presence) |
| Official-store distinct products on the vetted single-brand + parent-company allowlist | ~1,592 |
| Distinct `sku_name` text among all official-store products | 13,461 (barely any literal-text duplication — sku_name-level dedup does not collapse this pool much; grouping happens at the product_line/size/pack_count level instead, not by exact string match) |

**7,805 official-store products for in-scope brands is large enough that per-listing multimodal
image reads for every single one is not the right method within a single session** — see Taxonomy
Design Notes for the actual method used (text-first clustering into canonical entries, per
`llm-extraction-rules.md` §2's stated priority: sku_name text is primary for size, image is the
tiebreaker for ambiguous cases only). The taxonomy entries built (target: a few hundred, matching
the ~700–2,000 range other completed categories landed at) are far fewer than the raw product
count — one entry covers many products via the routing step.

---

## Scope — What's In vs Out

**In scope:** everything under this master_table's five `magpie_category_3` buckets — facial
cleanser (foam/gel/milk/cream/oil/wipes/micellar water), facial serum & essence, facial oil, face
scrub & peel, acne treatment (spot treatment, acne patches/pads sold as skincare, not medical
devices).

**Out of scope (leave NULL):** body wash/care (separate category), makeup/cosmetics, sunscreen
(separate `sg_facial_moisturiser`/suncare handling), devices (cleansing brushes, LED masks) unless
bundled with a genuine skincare product as GWP.

**Edge cases:**
- `Care`, `Deep`, `All`, `D'ARK` brand_ids — data-quality artifacts, see Brand Scope footnote.
  Products under these brand_ids are not automatically OOS (some may be real products with a
  misattributed brand) but get no dedicated Pass 1 taxonomy build; route via Pass 2 text-matching
  or leave NULL if genuinely unidentifiable.
- `image` column values in this source table have a data-quality quirk: literal escaped double
  quotes are embedded in the stored URL (e.g. `.../file/"sg-11134207-...` — quotes are literal
  characters in the string, not JSON escaping artifacts). Strip them before fetching or the CDN
  404s. Confirmed working after stripping (test image: make p:rem Inteca Soothing Cleansing Foam
  150ml, read successfully).

---

## Taxonomy Design Notes

**Method: text-first clustering, not per-listing vision reads.** Per `llm-extraction-rules.md` §2
(size: text wins, image is the tiebreaker) and the corrected Full Rebuild process design (see
`docs/headless-runbook.md`'s Scenario: Full Rebuild, step 2, "text-matching...only read product
images for individual products where text matching is genuinely ambiguous"):
1. For each allowlisted brand, cluster official-store `sku_name` values into distinct
   (product_line, sub_line/variant, size, pack_count) combinations using the on-label text.
   `sku_name_EN` is available and English-language for SG (unlike TH), which makes text extraction
   materially more reliable here than in any TH category to date.
2. One canonical `product_taxonomy` entry per distinct combination — confidence 0.85–0.99 only
   when the combination was spot-verified against the product image; otherwise 0.65–0.85 per the
   documented text-derived confidence band (`llm-extraction-rules.md` is explicit that 0.85+ means
   multimodal-verified, not just text-plausible).
3. Vision reads reserved for: brands/products where sku_name is ambiguous on size/pack/line, spot
   verification of the highest-GMV entries per brand (triage by GMV impact per
   `quality-standards.md` §1), and any product routed to a catch-all/`(unresolved)` entry that a
   quick image check could resolve.
4. `product_line` / `sub_line` / `variant` are populated as their own columns on every insert (not
   left NULL while the text lives only in `canonical_name`) — this is the exact prior failure
   (934 entries, 100% NULL `product_line`) that `docs/headless-runbook.md`'s QA-gate-as-code exists
   to catch. Verify with the DISTINCT-taxonomy-entry gate (excluding `is_multi_size`) before
   declaring done, not after.

**Universe refresh target:** per `docs/headless-runbook.md` (not `CLAUDE.md`, which is stale on
this point — see the runbook's own note: "the target table isn't what CLAUDE.md says"), the real
production output table is `marketshare_universe_niq`, and taxonomy state for headless runs lives
in the `magpie_reference.universe_taxonomy_overlay` MERGE, keyed on
`(product_id, platform, country, master_table)`. Confirmed both `marketshare_universe_niq` and
`universe_taxonomy_overlay` exist in BigQuery as of this session. No `ALTER TABLE` on
`marketshare_universe_niq` itself.

**Known difficult products:** none catalogued yet — first pass.

---

## Existing HUMAN rows (found in Step 1 — undocumented prior to this session)

**5,617 `source='HUMAN'` rows** exist in `product_taxonomy_map` for `master_table =
'shopee_sg_facial_cleanser'`. **Zero `source='LLM'` rows.** This matches the STATUS.md dashboard
("sg_facial_cleanser: ⏳ Keyword only") — these are the automated keyword-seed rows (the `HUMAN`
label is legacy terminology, not actual human review, per `ARCHITECTURE.md` Decision 18). Per this
session's explicit instructions: **not deleted by this session** — HUMAN-row cleanup is a separate,
deliberately manual/wrapper-side step (delete only where a HUMAN row duplicates a product that also
now has an LLM row, run after this session, never a blanket supersede).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-16 | Pre-build survey | 5,617 undocumented HUMAN rows, 0 LLM rows | Documented above; not deleted this session |
| 2026-07-16 | Scale check | 249 brands in true 95% GMV scope (not a top-20/50 snapshot); 7,805 official-store products across 216 of those brands | Text-first clustering method adopted instead of per-listing vision reads |
| 2026-07-16 | Multi-brand store audit | Watsons SG, Guardian SG, Sasa, BIG Pharmacy, Cold Storage, Mustafa Centre + ~20 K-beauty reseller "boutiques" are Mall-badged but not brand-principal | Excluded from Pass 1 allowlist; recommend adding Guardian/Sasa/BIG Pharmacy/Cold Storage/Mustafa Centre to `llm-extraction-rules.md` §4's SG list |
| 2026-07-16 | Brand_dict data quality | `Care`, `Deep`, `All`, `D'ARK` brand_ids are PRODUCT_NAME_SCAN artifacts on common English words, not real brands | Excluded from Pass 1 taxonomy build; flagged as a `brand_dict` cleanup item, out of scope for this session |

---

## Scripts

No dedicated pipeline scripts for this category yet — this session performs extraction directly
(own multimodal reading + `bq query` DML), per `docs/headless-runbook.md`'s Full Rebuild scenario.

---

## Map Row Counts (as of session start, before this run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Not yet extracted |
| HUMAN | 5,617 | Automated keyword-seed rows (see above) |
| NULL (unmapped) | ~66,777 (72,394 distinct products in 2026-05 minus rows with any HUMAN mapping — approximate, HUMAN rows aren't necessarily 1:1 with 2026-05 products) | |
