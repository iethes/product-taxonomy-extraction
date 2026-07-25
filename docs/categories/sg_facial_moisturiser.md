# shopee_sg_facial_moisturiser — Category Context

> Master table name is `shopee_sg_facial_moisturiser` (the `shopee_{country}_{category}` convention
> used everywhere else in this pipeline — the shorthand `sg_facial_moisturiser` used in STATUS.md and
> task prompts is not the literal table name, same naming gap already documented in
> `docs/categories/sg_facial_cleanser.md`).

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ Partial — 188 taxonomy entries, 25 brands (top-25-by-allowlist-GMV, ~93% of allowlist GMV within those brands), text-first + spot vision-verification. 233 of 258 in-scope brands not yet covered — see Remaining Work. |
| LLM Pass 2 | ⏳ Partial — bulk SQL text-match (product_line/sub_line substring + pack-count signal check) against the 188 Pass 1 entries, scoped to the same 25 brands. 1,885 products routed, 15 ambiguous matches deliberately skipped. |
| GMV Coverage (new LLM this session) | 38.8% of total category GMV (2026-05-01) newly mapped by LLM: 2,073 products, $1,818,622 SGD of $4,689,432 SGD total. Additive to whatever pre-existing HUMAN keyword-seed already covered — not independently re-measured this session. |
| Last run | 2026-07-16 |
| Current MAX taxonomy_id (at session start) | SKU-072536 (STATUS.md's SKU-058455 is stale — confirmed live via `sku_block_registry` and `product_taxonomy`, per `CLAUDE.md`'s own warning not to trust the static file) |

---

## Important: this master_table spans 7 magpie categories, not just "moisturiser"

`niq_category_mapping` shows `shopee_sg_facial_moisturiser` maps to **seven** distinct
`magpie_category_3` buckets, all under Beauty & Personal Care:

| NIQ category_3 (raw) | magpie_category_3 | Products (2026-06 latest month) | GMV (2026-06) |
|---|---|---|---|
| Facial Moisturizer | Face Moisturizer | 40,449 | 2,536,284 |
| Face Mask & Packs | Face Mask | 30,644 | 2,228,002 |
| Toner | Toner | 15,855 | 1,291,026 |
| Facial Mist | Facial Mist | 2,982 | 290,091 |
| Skincare (Men's Care, category_4 blank) | Men's Face Cleanser | 6,692 | 59,002 |
| Skincare (Men's Care, category_4="Moisturizer & Treatment") | Men's Moisturizer | included above | included above |
| Skincare (Men's Care, category_4="Facial Cleanser") | Men's Face Cleanser | included above | included above |

Like `shopee_sg_facial_cleanser` (and unlike `shopee_th_body_wash`), **all buckets here are
legitimate skincare** — there is no keyword-exclusion gate needed. Face masks, toners, and facial
mists are routinely sold and extracted alongside moisturizers proper; taxonomy and mapping for this
table covers all seven buckets. Universe refresh (not run this session) must use the NIQ join
pattern, and per `docs/headless-runbook.md` the real refresh target is the
`universe_taxonomy_overlay` MERGE against `marketshare_universe_niq`, not `magpie.marketshare_universe`
(`CLAUDE.md` is stale on this point).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-074001–076000 | Full Rebuild (Pass 1 + Pass 2), claimed 2026-07-16, scenario=full_rebuild. **188 used** (SKU-074001–074188), ~1,812 slots unused for a follow-up session. |

---

## Brand Scope (GMV threshold 95%, review month 2026-05-01, GWP zeroed, category-relevant products only)

**258 brands** in the true 95% cumulative-GMV threshold (ranking all brands by GWP-zeroed
product-level GMV descending, running cumulative sum — not a fixed top-N snapshot; matches the
method already validated in `docs/categories/sg_facial_cleanser.md`). `BRD-UNDEFINED` (unresolved
brand, 31.09% of category GMV cumulative position, rank 8, 20,471 products) is excluded from this
brand list since it cannot have an official store or a real product line — Pass 2 / NULL-coverage
passes may still resolve individual high-GMV BRD-UNDEFINED products via text/image brand
identification, but it isn't a "brand" for allowlist purposes. Review month chosen to match the
sibling `sg_facial_cleanser` session (2026-05-01) rather than the newer 2026-06-01, which is
available in the source data but untested for completeness in this pipeline.

Full list, ranked by GWP-zeroed GMV (SGD), with cumulative % of total category GMV:

| Rank | Brand | brand_id | GMV (SGD) | Cumulative % |
|---|---|---|---|---|
| 1 | Torriden | `BRD-GLOBAL-00011` | 343,778 | 7.33% |
| 2 | medicube | `BRD-GLOBAL-00299` | 280,618 | 13.31% |
| 3 | Mediheal | `BRD-GLOBAL-00361` | 177,516 | 17.1% |
| 4 | Biodance | `BRD-GLOBAL-00723` | 154,985 | 20.41% |
| 5 | Dr. Althea | `BRD-GLOBAL-00071` | 129,869 | 23.17% |
| 6 | Skintific | `BRD-GLOBAL-00026` | 129,820 | 25.94% |
| 7 | Skin1004 | `BRD-GLOBAL-00108` | 125,330 | 28.62% |
| 8 | Dr.Reju-All | `BRD-SG-00770` | 105,671 | 33.34% |
| 9 | Rejuran | `BRD-GLOBAL-00335` | 103,775 | 35.56% |
| 10 | Laneige | `BRD-GLOBAL-00128` | 103,670 | 37.77% |
| 11 | Aestura | `BRD-GLOBAL-00235` | 101,633 | 39.93% |
| 12 | Cosrx | `BRD-GLOBAL-00109` | 100,793 | 42.08% |
| 13 | La Roche-Posay | `BRD-GLOBAL-00002` | 94,362 | 44.1% |
| 14 | CENTELLIAN 24 | `BRD-GLOBAL-00982` | 82,012 | 45.84% |
| 15 | The Ordinary | `BRD-SG-00010` | 71,006 | 47.36% |
| 16 | Innisfree | `BRD-GLOBAL-00070` | 67,430 | 48.8% |
| 17 | Kiehl's | `BRD-GLOBAL-00084` | 63,140 | 50.14% |
| 18 | ROUND LAB | `BRD-GLOBAL-00218` | 62,757 | 51.48% |
| 19 | Cerave | `BRD-GLOBAL-00006` | 61,207 | 52.79% |
| 20 | Lassie Manna | `BRD-SG-00160` | 60,540 | 54.08% |
| 21 | SOME BY MI | `BRD-GLOBAL-00605` | 52,525 | 55.2% |
| 22 | VT COSMETICS | `BRD-GLOBAL-00406` | 48,033 | 56.22% |
| 23 | SK-II | `BRD-GLOBAL-00215` | 42,376 | 57.13% |
| 24 | Klairs | `BRD-GLOBAL-01278` | 40,985 | 58.0% |
| 25 | Skinfood | `BRD-GLOBAL-00657` | 38,305 | 58.82% |
| 26 | Sulwhasoo | `BRD-GLOBAL-00122` | 36,081 | 59.59% |
| 27 | Paula's Choice | `BRD-GLOBAL-00251` | 34,664 | 60.32% |
| 28 | Alluora | `BRD-SG-00567` | 34,204 | 61.05% |
| 29 | Eau Thermale Avène | `BRD-SG-01081` | 33,586 | 61.77% |
| 30 | Pyunkang Yul | `BRD-GLOBAL-01252` | 33,178 | 62.48% |
| 31 | Bio Essence | `BRD-GLOBAL-00754` | 32,185 | 63.16% |
| 32 | Shiseido | `BRD-GLOBAL-00072` | 32,007 | 63.85% |
| 33 | dermalogica | `BRD-GLOBAL-00408` | 31,747 | 64.52% |
| 34 | Anua | `BRD-GLOBAL-00259` | 30,841 | 65.18% |
| 35 | Cetaphil | `BRD-GLOBAL-00069` | 29,992 | 65.82% |
| 36 | numbuzin | `BRD-GLOBAL-00200` | 28,990 | 66.44% |
| 37 | PURITO | `BRD-GLOBAL-01040` | 28,372 | 67.04% |
| 38 | Ceradan | `BRD-SG-00860` | 27,707 | 67.63% |
| 39 | Isntree | `BRD-GLOBAL-00308` | 27,620 | 68.22% |
| 40 | The Face Shop | `BRD-GLOBAL-00275` | 27,500 | 68.81% |
| 41 | TRUU | `BRD-SG-00875` | 27,081 | 69.39% |
| 42 | GLAD2GLOW | `BRD-GLOBAL-03244` | 26,584 | 69.95% |
| 43 | Beauty of Joseon | `BRD-GLOBAL-00136` | 24,845 | 70.48% |
| 44 | Clinique | `BRD-GLOBAL-00171` | 23,003 | 70.98% |
| 45 | JUNGSAEMMOOL | `BRD-SG-01684` | 22,629 | 71.46% |
| 46 | olay | `BRD-GLOBAL-00075` | 22,485 | 71.94% |
| 47 | Dr.Jart | `BRD-GLOBAL-00611` | 22,357 | 72.41% |
| 48 | d'Alba | `BRD-GLOBAL-00013` | 20,429 | 72.85% |
| 49 | Abib | `BRD-GLOBAL-00325` | 19,622 | 73.27% |
| 50 | Kose | `BRD-GLOBAL-00014` | 18,162 | 73.66% |
| 51 | QV | `BRD-SG-00660` | 18,015 | 74.04% |
| 52 | Hada Labo | `BRD-GLOBAL-00055` | 17,228 | 74.41% |
| 53 | beplain | `BRD-GLOBAL-00353` | 17,207 | 74.77% |
| 54 | EQQUALBERRY | `BRD-SG-00788` | 16,926 | 75.13% |
| 55 | Neutrogena | `BRD-GLOBAL-00080` | 16,707 | 75.49% |
| 56 | Jorubi | `BRD-SG-01905` | 16,190 | 75.84% |
| 57 | L'Oreal Paris | `BRD-SG-00815` | 15,943 | 76.18% |
| 58 | P.Calm | `BRD-GLOBAL-00903` | 15,359 | 76.5% |
| 59 | HEXKIN | `BRD-GLOBAL-01827` | 15,056 | 76.82% |
| 60 | Tirtir | `BRD-GLOBAL-00212` | 14,212 | 77.13% |
| 61 | Bioderma | `BRD-GLOBAL-00062` | 13,947 | 77.43% |
| 62 | Eucerin | `BRD-GLOBAL-00003` | 13,324 | 77.71% |
| 63 | Dr.G | `BRD-GLOBAL-00053` | 13,278 | 77.99% |
| 64 | I'm from | `BRD-GLOBAL-01497` | 13,050 | 78.27% |
| 65 | Illiyoon | `BRD-GLOBAL-00796` | 13,017 | 78.55% |
| 66 | The Lab By Blanc Doux | `BRD-GLOBAL-01755` | 12,797 | 78.82% |
| 67 | Physiogel | `BRD-GLOBAL-00124` | 12,426 | 79.09% |
| 68 | IEM | `BRD-SG-00435` | 12,299 | 79.35% |
| 69 | MENOKIN | `BRD-SG-01591` | 12,014 | 79.6% |
| 70 | Lancôme | `BRD-GLOBAL-00116` | 11,770 | 79.86% |
| 71 | AweMed | `BRD-SG-01980` | 11,339 | 80.1% |
| 72 | Curel | `BRD-GLOBAL-00199` | 11,277 | 80.34% |
| 73 | OZIO | `BRD-SG-01796` | 10,917 | 80.57% |
| 74 | Celimax | `BRD-GLOBAL-00764` | 10,713 | 80.8% |
| 75 | Zeroid | `BRD-GLOBAL-00498` | 10,386 | 81.02% |
| 76 | Helena Rubinstein | `BRD-GLOBAL-01675` | 9,995 | 81.23% |
| 77 | LuLuLun | `BRD-SG-02226` | 9,770 | 81.44% |
| 78 | ICM Pharma | `BRD-SG-00833` | 9,401 | 81.64% |
| 79 | Whoopzie | `BRD-SG-01885` | 9,322 | 81.84% |
| 80 | lamer | `BRD-SG-02352` | 9,143 | 82.04% |
| 81 | TDF | `BRD-SG-01956` | 8,981 | 82.23% |
| 82 | Estee Lauder | `BRD-GLOBAL-00139` | 8,927 | 82.42% |
| 83 | DR.WU | `BRD-SG-01654` | 8,816 | 82.61% |
| 84 | Clarins | `BRD-GLOBAL-00242` | 8,662 | 82.79% |
| 85 | FAN BEAUTY DIARY | `BRD-SG-02573` | 8,367 | 82.97% |
| 86 | Avarelle | `BRD-SG-01543` | 8,340 | 83.15% |
| 87 | Aprilskin | `BRD-GLOBAL-01300` | 8,217 | 83.32% |
| 88 | ARENCIA | `BRD-GLOBAL-00464` | 7,855 | 83.49% |
| 89 | PROYA | `BRD-SG-02389` | 7,644 | 83.65% |
| 90 | belif | `BRD-GLOBAL-01350` | 7,604 | 83.82% |
| 91 | YUN | `BRD-SG-02248` | 7,440 | 83.97% |
| 92 | La Mer | `BRD-GLOBAL-00291` | 7,409 | 84.13% |
| 93 | Skinceuticals | `BRD-GLOBAL-00647` | 7,190 | 84.29% |
| 94 | CRYSTAL TOMATO | `BRD-SG-02552` | 7,064 | 84.44% |
| 95 | Meditherapy | `BRD-GLOBAL-01408` | 6,496 | 84.57% |
| 96 | Garnier | `BRD-GLOBAL-00046` | 6,410 | 84.71% |
| 97 | Aqualabel | `BRD-GLOBAL-00677` | 5,984 | 84.84% |
| 98 | Uriage | `BRD-GLOBAL-01644` | 5,836 | 84.96% |
| 99 | Seyoul | `BRD-GLOBAL-00248` | 5,831 | 85.09% |
| 100 | PDRN | `BRD-SG-12179` | 5,781 | 85.21% |
| 101 | Suntory | `BRD-GLOBAL-01032` | 5,581 | 85.33% |
| 102 | Care * | `BRD-GLOBAL-00623` | 5,579 | 85.45% |
| 103 | Clé de peau beaute | `BRD-GLOBAL-00482` | 5,513 | 85.57% |
| 104 | Lydimoon | `BRD-SG-00884` | 5,470 | 85.68% |
| 105 | Suu Balm | `BRD-SG-00424` | 5,330 | 85.8% |
| 106 | blanc dubu | `BRD-SG-01474` | 5,180 | 85.91% |
| 107 | DPPR | `BRD-SG-02311` | 5,173 | 86.02% |
| 108 | Neostrata | `BRD-GLOBAL-01866` | 5,124 | 86.13% |
| 109 | MKUP | `BRD-GLOBAL-02108` | 5,073 | 86.23% |
| 110 | make p:rem | `BRD-GLOBAL-01563` | 4,877 | 86.34% |
| 111 | MIRAE | `BRD-SG-02768` | 4,824 | 86.44% |
| 112 | incellderm | `BRD-GLOBAL-01889` | 4,816 | 86.54% |
| 113 | FANCL | `BRD-GLOBAL-00856` | 4,785 | 86.65% |
| 114 | LUMI | `BRD-SG-02345` | 4,769 | 86.75% |
| 115 | VEMONTES | `BRD-SG-02406` | 4,716 | 86.85% |
| 116 | Dr.Melaxin | `BRD-GLOBAL-00962` | 4,693 | 86.95% |
| 117 | Nature Republic | `BRD-GLOBAL-01010` | 4,623 | 87.05% |
| 118 | JMsolution | `BRD-GLOBAL-02044` | 4,609 | 87.15% |
| 119 | saborino | `BRD-SG-09013` | 4,561 | 87.24% |
| 120 | Derma Lab | `BRD-GLOBAL-01449` | 4,442 | 87.34% |
| 121 | Etude House | `BRD-GLOBAL-00364` | 4,410 | 87.43% |
| 122 | Beyond | `BRD-GLOBAL-00208` | 4,401 | 87.53% |
| 123 | Obagi | `BRD-GLOBAL-01751` | 4,394 | 87.62% |
| 124 | Minimalist | `BRD-SG-01967` | 4,336 | 87.71% |
| 125 | Fast * | `BRD-SG-04063` | 4,232 | 87.8% |
| 126 | Deep * | `BRD-SG-12678` | 4,205 | 87.89% |
| 127 | AHC | `BRD-GLOBAL-01047` | 4,152 | 87.98% |
| 128 | Quality 1st | `BRD-SG-02636` | 4,113 | 88.07% |
| 129 | komfymed | `BRD-SG-02748` | 4,023 | 88.15% |
| 130 | fully | `BRD-GLOBAL-02097` | 3,993 | 88.24% |
| 131 | Aveeno | `BRD-GLOBAL-00265` | 3,991 | 88.32% |
| 132 | Thayers | `BRD-SG-01310` | 3,985 | 88.41% |
| 133 | Atomy | `BRD-GLOBAL-00813` | 3,938 | 88.49% |
| 134 | Lab Series | `BRD-GLOBAL-00882` | 3,930 | 88.58% |
| 135 | sukin | `BRD-SG-00948` | 3,912 | 88.66% |
| 136 | monday museum | `BRD-SG-02132` | 3,870 | 88.74% |
| 137 | Elixir | `BRD-GLOBAL-00106` | 3,835 | 88.82% |
| 138 | Tower 28 | `BRD-GLOBAL-01792` | 3,817 | 88.91% |
| 139 | Barrier Repair | `BRD-SG-07838` | 3,805 | 88.99% |
| 140 | Mamonde | `BRD-GLOBAL-01911` | 3,769 | 89.07% |
| 141 | Medi Plus | `BRD-GLOBAL-02274` | 3,763 | 89.15% |
| 142 | OGANACELL | `BRD-SG-02065` | 3,696 | 89.23% |
| 143 | Blanc Nature | `BRD-GLOBAL-00337` | 3,685 | 89.3% |
| 144 | FRANKLY | `BRD-GLOBAL-01773` | 3,637 | 89.38% |
| 145 | mixsoon | `BRD-GLOBAL-00890` | 3,613 | 89.46% |
| 146 | Simple | `BRD-GLOBAL-01190` | 3,597 | 89.54% |
| 147 | 1.618 | `BRD-SG-06260` | 3,591 | 89.61% |
| 148 | Genabelle | `BRD-GLOBAL-01806` | 3,584 | 89.69% |
| 149 | Alteya Organics | `BRD-GLOBAL-01709` | 3,565 | 89.77% |
| 150 | Sadoer | `BRD-GLOBAL-00488` | 3,546 | 89.84% |
| 151 | MEDI-PEEL | `BRD-GLOBAL-00727` | 3,493 | 89.92% |
| 152 | Snake Brand | `BRD-GLOBAL-00433` | 3,492 | 89.99% |
| 153 | Ishizawa Lab | `BRD-GLOBAL-02280` | 3,446 | 90.06% |
| 154 | Parnell | `BRD-GLOBAL-01380` | 3,431 | 90.14% |
| 155 | TONYMOLY | `BRD-GLOBAL-01733` | 3,419 | 90.21% |
| 156 | IUNIK | `BRD-GLOBAL-01316` | 3,415 | 90.28% |
| 157 | Himalaya | `BRD-GLOBAL-00470` | 3,345 | 90.35% |
| 158 | murad | `BRD-GLOBAL-00981` | 3,337 | 90.42% |
| 159 | IN * | `BRD-SG-06662` | 3,302 | 90.49% |
| 160 | SNATURE | `BRD-GLOBAL-01881` | 3,222 | 90.56% |
| 161 | Dermafirm | `BRD-GLOBAL-01439` | 3,204 | 90.63% |
| 162 | Niks | `BRD-SG-02218` | 3,195 | 90.7% |
| 163 | PURITO SEOUL | `BRD-GLOBAL-00376` | 3,171 | 90.77% |
| 164 | The History Of Whoo | `BRD-GLOBAL-00988` | 3,159 | 90.84% |
| 165 | Needly | `BRD-GLOBAL-00849` | 3,156 | 90.9% |
| 166 | ฺBiotherm | `BRD-GLOBAL-00625` | 3,143 | 90.97% |
| 167 | BIOHEAL BOH | `BRD-GLOBAL-01587` | 3,128 | 91.04% |
| 168 | Avene | `BRD-GLOBAL-00530` | 3,100 | 91.1% |
| 169 | Kose Cosmeport | `BRD-SG-02378` | 3,048 | 91.17% |
| 170 | Rejuall | `BRD-SG-00822` | 3,043 | 91.23% |
| 171 | AROCELL | `BRD-GLOBAL-02211` | 3,025 | 91.3% |
| 172 | Calecim Professional | `BRD-SG-01587` | 2,967 | 91.36% |
| 173 | Axis-y | `BRD-GLOBAL-00388` | 2,964 | 91.42% |
| 174 | Elizabeth Arden | `BRD-GLOBAL-01349` | 2,963 | 91.49% |
| 175 | All * | `BRD-SG-06567` | 2,962 | 91.55% |
| 176 | evian | `BRD-GLOBAL-00239` | 2,917 | 91.61% |
| 177 | Wellage | `BRD-GLOBAL-01214` | 2,899 | 91.67% |
| 178 | One day's you | `BRD-GLOBAL-02086` | 2,813 | 91.73% |
| 179 | HaruHaru Wonder | `BRD-GLOBAL-00415` | 2,788 | 91.79% |
| 180 | Heveblue | `BRD-GLOBAL-02033` | 2,775 | 91.85% |
| 181 | The Body Shop | `BRD-GLOBAL-01534` | 2,775 | 91.91% |
| 182 | Guboncho | `BRD-GLOBAL-01736` | 2,745 | 91.97% |
| 183 | Butterfly Apothecary | `BRD-SG-03535` | 2,528 | 92.02% |
| 184 | Furano | `BRD-TH-00826` | 2,518 | 92.08% |
| 185 | D'ARK * | `BRD-SG-12623` | 2,502 | 92.13% |
| 186 | goodal | `BRD-GLOBAL-01730` | 2,496 | 92.18% |
| 187 | Hipapa | `BRD-GLOBAL-01023` | 2,463 | 92.24% |
| 188 | Badskin | `BRD-GLOBAL-00840` | 2,442 | 92.29% |
| 189 | ilso | `BRD-GLOBAL-02116` | 2,422 | 92.34% |
| 190 | Marshique | `BRD-GLOBAL-02352` | 2,408 | 92.39% |
| 191 | MENARD | `BRD-SG-04355` | 2,405 | 92.44% |
| 192 | Chuck's | `BRD-SG-03622` | 2,404 | 92.49% |
| 193 | AweMed Series | `BRD-SG-05002` | 2,384 | 92.54% |
| 194 | Nivea | `BRD-GLOBAL-00023` | 2,372 | 92.6% |
| 195 | the therapy | `BRD-SG-03351` | 2,354 | 92.65% |
| 196 | Caudalie | `BRD-GLOBAL-00975` | 2,340 | 92.7% |
| 197 | By Wishtrend | `BRD-GLOBAL-02265` | 2,327 | 92.75% |
| 198 | REJUVEON | `BRD-SG-03289` | 2,318 | 92.79% |
| 199 | Purcell | `BRD-SG-03688` | 2,290 | 92.84% |
| 200 | Kelly Oriental | `BRD-SG-03705` | 2,287 | 92.89% |
| 201 | Sooryehan | `BRD-GLOBAL-02003` | 2,229 | 92.94% |
| 202 | Bioaqua | `BRD-GLOBAL-01482` | 2,210 | 92.99% |
| 203 | Benton | `BRD-GLOBAL-02315` | 2,187 | 93.03% |
| 204 | Yukinoue | `BRD-SG-03609` | 2,156 | 93.08% |
| 205 | Legacy | `BRD-GLOBAL-00452` | 2,154 | 93.13% |
| 206 | Cell Fusion C | `BRD-GLOBAL-01582` | 2,046 | 93.17% |
| 207 | Origins | `BRD-GLOBAL-00616` | 2,032 | 93.21% |
| 208 | embryolisse | `BRD-GLOBAL-00765` | 2,004 | 93.26% |
| 209 | MIZON | `BRD-GLOBAL-02249` | 1,973 | 93.3% |
| 210 | IOPE | `BRD-GLOBAL-01757` | 1,965 | 93.34% |
| 211 | hanmi | `BRD-GLOBAL-01564` | 1,910 | 93.38% |
| 212 | Chando | `BRD-TH-03255` | 1,886 | 93.42% |
| 213 | Luvum | `BRD-SG-03145` | 1,817 | 93.46% |
| 214 | ma:nyo | `BRD-GLOBAL-00370` | 1,798 | 93.5% |
| 215 | CNP LABORATORY | `BRD-GLOBAL-01501` | 1,795 | 93.54% |
| 216 | SEKKISEI | `BRD-SG-03247` | 1,771 | 93.57% |
| 217 | SAMU | `BRD-SG-11941` | 1,767 | 93.61% |
| 218 | Papa Recipe | `BRD-GLOBAL-00637` | 1,752 | 93.65% |
| 219 | Florasis | `BRD-GLOBAL-01540` | 1,737 | 93.69% |
| 220 | Missha | `BRD-GLOBAL-01223` | 1,725 | 93.72% |
| 221 | My Beauty Diary | `BRD-SG-03780` | 1,714 | 93.76% |
| 222 | D Program | `BRD-GLOBAL-00534` | 1,707 | 93.8% |
| 223 | Neogence | `BRD-GLOBAL-02154` | 1,692 | 93.83% |
| 224 | Babor | `BRD-SG-02269` | 1,689 | 93.87% |
| 225 | KOPHER | `BRD-SG-00270` | 1,671 | 93.9% |
| 226 | Orien | `BRD-SG-03077` | 1,667 | 93.94% |
| 227 | ATORREGE AD+ | `BRD-SG-02650` | 1,660 | 93.97% |
| 228 | est.lab | `BRD-SG-02649` | 1,654 | 94.01% |
| 229 | DERMATORY | `BRD-SG-03182` | 1,652 | 94.04% |
| 230 | Suisse Programme | `BRD-GLOBAL-01943` | 1,632 | 94.08% |
| 231 | Auolive | `BRD-SG-03813` | 1,626 | 94.11% |
| 232 | Lepique | `BRD-SG-02500` | 1,622 | 94.15% |
| 233 | ApexFlow | `BRD-SG-03448` | 1,612 | 94.18% |
| 234 | DR.Belmeur | `BRD-SG-02791` | 1,592 | 94.22% |
| 235 | Charming Skin | `BRD-GLOBAL-01141` | 1,590 | 94.25% |
| 236 | It's Skin | `BRD-GLOBAL-00612` | 1,569 | 94.28% |
| 237 | Kahi | `BRD-GLOBAL-02348` | 1,567 | 94.32% |
| 238 | Skinlycious | `BRD-SG-01578` | 1,566 | 94.35% |
| 239 | Snowflake Skin | `BRD-SG-03426` | 1,551 | 94.38% |
| 240 | PIEN TZE HUANG | `BRD-SG-12207` | 1,546 | 94.42% |
| 241 | Pretty Skin | `BRD-GLOBAL-02214` | 1,540 | 94.45% |
| 242 | S-ERUM | `BRD-GLOBAL-02143` | 1,536 | 94.48% |
| 243 | PCA Skin | `BRD-GLOBAL-02410` | 1,535 | 94.52% |
| 244 | Dr Morita | `BRD-SG-03990` | 1,520 | 94.55% |
| 245 | Men+ | `BRD-SG-09828` | 1,515 | 94.58% |
| 246 | Noreva | `BRD-SG-03086` | 1,510 | 94.61% |
| 247 | Horse Oil | `BRD-SG-05969` | 1,496 | 94.64% |
| 248 | Keana Nadeshiko | `BRD-GLOBAL-01954` | 1,477 | 94.68% |
| 249 | TOSOWOONG | `BRD-SG-04181` | 1,464 | 94.71% |
| 250 | HISTOLAB | `BRD-SG-03100` | 1,453 | 94.74% |
| 251 | Pinnara | `BRD-GLOBAL-00290` | 1,442 | 94.77% |
| 252 | Atopalm | `BRD-GLOBAL-00253` | 1,442 | 94.8% |
| 253 | Zo Skin Health | `BRD-GLOBAL-02212` | 1,424 | 94.83% |
| 254 | Guinot | `BRD-SG-03919` | 1,416 | 94.86% |
| 255 | LEFILLEO | `BRD-SG-04862` | 1,394 | 94.89% |
| 256 | pdc | `BRD-GLOBAL-02537` | 1,394 | 94.92% |
| 257 | blanc doux | `BRD-SG-02975` | 1,356 | 94.95% |
| 258 | DASHU | `BRD-GLOBAL-01395` | 1,351 | 94.98% |

**\* Data-quality flag — likely not real brands.** `Care`, `All`, `Deep`, `Fast`, `IN`, `D'ARK`
show up as `brand_id` in `brand_dict` and are almost certainly `PRODUCT_NAME_SCAN` mismatches on
common English words (e.g. matching "Care" inside "Skin Care" sku_names) — the exact same artifacts
already flagged in `sg_facial_cleanser.md`'s Brand Scope footnote, confirmed independently in this
category by spot-checking their "official stores": dozens of 1–4-product listings from stores like
`kozeey`, `Leipupa`, `Baosity` map their sole product to `Care`/`Deep`/`D'ARK`. **Excluded from the
Pass 1 allowlist** — a `brand_dict` cleanup issue out of scope for this session, not a taxonomy
problem to solve here. Their GMV stays in the 95% denominator (it's real category GMV), but no
taxonomy entries are built under these brand_ids.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'`, joined to the 258
in-scope brand_ids (2026-05-01 snapshot), then keeping only stores where **exactly one** in-scope
brand appears (clean single-brand stores), plus a short manually-confirmed list of legitimate
parent-company multi-brand stores.

**Multi-brand retailers found and excluded** (Mall-badged but not brand-principal — carry 3+
distinct in-scope brands each, confirmed resellers/marketplaces, not manufacturer stores):

- `Watsons Singapore Official Store` (87 brands, 677 products) — e.g. AHC,ATORREGE AD+,Abib,Aveeno,Avene
- `Sasa Official Store` (65 brands, 498 products) — e.g. AHC,Abib,Aestura,Alteya Organics,Anua
- `Guardian SG Official Store` (74 brands, 431 products) — e.g. ARENCIA,ATORREGE AD+,Abib,Anua,Aveeno
- `Nana Mall Official Store` (46 brands, 399 products) — e.g. AHC,Abib,CNP LABORATORY,Calecim Professional,Caudalie
- `Strawberrynet SG Official Store` (41 brands, 289 products) — e.g. ARENCIA,All,Avene,Axis-y,Babor
- `Younfamily` (39 brands, 272 products) — e.g. AHC,Abib,Aestura,Anua,Beauty of Joseon
- `BEAUTY U & ME.SG Official Store` (41 brands, 222 products) — e.g. AHC,Abib,Avene,BIOHEAL BOH,Bioderma
- `Beautyhaus SG` (56 brands, 220 products) — e.g. AHC,Abib,Anua,Avene,Beauty of Joseon
- `cosblah` (40 brands, 178 products) — e.g. Abib,Aestura,Anua,Atopalm,Axis-y
- `YAOCOS.kr` (39 brands, 167 products) — e.g. AHC,AROCELL,Abib,Aestura,Anua
- `HEY SUP` (35 brands, 140 products) — e.g. AHC,Aqualabel,Cerave,Cetaphil,Clarins
- `Pestlo.SG` (30 brands, 134 products) — e.g. ARENCIA,AROCELL,Abib,Anua,Axis-y
- `BB Beauty Global Official Store` (32 brands, 93 products) — e.g. AHC,CNP LABORATORY,Clarins,Clinique,Clé de peau beaute
- `THEFACESHOP Official Store` (7 brands, 69 products) — e.g. Beyond,CNP LABORATORY,DR.Belmeur,Sooryehan,The Face Shop
- `Klairs & I'm from Official Store_SG` (3 brands, 62 products) — e.g. By Wishtrend,I'm from,Klairs
- `Cosmede Official Store` (14 brands, 60 products) — e.g. All,Bioderma,Clarins,Clinique,Elizabeth Arden
- `BIG Pharmacy` (16 brands, 57 products) — e.g. Avene,Barrier Repair,Bio Essence,Ceradan,Cerave
- `hermo Official Flagship Store` (7 brands, 57 products) — e.g. Cosrx,Dr. Althea,PURITO,SOME BY MI,Skinfood
- `BRIDGE DRUG Official` (8 brands, 50 products) — e.g. Care,Cerave,Cetaphil,Eau Thermale Avène,La Roche-Posay
- `The Beauty Curated Co.` (15 brands, 42 products) — e.g. Benton,CENTELLIAN 24,Dr. Althea,Heveblue,Isntree
- `Beauty Morning Makeup Boutique` (6 brands, 42 products) — e.g. All,Anua,Care,D'ARK,Deep
- `Supple Beauty` (3 brands, 41 products) — e.g. Cerave,La Roche-Posay,Skinceuticals
- `Ksisters Official Store ` (8 brands, 40 products) — e.g. Anua,Care,Celimax,Dr. Althea,Genabelle
- `Cold Storage Official Store` (6 brands, 35 products) — e.g. Beyond,Care,Cetaphil,Mediheal,The Face Shop
- `Beauty Hub SG` (9 brands, 32 products) — e.g. ARENCIA,Celimax,Dr. Althea,HaruHaru Wonder,KOPHER
- `Farmasi C S` (9 brands, 31 products) — e.g. All,Barrier Repair,Bioderma,Ceradan,Cetaphil
- `myCK_online` (12 brands, 29 products) — e.g. Bio Essence,Cetaphil,Eau Thermale Avène,Hada Labo,L'Oreal Paris
- `Xiaoling  Boutique Store` (4 brands, 24 products) — e.g. All,Anua,Care,SOME BY MI
- `Tsupply Official Store` (4 brands, 22 products) — e.g. Abib,Ishizawa Lab,Keana Nadeshiko,Kose Cosmeport
- `Beauty Duck Official ` (4 brands, 15 products) — e.g. Abib,Mediheal,Torriden,VT COSMETICS
- `J-Mart Official` (7 brands, 14 products) — e.g. All,Care,Hada Labo,Kose,MEDI-PEEL
- `GadgetLion` (3 brands, 13 products) — e.g. Care,D'ARK,La Roche-Posay
- `L.L  Office Beauty` (3 brands, 13 products) — e.g. Care,D'ARK,Deep
- `Sasa Singapore` (6 brands, 11 products) — e.g. Alteya Organics,Cell Fusion C,Lancôme,SK-II,Suisse Programme
- `EZMORE Official` (5 brands, 9 products) — e.g. MEDI-PEEL,Meditherapy,Rejuran,Torriden,VT COSMETICS
- `Nanyang Curio Vault` (4 brands, 9 products) — e.g. Biodance,Care,D'ARK,Deep
- `slxcp02.sg` (4 brands, 8 products) — e.g. Barrier Repair,Care,Deep,Men+
- `Miin You Singapore Official Store` (3 brands, 8 products) — e.g. Anua,Celimax,I'm from
- `htcjh01.sg` (3 brands, 7 products) — e.g. D'ARK,Deep,Men+
- `eslite 誠品 Flagship Bookstore` (6 brands, 6 products) — e.g. Clarins,Elizabeth Arden,La Mer,MEDI-PEEL,Origins
- `Devoko Vase` (4 brands, 6 products) — e.g. All,Care,Fast,Men+
- `Eigell-Sports&Outdoors` (3 brands, 6 products) — e.g. All,Care,Fast
- `WoW beautiful.SG` (5 brands, 5 products) — e.g. Avene,Biodance,Care,Isntree,PDRN
- `Ren Ren Pharmacy Official` (3 brands, 5 products) — e.g. Horse Oil,Nivea,Physiogel
- `mbmofficial` (3 brands, 5 products) — e.g. By Wishtrend,I'm from,Klairs
- `Bvdfgk` (3 brands, 5 products) — e.g. All,Fast,Men+
- `chulisia` (3 brands, 5 products) — e.g. All,Care,Men+
- `Wazsnhm` (3 brands, 5 products) — e.g. All,Fast,Men+
- `XXIAOSG3.sg` (4 brands, 4 products) — e.g. Anua,Biodance,Care,Deep
- `白富媚 Buyforme Cosmetics Official` (3 brands, 4 products) — e.g. Eau Thermale Avène,MEDI-PEEL,evian
- `deevoka` (3 brands, 4 products) — e.g. All,Care,Deep
- `wangruipeng01.sg` (3 brands, 3 products) — e.g. Care,Men+,dermalogica
- `Lemonague夏派柠盟（x1）` (3 brands, 3 products) — e.g. Biodance,FAN BEAUTY DIARY,IN

Several of these (Watsons, Guardian, Sasa, BIG Pharmacy, Cold Storage) were already flagged as
SG multi-brand retailers in `sg_facial_cleanser.md` — confirms the pattern is category-independent.
**Recommendation carried over from that session:** add Guardian, Sasa, BIG Pharmacy, Cold Storage,
and Mustafa-style pharmacy/mall stores to `llm-extraction-rules.md` §4's exclusion list explicitly
(they aren't there yet — no SG category had been LLM-extracted before `sg_shampoo`/`sg_facial_cleanser`).

**Confirmed legitimate parent-company multi-brand stores** (Pass-1-eligible for all brands listed):

| Merchant Name | Brands carried | Parent company |
|---|---|---|
| `belif Official Store` | belif, CNP LABORATORY | LG H&H (confirmed in `sg_facial_cleanser.md`) |
| `Babor Official Store` / `Guinot Official Store` | Babor, Guinot | Babor Group (owns Guinot) |
| `Kenvue Official Store` | Aveeno, Neutrogena | Kenvue Inc (J&J consumer-health spinoff) |
| `Kosé Official Store` | Kose, SEKKISEI | Kosé Corporation |
| `AMOREPACIFIC Official Store` | Aestura, Mamonde | Amorepacific |
| `Mentholatum Flagship Store` | ATORREGE AD+, Hada Labo | Rohto/Mentholatum Group |
| `Clubclio_Singapore` | DERMATORY, goodal | CLIO Cosmetics |
| `Superberry Official Store` | By Wishtrend, Klairs | Wishtrend/Wishcompany (Klairs is manufactured by Wishtrend) |

**Ambiguous 2-brand "official stores" not vetted** (unrelated companies bundled by what looks like a
regional distributor, not a shared parent — deferred rather than blindly trusted, per the same logic
`sg_facial_cleanser.md` applied to single-listing "Official" stores): `Bio Essence Official Store`
(Bio Essence + Derma Lab, 99 products — plausible SG-distributor pairing, unverified), `Florray
Singapore Official Store` (Mediheal + ma:nyo), `Able Curates Official Store` (LuLuLun + Quality 1st),
`Dr Wu SG Official Store` (DR.WU + beplain), `Adoraeofficial`, `Japan Beauty & Health official store`,
`NOTAG BEAUTY`, `Dr.Reju-All Official Store` (Cosrx + Dr.Reju-All), `Corlison Official Store` (QV +
evian — both real distributed brands but different manufacturers), `iQueen Official Store`, `Mandom
Official Store` (Barrier Repair + saborino — saborino is genuinely Mandom's, Barrier Repair's
relationship unconfirmed), `JP Cosme Official Store` (SK-II + Shiseido — different companies,
treated as reseller not parent store), `ToppingsKids Official Store`, `ILSO SG Official Store`,
`Prestigio Delights Official`, `Taihopai Mall`, `VividHue Co.`. None of these are on the Pass 1
allowlist this session.

**Single-brand official stores** (183 stores, 183 distinct brands, 3,365 products at 2026-05
snapshot; excludes the `Care`/`All`/`Deep`/`Fast`/`IN`/`D'ARK` noise-brand "stores" — 25 tiny
1–4-product listings removed, see Brand Scope footnote):

| Brand | brand_id | Official Store Merchant Name | Products |
|---|---|---|---|
| The Face Shop | `BRD-GLOBAL-00275` | `THEFACESHOP VIỆT NAM` | 110 |
| Innisfree | `BRD-GLOBAL-00070` | `Innisfree Official Store` | 92 |
| medicube | `BRD-GLOBAL-00299` | `Medicube Official Store` | 91 |
| Skinfood | `BRD-GLOBAL-00657` | `Skinfood Official Store` | 87 |
| Mediheal | `BRD-GLOBAL-00361` | `Mediheal Singapore Official Store` | 80 |
| VT COSMETICS | `BRD-GLOBAL-00406` | `vtcosmetics_official` | 77 |
| Himalaya | `BRD-GLOBAL-00470` | `Himalaya Official Store` | 67 |
| Cosrx | `BRD-GLOBAL-00109` | `COSRX Official Store` | 65 |
| Papa Recipe | `BRD-GLOBAL-00637` | `papa recipe SG Official Store` | 56 |
| Torriden | `BRD-GLOBAL-00011` | `SG_Torriden Official Store` | 55 |
| SOME BY MI | `BRD-GLOBAL-00605` | `SOMEBYMI SG Official Store` | 55 |
| Skin1004 | `BRD-GLOBAL-00108` | `SKIN1004 Official Store` | 53 |
| Dr.Jart | `BRD-GLOBAL-00611` | `Dr.Jart+ Official Store` | 52 |
| Laneige | `BRD-GLOBAL-00128` | `Laneige Official Store` | 51 |
| Dermafirm | `BRD-GLOBAL-01439` | `DERMAFIRM Official Store` | 48 |
| One day's you | `BRD-GLOBAL-02086` | `One-day's you Korea Official Store` | 48 |
| FAN BEAUTY DIARY | `BRD-SG-02573` | `Fan Beauty Official Store` | 46 |
| IEM | `BRD-SG-00435` | `IEM Flagship Store` | 45 |
| MIZON | `BRD-GLOBAL-02249` | `MIZON Singapore Official` | 44 |
| HISTOLAB | `BRD-SG-03100` | `HISTOLAB SG` | 42 |
| TRUU | `BRD-SG-00875` | `TRUU 童 Official Store` | 41 |
| Isntree | `BRD-GLOBAL-00308` | `ISNTREE Official` | 40 |
| It's Skin | `BRD-GLOBAL-00612` | `ITSSKIN SG OFFICIAL` | 39 |
| Neogence | `BRD-GLOBAL-02154` | `Neogence Official Store` | 38 |
| olay | `BRD-GLOBAL-00075` | `P&G Beauty Official Store` | 34 |
| Cosrx | `BRD-GLOBAL-00109` | `Confirm Trading Cos-RX Distributor` | 34 |
| Pyunkang Yul | `BRD-GLOBAL-01252` | `PyunkangYul Official Store` | 34 |
| Biodance | `BRD-GLOBAL-00723` | `Biodance Official Store` | 34 |
| Eau Thermale Avène | `BRD-SG-01081` | `Eau Thermale Avene Official Flagship Store` | 33 |
| Rejuran | `BRD-GLOBAL-00335` | `Rejuran Official Store` | 32 |
| sukin | `BRD-SG-00948` | `SukinSG Official Store` | 32 |
| ROUND LAB | `BRD-GLOBAL-00218` | `ROUNDLAB Official Store` | 32 |
| sukin | `BRD-SG-00948` | `Natural Therapeutic House ` | 30 |
| GLAD2GLOW | `BRD-GLOBAL-03244` | `Glad2Glow OFFICIAL STORE` | 30 |
| Skintific | `BRD-GLOBAL-00026` | `SKINTIFIC Official Store` | 29 |
| Cetaphil | `BRD-GLOBAL-00069` | `Cetaphil Official Store` | 29 |
| dermalogica | `BRD-GLOBAL-00408` | `Dermalogica Official Store` | 29 |
| MEDI-PEEL | `BRD-GLOBAL-00727` | `MEDIPEEL Official Store` | 29 |
| Paula's Choice | `BRD-GLOBAL-00251` | `Paula’s Choice Official Store` | 28 |
| Dr. Althea | `BRD-GLOBAL-00071` | `Dr.Althea Official Store_SG` | 28 |
| Uriage | `BRD-GLOBAL-01644` | `Uriage Official Store` | 28 |
| JUNGSAEMMOOL | `BRD-SG-01684` | `JUNGSAEMMOOL OFFICIAL SG` | 27 |
| Shiseido | `BRD-GLOBAL-00072` | `SHISEIDO Official Store` | 27 |
| beplain | `BRD-GLOBAL-00353` | `beplain` | 27 |
| numbuzin | `BRD-GLOBAL-00200` | `numbuzin Official Store` | 26 |
| EQQUALBERRY | `BRD-SG-00788` | `EQQUALBERRY_official.sg` | 26 |
| OGANACELL | `BRD-SG-02065` | `Oganacell Official Store SG` | 26 |
| Kiehl's | `BRD-GLOBAL-00084` | `Kiehl's Official Store` | 24 |
| The History Of Whoo | `BRD-GLOBAL-00988` | `The Whoo Official Store` | 24 |
| Alteya Organics | `BRD-GLOBAL-01709` | `Alteya Organics Official Store` | 23 |
| Elizabeth Arden | `BRD-GLOBAL-01349` | `Elizabeth Arden Official Store` | 23 |
| Dr.Melaxin | `BRD-GLOBAL-00962` | `Dr.Melaxin Singapore` | 23 |
| Meditherapy | `BRD-GLOBAL-01408` | `Meditherapy Korea Official Store` | 22 |
| Alluora | `BRD-SG-00567` | `Alluora` | 22 |
| Parnell | `BRD-GLOBAL-01380` | `Parnell` | 22 |
| Chando | `BRD-TH-03255` | `CHANDO Himalaya 自然堂` | 21 |
| Sulwhasoo | `BRD-GLOBAL-00122` | `Sulwhasoo Official Store` | 21 |
| komfymed | `BRD-SG-02748` | `可复美Komfymed Official Store SG` | 21 |
| beplain | `BRD-GLOBAL-00353` | `First Dibs Beauty` | 20 |
| HEXKIN | `BRD-GLOBAL-01827` | `Hexkin 赫诗琴 Official Flagship Store` | 20 |
| Aprilskin | `BRD-GLOBAL-01300` | `Aprilskin Official Store` | 20 |
| PROYA | `BRD-SG-02389` | `Proya Official Store` | 19 |
| La Roche-Posay | `BRD-GLOBAL-00002` | `La Roche Posay Official Store` | 19 |
| The Body Shop | `BRD-GLOBAL-01534` | `The Body Shop Official Store` | 19 |
| SAMU | `BRD-SG-11941` | `SAM'U Official Store SG` | 19 |
| Derma Lab | `BRD-GLOBAL-01449` | `Derma Lab Official Store` | 18 |
| murad | `BRD-GLOBAL-00981` | `Murad Official Store` | 18 |
| LUMI | `BRD-SG-02345` | `LUMI Beauty Official Store` | 18 |
| L'Oreal Paris | `BRD-SG-00815` | `L'Oreal Paris Official Store` | 18 |
| Benton | `BRD-GLOBAL-02315` | `bentoncosmetic.sg` | 17 |
| Tirtir | `BRD-GLOBAL-00212` | `TIRTIR Official Store` | 17 |
| SK-II | `BRD-GLOBAL-00215` | `SK-II Official Store` | 17 |
| Aqualabel | `BRD-GLOBAL-00677` | `SHISEIDO JAPAN Group Store` | 17 |
| CENTELLIAN 24 | `BRD-GLOBAL-00982` | `Centellian24.sg` | 17 |
| ARENCIA | `BRD-GLOBAL-00464` | `Arencia` | 17 |
| d'Alba | `BRD-GLOBAL-00013` | `d'Alba Singapore Official Store` | 16 |
| Eucerin | `BRD-GLOBAL-00003` | `EUCERIN Official Store` | 16 |
| mixsoon | `BRD-GLOBAL-00890` | `MIXSOON SG Official Store` | 16 |
| Etude House | `BRD-GLOBAL-00364` | `ETUDE Singapore` | 16 |
| Celimax | `BRD-GLOBAL-00764` | `Celimax OS Singapore` | 16 |
| QV | `BRD-SG-00660` | `QV Official Store` | 16 |
| CNP LABORATORY | `BRD-GLOBAL-01501` | `CNP Laboratory Official Store` | 15 |
| Garnier | `BRD-GLOBAL-00046` | `Garnier SG Official Store` | 15 |
| evian | `BRD-GLOBAL-00239` | `Evian Brumisateur Official Store` | 15 |
| Anua | `BRD-GLOBAL-00259` | `ANUA Official Store_SG` | 15 |
| OZIO | `BRD-SG-01796` | `OZIO Official` | 15 |
| AHC | `BRD-GLOBAL-01047` | `AHC Beauty Official Store` | 14 |
| Wellage | `BRD-GLOBAL-01214` | `Wellage Official Store SG` | 13 |
| Physiogel | `BRD-GLOBAL-00124` | `Physiogel  Official  Store` | 13 |
| TONYMOLY | `BRD-GLOBAL-01733` | `TONYMOLY MALAYSIA OFFICIAL STORE` | 13 |
| Cerave | `BRD-GLOBAL-00006` | `CeraVe Official Store` | 13 |
| Thayers | `BRD-SG-01310` | `Thayers Official Store` | 13 |
| est.lab | `BRD-SG-02649` | `ést.lab Official Store` | 12 |
| D Program | `BRD-GLOBAL-00534` | `d program Official Store` | 12 |
| Curel | `BRD-GLOBAL-00199` | `Kao Beauty Official Store` | 12 |
| make p:rem | `BRD-GLOBAL-01563` | `makepremglobal.sg` | 12 |
| embryolisse | `BRD-GLOBAL-00765` | `Embryolisse Official Store` | 12 |
| Celimax | `BRD-GLOBAL-00764` | `celimax.sg` | 12 |
| Mamonde | `BRD-GLOBAL-01911` | `VITALBEAUTIE OFFICIAL` | 12 |
| Noreva | `BRD-SG-03086` | `Noreva Official Store` | 12 |
| PCA Skin | `BRD-GLOBAL-02410` | `PCA Skin Official Store` | 11 |
| DPPR | `BRD-SG-02311` | `DPPR_Official.sg` | 11 |
| Needly | `BRD-GLOBAL-00849` | `Needly Official Store` | 11 |
| FRANKLY | `BRD-GLOBAL-01773` | `FRANKLY` | 11 |
| AROCELL | `BRD-GLOBAL-02211` | `Arocell.SG` | 11 |
| Obagi | `BRD-GLOBAL-01751` | `Obagi Medical` | 11 |
| Charming Skin | `BRD-GLOBAL-01141` | `Caring Skin Official Store` | 10 |
| Anua | `BRD-GLOBAL-00259` | `Anua Singapore` | 10 |
| Kelly Oriental | `BRD-SG-03705` | `Kelly Oriental Skinlab` | 10 |
| Minimalist | `BRD-SG-01967` | `Minimalist Official Store` | 9 |
| Axis-y | `BRD-GLOBAL-00388` | `AXIS-Y Official Store` | 9 |
| Curel | `BRD-GLOBAL-00199` | `Kao Official Store` | 9 |
| Florasis | `BRD-GLOBAL-01540` | `花西子 Florasis Official Store` | 8 |
| Beauty of Joseon | `BRD-GLOBAL-00136` | `Beauty of Joseon Official Store` | 8 |
| MENOKIN | `BRD-SG-01591` | `Menokin Singapore` | 8 |
| Bioderma | `BRD-GLOBAL-00062` | `Bioderma Official Store` | 7 |
| The Ordinary | `BRD-SG-00010` | `The Ordinary Official Store` | 7 |
| Neostrata | `BRD-GLOBAL-01866` | `Dermaskinshop Official Store` | 7 |
| Nivea | `BRD-GLOBAL-00023` | `Nivea Official Store` | 6 |
| AROCELL | `BRD-GLOBAL-02211` | `AROCELL Official Store` | 6 |
| Kelly Oriental | `BRD-SG-03705` | `Kelly Oriental Official Store` | 6 |
| Abib | `BRD-GLOBAL-00325` | `大買家網路店 Save & Safe Official` | 6 |
| Badskin | `BRD-GLOBAL-00840` | `BADSKIN SINGAPORE` | 6 |
| Lepique | `BRD-SG-02500` | `Lepique` | 6 |
| Suntory | `BRD-GLOBAL-01032` | `BRAND'S Health Supplements Store` | 5 |
| Celimax | `BRD-GLOBAL-00764` | `Celimax Singapore` | 5 |
| Snowflake Skin | `BRD-SG-03426` | `BODYBLENDZ.SG Official Store` | 5 |
| Elixir | `BRD-GLOBAL-00106` | `Chemist Curated Official Store` | 5 |
| DASHU | `BRD-GLOBAL-01395` | `DASHU_official.sg` | 5 |
| Illiyoon | `BRD-GLOBAL-00796` | `AMOREPACIFIC Hair&Beauty Shop` | 5 |
| Kahi | `BRD-GLOBAL-02348` | `Nature's Mart` | 4 |
| LUMI | `BRD-SG-02345` | `Skin Inc Official Store` | 4 |
| goodal | `BRD-GLOBAL-01730` | `Clubclio_official` | 4 |
| MKUP | `BRD-GLOBAL-02108` | `MKUP 美咖 Official Store` | 4 |
| BIOHEAL BOH | `BRD-GLOBAL-01587` | `BIOHEAL_SG` | 3 |
| Bio Essence | `BRD-GLOBAL-00754` | `Eversoft Singapore Official Store` | 3 |
| Simple | `BRD-GLOBAL-01190` | `Unilever International` | 3 |
| Etude House | `BRD-GLOBAL-00364` | `ETUDE Official Store` | 3 |
| Ceradan | `BRD-SG-00860` | `Ceradan SG Official Store` | 3 |
| Mediheal | `BRD-GLOBAL-00361` | `BellaVie1.sg` | 3 |
| SNATURE | `BRD-GLOBAL-01881` | `S.NATURE` | 3 |
| Cetaphil | `BRD-GLOBAL-00069` | `Haleon Official Store` | 2 |
| KOPHER | `BRD-SG-00270` | `KOPHER Singapore` | 2 |
| Physiogel | `BRD-GLOBAL-00124` | `LINE FS Korea` | 2 |
| Blanc Nature | `BRD-GLOBAL-00337` | `Blanc Nature` | 2 |
| Avarelle | `BRD-SG-01543` | `Avarelle SG Official Online Store` | 2 |
| olay | `BRD-GLOBAL-00075` | `Oral Oasis` | 2 |
| Torriden | `BRD-GLOBAL-00011` | `Beatriz Korea` | 2 |
| CRYSTAL TOMATO | `BRD-SG-02552` | `Crystal Tomato® Official Store` | 2 |
| Hipapa | `BRD-GLOBAL-01023` | `Hi!papa` | 2 |
| HaruHaru Wonder | `BRD-GLOBAL-00415` | `Haruharu Wonder Official` | 2 |
| Auolive | `BRD-SG-03813` | `AUOLIVE` | 2 |
| Bio Essence | `BRD-GLOBAL-00754` | `SAFI Official` | 2 |
| IUNIK | `BRD-GLOBAL-01316` | `IUNIK Official Store Singapore` | 2 |
| evian | `BRD-GLOBAL-00239` | `Ecover Official Store` | 1 |
| dermalogica | `BRD-GLOBAL-00408` | `Global Buyer` | 1 |
| Logically, Skin | `BRD-GLOBAL-01277` | `Logically, Skin Official Store` | 1 |
| Suu Balm | `BRD-SG-00424` | `Suu Balm OFFICIAL STORE` | 1 |
| KOPHER | `BRD-SG-00270` | `KOPHER Singapore Official Store` | 1 |
| ApexFlow | `BRD-SG-03448` | `ApexFlow ` | 1 |
| Men+ | `BRD-SG-09828` | `twd6ontqdd` | 1 |
| Men+ | `BRD-SG-09828` | `AWHAO` | 1 |
| Rejuran | `BRD-GLOBAL-00335` | `Ustar Beauty` | 1 |
| Men+ | `BRD-SG-09828` | `Romantic Full Store` | 1 |
| evian | `BRD-GLOBAL-00239` | `Pearlie White Official Store` | 1 |
| Sulwhasoo | `BRD-GLOBAL-00122` | `HappyBeauty Official Store` | 1 |
| Sadoer | `BRD-GLOBAL-00488` | `Brand Choice` | 1 |
| OZIO | `BRD-SG-01796` | `BEME Japan Official Store` | 1 |
| Aqualabel | `BRD-GLOBAL-00677` | `K.O.I STORE VN` | 1 |
| fully | `BRD-GLOBAL-02097` | `FOODOLOGY Official Store` | 1 |
| Laneige | `BRD-GLOBAL-00128` | `L.Bean Store` | 1 |
| evian | `BRD-GLOBAL-00239` | `Method Official Store` | 1 |
| S-ERUM | `BRD-GLOBAL-02143` | `KOCSKIN Official ` | 1 |
| 1.618 | `BRD-SG-06260` | `JAN.SG Official Store` | 1 |
| Bioaqua | `BRD-GLOBAL-01482` | `Benjemarketing` | 1 |
| Barrier Repair | `BRD-SG-07838` | `PAZIUM` | 1 |
| Anua | `BRD-GLOBAL-00259` | `nciejfjksds003.sg` | 1 |
| fully | `BRD-GLOBAL-02097` | `Ronyme` | 1 |
| Beauty of Joseon | `BRD-GLOBAL-00136` | `XLzkbs7G2.sg` | 1 |
| Barrier Repair | `BRD-SG-07838` | `healthcareonlinepharmacyls.sg` | 1 |
| Beauty of Joseon | `BRD-GLOBAL-00136` | `Xxiao.SG1.sg` | 1 |
| PDRN | `BRD-SG-12179` | `Cothekoo Official Store` | 1 |
| Himalaya | `BRD-GLOBAL-00470` | `Himalaya Wellness Official Store` | 1 |

**Brands in the 95% GMV scope with no discoverable single-brand official store** (258 − 183 legit
single-brand − 8 confirmed parent-store brands ≈ 67, includes several large brands with no Mall
presence at all, e.g. Torriden's own store wasn't found under an obvious "Torriden Official" name in
this scan — verify per-brand before assuming Pass-2-only; not independently re-checked brand by
brand this session): Pass 2 only, or defer to a follow-up session's targeted search.

---

## Scale

| Metric | Value |
|---|---|
| Total table rows (all months, `master_clean_niq.shopee_sg_facial_moisturiser`) | 4,761,043 |
| Distinct products, latest complete month (2026-05-01) | 96,286 |
| Total rows, 2026-05-01 | 339,416 |
| Official-store (`merchant_badge='Shopee Mall'`) rows, 2026-05-01 | 45,542 |
| Official-store distinct products, 2026-05-01 | 16,387 |
| Distinct `sku_name` among official-store products, 2026-05-01 | 16,259 |
| Official-store distinct products **restricted to the 258 in-scope brands** | 8,733 |
| Official-store distinct products on the vetted single-brand + parent-company allowlist | ~3,630 (3,365 single-brand + 265 across the 8 confirmed parent stores) |

**8,733 official-store products for in-scope brands is large enough that per-listing multimodal
image reads for every single one is not the right method within a single session** — same
conclusion as `sg_facial_cleanser.md`. Method: text-first clustering into canonical entries (see
Taxonomy Design Notes), with vision reads reserved for spot-verification and genuinely ambiguous
cases, not exhaustive per-listing coverage.

---

## Scope — What's In vs Out

**In scope:** everything under this master_table's seven `magpie_category_3` buckets — facial
moisturizer (cream/lotion/gel/emulsion/serum-as-moisturizer where NIQ-classified here), toner,
facial mist, face mask & packs (sheet masks, wash-off masks, sleeping packs), men's moisturizer,
men's face cleanser (as mapped by `niq_category_mapping` for this table specifically — note this
differs from `sg_facial_cleanser`'s own cleanser bucket; a men's cleanser product could in principle
appear in either source table depending on how NIQ tagged it, not resolved this session).

**Out of scope (leave NULL):** body wash/care, makeup/cosmetics, sunscreen (separate suncare
handling), skincare devices (cleansing brushes, LED masks, jade rollers) unless bundled with a
genuine skincare product as GWP, standalone facial cleanser products that are NOT tagged under this
table's Men's Care buckets (i.e. don't reroute mainstream cleansers here — `sg_facial_cleanser` owns
those).

**Edge cases:**
- `Care`, `All`, `Deep`, `Fast`, `IN`, `D'ARK` brand_ids — data-quality artifacts, see Brand Scope
  footnote. Products under these brand_ids are not automatically OOS (some may be real products with
  a misattributed brand) but get no dedicated Pass 1 taxonomy build; route via Pass 2 text-matching
  or leave NULL if genuinely unidentifiable.
- `image` column has the same literal-embedded-double-quote data-quality quirk documented in
  `sg_facial_cleanser.md` (e.g. `.../file/"sg-11134207-...` — quotes are literal characters in the
  stored string). **Confirmed in this session**: stripping the quotes and fetching via `curl` to a
  local temp file, then viewing with the Read tool, successfully renders the image (test product:
  `[Sante] Aka Semi-gel Face Mask 5sheets without Cooler`, product_id 18883214720) — this is the
  actual working method for image access in this environment (see Taxonomy Design Notes; this
  session does not have a URL-native vision fetch tool, only local-file image reading, so
  curl-to-tmp-then-Read is the required two-step pattern for every image check).

---

## Taxonomy Design Notes

**Image access method (environment-specific finding, worth recording for future sessions):** this
session has no tool that reads a remote image URL directly for vision. `WebFetch` runs the URL
through a small text-summarization model and cannot be used for visual product verification. The
working pattern is: strip the literal embedded quotes from the `image` column value, `curl -sL -o
/tmp/<file>.jpg "<cleaned url>"`, then use the file-reading tool on the local path — this does give
genuine multimodal image access, confirmed working this session. This is slower per-image than a
native fetch would be (one shell round-trip per image) which reinforces the text-first approach
below rather than changing it.

**Method: text-first clustering, not per-listing vision reads.** Per `llm-extraction-rules.md` §2
(size: text wins, image is the tiebreaker) and `docs/headless-runbook.md`'s Full Rebuild scenario
step 2 ("text-matching...only read product images for individual products where text matching is
genuinely ambiguous"):
1. For each allowlisted brand, cluster official-store `sku_name`/`sku_name_EN` values into distinct
   (product_line, sub_line/variant, size, pack_count) combinations using the on-label text.
   `sku_name_EN` is English for SG, making text extraction materially more reliable than in TH
   categories.
2. One canonical `product_taxonomy` entry per distinct combination — confidence 0.85–0.99 only when
   spot-verified against the product image (via the curl-to-tmp-then-Read pattern above); otherwise
   0.65–0.85 for text-derived-only entries.
3. Vision reads reserved for: ambiguous size/pack/line cases, spot verification of the highest-GMV
   entries per brand (triage by GMV impact per `quality-standards.md` §1), and look-alike sub-line
   disambiguation for clinical/derma brands (`llm-extraction-rules.md` §3 — e.g. Eucerin, CeraVe, La
   Roche-Posay have multiple similar-looking lines that require reading the actual label).
4. `product_line` / `sub_line` / `variant` populated as their own columns on every insert, never left
   NULL while the same text lives only in `canonical_name` — this is the exact prior failure (934
   entries, 100% NULL `product_line`, `shopee_sg_shampoo` attempt #2) that
   `docs/headless-runbook.md`'s QA-gate-as-code exists to catch.

**Universe refresh target:** per `docs/headless-runbook.md` (not `CLAUDE.md`, which is stale on this
point), the real production output table is `marketshare_universe_niq`; taxonomy state for headless
runs lives in `magpie_reference.universe_taxonomy_overlay`. **Not run this session** — this session's
task scope is `product_taxonomy`/`product_taxonomy_map` writes only (Steps 0–7); universe refresh is
explicitly out of scope for this run.

**Method actually executed this session:** built 188 `product_taxonomy` entries across the 25
highest-GMV allowlisted brands (Torriden, medicube, Mediheal, Biodance, Skintific, Skin1004,
Rejuran, Aestura, Dr. Althea, Cosrx, CENTELLIAN 24, The Ordinary, Laneige, ROUND LAB, SOME BY MI,
Innisfree, VT COSMETICS, La Roche-Posay, Cerave, Skinfood, Paula's Choice, Alluora, Pyunkang Yul,
Isntree, GLAD2GLOW), grouping each brand's official-store `sku_name_EN` text into distinct
(product_line, sub_line, size, pack_count) entries. 6 of the highest-GMV entries were spot-verified
against the actual product image (curl-to-tmp-then-Read): Torriden Dive In Facial Serum Sheet Mask
(confirmed 27ml x10 sheets), Medicube Best Daily Toner Pad Set (confirmed 7-flavor 100-pad set,
exact match to text-derived flavor list), Medicube Salmon DNA PDRN Capsule Cream (resolved a
text-ambiguous size to 50g), Medicube Collagen Night Wrapping Mask (resolved to ~75ml from the fl-oz
label), Biodance Real Deep Overnight Mask 1+1 Set (confirmed 34g x8 sheets, 5 flavors), The Ordinary
Glycolic Acid Toner (hero shot, did not resolve the multi-size ambiguity). Everything else is
text-derived only (confidence 0.55–0.85 per the documented band), not vision-verified.

**Multi-size / multi-variant handling:** 19 of the 188 entries are seller-listings where a single
`product_id` offers multiple selectable sizes at the model level (e.g. Medicube Hypochlorous Acid
Face Spray 50ml/125ml) — since `product_taxonomy_map` grain is one taxonomy_id per `product_id` (not
per model), these were built with `is_multi_size=TRUE`, `size=NULL`, canonical name ending "Multiple
Sizes", rather than arbitrarily picking one size. 13 entries use `is_multi_variant=TRUE` for
same-listing flavor/formula selectors (Mediheal's 7/8-flavor toner pad sets, Biodance's 5-flavor
mask sets, etc.) — `variant` column left NULL on these since no single variant applies; `product_line`
and `sub_line` are still populated.

**Genuinely NULL size (19 of 188, documented, not guessed):** capsule-format creams and peel-off
masks where neither `sku_name` nor the spot-checked image states a volume/weight (e.g. Medicube Deep
Vitamin C Golden Capsule Face Moisturizer, Cerave PM Facial Moisturizing Lotion, Paula's Choice
Skin Balancing Invisible Finish Moisture Gel, GLAD2GLOW Morning C Night A Set) — confidence dropped
to 0.55–0.6 accordingly per `llm-extraction-rules.md` §2's "return UNRESOLVED only after all signals
exhausted" guidance; these were deferred rather than guessed.

**Pass 2 matching rule:** bulk substring match of `product_line` (+ `sub_line` if present) against
`sku_name`/`sku_name_EN` for the same `brand_id`, restricted to the 25 Pass-1 brands. Entries with
`pack_count > 1` additionally required an explicit pack signal in the text (`x2`, `x3`, "twin",
"duo", "trio", "1+1", "bundle of N") to avoid silently multiplying a single-unit reseller listing
into a bundle match. 15 candidate products matched two Pass-1 entries of equal specificity (same
match-length tie) and were left unmapped rather than guessed, per the conservative-unambiguous-rule
precedent in `docs/categories/sg_facial_cleanser.md`.

**Known difficult products:** none catalogued yet beyond the NULL-size list above — first pass.

---

## Existing HUMAN rows (found in Step 1 — undocumented prior to this session)

**6,447 `source='HUMAN'` rows** exist in `product_taxonomy_map` for `master_table =
'shopee_sg_facial_moisturiser'`. **Zero `source='LLM'` rows.** This matches the STATUS.md dashboard
("sg_facial_moisturiser: ⏳ Keyword only") — these are automated keyword-seed rows (the `HUMAN` label
is legacy terminology, not actual human review, per `ARCHITECTURE.md` Decision 18). Per this
session's explicit instructions: **not deleted by this session** — HUMAN-row cleanup is a separate,
deliberately manual/wrapper-side step (delete only where a HUMAN row duplicates a product that also
now has an LLM row, run after this session, never a blanket supersede).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-16 | Pre-build survey | 6,447 undocumented HUMAN rows, 0 LLM rows | Documented above; not deleted this session |
| 2026-07-16 | Scale check | 258 brands in true 95% GMV scope; 8,733 official-store products across those brands | Text-first clustering method adopted instead of per-listing vision reads |
| 2026-07-16 | Multi-brand store audit | 53 Mall-badged stores carry 3+ in-scope brands (Watsons, Guardian, Sasa, Beautyhaus SG, Nana Mall, etc.) | Excluded from Pass 1 allowlist |
| 2026-07-16 | Brand_dict data quality | `Care`, `All`, `Deep`, `Fast`, `IN`, `D'ARK` brand_ids are PRODUCT_NAME_SCAN artifacts on common English words, not real brands | Excluded from Pass 1 taxonomy build |
| 2026-07-16 | Image access | No native URL-vision tool in this environment; `WebFetch` is text-only | curl-to-tmp-then-Read confirmed working; adopted as the vision-verification method for ambiguous cases |
| 2026-07-16 | Schema check | `product_taxonomy_map.confidence` is STRING (decimal-as-text, e.g. `'0.85'`), not FLOAT as `ARCHITECTURE.md`/`data-dictionary.md` state; table also has `platform`/`country`/`source_listing` columns not documented in those files | Used actual `bq show --schema` output, not the docs, for the INSERT column list and types |
| 2026-07-16 | Pass 1 build | 188 taxonomy entries built across 25 brands (SKU-074001–074188), 6 spot-verified by image | G1=0, G3=0, structured-fields NULL%=0 (all pass); G2=794 (expected, `--skip-coexistence`) |
| 2026-07-16 | Pass 2 build | 1,885 products routed via bulk text-match; 15 ambiguous ties left unmapped | Confidence 0.6–0.75, `source_listing='RESELLER'` |
| 2026-07-16 | Post-build gates | Re-ran all 4 gates after Pass 1+2 | G1=0 ✅, G2=794 (expected, not yet cleaned up) ✅, G3=0 ✅, structured-fields NULL%=0 ✅ |
| 2026-07-23 | Top-up coverage session (month 2026-06) | Live worklist (top-95%-cumulative-GMV, GWP-zeroed, `taxonomy_id IS NULL`) independently re-queried at session start: 2,997 model-grain rows / 2,495 distinct products, $2,111,823.83 GMV — confirms the wrapper's pre-check number was still accurate this time, but verified live rather than trusted. Bulk-first reuse-before-mint: text-clustered by (resolved brand_id, normalized sku_name signature) — only 2 products bulk-matched to the 188 existing Pass-1/Pass-2 taxonomy entries (expected: those were already resolved in the 2026-07-16 run; this worklist is what was left). Remaining 2,493 products clustered into 2,363 distinct new entries (mostly singleton long-tail reseller listings — text normalization only merged ~130 near-duplicates) and minted via bulk `bq query` DML, text-only (sku_name regex for size/pack_count), no per-product image reads except 3 spot-verifications on the top-3 highest-GMV new entries (all Lassie Manna, confirmed via curl-to-tmp-then-Read: 50ml/25ml/30g sizes not stated in sku_name, patched in after verification). **Post-hoc scope audit (advisor-prompted, since the category/type match-or-create gate was never applied per-product during the bulk text pass — a real process gap, not a deferred-precision item):** keyword-scanned all 2,495 newly-mapped products for OOS signals (sunscreen/makeup/haircare/water terms). Nearly all SPF hits are legitimate face-moisturizer-with-SPF products (in scope) — but found and removed 2 genuinely miscategorized singletons: `10981756831` "Assos Chamois Creme" (a cycling saddle-chafing cream, not a skincare product at all — its brand had also been mis-scanned to noise-brand "IN" via "Made **In** Swiss") and `29292218697` "AYUNCHE Pro Care..." (a haircare bundle — shampoo/bond enhancer/volumizing fluid, no facial terms at all). Both were singleton taxonomy entries (no sibling products), so both the `product_taxonomy` row and the `product_taxonomy_map` row were deleted outright (session's own newly-created rows, not pre-existing data). No other blatant OOS contamination found in the scan; the remainder of the flagged SPF/mist/water hits are legitimately in-scope. **This audit was not exhaustive** — it was one keyword pass over the session's own 2,495 products, not a systematic re-application of the category/type gate to every entry; a follow-up should treat this as owed, not done. | 2,361 new `product_taxonomy` entries (SKU-122056–SKU-124418 range, 2 since deleted as OOS — see scope-audit finding; spanning the newly-claimed SKU-122056–124055 + SKU-124056–124555 blocks — 2,000-slot block undersized for the 2,363 originally minted, claimed a second 500-slot block via the same atomic mechanism rather than truncate the tail), 2,493 `product_taxonomy_map` LLM/RESELLER rows after the OOS cleanup (2,491 new-entry + 2 reused-existing). Found and corrected a real brand-mismatch: Lassie Manna Singapore's official-store `PRODUCT_NAME_SCAN` brand assignment falsely resolved 2 products (~$120K GMV) to unrelated brands "Crystal" and "Biocare" (stray word matches inside the titles) — overrode to Lassie Manna (BRD-SG-00160) for all 8 products from that merchant, consistent with official-store brand-vouching precedent. Also excluded the known noise brand_ids (Care*/All*/Deep*/Fast*/IN*/D'ARK*, documented in this file's Brand Scope footnote) from canonical_name text for 30 affected clusters (~$13K GMV) — routed to BRD-UNDEFINED instead of perpetuating the mismatch (one of these, "IN", was the same mis-scan behind the Assos Chamois Creme OOS product above). Live worklist re-checked post-run: 0 remaining (the 2 OOS removals are back to NULL, correctly excluded from any future worklist by scope, not by a text pre-filter). Overall table GMV coverage (mapped/total, 2026-06): ~98.0% (pre-OOS-cleanup figure; negligible change from 2 removed rows). **G4 (cross-category) explicitly verified, not just assumed: 0 mapped taxonomy_ids for this table fall outside its own SKU blocks (74001–76000, 122056–124555) ✅.** QA gates (no `--skip-coexistence`, per this session's instructions): G1=0 ✅, **G2=794 — this hard gate is RED, not passing.** Unchanged from the 2026-07-16 baseline; confirmed via direct cross-check that none of this session's product_ids have any pre-existing HUMAN row (0 new coexistence introduced by this session), but the category is not gate-clean right now — the 794 pre-existing HUMAN+LLM coexisting products still require the wrapper's narrowly-scoped HUMAN-row cleanup (delete only where a HUMAN row duplicates a product that now also has an LLM row) before G2 genuinely reaches 0. That cleanup is explicitly out of scope for this session (not authorized to delete pre-existing HUMAN rows here). G3 (placeholder-leak)=0 ✅, structured-fields NULL%=0 ✅, G5 (provenance)=0 ✅. Universe refresh **not run** this session (out of scope per task instructions). |
| 2026-07-23 | Top-up coverage session #2 (month 2026-06, same-day follow-up) | Re-ran STEP 0's live worklist query independently rather than trusting the wrapper's "3 products still gap" pre-check. Result: 3 model-grain rows / **2 distinct product_ids**, both already known — `10981756831` (Assos Chamois Creme, cycling chafing cream) and `29292218697` (AYUNCHE Pro Care haircare bundle). These are the exact 2 products the earlier same-day session (row above) identified as OOS and deliberately deleted from `product_taxonomy`/`product_taxonomy_map`; they reappear in the worklist purely because "deleted → back to NULL → still within 95% cumulative GMV" is expected, correct behavior for genuinely out-of-scope products, not a new coverage gap. Re-verified both against sku_name text (no image read needed — text is unambiguous): Assos is a cycling-saddle anti-chafing product, no skincare/moisturizer/toner/mask/mist term anywhere; AYUNCHE is an all-hair-care bundle (shampoo/polish oil/volumizing fluid/bond enhancer/grease wax). Both confirmed OOS again — correctly left NULL, not minted. **Net action this session: 0 rows created, 0 rows mapped, no SKU block claimed** (nothing to write; matches `docs/headless-runbook.md`'s Full Rebuild top-up scenario's documented behavior for a live gap that resolves to 0 after the category's own match-or-create gate). **Full QA gate self-check re-run (per this session's STEP 5), scoped correctly to `source='LLM'` per `run_qa_gates()`'s own methodology — not just the prior session's own new rows:** G1 (dual-mapped LLM)=0 ✅. G2 (HUMAN+LLM coexistence, unscoped by source per the exact gate query)=794 — still RED, unchanged, same pre-existing gap noted in the row above (wrapper-side HUMAN-row cleanup still not run). G4 (cross-category, LLM rows outside this table's own SKU blocks 74001–76000/122056–124555)=0 ✅. G5 (provenance)=0 ✅. **G3 (placeholder-leak) is RED — this is a genuine finding, not previously caught.** Ran the exact `run_qa_gates()` query (unscoped by source, per `docs/headless-runbook.md`): **5,946 map rows total** (634 `source='LLM'` + 5,312 pre-existing `source='HUMAN'` keyword-seed rows — the HUMAN-side hits are a separate, longstanding artifact of the keyword-seed process, not examined further this session since HUMAN-row remediation is explicitly out of scope). The LLM-attributable 634 rows trace to **36 distinct taxonomy entries**, all original 2026-07-16 Pass-1 `is_multi_size=TRUE` entries using the canonical-name suffix "Multiple Sizes" (e.g. `SKU-074026` "Biodance Bio-Collagen Real Deep Mask Multiple Sizes", 86 mapped products; `SKU-074096` "Laneige Water Sleeping Mask Multiple Sizes", 73 mapped products). This phrasing was compliant with `llm-extraction-rules.md` at build time (2026-07-16) but was retroactively banned unconditionally by the 2026-07-22 rule change documented in that file's changelog ("'Multiple Sizes'/'Multiple Variants' banned unconditionally... the flag column already conveys that semantic"). The prior same-day session's G3=0 result (row above) only checked its own 2,361 newly-minted entries, which don't use this phrasing — it never re-scanned the category's full existing LLM population, so this pre-existing defect went unflagged until this session's broader gate re-run. **Not fixed here** — renaming 36 canonical_name entries is a D1/D3 precision fix (exact wording), explicitly out of this top-up session's scope per its own instructions; flagging for `script/targeted_qa_fix.sh`, prioritized by the mapped-product counts above (Biodance/Laneige/Dr. Althea/Cerave entries are the highest-impact). **Fourth gate (`structured_fields_missing_pct`, whole category `source='LLM'` excl. `is_multi_size`) also re-run this session, not just inherited from the prior session's own-rows-only check: 0% (0 of 2,513 distinct non-multi-size LLM entries have NULL `product_line`) ✅ — genuinely clean, confirmed at full-category scope.** Universe refresh **not run** this session (out of scope). |
| 2026-07-23 | Automated Targeted QA Fix, session 2 (auto-discovery mode, no Brief on file) | STEP 1 worklist re-queried fresh: 2,650 distinct taxonomy entries (never-reviewed or previously-unconfident). Tier 1 SQL sweep flagged: `stub_leak`=58, `duplicate_brand`=3(6 pre-dedup), `wrong_field_order`=203, `brand_casing_mismatch`=57, `excess_content`=4, `canonical_field_mismatch`=106, `null_size`=706, `garbage_brand`=3(all false positives, see below). **Root-cause investigation before bulk-fixing (advisor-prompted):** two flag counts rose vs the prior session (`canonical_field_mismatch` 9→106, `brand_casing_mismatch` 14→57) — verified these are *derivative* artifacts of the prior session's own fixes, not fresh defects: 91 of the 106 `canonical_field_mismatch` hits are a cosmetic space-format mismatch (`size`="10 pcs" vs canonical_name's "10pcs", introduced by the prior session's regex size-backfill), 8 are the already-deferred `SKU-000xxx` slash-range cluster, 3 are the already-deferred `(all variants)` HUMAN stubs — leaving **3 genuine hits**: `SKU-074183`/`SKU-123960`/`SKU-074037`, where the prior session's Tier-2 image-verification had correctly updated `size`/`pack_count` but never propagated the value into `canonical_name` text — fixed by appending the confirmed size/pack (e.g. `SKU-074037` "Skintific Acne Clay Stick Mask" → "...40g"). `brand_casing_mismatch`'s rise traced to 6 `brand_dict` entries themselves being improperly cased (`guerlain`/`dermalogica`/`embryolisse`/`goodal`/`sisley`/`lamer`, all lowercase) rather than `canonical_name` being wrong — fixed at the root (`brand_dict.canonical_name` capitalized) rather than degrading `canonical_name` to match; then one bulk `UPDATE...FROM brand_dict` realigned all 87 (58 flagged + 29 more caught by the same pattern once brand_dict was corrected) `canonical_name` brand-prefix casings to `brand_dict`'s now-correct values in one statement. **`wrong_field_order`** (203): 200 are `BRD-UNDEFINED` with a real brand seemingly stated in `canonical_name` (case (b)) — bulk word-boundary prefix-match against ACTIVE `brand_dict` (excluding the 6 known noise-brand_ids) found only the same 6 known-false-positive matches this file's own Brand Scope footnote already excludes (Birch/Gardenia/Instant/Mela/Rosemary/Yellow — generic English words coincidentally registered as ID-scope brands) — correctly left `BRD-UNDEFINED`, no fabricated matches; brands like Cactox/MayMorning/AXENDA/Mariv genuinely don't exist in `brand_dict` yet. 3 non-`BRD-UNDEFINED` exceptions handled individually: `SKU-122517` "Dr. Morita..." resolved to `brand_id` `BRD-GLOBAL-03765`, which **`brand_dict` returns two different `canonical_name` values for the same `brand_id`** (a real PK-duplication data-integrity bug — confirmed 5 such duplicate-PK brand_ids exist, all clustered `BRD-GLOBAL-03765`–`03769`, likely a batch-seeding collision; out of this session's authority to fully remediate, flagging for a `brand_dict`-focused session) — repointed to the unambiguous `BRD-SG-03990` "Dr Morita" instead of relying on the corrupted ID. `SKU-123174` "Shopee x TONYMOLY Brand Box..." already had the correct `brand_id` (fixed by the prior session) but `canonical_name` text was never reordered — fixed (case (a), text reorder only). `SKU-002555` "Glad2Glow...(all variants)" resolved to `BRD-GLOBAL-00130` whose own `canonical_name` is literally "Glad2Glow Official Store" (a merchant name leaked into `brand_dict`, the §11 problem one level up the reference chain) — repointed to the clean `BRD-GLOBAL-03244` "GLAD2GLOW" entry already used by this file's own Brand Scope table. **`excess_content`** (4): 3 are the deferred `SKU-000xxx` slash-range cluster; `SKU-074107` "ROUND LAB...30ml x10 sheets x2" was a genuine nested-multiplier miss (same class as the th_softdrink `[แพ็ก12] ยกลังxM` precedent) — sku_name confirmed "30ml*10eaX2ea" = 20 sheets total; corrected to `size`="30ml", `pack_count`=20, canonical_name "...30ml x20". **`duplicate_brand`** (6 raw hits, 3 false positives on legitimate product-line text containing the brand word coincidentally — PDRN/Sisley/Babor left untouched): `SKU-122212` "Skin1004 Skin1004 Daily Calm..." and `SKU-124215` "Biore Men's Biore Pore Pack..." were genuine brand-repeated-in-product_line bugs — deduped in both `canonical_name` and `product_line`. `SKU-124043` "NOWNESS...NOWNESS..." traced to sku_name itself containing the brand twice across a genuinely garbled multi-language, multi-product reseller listing (3 distinct sku_names — mist/toner/lotion — merged under one entry) — deferred, not guessed. **Tier 2, GMV-prioritized** (month 2026-06-01; first attempt at this query wrongly summed `gmv_monthly` without a month filter or product-grain dedup, producing nonsense fanout totals up to $40M/entry — caught and corrected per `ARCHITECTURE.md`'s own aggregation warning before using the numbers): top ~24 non-`(all variants)`/non-`SKU-000xxx` entries by GMV cross-checked against `sku_name`. Found and fixed: `SKU-122061` "Lassie Manna...PERFUME TREE & ROSE WATER" had `size`=NULL despite the sku_name giving no size — curl-to-tmp-then-Read on the product image confirmed 50ml, backfilled (genuine D4 miss, $31K/mo). `SKU-074139` "Cerave Moisturizing Cream" was `is_multi_size`=FALSE despite covering genuinely diverse sizes (50ml/177ml/340g/454g/twin-packs across 55 products, confirmed via full sku_name scan) — corrected to `is_multi_size`=TRUE; a minor sub-line contamination surfaced in the same scan (Itch Relief/Diabetics'/SA Lotion/AM-PM Lotion variants bulk-matched into the base entry) but totals only ~$46/mo combined — documented, not worth a SKU-mint. 17 other top-GMV entries (Torriden/Biodance/Dr.Althea/Innisfree spot-checks) cross-checked against `sku_name` and confirmed correct, including re-confirming `SKU-074064` Dr.Althea's genuine 60ml/100ml `is_multi_size` and `SKU-074087` The Ordinary's genuine 100mL/240mL multi-size (both already correct from the prior session). **STEP 2b** (pack_count=1 + promo language, 1,078 hits, GMV-prioritized top slice manually reviewed): confirmed the `free` term's heavy false-positive rate on `Paraben-Free`/`Oil-Free`/`Freeze-Dried` claims (same known class, e.g. product `49358278319` "FREEZE-DRIED..." matched only because "free" is a substring of "freeze"). Found a real, GMV-significant class: **`[Bundle of N]` reseller listings for Torriden's official-store products bulk-matched to the single-pack base entry with no pack-count adjustment** — `10eaX2ea`/`10eaX3ea`/`300mlX2ea`/`80eaX2ea`/`100mlX2ea` patterns under `SKU-074001`/`074002`/`074005`/`074006` respectively (combined ~$28K/mo across 4 products) each meant the buyer receives N× the base entry's contents, not 1×. Claimed a new 200-slot SKU block (`SKU-134332–134531`) — **not** the prior session's `SKU-133646–133845` block, which this session found marked `FAILED_QA` in `sku_block_registry` despite that session's own QA History entry claiming all hard gates passed (G1/G3/G4/G5=0, G2 red-but-expected) — a real discrepancy between the registry and the self-reported narrative, flagged here for human review rather than investigated further (per the runbook's "never reuse a `FAILED_QA` block" rule, reuse was never on the table regardless of the reason). Minted 5 new entries (`SKU-134332`–`134336`: Serum Sheet Mask 10 sheets x2/x3, Toner 300ml x2, Multi Pad 80 pads x2, Soothing Cream 100ml x2) and rerouted the 5 corresponding `product_taxonomy_map` rows off the single-pack base entries. One related cross-product bundle (`SKU-074006`'s product `25895265708`, "...Multi Pad 80ea, BALANCEFUL Cica Daily Toner Pad 60ea" — two different Torriden products in one listing, $1,350/mo) deferred rather than decomposed, same class as this file's own previously-documented "+10 Pads Special Set" precedent. **Tier-2 correct-verdict promotions**: 19 entries re-judged and confirmed correct this session (the 4 Torriden base entries post-reroute, plus medicube/Mediheal/Biodance/Dr.Althea/Innisfree spot-checks) bulk-marked via one `_meta` UPDATE; 6 of these had also been judged correct by the prior session (`unconfident` + `last_verdict='correct'`) and now promote to **`confident`** on this second agreeing review — the first `confident` entries this category has ever had. **New taxonomy entries**: 5 (`SKU-134332–134336`), all `meta_agent='CLAUDE_CODE'`/`source='LLM'`; other changes were in-place field UPDATEs (87 brand-casing realignments, 3 brand_dict corrections, 6 individual fixes, 5 map-row reroutes) — no other rows inserted or deleted. **Hard gate self-check (no `--skip-coexistence`)**: G1 (dual-mapped LLM)=0 ✅. G2 (HUMAN+LLM coexistence)=794 — still RED, unchanged, confirmed still the same pre-existing wrapper-side cleanup gap. **G3 (placeholder-leak)=5,298, still RED — re-verified this is unchanged, pre-existing, 100% `source='HUMAN'`** (this session initially suspected a fresh LLM-driven contribution to G3 from 3 SG `(all variants)` entries showing associated `LLM` map rows, but tracing those rows found they belong to `shopee_th_moisturizer_for_face`/`shopee_th_moisturizer_for_body` — a different category entirely, sharing the same `SKU-002xxx` taxonomy_id range cross-market, the same open block-ownership question this file's prior session already flagged for `SKU-000xxx` — corrected before reporting a false finding; the properly-`master_table`-scoped check confirms 0 LLM contribution within this category, matching the documented baseline). G4 (LLM rows outside this table's own claimed blocks `74001–76000`/`122056–124555`/`133646–133845`/`134332–134531`)=0 ✅, explicitly re-verified. G5 (provenance)=0 ✅. Confidence distribution left behind (whole category): 6 `confident` (first-ever for this category — two consecutive agreeing reviews), 48 `unconfident`, 2,600 `unreviewed`. Universe refresh **not run** this session (out of scope per task instructions). |
| 2026-07-23 | Automated Targeted QA Fix (auto-discovery mode, no Brief on file) | STEP 1 worklist (never-reviewed or previously-unconfident entries via `_meta.review_confidence`): 2,640 distinct taxonomy entries. Tier 1 SQL sweep flagged 1,073 rows across 8 defect classes: `stub_leak`=94, `wrong_field_order`=332, `brand_casing_mismatch`=14, `excess_content`=4, `canonical_field_mismatch`=9, `null_size`=810, `garbage_brand`=5 (`duplicate_brand`=0). Triaged by fix-feasibility, not flag order (a single cluster tripped multiple flags at once). **Fixed, bulk SQL, mechanical:** (1) 36 entries had the now-banned "Multiple Sizes" canonical_name suffix (`llm-extraction-rules.md` 2026-07-22 rule, flagged but left unfixed by the 2026-07-23 top-up session above) — stripped via `REGEXP_REPLACE`, `product_line` already populated on all 36 so none stripped to a bare brand; this directly cleared the **G3 hard gate the prior session left RED** (634 LLM map rows traced to these 36 entries). (2) 14 Skin1004 entries had `SKIN1004` (all-caps) instead of brand_dict's proper-cased `Skin1004` — bulk-corrected. (3) `garbage_brand`'s 5 hits included 3 false positives — "1.618" (a real numeric brand name, rank 147 in this file's own Brand Scope table, `BRD-SG-06260`) has no letters and tripped the regex's letter-check; left untouched. The other 2 (`brand_id` resolved to literal text "12/+＝") matched the exact watermark-misread pattern `llm-extraction-rules.md` §11 documents — curl-to-tmp-then-Read on both product images confirmed the real on-package brands are **AmLactin** (`BRD-SG-01196`) and **Kelly** (`BRD-SG-04561`, "Kelly Pearl Cream"); reassigned `brand_id` and corrected `canonical_name`/`product_line` for both. (4) `wrong_field_order` — 331 of 332 hits were `brand_id=BRD-UNDEFINED` with a real brand stated in `canonical_name` (case (b) in this session's own instructions); the 1 exception was an "(all variants)" HUMAN stub (see below). Bulk prefix-match against `brand_dict` (ACTIVE only, ≥4 chars, word-boundary after match, excluding the 6 known noise-brand_ids from this file's Brand Scope footnote) found 130 unambiguous matches, repointed `brand_id` in one UPDATE; excluded generic-word false-positive matches (Shopee/Yellow/Instant/Rosemary/Birch/Mela/Gardenia) from the automated pass. 1 more fixed manually: `SKU-123174` "Shopee x TONYMOLY Brand Box..." had matched noise-word "Shopee" — repointed to the real brand TONYMOLY (`BRD-GLOBAL-01733`). ~200 BRD-UNDEFINED rows left untouched (genuinely no identifiable brand, or excluded generic-word matches deferred rather than guessed). (5) `null_size`=810 distinct entries — 99 had a size/count already stated in `canonical_name` text but never captured into the `size` column (extraction-decomposition gap, same class as `docs/quality-standards.md`'s D4); bulk-backfilled via regex extraction (ml/g/kg/L/oz/pcs/ea/pads/sheets/pack units), following this category's own precedent (`SKU-000538` "Torriden...80 Pads") that pad/sheet counts are valid `size` values for mask/pad products here. **Tier 2 GMV-prioritized judgment**, image-verified via curl-to-tmp-then-Read on the remaining 711: top 12 by GMV read against product images — 6 fixed (Lassie Manna Fermented Dragon's Blood Biocare Mask → 30ml x5, was pack_count=1 despite image showing 5 sheets; Lassie Manna Crystal Bloom Peony Glow Mask → 30ml x5, same pack-count miss; Sadoer Facial Sheet Mask → 30ml; Skintific Mugwort Acne Clay Stick → 40g; Glad2Glow Morning C Night A Set → 30g x2, two-jar day/night kit; The Lab By Blanc Doux Oligo HA Deep Toner → `is_multi_size=TRUE`, packaging states 200ml/55ml but the promo graphic separately claims 250ml/600ml, genuinely ambiguous, not guessed), 2 left genuinely unresolvable (Bioaqua/Sadoer and Neogence entries are both reseller catalog-page images showing dozens of distinct products, not a single item — `docs/llm-extraction-rules.md` §2's "return UNRESOLVED only after all signals exhausted"), 3 already correctly documented as genuinely-NULL in this file's own Taxonomy Design Notes (medicube capsule/patch/peel-off-mask entries) were not re-touched. Remaining ~699 `null_size` entries are long-tail (mostly singleton reseller listings from the 2026-07-23 top-up session) — flagged, not fixed, per this session's GMV-impact-first triage rule. **STEP 2b** (pack_count=1 + promo language in sku_name): 752 hits, but the regex's bare `free` term false-positived heavily on cosmetic claims like "Paraben-Free"/"Oil-Free"/"Fragrance-Free" (not a real promo signal) — GMV-prioritized top 40 manually cross-checked against sku_name text; found and fixed 2 genuine pack_count misses where `canonical_name` itself already stated a multiplier the `pack_count` column didn't reflect: `SKU-122185` Furano Hokkaido Lavender Q10 Water Cream (canonical said "x5tubes" and sku_name confirms "买四送一"/buy-4-free-1=5 total; pack_count 1→5) and `SKU-074025` Biodance Real Deep Overnight Mask 1+1 Set (canonical said "x8 sheets", matches this file's own 2026-07-16 spot-verification note; pack_count 1→8). One pre-existing pack-multiplier mapping issue noted but not fixed (see Deferred below). **Tier 2 judgment on 40 Tier-1-clean, un-flagged, high-GMV entries** (text cross-checked against a sample `sku_name` per taxonomy_id — this category's own established text-first method): found and fixed 2 real D2/D3 defects requiring decomposition, not just field edits — claimed a 200-slot SKU block (`SKU-133646–133845`) via the atomic mechanism first. (a) `SKU-074039` "Skintific Moisture Gel 30g" was a **variant-collapse stub**: bulk Pass-2 text-matching on the shared keyword "Moisture Gel" had conflated 4 genuinely distinct Skintific product lines (MSH Niacinamide Brightening, 5X Ceramide Barrier, SYMWHITE 377 Dark Spot, Sensitive) across 4 different stated sizes (6g/30g/40ml/80g) into one entry, 17 distinct products. Split into 9 precise entries by (product_line, size) read directly off each product's own `sku_name` (no image reads needed, text was unambiguous); the 4 products whose `sku_name` didn't state a size were routed to a per-line `is_multi_size=TRUE` catch-all rather than guessed. `SKU-074039` itself is now orphaned (0 remaining map rows) — left in place, not deleted, per this session's own "never delete an existing row" instruction. (b) `SKU-074002` "Torriden Dive In...Facial Soothing Cream 100ml" had a mini-trial-size product (`sku_name`: "Mini Size Trial...20ml", 2 product_ids) bulk-matched to the 100ml entry on product-line text alone with no size cross-check — split out a new `SKU-133655` 20ml entry; the other 7 (genuinely 100ml) stayed. 37 further entries (mostly the original 2026-07-16 Pass-1 build plus a `SKU-000xxx` Torriden/Skin1004 cluster, see Deferred below) were text-cross-checked and found correct; 3 of the `garbage_brand` false-positive "1.618" rows above are also included. All 40 bulk-marked via one `_meta` UPDATE (first-ever review → `unconfident`, per this session's own STEP 5 semantics, not `confident`). **Deferred, documented, not fixed:** (1) The `stub_leak` cluster's other 79 hits are `"(all variants)"` brand-level catch-alls (e.g. `SKU-002511` "medicube Facial Moisturiser (all variants)", 327 products) — confirmed via direct query that **100% of their map rows are `source='HUMAN'`** (5,312 of the unscoped-G3 count from the 2026-07-23 session above), i.e. the pre-existing keyword-seed population this file's own "Existing HUMAN rows" section already scoped as out-of-session-scope. They also fail the same way `canonical_field_mismatch`'s 9 hits do (brand-level, cross-product-line catch-alls, e.g. Torriden/Skin1004 `SKU-0005xx` entries listing 2-3 different product types joined by "/") — genuine decomposition requires per-brand Pass-1-scale rebuild work, not a targeted fix; renaming in place would just swap one generic stub for another without resolving anything, so left untouched and unmarked (no fabricated review). (2) `excess_content`'s 4 hits are the same `SKU-000xxx` cluster (size field storing slash-separated ranges like "55ml / 100ml" instead of NULL+`is_multi_size`) — same deferral. (3) **`SKU-000xxx` block-ownership question, checked but not resolved**: `docs/categories/STATUS.md` attributes `SKU-000001–000820` to "TH wave scripts (brand-specific seeds)", yet 13 of these taxonomy_ids are mapped to real SG products in this table. Confirmed this is **not a G4 violation** — every one of these map rows is `source='HUMAN'`, and G4 (verified below) checks only the LLM population, which is 100% inside this category's own claimed blocks. Left open whether `product_taxonomy` entries are meant to be intentionally shared cross-market for identical global-brand products (plausible, given `brand_dict` is explicitly global) or are legacy cross-category contamination — a `brand_dict`/architecture question out of this session's authority to resolve. (4) `SKU-074001` "Torriden...10 sheets" has one bulk-matched product whose own `sku_name` says "[Bundle of 3]...10eaLX3ea" (30 sheets) — likely under-counted for that one product_id, left unfixed (Pass-2 bulk-match simplification, single low-GMV product, same class as the `SKU-074006` "+10 Pads Special Set" case also left alone). (5) Remaining ~699 `null_size` and ~200 excluded-match `wrong_field_order` entries — long-tail, GMV-prioritization exhausted this session's budget before reaching them; no `_meta` written, fully eligible for the next run. **New taxonomy entries**: 10 (`SKU-133646–133655`), all `meta_agent='CLAUDE_CODE'`, `source='LLM'`; 19 map rows rerouted from the 2 split entries plus 130+1 brand repoints plus assorted field-level UPDATEs — no `product_taxonomy_map` rows inserted or deleted, only `taxonomy_id`/`brand_id`/`meta_agent` updated in place. **Hard gate self-check (no `--skip-coexistence`, per this session's own instructions):** G1 (dual-mapped LLM)=0 ✅. G2 (HUMAN+LLM coexistence)=794 — still RED, unchanged, confirmed still entirely the pre-existing wrapper-side cleanup gap (not this session's to fix). **G3 (placeholder-leak)=0 ✅ — fixed this session** (was RED at 634 rows / 36 entries per the row above). G4 (LLM rows outside this table's own claimed blocks `74001–76000`/`122056–124555`/`133646–133845`)=0 ✅, explicitly re-verified against the live map rather than assumed. G5 (provenance)=0 ✅. Confidence distribution left behind (whole category, not just this session's sample): 41 `unconfident` (first-ever review, this session — will promote to `confident` next session if re-reviewed and still found correct), 2,608 `unreviewed` (includes every row this session fixed — `_meta` reset per STEP 4 so the next run re-evaluates fresh — plus everything not reached this session), 0 `confident` (expected on a first QA-fix pass; nothing has had 2 consecutive agreeing reviews yet). Universe refresh **not run** this session (out of scope per task instructions). |
| 2026-07-23 | Top-up coverage session (month 2026-06, later same-day follow-up) | STEP 0 live worklist independently re-queried (not trusted from the wrapper's 1,821-row pre-check): confirmed exactly 1,821 model-grain rows / **1,404 distinct products**, $1,539,622.13 GMV (GWP-zeroed). This is a fresh gap, not a re-surfacing of the same 3 known OOS products — the category had resolved to a 0/3-row gap as of the last top-up session in this file; new listings evidently entered the source data since then.
| 2026-07-23 | Top-up coverage session (month 2026-06, later same-day follow-up #2) | STEP 0 live worklist independently re-queried (not trusted from the wrapper's "4 products" pre-check): confirmed exactly 4 model-grain rows / **3 distinct products** — `10981756831` (Assos Chamois Creme, cycling anti-chafing cream), `29292218697` (AYUNCHE Pro Care, all-haircare bundle: shampoo/polish oil/volumizing fluid/bond enhancer/grease wax, no facial terms), `23900662444` (GUANJING KOJIC ACID COLLAGEN WHITENING UNDERARM CREAM — body/underarm product, not facial). All 3 are the exact same products confirmed OOS in this file's immediately preceding QA History entry; verified zero existing `product_taxonomy_map` rows for all 3 (genuinely unmapped, not a stale worklist artifact). Re-confirmed OOS via `sku_name` text alone (unambiguous, no image read needed, consistent with prior sessions' precedent): none contain any facial-moisturizer/toner/mask/mist/men's-face term; all remain within the 95%-cumulative-GMV threshold purely because they're real category GMV that's never been mapped, which is expected, correct recurrence for genuinely out-of-scope products (documented pattern in this file since the first "later same-day follow-up" entry). **Net action this session: 0 rows created, 0 rows mapped, no SKU block claimed** — matches the runbook's documented top-up behavior for a live gap that resolves to 0 after the category's own match-or-create gate. **Full QA gate self-check (no `--skip-coexistence`, per this session's STEP 5):** G1 (dual-mapped LLM)=0 ✅. G2 (HUMAN+LLM coexistence)=0 ✅ (still clean, consistent with the wrapper-side HUMAN cleanup observed in the prior session). G3 (placeholder-leak)=0 ✅. G4 (LLM taxonomy_ids outside this table's own claimed blocks `74001–76000`/`122056–124555`/`133646–133845`/`134332–134531`/`143193–145013`)=0 ✅. G5 (provenance)=0 ✅. Structured-fields-missing % (distinct LLM entries, excl. `is_multi_size`)=0% ✅. GMV coverage (mapped/total, 2026-06): 97.01% (5,967 of 96,622 distinct products). Universe refresh **not run** this session (out of scope per task instructions). **Bulk-first reuse-before-mint** per this session's instructions: (1) Pulled all 2,563 existing `product_taxonomy` entries for this `master_table` and bulk-matched worklist products via `CONTAINS_SUBSTR`-style Python text matching (brand_id + `product_line` substring in `sku_name`, pack-count entries additionally required an explicit multiplier signal in text) — an initial permissive pass (min match length 4 chars) produced false collapses (e.g. Torriden's generic sub-brand word "Dive In" alone matching 7 genuinely different Dive In product types: serum, mask, toning booster); tightened to require `product_line` ≥12 chars and ≥2 words, and to skip ties where two different taxonomy_ids matched at equal specificity — final clean match: **51 products** reused against existing entries (confidence 0.65–0.7, `source_listing` inherited from `merchant_badge`). (2) Remaining 1,353 unmatched products clustered by `(brand_id, cleaned product_line text, extracted size, extracted pack_count)` using regex-based text extraction (size: ml/g/kg/L/oz/pcs/ea/sheets/pads/capsules units; pack: `xN`, "bundle of N", "twin(pack)", duo, trio, "1+1", "set of N", 买N送N) after stripping seller bracket-tags, noise words, and a marketing-description tail (cut at first `-`/`|`/"for"/"with"/etc.) — 1,259 distinct clusters, mostly singleton long-tail reseller listings (consistent with this file's own precedent that bulk reuse saturates quickly and new gaps are dominated by genuinely new products, not re-matchable ones). **Scope audit applied per-cluster before minting, not as a post-hoc afterthought this time:** found and excluded 3 genuinely out-of-scope products before writing anything — `10981756831` "Assos Chamois Creme" (the exact same cycling anti-chafing cream flagged OOS in this file's earlier 2026-07-23 sessions, re-surfaced because a new reseller listing brought it back within the 95% GMV threshold; a keyword-only OOS filter for "chafing"/"cycling"/"saddle" would have missed it since this listing's own text never uses those words — caught only by manually reviewing the noise-brand cluster, see below) and `29292218697` "AYUNCHE Pro Care..." (the same haircare bundle, same recurrence reason) — both already known from this file's QA History; plus one newly-identified singleton, `23900662444` "GUANJING KOJIC ACID COLLAGEN WHITENING UNDERARM CREAM" (body/underarm product, not facial). All 3 left NULL, not minted. **Noise-brand routing:** 9 clusters resolved to this file's documented noise brand_ids (`Deep`×8, `IN`×1 — the `IN` one was the Assos product above, already excluded) — routed to `BRD-UNDEFINED` with the noise word stripped from `product_line`/`canonical_name` text, per this file's established precedent, rather than building taxonomy entries under a known-fake brand. **Brand correction:** 3 products had `product_brand_map.brand_id = BRD-UNDEFINED` despite the brand being unambiguously stated in `sku_name` text (`FALLBACK`/no-match source) — corrected to the real brand (`BRD-GLOBAL-00026` Skintific ×2, `BRD-SG-02500` Lepique ×1, the latter matched via its own official-store merchant name), `brand_mismatch=TRUE` set on `product_brand_map` per the documented Phase 5 brand-correction flow, before using the corrected brand for taxonomy minting. **Critical fix caught before insert:** the initial canonical-name template literally wrote the brand display string "Undefined" into `canonical_name` for `BRD-UNDEFINED` entries (e.g. "Undefined REVCELL INTENSIVE Vita Collagen Ampoule 100ml") — this would have tripped the G3 placeholder-leak hard gate on insert; fixed by omitting the brand segment entirely for `BRD-UNDEFINED` entries, matching the convention already used by this category's existing `BRD-UNDEFINED` entries (verified against 200 existing examples, none of which prefix "Undefined"). **Writes:** claimed a 1,821-slot SKU block (`SKU-143193–145013`) via the atomic mechanism; inserted 1,259 new `product_taxonomy` entries (`SKU-143193–SKU-144451`, 562 slots of the claimed block unused) and 1,401 total `product_taxonomy_map` LLM rows (51 reuse + 1,350 new-entry), all `meta_agent='CLAUDE_CODE'`, `platform='Shopee'`, `country='SG'`, confidence 0.55–0.7 (text-only, no image reads needed this session — text signals were sufficient for every in-scope product). Live worklist re-checked post-run: 4 rows / 3 distinct products remaining, all 3 the confirmed-OOS products above (expected — "deleted/never-mapped → still within 95% GMV → reappears in worklist" is correct behavior for genuinely out-of-scope products, not a residual gap). Overall table GMV coverage (mapped/total, 2026-06): 96.05% (5,967 of 96,622 distinct products mapped). **Also observed, not caused by this session:** `product_taxonomy_map` for this table now has 0 `source='HUMAN'` rows (was 5,312 as of this file's most recent prior QA History entry) — the wrapper-side narrowly-scoped HUMAN-row cleanup that every session since 2026-07-16 flagged as "out of scope, not yet run" has evidently run at some point between sessions; this explains G2 now reading clean. **QA gate self-check (no `--skip-coexistence`, per this session's STEP 5):** G1 (dual-mapped LLM)=0 ✅. G2 (HUMAN+LLM coexistence)=0 ✅ (genuinely clean now, not just unchanged-red — see observation above). G3 (placeholder-leak)=0 ✅. G4 (LLM taxonomy_ids outside this table's own claimed blocks `74001–76000`/`122056–124555`/`133646–133845`/`134332–134531`/`143193–145013`)=0 ✅, explicitly re-verified against the live map. G5 (provenance)=0 ✅. Structured-fields-missing % (distinct LLM entries, excl. `is_multi_size`)=0% ✅. Universe refresh **not run** this session (out of scope per task instructions). |

| 2026-07-24 10:37 UTC | Automated review session (auto-discovery) | STEP 1 worklist: 3,816 distinct taxonomy entries (never-reviewed or previously-unconfident). Pre-fix qa_report.sh showed 2 FAILing entry-level gates: canonical_name fields (95) and garbled brand text (3). All 95 canonical_name-fields hits traced to one root cause: 91 were a cosmetic size-format mismatch (e.g. size='70 ea' vs canonical_name's '70ea', introduced by an earlier regex size-backfill), the other 4 were a Lassie Manna/AmLactin product_line drift. All 3 garbled-brand hits were the already-known 'BRD-SG-06260 ("1.618", a real numeric brand name with no letters)' false positive, now confirmed a second time — recorded as a permanent qa_gate_exceptions entry so no future session re-spends turns on it. STEP 1C fast-lane recheck found 493 rows in the 'fixed pending recheck' bucket; 168 were genuinely Tier-1-clean and bulk-promoted. STEP 2 Tier-1 sweep flagged 1,113 rows: duplicate_brand=6 (3 genuine — a medicube product mis-brand-mapped to ingredient-name 'PDRN', two multi-product-catalog listings with brand repeated in product_line; 3 confirmed-precedent false positives left untouched — Sisley/Babor coincidental substring, NOWNESS already-deferred garbled multi-product listing), wrong_field_order=221 (1 cosmetic Dr Morita punctuation mismatch + 4 genuine BRD-UNDEFINED brand repoints [ReVcell x2, ClearDea, LAVIEN, including a brand_dict casing root-fix for ClearDea] + ~216 correctly left BRD-UNDEFINED after excluding generic-English-word false matches from a bulk word-boundary brand_dict match), excess_content=3 (duplicated 'xN' multiplier text in Clinique/Kiehl's/Sulwhasoo canonical_names), null_size=878 (top-GMV cluster dominated by Lassie Manna: 12 resolved via curl-to-tmp-then-Read image verification, 3 more resolved via sku_name text, 866 remain long-tail/genuinely unresolvable). Tier-2 GMV-prioritized sampling (top ~60 clean entries + top pack_count=1/promo-language hits) surfaced a systemic, previously-undocumented defect: 26 Lassie Manna entries across this category had internal reseller SKU codes (LM-COS####/LM-EO###) leaking into product_line/canonical_name instead of the real on-package product name — fixed brand-wide via image/text re-derivation. Also found and fixed a genuine duplicate-entry pair (SKU-074097 and SKU-143198, byte-identical 'Laneige Water Sleeping Mask 70ml x2' entries) by consolidating map rows onto the original. 51 additional top-GMV entries cross-checked and confirmed correct. G2 (HUMAN+LLM coexistence), red at 794 for every prior session since 2026-07-16, is now genuinely 0 — the wrapper-side narrowly-scoped HUMAN-row cleanup evidently ran between sessions. | Fixed in place (no new taxonomy entries minted, no rows deleted): 95 canonical_name-fields rows (size-format normalization + 4 product_line corrections), 1 qa_gate_exceptions row recorded (garbled brand text / BRD-SG-06260, second confirmation), 3 duplicate_brand fixes (1 brand_id repoint + 2 multi-product stub cleanups), 5 wrong_field_order brand repoints (4 genuine + 1 brand_dict casing root-fix) + 1 cosmetic text fix, 3 excess_content dedup fixes, 15 null_size backfills (12 image-verified + 3 text-verified), 26 Lassie Manna internal-SKU-code cleanups (product_line/canonical_name), 1 is_multi_size correction (CeraVe SA Smoothing Cleanser, ambiguous seller multi-size listing), 1 duplicate-entry consolidation (2 map rows rerouted). Every fixed row had _meta reset to unreviewed per STEP 4. 168 pre-existing fast-lane rows promoted to confident/unconfident; 51 freshly Tier-2-judged-correct rows promoted. Confidence distribution left behind (distinct taxonomy_ids, whole category): 30 confident, 200 unconfident, 3,591 unreviewed. All hard gates re-verified clean after fixes: G1=0, G2=0 (genuinely clean, not just unchanged), G3(placeholder-leak)=0, G4(cross-category, all claimed blocks 74001-76000/122056-124555/133646-133845/134332-134531/143193-145013)=0, G5(structured-fields)=0%, canonical_name fields=0, garbled brand text=0, 'all variant/size' name=0. Universe refresh not run (out of scope per task instructions). |
| 2026-07-24 11:13 UTC | Automated review session (auto-discovery) | STEP 1 worklist: 3,791 distinct taxonomy entries (never-reviewed or previously-unconfident). STEP 1B pre-fix qa_report.sh showed all gates PASS (no gate-directed targets this session — purely worklist-driven). qa_gate_exceptions already had one confirmed entry (garbled brand text / BRD-SG-06260 '1.618') from the prior session, correctly skipped rather than re-verified. STEP 1C fast-lane recheck on the 363-row 'fixed pending recheck' bucket found 101 genuinely Tier-1-clean, bulk-promoted directly. STEP 2 Tier-1 sweep on the remaining 3,690 rows flagged: null_size=865, wrong_field_order=215, duplicate_brand=3, excess_content=1 (stub_leak/brand_casing_mismatch/canonical_field_mismatch/garbage_brand all 0, already resolved by prior sessions). wrong_field_order: all 215 were BRD-UNDEFINED (case b); bulk word-boundary brand_dict match produced only known-class generic-word false positives (Rose/Spot/Clear/Bubble/Solution/Vera/Birch/Gardenia/Instant, etc.) plus 'PDRN' (BRD-SG-12179) which a prior session already flagged as itself a suspect ingredient-name-as-brand mismapping target — no canonical_name in the flagged set actually starts with its matched brand candidate, so nothing met the bar for a confident repoint; all 215 left untouched (genuinely no identifiable brand this pass). duplicate_brand's 3 hits (Sisley/Babor/NOWNESS) are the same coincidental-substring/garbled-multi-product false positives already confirmed in the 2026-07-23 and 2026-07-24 10:37 sessions — recurring a third time, left untouched. excess_content's 1 hit (SKU-144433, Lassie Manna '25ml+10g' kit) is a genuine 2-component kit, not a data error — false positive, left untouched. null_size (865): GMV-ranked (product-grain, month-filtered per ARCHITECTURE.md's own aggregation warning) and curl-to-tmp-then-Read image-verified on the top ~15: fixed 5 (Lassie Manna Refreshing Micro Crystal->30ml, medicube PDRN Balm Stick->10g, medicube Deep Vita C Patch->6 patches, Alluora Mist->120ml+pack_count 1->2 [Buy1Get1 same product, not GWP], Biodance 2 Toner Pads SET->60 pads); left 6 genuinely unresolved (hero-shot/catalog-page images with no legible size: monday museum Toner Pad Trio, THEFACESHOP Real Nature multi-flavor catalog page, IEM cream, medicube Triple Deep Erasing Cream, medicube Color-Changing Jelly Mask Set, Lassie Manna Niu Niu Face Cream) - not guessed. STEP 2b (pack_count=1 + promo language, month-filtered, deduped by product_id): found a systemic bug affecting 8 'Buy X Get Y'-templated entries where a bogus placeholder size='1g' had overwritten a real size stated in sku_name (or should have stayed NULL for GWP-different-gift cases) - all fixed via text alone. Also found and fixed 6 more genuine pack-count misses where canonical/promo text already stated a multiplier the pack_count column didn't reflect (I'm from Mugwort Toner Buy1Get1, Kelly Oriental Buy2Get1, Skintific Buy1Free1, SOME BY MI 1+1, Paula's Choice Buy1Free1 Duo, Meditrina 3-free-1->x4). STEP 3 Tier-2 GMV-prioritized sample (35 highest-GMV Tier-1-clean entries, text-cross-checked against sku_name per this category's established method): found and split 3 multi-product bulk-match collapses that a shared base entry's dominant single-unit pattern had masked - (a) 3 Innisfree 'Best Duo'/'Bundle of 2' listings (Super Volcanic Pore Clay Mask 80g, Green Tea Seed Hyaluronic Cream 50ml, Green Tea Hyaluronic Skin 150ml) each bulk-matched to their respective single-unit base entries, ~$11.6K/mo combined - also caught the SVPC Mask base entry's own size was wrong (80ml vs the dominant 100ml stated in 29 of its 30 mapped sku_names) and fixed that too; (b) ROUND LAB Birch Juice Moisturizer - 2 genuine '1+1'/'Bundle of 2' 80ml duo listings split from the single-unit base (a 3rd bundled-with-different-product listing left mapped to base, $0 GMV, deferred, same class as this file's prior '+10 Pads Special Set' precedent); (c) Jorubi Aloe Vera Gel - a 7-way size/pack-count collapse (120ml/40ml x1, 10ml/40ml/120ml x2, 10ml/120ml x4 all merged into one 'size=120ml,pack=1' entry), ~$14.2K GMV, split into 6 new entries by exact sku_name text, base entry kept as the 120ml x1 subset; (d) Torriden Dive In Glow Mist - 2 'Mini Size Trial 50ml' listings (single + Bundle-of-2) bulk-matched to the 120ml base, ~$4.7K/mo, split out. Also found and fixed one more standalone D4 miss (Cosrx One Step Pad, size stated as '100 pads' in sku_name but never captured) and confirmed one apparent contamination case (Biodance Collagen Gel Toner Pad, 32 mapped products including several off-catalog/multi-product listings) as immaterial - the dominant $10,220/mo product is a correct 60-pad match and every contaminating listing is $0 GMV, not worth a split. 31 other top-GMV Tier-1-clean entries cross-checked and confirmed correct as-is. | Fixed in place (no rows deleted): 101 STEP-1C fast-lane bulk promotions; 5 image-verified null_size/pack fixes; 8 buggy-placeholder-size fixes; 6 pack-count-miss fixes; 1 base-entry size correction (Innisfree SVPC Mask 80ml->100ml); 1 base-entry size fix (Cosrx pad count). Claimed a new 200-slot SKU block (SKU-162387-162586) and minted 12 new taxonomy entries (SKU-162387-SKU-162398: 3 Innisfree Duo splits, 1 ROUND LAB Duo split, 6 Jorubi size/pack splits, 2 Torriden mini-size splits), rerouting 13 product_taxonomy_map rows off their prior shared base entries onto the new precise entries - all meta_agent='CLAUDE_CODE'. Every content-changed existing entry had _meta reset to unreviewed per STEP 4; every genuinely Tier-2-judged-correct entry (32) and every STEP-1C-clean entry (101) bulk-promoted via one _meta UPDATE each per STEP 5 semantics. Confidence distribution left behind (whole category): 58 confident, 274 unconfident, 3,501 unreviewed. Hard gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0, G3 (placeholder-leak)=0, G4 (cross-category, all 6 claimed blocks including the new 162387-162586)=0, G5 (provenance)=0, structured-fields-missing%=0%, garbled-brand-text=3 (all the single known BRD-SG-06260 '1.618' exception, already recorded, not re-verified). All gates pass. Remaining backlog for a follow-up: ~215 wrong_field_order BRD-UNDEFINED rows with no confident brand match found this pass; ~850 long-tail null_size entries below this session's GMV cutoff; the Skin1004 Toning Toner (42 products) and Beauty of Joseon Dynasty Cream (2 products) genuine multi-size listings spotted opportunistically but not yet decomposed. Universe refresh not run this session (out of scope per task instructions). |
| 2026-07-24 11:36 UTC | Automated review session (auto-discovery) | STEP 1 worklist: 3,775 distinct taxonomy entries (never-reviewed or previously-unconfident). Pre-fix qa_report.sh showed 1 FAILing entry-level gate: canonical_name fields (1 hit, SKU-122391 — product_line had a marketing-description tail leaked in, 'Hydration, SOS Care, Sensitive Skin Facial Mask', instead of just the real on-package line 'Medical Repair Face Mask'; confirmed via sku_name text). garbled brand text (BRD-SG-06260 '1.618') already had a confirmed qa_gate_exceptions row from prior sessions, correctly skipped rather than re-verified. STEP 1C fast-lane recheck on the 278-row 'fixed pending recheck' bucket: 18 genuinely Tier-1-clean, bulk-promoted directly; 260 still flagged (200 wrong_field_order, all BRD-UNDEFINED — bulk brand_dict prefix-match found only generic-word false positives from other-market brand_dicts, e.g. 'Fres'/'Collagen'/'Moist', no genuine repoints; 125 null_size, left for the worklist-wide sweep; 3 duplicate_brand, already-known Sisley/Babor/NOWNESS false positives). STEP 2 Tier-1 sweep on the remaining 3,775 rows flagged: wrong_field_order=215 (same BRD-UNDEFINED pattern, re-checked via bulk brand_dict match, no genuine matches beyond noise words — left untouched), null_size=862, duplicate_brand=3 (same 3 confirmed false positives), excess_content=1 (SKU-144433 Lassie Manna '25ml+10g', genuine 2-component kit, false positive), garbage_brand=3 (all the same confirmed BRD-SG-06260 '1.618' exception). GMV-prioritized Tier-2 sample on null_size (top ~15 by GMV, month 2026-06, product-grain): image-verified via curl-to-tmp-then-Read — 3 genuine misses fixed (2 Biodance Real Deep Mask entries missing '34g' per-sheet size visible on packaging; CeraVe Moisturising Lotion Twin Pack missing '473ml' per-bottle size). 3 confirmed genuinely unresolvable (medicube Triple Collagen Toner/Serum 3.0 marketing hero shot with no legible size; MENOKIN 30 Seconds Bubble Mask 5-flavor hero shot, no legible size; CENTELLIAN 24 Brand Box Kit, a 2-product kit — matches this file's own documented deferred-kit precedent). Also found via sku_name '[REJURAN]' bracket tag: SKU-122077 'Advanced PDRN Pore Care Duo' was mapped to BRD-UNDEFINED despite Rejuran being a real, in-scope brand (BRD-GLOBAL-00335, rank 9 in this file's own Brand Scope table) — repointed. STEP 2b (pack_count=1 + promo language): 930 hits, 816 after excluding 'XXX-free' cosmetic-claim false positives (paraben-free, oil-free, etc. — same known class as the documented 'FREEZE-DRIED' substring match). GMV-prioritized top 40 reviewed: found 2 genuine pack-count/text-decomposition misses — SKU-143394 Mediheal Wrapping Serum Mask had garbled '* *' placeholder text (from an unstripped '*NEW*' marketing marker) in product_line/canonical_name and pack_count=1 despite sku_name stating 'Box 10S' (10 sheets); SKU-143361 Eau Thermale Avène Thermal Spring Water had pack_count=1 despite canonical_name itself stating 'Triple pack 3 x 50ml'. Most other hits (dominant pattern: Innisfree 'BUY 1 GIFT N' listings) correctly confirmed as GWP (different free gift, not a multipack) per llm-extraction-rules.md §1 — pack_count=1 is correct, no fix. STEP 3 Tier-2 GMV-prioritized sample of 25 Tier-1-clean high-GMV entries (mostly Lassie Manna, cross-checked against sku_name text): found and fixed 2 more defects — SKU-122140 Dr.G Red Blemish Clear Soothing Cream was a genuine multi-size seller listing (sku_name lists 4 different size/format options) incorrectly stored as a single garbled 70ml entry — converted to is_multi_size=TRUE; SKU-143202 Beauty of Joseon Dynasty Cream, a genuine 50ml/100ml multi-size listing flagged as remaining backlog by the prior session, converted to is_multi_size=TRUE (closes that backlog item). Also found SKU-122064 Skin1004 Madagascar Centella Variety Mask Set had a canonical_name truncated mid-sentence (cut off after 'Clarifying Mask 5ea +') — completed from the full sku_name text. 22 other Tier-1-clean high-GMV entries (Lassie Manna, ROUND LAB, La Roche-Posay, Innisfree, medicube) cross-checked and confirmed correct as-is. | Fixed in place (no new taxonomy entries minted, no rows deleted, no map rows inserted/rerouted): SKU-122391 (product_line marketing-tail trim), SKU-122077 (brand_id BRD-UNDEFINED->Rejuran BRD-GLOBAL-00335 + canonical_name), SKU-074029 + SKU-074031 (Biodance size backfill, 34g, image-verified), SKU-122078 (CeraVe size backfill, 473ml, image-verified), SKU-143394 (text cleanup + pack_count 1->10), SKU-143361 (pack_count 1->3 + canonical_name reformatted to x{TOTAL} convention), SKU-122140 (converted to is_multi_size=TRUE for a genuine multi-option listing), SKU-143202 (converted to is_multi_size=TRUE, closes a documented backlog item), SKU-122064 (completed a truncated canonical_name). 10 taxonomy entries fixed total, all meta_agent='CLAUDE_CODE', all _meta reset to unreviewed per STEP 4. 18 STEP-1C fast-lane rows + 41 genuinely Tier-2-judged-correct rows bulk-promoted via two _meta UPDATEs per STEP 5 semantics. No new qa_gate_exceptions row needed (the one pre-existing entry, garbled brand text/BRD-SG-06260, was already confirmed twice by prior sessions and correctly skipped, not re-verified). Confidence distribution left behind (whole category, distinct taxonomy_ids): 86 confident, 276 unconfident, 3,471 unreviewed (total 3,833). Hard gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0, G3 (placeholder-leak)=0, G4 (cross-category, all 6 claimed blocks 74001-76000/122056-124555/133646-133845/134332-134531/143193-145013/162387-162586)=0, G5 (structured-fields-missing%)=0%, canonical_name fields=0, garbled brand text=0 (excl. confirmed exception). All gates pass. Remaining backlog for a follow-up: 215 wrong_field_order BRD-UNDEFINED rows with no confident brand match found this pass (unchanged from prior sessions' documented finding); ~859 remaining null_size entries below this session's GMV cutoff (long-tail); 3 duplicate_brand + 1 excess_content + 3 garbage_brand rows are all confirmed recurring false positives (Sisley/Babor/NOWNESS substring matches, Lassie Manna 2-component kit, BRD-SG-06260 '1.618' numeric brand) — stable across at least 5 sessions now, could be worth a qa_gate_exceptions entry for duplicate_brand's 2 stable false positives (Sisley/Babor) if a Tier-1-sweep-level exception mechanism is ever added for that flag. Universe refresh not run this session (out of scope per task instructions). |
| 2026-07-24 13:16 UTC | Automated review session (auto-discovery) | STEP 1B's given pre-fix gate report (all-PASS) was independently re-verified against live BigQuery rather than trusted blindly, since every prior QA History entry for this category showed G2 (HUMAN+LLM coexistence) stuck at 794 — confirmed genuinely 0 now (all 6,447 HUMAN rows for this table are gone; the wrapper's narrowly-scoped cleanup evidently ran between the 2026-07-23 session and today). STEP 1C fast-lane sweep on the 267 'fixed pending recheck' rows found only 8 genuinely Tier-1-clean (promoted); the other 259 are mostly BRD-UNDEFINED/null_size mints from the earlier NULL-coverage top-up, correctly left untouched. STEP 2's full Tier-1 sweep (3,747-row worklist) flagged 1,009 rows: null_size=859, wrong_field_order=214 (100% BRD-UNDEFINED, no unambiguous new brand_dict matches beyond known generic-word noise — same conclusion as every prior session), garbage_brand=3 ("1.618", confirmed false positive a second time, already has a qa_gate_exceptions row from an earlier same-day run), duplicate_brand=3 (2 false positives — "Sisleya"/"Doctor Babor" are genuine on-package sub-line names containing the brand word; 1 already-deferred genuine defect, NOWNESS, unchanged), excess_content=1 (false positive, legitimate 2-component kit weight). Beyond the standard Tier-1 checklist, this session found two systemic defect classes never previously caught: (1) 200 entries carried a stray empty-parenthesis artifact ("()"/"( )") from a broken canonical_name template substitution; (2) 43 entries had the reseller name "COCOMO" (from "COCOMO Official Store") baked into canonical_name — a genuine docs/llm-extraction-rules.md §11 signal-provenance violation — plus 2 more one-off cases (a seller's own "- Beureka"/"- MeowCat" self-branding surviving from sku_name into canonical_name). STEP 2b's promo-language sweep (321 hits, mostly 'X-Free' cosmetic-claim false positives) surfaced 12 genuine pack_count/multiplier misses (1+1, Buy-1-Get-1, xNpcs patterns never reflected in the pack_count column), plus a separate double-counted-multiplier bug ("2 x 300ml x2") on 2 Eau Thermale Avène entries found during the Tier-2 GMV-prioritized clean-sample cross-check. Tier-2 image verification (curl-to-tmp-then-Read) on the top 15 highest-GMV null_size entries confirmed 5 genuine misses (medicube PDRN mist 100ml; medicube Color-Changing Jelly Mask Set 28g x8; a Jiyu toner-pad jar reading '100 PADS', requiring a new brand_dict entry since 'Jiyu' didn't exist yet; VT Cosmetics Daily Soothing Mask '30 sheets' from box text; medicube BEST Mask Sheet Collection correctly re-flagged is_multi_size+is_multi_variant given genuinely mixed per-sheet weights) — the other 10 had no visible size text in the product image and were left deferred, not guessed. | Fixed and committed via bq DML, all meta_agent='CLAUDE_CODE': 5 image-verified size/variant fixes, 2 double-multiplier canonical_name fixes, 200-row bulk empty-parenthesis cleanup, 43-row bulk COCOMO merchant-name-leak cleanup, 4 individual reseller-name/marketing-junk suffix fixes, 12 pack_count/multiplier fixes from the promo-language sweep, and 1 new brand_dict entry (BRD-SG-14371 'Jiyu'). 234 distinct taxonomy_id rows received a real content fix this session; 8 rows promoted confident via STEP 1C; 27 rows bulk-marked via STEP 5 as Tier-2-confirmed-correct (3 of which — the '1.618' garbage_brand false positives — reached confident on a second agreeing review). Deferred, documented, not fixed: ~200 remaining wrong_field_order BRD-UNDEFINED rows (no identifiable brand beyond known noise-word collisions), ~850 remaining null_size long-tail rows (GMV budget exhausted before reaching them), and a handful of genuinely ambiguous multi-product kits/listings (Rejuran Advanced PDRN Pore Care Duo, Centellian24 Brand Box, Lancôme 400ml+50mlx8pcs Value Set, Mamonde 'Random Package' multi-size ambiguity, an Illiyoon multi-product-merged listing, a Cyber Colors nested-multiplier listing, and the already-known NOWNESS garbled 3-product listing). Final confidence distribution (whole category): 1,186 confident, 668 unconfident, 4,113 unreviewed. Universe refresh not run (out of scope per task instructions). |
| 2026-07-24 15:51 UTC | Automated review session (auto-discovery) | Pre-run gate report showed canonical_name fields FAILING at 208 (all others passing). Root-caused: 197/208 had a literal '()'/'( )' empty-placeholder token in product_line (unfilled sub_line/variant template slot), ~45 of those also carried a leaked reseller-name suffix ('- COCOMO'/'- Retailer'/'- Beureka'/'- MeowCat', a §11 signal-provenance defect canonical_name correctly omitted). 9 heterogeneous outliers had malformed pack-count placeholders or a curly-apostrophe Unicode mismatch. STEP1C fast-lane reconfirmed 197 previously-fixed-pending-recheck rows as Tier-1-clean, bulk-promoted. Full-worklist Tier-1 sweep (3,737 rows) found: stub_leak=0, duplicate_brand=3 (all confirmed false positives - Sisley/Sisleya substring, Babor/'Doctor Babor' real sub-line, NOWNESS already-documented garbled multi-product listing), wrong_field_order=215 (213 BRD-UNDEFINED-with-stated-brand candidates - bulk brand_dict prefix-match surfaced only generic-word false positives (Korea/Korean/Collagen/Retinol/Gold/Mask/etc, a much broader noise-brand pattern than the 6 previously documented) except 18 genuine 'Fresh' brand products (Rose Deep Hydration/Black Tea/Lotus Youth Preserve lines, sold via Sasa/Beautyhaus SG at matching authentic sizing) plus one outright wrong brand_id (La Meriel to La Mer, product_id 42269025494)), brand_casing_mismatch=2 (LUMIN/Wollyo, canonical_name was the outlier vs brand_dict+siblings, not the reverse), excess_content=0, canonical_field_mismatch=0, null_size=852 (GMV-prioritized top 7 image/product_specification-verified: 2 backfilled from spec (IEM 50g, medicube Triple Deep Erasing Cream 50ml), 3 flagged is_multi_variant=TRUE (Menokin 30 Seconds Bubble Mask 6-formula selector, TheFaceShop Real Nature 15-flavor sheet mask 30g/sheet, medicube Triple Collagen Toner/Serum/Duo-Set selector), 2 confirmed genuinely unresolvable across all 4 signal sources - Lassie Manna Niu Niu Face Cream ($113,886/mo, no size in sku_name/image/spec/description) and Monday Museum Toner Pads Trio (3-product kit, no single size applies) - remaining ~845 are long-tail, deferred per GMV-impact triage), garbage_brand=0. G2 (HUMAN+LLM coexistence) is now 0, down from 794 documented in every prior session on this category - the wrapper-side narrowly-scoped HUMAN cleanup evidently ran between sessions, not something this session did. Found an undocumented FAILED_QA SKU block (SKU-162387-162586, claimed and failed 2026-07-24 today, 12 live CLAUDE_CODE taxonomy entries e.g. SKU-162387 'Innisfree Super Volcanic Pore Clay Mask 80g x2') with no corresponding QA History entry in this file - a gap in the session record from a run this session has no other trace of; flagged for human review, not touched (never delete existing rows). | Fixed via bulk SQL (2 statements for the paren/suffix defect class, 1 for the 9 outliers, 1 correction pass for 2 over-stripped tokens), 2 brand-casing corrections, 1 brand_id repoint, 18 brand_id+canonical_name fixes (Fresh), 5 null_size/is_multi_variant fixes - all with meta_agent='CLAUDE_CODE' and _meta reset to unreviewed in the same statements. 197 STEP1C rows and 5 Tier-2-confirmed-correct rows (Lassie Manna, Monday Museum Trio, and the 3 duplicate_brand false positives) bulk-promoted via STEP5 semantics. Final hard-gate self-check (no --skip-coexistence): G1=0, G2=0, G3=0, structured_fields_missing_pct=0%, G4=0 (verified against the complete 7-block sku_block_registry list including the previously-untracked 143193-145013 and 162387-162586 ranges), G5=0, garbled-brand-text=0, canonical_name fields=0 - all gates pass. Confidence distribution left behind: 99 confident, 475 unconfident, 271 fixed_pending_recheck, 2,988 unreviewed. Universe refresh not run this session (out of scope). |
| 2026-07-24 17:45 UTC | Automated review session (auto-discovery) | STEP1B pre-fix gate report independently re-verified against live BQ (all match: G1/G2/G3/dup-checks=0). STEP1C fast-lane on 271 'fixed pending recheck' rows: only 5 Tier-1-clean, bulk-promoted; other 266 remain dirty (mostly BRD-UNDEFINED null_size/wrong_field_order long-tail), left untouched per instructions. Full-worklist Tier1 sweep (3,735 rows): null_size=847, wrong_field_order=196 (195 BRD-UNDEFINED + 1 brand_dict PK-duplication artifact), brand_casing_mismatch=18, duplicate_brand=1, stub_leak/excess_content/canonical_field_mismatch/garbage_brand=0. brand_casing_mismatch traced to a leftover defect from a prior session's brand_id fix: 18 'Fresh' brand entries had canonical_name literally starting 'fresh Fresh ...' (product_line was already correct, only canonical_name text carried the stray duplicate). duplicate_brand=1 is the already-documented NOWNESS garbled 3-product listing, unchanged. wrong_field_order's 195 BRD-UNDEFINED rows re-checked via bulk word-boundary brand_dict prefix-match — no genuine new matches, only known noise-word false positives (Bloom/Yellow/Gardenia/Rosemary/Colla/kore/Moist/Clear/mela/BIRCH/etc.), same conclusion as every prior session on this category. The 1 non-BRD-UNDEFINED wrong_field_order hit (SKU-122081, brand shown as 'Yasenshi') traced to a genuine brand_dict data-integrity bug: BRD-SG-14371 has two duplicate-PK rows with different canonical_name ('Jiyu' created 2026-07-24 13:03:48, 'Yasenshi' created 42s later at 13:04:30) — same defect class as the previously-documented BRD-GLOBAL-03765 cluster, likely a race condition on brand_id assignment between two near-simultaneous sessions; the taxonomy entry's own canonical_name ('Jiyu...') is correct, the JOIN fan-out is what caused the false flag. STEP2b promo-language sweep (719 hits) found a real, previously-uncaught D5 class: 12 GMV-significant 'Buy N Get M'/'1+1'/genuine-xN-separate-units rows where pack_count was never updated despite explicit multiplier text (mamaearth Aloe Vera Gel Buy-2-Get-1, Bioaqua/Darphin/SADOER Buy-1-Get-1, Real Barrier 1+1, Bioderma/DPPR/Eau Thermale Avène/Cetaphil/Loshi(x2 entries)/Lucas Papaw xN-separate-unit sets) — distinguished from a much larger false-positive class where 'xN sheets/pads/pcs' in canonical_name describes sheet-count-within-one-box (this category's established size-field convention, e.g. Torriden '10 sheets', medicube '70pads') rather than a genuine pack multiplier; also found and deferred (not forced) SKU-143996 Eau Thermale Avène Packset mixing two different sizes (300ml x3 + 50ml x1) which can't be expressed as one pack_count, and SKU-123242 Neogence Buy-1-Get-1 across a 3-series listing where the free item may be a different variant (ambiguous, not fixed). Tier-2 GMV-prioritized null_size sample (top ~25 of 847 by GMV, sku_name+image since raw_niq_history is unavailable in this project — checked both asia-southeast1 and US, dataset does not exist, a real environment gap vs the documented priority chain): found 7 genuine misses where sku_name or image stated a size never extracted (CeraVe PM 89ml, TRUU PDRN mask 120g, Monday Museum pad 170ml+60 sheets, VT Cosmetics mist 120ml, medicube PDRN mask 28g, Lassie Manna soak pads 60pcs, Neutrogena Hydro Boost 50g); confirmed 8 more as genuinely unresolvable at available signal (medicube Triple Collagen Toner/Serum duo-kit, Mirae Ex8 4-variant box, medicube AGE-R/Hyaluronic Jelly capsule-jar labels obscured by marketing text, Lassie Manna Silk Mask sachet text illegible, MENOKIN Bubble Mask genuine 6-formula multi-variant selector, medicube Deep Vitamin C capsule cream, Cerave AM lotion — none previously given a _meta review stamp despite some being documented in prose since the category's first session); reconfirmed 3 already-unconfident+correct entries a second time (Lassie Manna Niu Niu Face Cream $113,886/mo, Monday Museum Toner Pad Trio, CENTELLIAN24 Brand Box Kit), promoting them to confident. Also confirmed via image: SKU-122091 'Whoopzie Hydra Body Brightening Spray' is a genuine body-care product (100ml, label reads 'BODY SPRAY'), not facial — scope contamination this session cannot fix since remediation would require deleting or rerouting the existing product_taxonomy_map row, prohibited by this scenario's rules. | Fixed via bq DML, all meta_agent='CLAUDE_CODE': 18-row bulk fix for the 'fresh Fresh' duplicate-brand-word canonical_name defect; 7 image/text-verified size backfills; 12 pack_count/multiplier fixes (Buy-N-Get-M and genuine xN-separate-unit patterns) with matching canonical_name updates. 5 rows bulk-promoted via STEP1C (Tier-1-clean fixed-pending-recheck). 11 rows given genuine Tier-2 judgment and bulk-marked via STEP5: 3 reached confident on a second agreeing correct verdict (Lassie Manna Niu Niu, Monday Museum Trio, CENTELLIAN24 Brand Box), 8 landed on unconfident as first-ever reviews of previously-undocumented-in-_meta entries. Deferred, documented, not fixed: ~830 remaining null_size and ~195 wrong_field_order (BRD-UNDEFINED, no identifiable brand beyond known noise-word collisions) long-tail rows, GMV budget exhausted before reaching them; a brand_dict PK-duplication bug on BRD-SG-14371 (Jiyu/Yasenshi) flagged for a brand_dict-focused session; SKU-122091 Whoopzie body-spray scope contamination flagged for a deletion-authorized session; the missing raw_niq_history dataset flagged as an environment gap limiting this and future sessions' size/pack signal chain to sku_name+image only. Final confidence distribution (whole category): 1,191 confident, 972 unconfident, 317 fixed_pending_recheck, 3,487 unreviewed. Hard gate self-check (no --skip-coexistence): G1=0, G2=0, G3=0, structured-fields-NULL%=0%, G5=0 — all pass. Universe refresh not run this session (out of scope per task instructions). |
| 2026-07-24 18:19 UTC | Automated review session (auto-discovery) | STEP 1B pre-fix qa_report.sh showed 1 FAILing entry-level gate: canonical_name fields (11 hits), all others PASS. All 11 traced to promo/marketing/pack-fragment text leaked into product_line while canonical_name itself was already clean (e.g. SKU-122856 product_line '🔥🔥Buy 1 Get 1 Free SADOER Blackhead Removal Mask...Remov' vs correct canonical 'SADOER Blackhead Removal Mask...60g x2'; SKU-124157 'Lucas Papaw x Shopee Brand Box - Ointment Bottle x 3pcs'). qa_gate_exceptions already had one confirmed entry (garbled brand text / BRD-SG-06260 '1.618'), correctly skipped rather than re-verified. STEP 1C fast-lane recheck on the 281-row 'fixed pending recheck' bucket found 32 genuinely Tier-1-clean, bulk-promoted; the other 249 remain dirty. STEP 2 full-worklist Tier-1 sweep (3,732 rows) flagged: null_size=837, wrong_field_order=199, duplicate_brand=1 (stub_leak/brand_casing_mismatch/excess_content/canonical_field_mismatch/garbage_brand all 0, already resolved by prior sessions). wrong_field_order: 195 BRD-UNDEFINED (no genuine new brand_dict matches beyond known noise words, same conclusion as every prior session) + 1 already-documented brand_dict PK-duplication false positive (SKU-122081/'Yasenshi') + 3 genuine hits: SKU-122856 and SKU-122833 had brand_id mismapped to unrelated real brands ('Bamboo', 'LAIKOU') despite canonical_name correctly stating 'SADOER'/'Bioaqua' (both of which have their own brand_dict entries, BRD-GLOBAL-00488/BRD-GLOBAL-01482) — repointed brand_id to match; SKU-124157 brand_id was already correct ('Lucas' Papaw') but canonical_name was missing the apostrophe — corrected the text instead of brand_id. duplicate_brand's 1 hit is the already-documented NOWNESS garbled multi-product listing, confirmed again, left untouched. STEP 2b promo-language sweep (454 hits, mostly 'X-Free' cosmetic-claim and single free-gift/free-shipping false positives) surfaced 3 genuine D5 misses: Seyoul Collagen Jelly Mask ('BUY 3 FREE 2' → pack_count 5, was 1), Neogence Aqua Burst ('[BUY 1 GET 1]' → pack_count 2, was 1), HEXKIN Collagen Mask Bundle ('Buy 3 Get 1 Free' across 3 distinct flavors → pack_count 4, is_multi_variant=TRUE; canonical_name was also truncated mid-sentence at 106 chars, completed from full sku_name). GMV-prioritized null_size sample (top 8 by GMV, image-verified via curl-to-tmp-then-Read) surfaced a new systemic defect never previously caught: 6 Mediheal/GIK entries (SKU-143241, 122724, 143407, 143795, 143922, 143494) carried a literal unfilled '* *' template placeholder in both canonical_name and product_line (a mis-parse of the sku_name '*NEW*' marketing badge) — 3 of the 6 are genuine multi-formula selectors per bracketed sku_name option lists and were flagged is_multi_variant=TRUE. Remaining top-GMV null_size entries (medicube Deep Vitamin C Golden Capsule Face Moisturizer, Triple Collagen Toner/Serum 3.0, OZIO Royal Jelly Mocchiri Gel EX, Rejuran Advanced PDRN Pore Care Duo, medicube PDRN Pink Peptide Cream, medicube AGE-R Glutathione Glow Capsule Cream) confirmed genuinely unresolvable — marketing hero shots with no legible size text, consistent with this exact product family's repeated 'confirmed unresolvable' verdict across multiple prior sessions. STEP 3 Tier-2 GMV-prioritized sample of the top 25 highest-GMV Tier-1-clean entries (Lassie Manna, Torriden, medicube, Biodance, Dr. Althea, Aestura, CENTELLIAN 24 — all previously vision-verified in earlier sessions) reconfirmed correct: on-type, structurally complete, no product-type conflicts. | Fixed 23 taxonomy entries total via bulk SQL: 11 canonical_name-fields-gate rows (stripped promo/pack-fragment text from product_line), 3 brand_id/text corrections (2 brand_id repoints to Sadoer/Bioaqua, 1 apostrophe fix for Lucas' Papaw), 6 '* *' placeholder-artifact entries (cleaned canonical_name/product_line, 3 flagged is_multi_variant=TRUE), 3 pack_count corrections (Buy-N-Get-M promo language, one with a previously-truncated canonical_name completed). All fixed rows had _meta reset to unreviewed and meta_agent='CLAUDE_CODE'. Bulk-promoted 32 rows via STEP 1C fast-lane (Tier-1-clean on recheck) and 25 rows via STEP 3 Tier-2 confirmed-correct sample — both via single bulk _meta UPDATE statements per the confidence-promotion formula. Post-fix qa_report.sh: all 9 gates now PASS, including canonical_name fields (11→0), the one gate that was RED at session start. qa_coverage_report.sh: 3,731/3,833 (97%) still pending across future sessions (2,956 never-reviewed, 258 fixed-pending-recheck, 517 unconfident, 102 confident) — expected long-tail continuation, not a regression. No new taxonomy entries minted, no SKU block claimed. |
| 2026-07-24 19:09 UTC | Automated review session (auto-discovery) | STEP 1 worklist: 3,731 distinct taxonomy entries (never-reviewed or previously-unconfident). STEP 1B pre-fix qa_report.sh showed all gates PASS. STEP 1C fast-lane recheck on the 258-row 'fixed pending recheck' bucket: only 6 genuinely Tier-1-clean, bulk-promoted. Full-worklist Tier-1 sweep flagged: null_size=836, wrong_field_order=196, duplicate_brand=1 (NOWNESS, already-documented recurring false positive, confirmed again, left untouched), brand_casing_mismatch=1 (SKU-122856 'SADOER' vs all 6 sibling entries' proper-cased 'Sadoer' — confirmed outlier, fixed). wrong_field_order: 195 BRD-UNDEFINED (bulk brand_dict word-boundary match found only known-class generic-word noise, same conclusion as every prior session — no genuine new brand identifiable) + 1 already-documented brand_dict PK-duplication artifact (Jiyu/Yasenshi). Two new systemic defect classes found, neither previously caught: (1) 20 entries had a pad/piece count explicitly stated in sku_name via a 'NP'/'N Pc(s)/Box' pattern (e.g. 'JUNGSAEMMOOL...(5P)', '(5Pc/Box) Dr Jart...') that was never captured into size — fixed via text alone, no image reads needed; 2 of these also required a genuine brand_id repoint (SKU-124392 'BIOAOUA' → the clean pre-existing BRD-GLOBAL-01482 'Bioaqua', since brand_dict's own BRD-GLOBAL-01283 'BIOAOUA' is itself a garbled duplicate). (2) 16 more Dr.Jart entries carried a duplicated 'Dr.Jart Dr Jart' brand prefix in both canonical_name and product_line (on top of 1 already found and fixed via the pad-count sweep, SKU-143278) — bulk-fixed via REGEXP_REPLACE. STEP 2b (pack_count=1 + promo language, GMV-prioritized): confirmed the dominant 'X-Free' cosmetic-claim and 'BUY 1 GIFT N' (genuine GWP) false-positive classes already documented by prior sessions; found and fixed 9 genuine multipack misses where canonical_name/sku_name already stated 'Bundle of N'/'x2'/'Twin Set' but pack_count was never updated (QV Moisturizing Cream x2, QV Intensive Cream x2, Kiehl's Ultra Facial Gel Cream x2, 2 Illiyoon Ceramide products x2, Curel Intensive Moisture Cream x3, Aprilskin Toner Pad Twin Set x2, Nature Republic Soothing Gel x3 — the last one's canonical_name already said '(Bundle of 3)' as free text but pack_count stayed 1, reformatted to the x{TOTAL} convention); also fixed ARENCIA Holy Hyssop Sheet Mask ('5ea * 2ea(10ea)' in sku_name, only 5ea captured) and a duplicate-brand-text defect on SNATURE (brand_dict casing 'SNATURE' vs canonical_name's inconsistent 'S.NATURE' stylization). STEP 3 Tier-2 GMV-prioritized sample of 40 Tier-1-clean high-GMV entries surfaced 3 more defects text-cross-checked against sku_name: SKU-143213 'Laneige Water Bank Blue Hyaluronic Gel Cream 50ml' conflated two different products under one entry — a dominant duo-bundle listing ('50ml + 50ml', $8,609/mo) and a minor genuine single-unit listing ($418/mo) — split the duo out into a new entry; SKU-143214 'Anua Heartleaf 77% Soothing Toner 150ml' was a genuine multi-size seller listing (same product_id, sku_name states '150ml/250ml/500ml', 3 selectable models) incorrectly stored as a single 150ml entry — converted to is_multi_size=TRUE; SKU-143203 'The Face Shop THEFACESHOP Real Nature Mask' had the brand duplicated in both canonical_name and product_line, same class as the Dr.Jart defect — fixed. Also found and consolidated a duplicate-entry pair: SKU-143264 'Innisfree Forest 100ml' (truncated product_line, 4 mapped products) and SKU-074122 'Innisfree Forest For Men Anti-Aging All-In-One Essence 100ml' (7 mapped products) were the same real product — rerouted SKU-143264's map rows onto SKU-074122, left SKU-143264 orphaned (not deleted, per this scenario's rules). Self-caught regression: two of this session's own null_size fixes initially reused the now-banned 'Multiple Sizes' canonical_name phrasing (llm-extraction-rules.md, banned 2026-07-22) — caught by re-running the Tier-1 sweep after applying fixes, corrected before finalizing. 14 further high-GMV Tier-1-clean entries (Skin1004 Variety Mask Set, IEM, Cerave PM, Ceradan x2, Shiseido, Klairs, 2 Torriden, Skin1004 Clay Stick, Aestura, Laneige Perfect Renew, Biodance) cross-checked against sku_name and confirmed correct as-is. | Fixed via bq DML, all meta_agent='CLAUDE_CODE', _meta reset to unreviewed on every content-changed row per STEP 4: 1 brand-casing fix (Sadoer), 20 pad/piece-count size backfills (2 of which also required a brand_id repoint off a garbled brand_dict duplicate), 17 Dr.Jart duplicate-brand-text cleanups (canonical_name + product_line), 9 genuine pack_count corrections (bundle/twin/multiplier language already present in text but never reflected in the pack_count column), 1 duplicate-brand-text fix (SNATURE), 1 duplicate-brand-text fix (The Face Shop), 1 is_multi_size correction (Anua, genuine 3-size seller listing), 1 entry split (Laneige duo bundle vs single-unit conflation — minted SKU-144452 within the pre-existing ACTIVE block, no new SKU block claimed since one was already active and unexhausted) with 1 product_taxonomy_map row rerouted, 1 duplicate-taxonomy-entry consolidation (Innisfree Forest for Men, 4 map rows rerouted onto the fuller pre-existing entry). ~56 distinct taxonomy_ids received a real content/structural fix this session. 6 STEP 1C fast-lane rows and 14 genuinely Tier-2-judged-correct rows bulk-promoted via _meta UPDATEs per STEP 5 semantics. Confidence distribution left behind (whole category, distinct taxonomy_ids joined via product_taxonomy_map): 116 confident, 506 unconfident, 303 fixed_pending_recheck, 2,908 unreviewed (total 3,833). Hard gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0, G3 (placeholder-leak)=0, structured-fields-missing%=0%, G5 (provenance)=0 — all pass, re-verified after every fix including the two self-caught 'Multiple Sizes' regressions. Remaining backlog for a follow-up, unchanged in character from prior sessions: ~195 wrong_field_order BRD-UNDEFINED rows with no confident brand match found this pass (bulk brand_dict word-boundary match repeatedly finds only generic-word noise); ~811 remaining null_size long-tail entries below this session's GMV cutoff; 1 duplicate_brand false positive (NOWNESS, garbled 3-product listing, recurring and stable across many sessions now — may be worth a Tier-1-level exception mechanism if one is ever added for that flag class, no such mechanism exists today since qa_gate_exceptions is scoped to the specific STEP 1B hard-gate list, not general Tier-1 flags). Universe refresh not run this session (out of scope per task instructions). |
| 2026-07-25 02:31 UTC | Automated review session (auto-discovery) | STEP1B pre-fix qa_report.sh (given): all gates PASS. STEP1C fast-lane on the 303-row 'fixed pending recheck' bucket: 44 genuinely Tier-1-clean, bulk-promoted; 259 remain dirty. Full-worklist Tier-1 sweep (3,718 distinct entries): stub_leak=0, brand_casing_mismatch=0, excess_content=0, canonical_field_mismatch=0, garbage_brand=0, duplicate_brand=1 (SKU-124043 NOWNESS garbled multi-product listing, reconfirmed again, unchanged — recurring stable false positive across many sessions, not qa_gate_exceptions-eligible since it's a Tier-1 flag not a STEP1B hard gate), wrong_field_order=195 (194 already-known BRD-UNDEFINED noise-word false positives on bulk brand_dict word-boundary re-check, same conclusion as every prior session, + 1 already-documented BRD-SG-14371 Jiyu/Yasenshi PK-duplication artifact, unchanged) — but this pass's bulk brand-match surfaced 4 GENUINE new hits missed by prior sessions: SKU-122170 (Shiseido), SKU-122172 (numbuzin), SKU-122336 (komfymed, Chinese '可复美' packaging text), SKU-123928 (ZEROID, all-caps on tube) — all BRD-UNDEFINED with a real, identifiable brand stated in canonical_name/sku_name. null_size=811, GMV-prioritized top ~30 sampled (sku_name text + image via curl-to-tmp-then-Read for 18 of them): 9 backfilled from clear text/image (IEM 50g, MIRAE Ex8 mask 5 sheets, Zeroid Intensive Cream 80ml image-confirmed, Skintific Alaska Volcano Stick 40g image, Paula's Choice Moisture Gel 60ml image, medicube Zero Pore Mud Mask 100g image, Sooryehan mask 34g image, Lassie Manna Dermal Resurfacing Mist 50ml image, GLAD2GLOW Moisturizer 30g image), 4 converted to is_multi_size=TRUE (Skin1004 Pore Care Solution 3-component kit, Rejuran PDRN Pore Care Duo 4-component kit, CeraVe Facial Moisturising Set AM+PM 2-product set, Blanc Doux x That Letter M 3-component collab kit — all confirmed via image as genuine differently-sized multi-item kits, not single-size stubs), 2 converted to is_multi_variant=TRUE (Marshique Wrinkle Repair Patches — image confirmed 5 distinct placement/formula types, also had brand_id=BRD-UNDEFINED despite real brand 'Marshique' existing in brand_dict, BRD-GLOBAL-02352, fixed; MENOKIN 30 Seconds Bubble Mask — image confirmed 5 distinct formula variants Moist/Bright/Lift/Repair/Clear). SKU-122108 (Zeroid) also had 'Toppingskids' — a reseller store-name fragment (ToppingsKids Official Store, a documented multi-brand ambiguous store) — leaked into canonical_name/product_line, a §11 signal-provenance violation; stripped. Remaining top-GMV null_size confirmed genuinely unresolvable this pass (marketing hero shots / no size in image, sku_name, or reachable signal — raw_niq_history still unavailable in this project per prior sessions' documented environment gap): the established medicube capsule-cream family (SKU-074013, 143247, 143281, 143260, 143244, 143223 — consistent with 3+ prior sessions' same finding), CeraVe AM Lotion SPF50 (SKU-074144), HEXKIN Collagen Bright Cream Mist (SKU-122114), Beyond Intensive Ampoule Mask 2X (SKU-122107, image revealed '2X' is an ampoule-concentration marketing claim not a pack multiplier, and the entry may conflate 6 flavor variants — deferred, not forced), OZIO Royal Jelly Mocchiri Gel EX/WHITE EX (SKU-122084/122102, no ml visible on either jar image), Mediheal Daily Toner Pad Portable Case (SKU-143294, an accessory case with no volume/size concept), Lassie Manna Porcelain Luminescence Youth Cream and Silk Comfortable Mask (SKU-144435/144451, livestream teaser images with no printed size). STEP2b promo-language sweep (24,834 raw hits across all months, deduped to 676 distinct product×sku_name pairs, 328 distinct taxonomy_ids; most are 'X-Free' cosmetic-claim and free-gift/free-shipping false positives, consistent with every prior session) surfaced 4 genuine fixes: Kelly Oriental Facial Mask (Buy 2 Get 1 Free -> pack_count 3), Klairs Freshly Juiced Toner (Buy 1 Get 1 Free -> pack_count 2, promo-text prefix stripped from canonical_name/product_line), Himalaya Aloe Vera Gel (dominant '[Value Pack] 2 x 300ml + FREE Nourishing Skin Cream' listing -> pack_count 2, malformed empty '(2 x )' placeholder in canonical_name fixed to state the size), and a genuinely garbled entry (SKU-124212) whose brand_id resolved to the nonsense word 'Get' (BRD-TH-01966, itself a text-extraction artifact scraped from the same garbled '💯Buy 2 Get 1 Free 377...' sku_name) -- repointed brand_id to the real '377' brand (BRD-SG-13427, present in brand_dict, matches the sku_name's Chinese product text) and unscrambled canonical_name/product_line; pack_count left at 1 since the promo text is inconsistent across months (not always present) and the multiplier can't be confidently generalized. Deferred as ambiguous, not forced: SKU-074099 (Laneige, a 34-product catch-all conflating plain-50ml singles with a minority 1+1/25ml+25ml promo listing -- needs a proper entry split, out of this session's budget), SKU-074169 (Pyunkang Yul, 12-product catch-all mixing 50ml/100ml 'and'-vs-'or' phrasing, ambiguous whether it's a genuine duo-size bundle or a size selector), SKU-124082 (conflicting 'Buy 1 get 3' vs 'Buy 1 free 2' promo text across the same product's listing history -- can't pick one total confidently), SKU-122457/SKU-124256 (buyer-selectable multi-tier bundle options, matches the established 'N options to select from' false-positive class), SKU-074049 (Rejuran Turnover Mask, sku_name states a genuine 2-box-vs-4-box selector while canonical_name already encodes x2 -- possible conflation, left as-is pending more investigation), SKU-074054 (Rejuran Rebalancing Toner, 17 mapped products, only 1 has an outlier 3-item-kit sku_name -- dominant single-toner identity is correct, minority listing flagged for follow-up), SKU-143306 (medicube Zero Pore Blackhead Mud Mask, image-confirmed 100g and fixed, but one of its mapped sku_name variants is actually a different '3-STEP Deep Clean Set' bundle -- same minority-conflation pattern, flagged not split). SKU-144339 (Neutrogena) reconfirmed as a Tier-1 false positive: its one 'Buy 1 Get 1' Retinol Moisturizer sku_name variant is a stale, zero-GMV, since-abandoned model row from a single March listing -- the canonical_name correctly reflects the real, GMV-bearing 'Ultimate Face & Body Cleansing Set' identity that persisted April-June; left untouched. STEP3 Tier-2 GMV-prioritized sample of 40 Tier-1-clean high-GMV entries cross-checked against sku_name surfaced 2 more genuine defects: SKU-122075 (AweMed, product_line had a stray '3x (R)' prefix mis-extracted as part of the brand/line text when it was actually a pack multiplier -- 'Bundle Deal 3x AweMed Repair+ Daily Moisturiser 250ml' -- fixed to pack_count=3, canonical_name/product_line cleaned) and SKU-143218 (Dr. Althea, canonical_name/product_line had a duplicated brand token 'Dr. Althea Dr.Althea 345 Relief Series' that Tier-1's duplicate_brand regex missed due to a punctuation/spacing mismatch against brand_dict's canonical form -- cleaned to a single brand mention). The other 38 sampled entries (Aestura, Rejuran x2, medicube x2, Torriden x4, Sulwhasoo, PURITO, Cosrx x2, SK-II x2, Dr.Reju-All, Mediheal, The Face Shop, CENTELLIAN 24, Beauty of Joseon [already correctly is_multi_size], Some By Mi, Eau Thermale Avene, Kiehl's x2, Skin1004, Physiogel, Tirtir, Alluora x2, Biodance, Anua, Neutrogena, Dr. Althea 345 mist variant) confirmed correct on-type and structurally complete, no product-type conflicts found. Post-fix self-check surfaced one new instance of the 'garbled brand text' gate (all-numeral brand names, letters-only regex): BRD-SG-13427 '377' -- this session's own newly-assigned brand for SKU-124212, structurally the same false-positive class as the already-exempted BRD-SG-06260 '1.618' (qa_gate_exceptions already covers 1.618 after two prior confirmations) -- this is 377's first confirmation only, not yet exception-eligible, flagged for a second session to close permanently. | Fixed via bq DML, all meta_agent='CLAUDE_CODE', _meta reset to unreviewed on every content-changed row: 4 brand_id repoints off BRD-UNDEFINED onto real brands (Shiseido, numbuzin, komfymed, Zeroid), 1 brand_id + canonical_name/product_line fix for a garbled-brand-artifact entry (377), 4 pack_count/canonical_name fixes from the promo-language sweep (Kelly Oriental x3, Klairs x2, Himalaya x2, plus AweMed x3 from the Tier-2 sample), 9 image/text-confirmed size backfills, 4 is_multi_size=TRUE conversions for genuine multi-item kits, 2 is_multi_variant=TRUE conversions (one paired with a brand_id fix), 1 reseller-name-leak cleanup (Toppingskids), 1 duplicate-brand-text cleanup (Dr. Althea). 25 distinct taxonomy_ids received a real content/structural fix this session. 44 rows bulk-promoted via STEP1C fast-lane (Tier-1-clean on recheck) and 38 rows via STEP3 Tier-2 confirmed-correct sample, both via single bulk _meta UPDATE statements per the confidence-promotion formula. Confidence distribution left behind (whole category, distinct taxonomy_ids joined via product_taxonomy_map): 138 confident, 542 unconfident, 275 fixed_pending_recheck, 2,878 unreviewed (total 3,833). Hard gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0, G3 (placeholder-leak)=0, structured-fields-missing%=0%, G5 (provenance)=0 -- all pass. Entry-level 'garbled brand text' gate = 1 unexempted genuine hit post-fix (BRD-SG-13427 '377', first confirmation of an already-recognized numeral-brand false-positive class, not yet qa_gate_exceptions-eligible) -- flagged, not inserted as an exception this session. Remaining backlog, unchanged in character from prior sessions: ~194 wrong_field_order BRD-UNDEFINED rows with no confident brand match after bulk word-boundary re-check (only known generic-word noise); ~795 remaining null_size long-tail entries below this session's GMV cutoff, including the well-established medicube capsule-cream 'confirmed unresolvable' family; several minority-listing conflation cases flagged for a follow-up with map-row-reroute authority (SKU-074054, SKU-143306, SKU-074099, SKU-074169) since this scenario never deletes/splits existing map rows; the BRD-SG-14371 Jiyu/Yasenshi brand_dict PK-duplication bug (still unresolved, needs a brand_dict-focused session); the missing raw_niq_history dataset (still an environment gap limiting size/pack signal to sku_name+image only). No new taxonomy entries minted, no SKU block claimed. Universe refresh not run this session (out of scope per task instructions). |
| 2026-07-25 02:52 UTC | Automated review session (auto-discovery) | Pre-fix qa_report.sh showed 2 FAILing entry-level gates: canonical_name fields (1 hit: SKU-122863, product_line contained a malformed empty-placeholder fragment '(2 x )' left over from a botched multiplier template) and garbled brand text (1 hit: SKU-124212, brand_id resolved to purely-numeral 'BRD-SG-13427 "377"'). Confirmed via curl-to-tmp-then-Read on the product image that '377' is the on-package product-line/formula number, not the brand -- the real printed brand is 'AOUFSE' (small logo on the jar). STEP 1C fast-lane on the 275-row 'fixed pending recheck' bucket: 16 genuinely Tier-1-clean, bulk-promoted (259 still dirty, left for a future session). Full-worklist Tier-1 sweep (3,696 distinct entries, post-1C): stub_leak=0, duplicate_brand=1, wrong_field_order=194 (189 BRD-UNDEFINED + 5 real-brand text-order issues), brand_casing_mismatch=0, excess_content=1, canonical_field_mismatch=0, null_size=798, garbage_brand=0. duplicate_brand's 1 hit (SKU-124043 'NOWNESS...NOWNESS...') was previously deferred by a prior session as 'multiple merged products' -- re-investigated and found to actually be ONE product_id whose sku_name text changed across 3 month-snapshots, naively concatenated into one garbled canonical_name. excess_content's 1 hit (SKU-122863) is a legitimate false positive (a genuine same-brand GWP bundle). Of the 194 wrong_field_order hits, bulk prefix-match against brand_dict found mostly known false-positive generic-word matches, except one genuine real-brand match (SKU-123102, Klairs) and one brand_dict data-integrity bug: BRD-SG-14371 has a duplicate-PK collision returning two different canonical_name values ('Jiyu' and 'Yasenshi') for the same brand_id. The other 5 non-Undefined wrong_field_order hits were expiry-date/alias/promo-tag prefixes pushed ahead of the brand. STEP 2b found 4 genuine buy-N-get-M pack_count misses and 1 correctly-already-pack_count=1 GWP case. Top-40-by-GMV sample of the 798 null_size entries: all genuinely unresolvable (no size in sku_name or image). | Fixed both pre-existing hard-gate failures plus 1 duplicate-brand garbled name, 6 text-reorder/prefix-contamination cases, 1 real BRD-UNDEFINED-to-Klairs brand repoint, 1 brand_dict duplicate-PK split (new BRD-SG-14375 'Jiyu'), and 2 in-place pack_count corrections. Minted 2 new taxonomy entries (SKU-164187, SKU-164188) via a newly-claimed block, rerouting 2 products off shared multi-product base entries with wrong pack_count. STEP 1C bulk-promoted 16 rows. Confidence distribution: 139 confident, 557 unconfident, 3,139 unreviewed. Post-fix qa_report.sh: all 9 gates PASS (was 2 FAILing at session start). ~795 null_size and ~187 BRD-UNDEFINED wrong_field_order entries remain, GMV-budget-exhausted, left for the next session. Universe refresh not run (out of scope). |
| 2026-07-25 03:57 UTC | Automated review session (auto-discovery) | STEP 1C fast-lane on the 262-row 'fixed pending recheck' bucket: 8 genuinely Tier-1-clean, bulk-promoted (254 still dirty, left for a future session). Full-worklist Tier-1 sweep (3,696 distinct entries, post-1C): stub_leak=0, duplicate_brand=0, wrong_field_order=188 (all BRD-UNDEFINED), brand_casing_mismatch=0, excess_content=1, canonical_field_mismatch=0, null_size=797, garbage_brand=0. Re-verified all 188 wrong_field_order hits via bulk prefix-match against brand_dict (excluding known noise-brand_ids): every match is a generic-English-word false positive (Face/Collagen/Aloe/Glow/Korea/etc. registered as brand_ids) -- no real brand identifiable for any of these, consistent with every prior session's same conclusion; left BRD-UNDEFINED, no fabricated matches. excess_content's 1 hit (SKU-122863, Himalaya GWP bundle) re-confirmed as the same legitimate false positive documented by the prior session. GMV-prioritized Tier 2 (month 2026-06-01, product-grain deduped): top-200-by-GMV worklist entries reviewed -- 17 null_size-flagged plus a further sample of pack_count=1+promo-language hits (STEP 2b, GMV-ordered, cosmetic 'free' claims like Paraben-Free/Oil-Free pre-excluded). curl-to-tmp-then-Read image verification on 15 of the null_size candidates: 13 confirmed genuinely unresolvable (hero/marketing shots with no legible volume text -- medicube capsule-jar family x4, OZIO gel jars x2, MENOKIN bubble-mask set, Lassie Manna tubes x2, CeraVe AM SPF50 lotion, HEXKIN mist, Mediheal empty travel case, Beyond 6-flavor ampoule-mask set), matching this category's own established precedent for capsule/jar-format products. 2 real fixes found via image: SKU-122091 Whoopzie Hydra Body Brightening Spray -- size legible on bottle as '100ml', backfilled (D4 miss). SKU-122110 Marshique Wrinkle Repair Patches (5 types) -- image shows 5 distinct patch products with visibly different unit counts (neck/eye/cheek/forehead patches), no single size applies -- set is_multi_size=TRUE rather than guess a combined count. STEP 2b GMV-prioritized sample surfaced 2 genuine D5 defects: SKU-122275 'Annaiyan...(Upgraded Version, 30g)' sku_name states '(Buy 1 Get 1 Free)' of the SAME product but pack_count was left at 1, with the promo text itself baked into canonical_name -- fixed to pack_count=2, canonical_name restructured to standard format ('...30g x2'). SKU-143397 'SK-II Facial Treatment Mask 10pcs' had 2 mapped products of different actual quantities collapsed onto one entry -- product 21081744520's own sku_name states '(10 pcs x 2 boxes)' = 20 total, was incorrectly sharing the single-box entry with a genuine 10pcs product. Also verified via image that SKU-122667 Dermalogica Stabilizing Repair Cream's 50ml size correctly belongs to the full-size cream (both bottles in the promo image are labeled 1.7fl oz/50ml), not misattributed from the free travel-size cleanser as initially suspected. 4 INNISFREE 'BUY N GET N FREE/GIFT' sku_name variants for SKU-143292 cross-checked -- all genuine GWP (gift items, one variant explicitly '160ML GIFT 90ML' confirming a different smaller size as the freebie), pack_count=1 correctly unchanged. Two other option-list ('X/Xx2pcs') sku_name patterns (Clinique SKU-143272, Kiehl's SKU-143510) reviewed and left at the conservative single-unit default per this category's established Pass-2 precedent for ambiguous option selectors. | Minted 1 new taxonomy entry (SKU-164437 'SK-II Facial Treatment Mask 10pcs x2') via a newly-claimed 200-slot block (SKU-164437-164636, ~199 slots unused for a follow-up), rerouting 1 product_taxonomy_map row off the shared single-box base entry. 3 in-place taxonomy corrections: SKU-122275 (pack_count 1->2, canonical_name/product_line restructured to remove baked-in promo text), SKU-122091 (size backfilled to 100ml), SKU-122110 (is_multi_size set TRUE). All 4 changed rows have meta_agent='CLAUDE_CODE' and _meta reset to unreviewed for next-session re-evaluation. STEP 1C bulk-promoted 8 rows from the fixed-pending-recheck bucket. STEP 5 bulk-promoted 21 additional rows given genuine Tier 2 judgment this session and confirmed correct (13 image-verified genuinely-NULL-size entries, the SK-II base entry post-reroute, Dermalogica, Dr.G multi-size entry, 3 GMV-prioritized option-list/GWP judgment calls, and the excess_content false-positive). Confidence distribution (whole category, deduplicated by taxonomy_id): 149 confident (was 139), 566 unconfident (was 557), 3,121 unreviewed-or-pending (was 3,139; includes 254 rows still dirty in the fast-lane bucket for next session), 3,836 total distinct entries (+1 from the new mint). Post-fix hard-gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0 (this pre-existing gap from prior sessions has resolved, likely via a wrapper-side HUMAN-row cleanup run between sessions -- not this session's own action), G3 (placeholder-leak)=0, structured-fields-NULL%=0% (0 of non-multi-size LLM entries), G4 (cross-category, LLM rows outside this table's own claimed SKU blocks per sku_block_registry)=0 (explicitly re-verified against the full live registry list, not an assumed/approximate range), G5 (provenance)=0. All gates PASS, unchanged from the pre-session baseline reported in STEP 1B. ~188 BRD-UNDEFINED wrong_field_order and ~795 null_size entries remain, genuinely unresolvable or GMV-budget-exhausted, left for the next session. Universe refresh not run (out of scope per task instructions). |
| 2026-07-25 04:16 UTC | Automated review session (auto-discovery) | STEP 1 worklist: 3,687 distinct taxonomy entries (never-reviewed or previously-unconfident). STEP 1C fast-lane recheck on the 254-row 'fixed pending recheck' bucket found only 3 genuinely Tier-1-clean (bulk-promoted); the other 251 remained flagged, overwhelmingly the same persistent wrong_field_order (175, all BRD-UNDEFINED case-b) / null_size (134) pattern documented in every prior session for this category — left untouched, not a regression. STEP 2 Tier-1 sweep on the full worklist flagged: null_size=789, wrong_field_order=197 (all BRD-UNDEFINED), duplicate_brand=2, excess_content=1 (stub_leak/brand_casing_mismatch/canonical_field_mismatch/garbage_brand all 0, already resolved by prior sessions). Investigating the 2 duplicate_brand hits (both Biotherm) surfaced a novel, previously-undetected systemic defect: all 9 Biotherm taxonomy entries mapped to this category had a stray leading Thai character (U+0E3A) prepended to canonical_name plus the brand name duplicated inside product_line (violates llm-extraction-rules.md §3) — only 2 of 9 tripped the case-sensitive regex since the other 7 used all-caps 'BIOTHERM', but all 9 shared the identical defect once case was disregarded. excess_content's 1 hit (Himalaya Dry Skin Moisturizer) had a GWP freebie ('+ FREE Nourishing Skin Cream 150ml') leaked into canonical_name despite size/pack_count already being correct. wrong_field_order: re-ran the established bulk brand_dict prefix-match methodology (excluding the 6 documented noise-brand_ids) — found 0 genuine repoints among 54 candidate matches, all the same class of coincidental generic-English-word brand_id collisions (Face/Collagen/Aloe/Gold/Glow/Whitening/Korean/Retinol/etc.) already confirmed false across 4+ prior sessions; all ~188 BRD-UNDEFINED rows left untouched. null_size: found 4 mechanically-extractable rows where size was already stated in canonical_name/sku_name ('10gm'/'500gm'/'80gm'/'500mll') but never captured to the size column; the remaining ~785 are long-tail, budget-exhausted (consistent with every prior session's documented triage). STEP 2b (pack_count=1 + promo language): 662 hits; GMV-prioritized top ~40 (month 2026-06-01, after excluding cosmetic '-free' claims like Paraben-Free/Fragrance-Free) manually cross-checked against sku_name. Found 2 genuine pack_count misses: SK-II Skinpower Advanced Cream Value Set (sku_name states '15g x 4pcs', taxonomy had pack_count=1) and Kiehl's Super Multi-Corrective Cream, where one of its two mapped products was actually a '75ml x2pcs' bundle silently merged onto the single-pack entry. Also found a second GWP-leak case in the same pass: La Roche-Posay Toleriane Dermallergo entry had '+ Dermo-Cleanser Free' baked into both product_line and canonical_name, and its 'Fluid/Cream/Night' phrasing (consistent across all 5 mapped listings) reads as a genuine 3-way variant selector never flagged as such. 37 further entries (Innisfree singles/mask-sets/twin-packs where 'free'/'x\d' regex hits were false positives on cosmetic claims, GWP, or legitimate sheet/pad-count conventions) were cross-checked against sku_name and confirmed correct via genuine Tier-2 judgment. | Fixed in place (all via bulk or targeted SQL, no rows deleted): (1) 3 fast-lane rows bulk-promoted to confident/unconfident. (2) All 9 Biotherm entries: stray Thai character stripped from canonical_name, duplicated brand token removed from product_line, canonical_name rebuilt — one bulk UPDATE, _meta reset, meta_agent='CLAUDE_CODE'. (3) Himalaya GWP-freebie text stripped from canonical_name. (4) La Roche-Posay Toleriane Dermallergo: GWP-freebie text stripped from product_line/canonical_name, is_multi_variant set TRUE for the genuine Fluid/Cream/Night selector. (5) 4 null_size rows backfilled via mechanical size extraction. (6) SK-II Value Set pack_count corrected 1→4, canonical_name updated to reflect x4. (7) Kiehl's 2-pack split: claimed SKU block SKU-164637-164836 (targeted_qa_fix), minted new entry SKU-164637 ('Kiehl's Super Multi-Corrective Cream 75ml x2', meta_agent=CLAUDE_CODE, source=LLM implied via reroute), rerouted the one mismapped product_taxonomy_map row onto it — original single-pack entry SKU-143510 untouched and still correct for its other product. (8) 37 entries given genuine Tier-2 judgment and confirmed correct this session, bulk-promoted via one _meta UPDATE (some second-time agreements now reaching 'confident'). wrong_field_order and the ~785 remaining null_size rows left untouched/unmarked (no fabricated reviews) — same long-tail/genuinely-unidentifiable conclusion as every prior session. Confidence distribution left behind (distinct taxonomy_ids, whole category): 165 confident, 570 unconfident, 266 fixed-pending-recheck, 2,836 unreviewed (total 3,837 mapped entries). Hard gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0, G3 (placeholder-leak)=0, G4 (cross-category, verified against the full live sku_block_registry rather than a hardcoded block list — found 15 taxonomy_ids in newer SKU-162xxx/164xxx blocks not yet reflected in this file's own QA History, confirmed all legitimately claimed for this master_table, not contamination)=0, G5 (provenance)=0, structured-fields-missing%=0%, 'all variant/size' name=0, garbled brand text=0 net of the pre-existing confirmed qa_gate_exceptions entry (BRD-SG-06260 '1.618', already twice-confirmed by prior sessions, correctly skipped rather than re-verified). All gates pass. Universe refresh not run (out of scope per task instructions). |
| 2026-07-25 13:09 UTC | Automated review session (auto-discovery) | STEP1B pre-fix gates all PASS (matches given report). STEP1C fast-lane on 266-row 'fixed pending recheck' bucket: 16 genuinely Tier-1-clean, bulk-promoted. Full-worklist Tier-1 sweep (3,672 entries): stub_leak/duplicate_brand/brand_casing_mismatch/excess_content/canonical_field_mismatch/garbage_brand all 0 (resolved by prior sessions); wrong_field_order=188 (all BRD-UNDEFINED); null_size=785. Investigated wrong_field_order via bulk brand_dict prefix-match against brands already used elsewhere in this category (not just generic english-word collisions like prior sessions checked): found 4 genuine repoints (IEM x3, SVR x1) missed by earlier passes; remaining ~184 confirmed same coincidental-word-collision false-positive class (Aloe/Mask/Collagen/Korea/etc.) already documented across 4+ prior sessions. null_size: 1 mechanical ml/g extraction + 14 sheet/pad/patch piece-counts backfilled to size + 1 set is_multi_size; remaining ~769 are long-tail with no text-extractable size. STEP2b (pack_count=1 + promo language, GMV-prioritized): found 6 genuine multiplier misses where canonical_name already stated 'xN'/'N sheets'/'N ea' but pack_count was never updated (Kiehl's Cicaplast, La Roche-Posay Cicaplast Masque B5, FAN BEAUTY DIARY, Mediheal Ampoule Mask Box, Abib sheet mask, Cetaphil Instant Radiance Mask). STEP3 Tier-2 GMV-prioritized sample (118 un-flagged rows): found 1 novel defect class — SKU-143259's product_line was 'Shopee x Brand Box', a promo-campaign label copied verbatim from sku_name text instead of the real product identity (the actual product, per sku_name, is Clinique Moisture Surge 100H 100-Hour Auto-Replenishing Hydrator 200ml, 2pcs) — distinct from the merchant_name-leak class in llm-extraction-rules.md §11, this is a sku_name-derived promo label overriding the real product line. Other 117 sampled rows confirmed correct (Tier A: real product line + size + pack_count, no stub). | Fixed in place (all via bulk or targeted SQL, no rows deleted): (1) 16 fast-lane rows bulk-promoted. (2) 4 brand_id repoints (IEM x3, SVR x1), meta_agent=CLAUDE_CODE, _meta reset. (3) 16 null_size backfills (15 to size column, 1 to is_multi_size=TRUE). (4) 6 pack_count corrections with matching canonical_name/product_line cleanup. (5) SKU-143259: product_line corrected from promo-campaign text to real product line, pack_count 1→2, canonical_name rebuilt. (6) 117 Tier-2-judged-correct rows bulk-promoted via one _meta UPDATE. wrong_field_order (~184, all confirmed coincidental brand-word collisions) and remaining null_size (~769, no extractable text) left untouched — same long-tail conclusion as every prior session. Confidence distribution left behind: 219 confident, 594 unconfident, 273 fixed-pending-recheck, 2,751 unreviewed (3,837 total mapped entries). Hard gate self-check (no --skip-coexistence): G1=0, G2=0, G3(placeholder-leak)=0, G5(provenance)=0, structured-fields-missing%=0%, duplicate product_id=0, duplicate product+taxon=0, garbled brand text=0 (net of pre-existing BRD-SG-06260 exception). All gates pass. Universe refresh not run (out of scope per task instructions). |
| 2026-07-25 16:35 UTC | Automated review session (auto-discovery) | STEP1B pre-fix gate 'canonical_name fields' failed on 3 rows (SKU-122499/123004/143885) — the same recurring cosmetic size-format mismatch (size column abbreviated e.g. '50pc' while canonical_name already spelled it out e.g. '50 pieces') documented in prior sessions; no qa_gate_exceptions entry existed, so treated as a genuine fix candidate. STEP1C fast-lane on the 273-row fixed-pending-recheck bucket: 25 genuinely Tier-1-clean, bulk-promoted. STEP2 Tier-1 sweep on the full 3,618-row worklist: wrong_field_order=185, null_size=769, excess_content=1, all others 0 (stub_leak/duplicate_brand/brand_casing_mismatch/canonical_field_mismatch/garbage_brand already resolved by prior sessions). Investigating the excess_content/wrong_field_order hit on SKU-122343 'Lancome...' (missing accent vs brand_dict's 'Lancôme') surfaced a previously-undetected systemic defect class, root-caused via advisor-prompted diagnosis: 6 brands whose canonical_name/product_line had the brand name duplicated in a different case/diacritic/typographic variant right after the correct prefix (e.g. 'Lancôme LANCOME...', "L'Oreal Paris L'OREAL...", 'Estee Lauder ESTEE LAUDER...', 'Eau Thermale Avène AVENE...', 'Clé de peau beaute Cle De Peau...', 'make p:rem MAKE PREM...') — missed by every prior session's duplicate_brand Tier-1 regex because BigQuery's case-insensitive REGEXP_REPLACE/REPLACE does not fold accented characters (confirmed via TO_CODE_POINTS: 'Ô' stored as decomposed 'O'+combining-circumflex, not the precomposed literal), and REPLACE() is exact-match so an unaccented/differently-cased duplicate was invisible to the length-ratio check. A systematic full-category sweep (Python NFC-normalized case-fold comparison of canonical_name's brand-prefix repetition) confirmed these 6 as the only unambiguous, exact full-multi-word-brand duplicates; several other single-word-brand first-word coincidences (Etude/ETUDE, ICM Pharma/ICM, PCA Skin/PCA, Benzac AC/Benzac, WONJIN EFFECT/Wonjin, The Face Shop/The, The History Of Whoo/THE WHOO, Janssen Cosmetics/Janssen, CLEF Skincare/CLEF, Shiseido Professional/Shiseido) were left untouched as genuinely ambiguous (could be legitimate on-package shorthand branding, not a mechanical duplicate). Bulk brand_dict prefix-match against the 184 BRD-UNDEFINED wrong_field_order candidates (103 candidate hits) found zero genuine brand identifications — all coincidental generic-word/ingredient-name collisions (Face, Collagen, White, Korea, Mask, Aloe, Whitening Cream, etc.), consistent with 5+ prior sessions' identical conclusion; correctly left BRD-UNDEFINED, no fabricated matches. null_size GMV-prioritized top 30: skipped the already-multiply-documented-unresolvable medicube capsule/OZIO/Beyond/HEXKIN/Mediheal-case/Lassie-Manna-teaser family; curl-to-tmp-then-Read image-verified 4 fresh medicube/Dr.Jart+ toners/creams (all had printed ml on the bottle label, just never captured) and 1 Lassie Manna mist (60ml, image also revealed the product's real label text 'Revitalize & Replenish' differs from the stored product_line 'Revitalize and Firm' — a genuine product-line drift, not just a missing size). 2 mechanical text-extraction size backfills (piece counts already stated in sku_name/canonical_name but never captured to the size column) and 2 is_multi_size=TRUE conversions for genuine multi-item/multi-option listings (Cetaphil '9 Options' selector, Dr.Jart+ assorted mask+cleanser+sunscreen kit). STEP2b promo-language sweep (GMV top 25, after excluding 'X-Free' cosmetic-claim false positives): found 1 genuine pack_count miss (P.Calm toner pad, sku_name explicitly states '160ml x 2') and, in the same reviewed set, a real INCI-name typo (numbuzin 'Pantothenic B5' should read 'Panthenol B5' per sku_name). One ambiguous case deferred, not forced: numbuzin 'Pure-full Calming Herb Toner 300ml' sku_name says '[1+1 Double Day]' with no separate GWP item named, genuinely unclear whether this is a real doubling or just a marketing campaign-day label — left as-is pending clearer evidence. STEP3 Tier-2 GMV-prioritized sample (top 50 Tier-1-clean entries): found and fixed 2 further defects beyond the Avène case that triggered the systemic investigation — SKU-143230/SKU-143252 were genuine duplicate taxonomy entries for the identical 'Ceradan Hydra Moisturizer 300g' product (same brand_id/product_line/size/pack_count, just spelled 'Moisturiser' vs 'Moisturizer'), rerouted the less-populated entry's 1 map row onto the primary entry and left the now-orphaned entry in place (not deleted, per this session's rules) — a taxonomy-level duplicate class this category had not previously caught since it isn't a product_id-level dual-map. SKU-143250 'numbuzin No.1 2 3 4 Mask 4 5 5sheets' was a garbled multi-variant/multi-size collapse stub (Numbuzin's numbered No.1-5 sheet-mask line where the buyer selects formula and pack size) — renamed to a real, meaningful 'numbuzin No.1-5 Sheet Mask' with is_multi_variant=TRUE and is_multi_size=TRUE rather than the ungrounded numeric-fragment stub. One low-GMV product (Cosrx 'One Step...Calming Pad', product_id 1970458872) has two sku_name snapshots across months naming different pad counts (100 vs 70) and a slightly different product-line name ('Original Clear Skin' vs 'Green Hero') — likely the same listing renamed by the seller over time; deferred as ambiguous rather than guessed, consistent with this file's precedent for similar cross-month renamed-listing conflicts. | Fixed via bq DML, all meta_agent='CLAUDE_CODE', _meta reset to unreviewed on every content-changed row: 3 canonical_name-fields gate hits (size format normalized to match already-correct canonical_name text). 132 duplicate-brand-text corrections across 6 brands, a newly-discovered systemic defect class invisible to the existing case/diacritic-sensitive Tier-1 regex — Lancôme (22 entries, plus 1 missing-accent fix), Eau Thermale Avène (52), Clé de peau beaute (9), L'Oreal Paris (24), Estee Lauder (20), make p:rem (5). 9 null_size/multi_size fixes (4 image-verified sizes, 1 image-verified size + product_line correction, 2 mechanical text-extraction size backfills, 2 is_multi_size=TRUE conversions for genuine multi-item kits). 2 STEP2b fixes (P.Calm pack_count 1→2 with canonical_name/size text update; numbuzin INCI-name typo corrected). 2 STEP3 structural fixes (Ceradan duplicate-taxonomy-entry reroute of 1 map row, no rows deleted; numbuzin garbled multi-variant stub renamed with is_multi_variant/is_multi_size set). 147 distinct taxonomy_ids received a real content/structural fix this session (verified via meta_agent+updated_at). 25 rows bulk-promoted via STEP1C fast-lane (Tier-1-clean on recheck) and 46 rows via STEP3 Tier-2 confirmed-correct sample, both via single bulk _meta UPDATE statements per the confidence-promotion formula. Confidence distribution left behind (whole category, distinct taxonomy_ids joined via product_taxonomy_map): 264 confident (was 219), 554 unconfident (was 594), 386 fixed_pending_recheck (was 273, +113 this session — all rows this session touched), 2,632 unreviewed (was 2,751), 3,836 total distinct mapped entries. Remaining backlog, unchanged in character from prior sessions: ~184 wrong_field_order BRD-UNDEFINED rows with no confident brand match after bulk word-boundary re-check (only known generic-word noise, re-confirmed this session); ~760 remaining null_size long-tail entries below this session's GMV cutoff; 1 numbuzin pack_count ambiguity and 1 Cosrx cross-month renamed-listing ambiguity, both deferred and documented rather than guessed. Post-fix qa_report.sh: all 9 gates PASS (was 1 FAILing — canonical_name fields — at session start). Hard gate self-check (no --skip-coexistence): G1 (dual-mapped LLM)=0, G2 (HUMAN+LLM coexistence)=0, G3 (placeholder-leak)=0, structured-fields-missing%=0%, G4 (cross-category, explicitly re-verified against the full live sku_block_registry rather than a hardcoded block list)=0, G5 (provenance)=0, duplicate product_id=0, duplicate product+taxon=0, garbled brand text=0 (net of pre-existing exceptions) — all pass. No new taxonomy entries minted, no SKU block claimed (all fixes were in-place field updates or a single map-row reroute within the existing entry population). Universe refresh not run this session (out of scope per task instructions). |
---

## Scripts

No dedicated pipeline scripts for this category yet — this session performs extraction directly
(own multimodal reading + `bq query` DML), per `docs/headless-runbook.md`'s Full Rebuild scenario.

---

## Map Row Counts (as of session start, before this run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Not yet extracted |
| HUMAN | 6,447 | Automated keyword-seed rows (see above) |
| NULL (unmapped) | ~89,839 (96,286 distinct products in 2026-05 minus HUMAN-mapped, approximate) | |

---

## Map Row Counts (after this session's run)

| Source | source_listing | Count | Notes |
|--------|----------------|-------|-------|
| LLM | `OFFICIAL` | 188 | Pass 1, text-derived (6 image-spot-verified), confidence 0.55–0.9 |
| LLM | `RESELLER` | 1,885 | Pass 2, bulk text-match, confidence 0.6–0.75 |
| HUMAN | (unchanged) | 6,447 | Not touched this session — deletion is a separate wrapper-side step |

**taxonomy_id range used: SKU-074001–SKU-074188** (188 entries; block SKU-074001–076000 stays
`ACTIVE` in `sku_block_registry` with ~1,812 slots unused for a follow-up session).

**New LLM mapping this session: 2,073 products, $1,818,622 SGD (38.8% of total category GMV,
2026-05-01, $4,689,432 SGD total).** Additive to the pre-existing 6,447 HUMAN keyword-seed rows —
not independently re-measured this session, so total combined coverage (HUMAN + new LLM) is unknown
without a follow-up query.

**QA gates (run per `docs/headless-runbook.md`'s QA-gate-as-code, `--skip-coexistence` semantics
— HUMAN+LLM coexistence is expected at this point since the narrowly-scoped HUMAN-row delete is a
separate, deliberately manual/wrapper-side step not run this session):**

| Gate | Result | Expected |
|------|--------|----------|
| G1 — dual-mapped LLM products | 0 | 0 |
| G2 — HUMAN+LLM coexistence | 794 | non-zero at this stage (informational; will re-check to 0 after the wrapper's narrowly-scoped HUMAN delete) |
| G3 — placeholder-leak canonical names | 0 | 0 |
| G4 — structured-fields NULL % (DISTINCT entries, excl. `is_multi_size`) | 0% (0 of 152 non-multi-size entries) | ≤50% |

19 of 188 taxonomy entries have `size IS NULL` — all documented in-line in Taxonomy Design Notes as
genuinely unextractable (capsule-format creams, peel-off masks, and multi-item kits with no stated
volume/weight in either `sku_name` or the spot-checked image), confidence dropped to 0.55–0.6
accordingly rather than guessed.

## Remaining Work (for a follow-up session)

- **233 of 258 in-scope brands** have zero Pass 1/Pass 2 entries yet — everything from rank 26
  (Innisfree was covered; next uncovered is roughly rank 26 onward, e.g. Sulwhasoo, Paula's Choice
  was covered but many rank 20-60 brands were not) — see the Brand Scope table above for the full
  ranked list. This session deliberately went deep (many entries per brand) on the top 25 rather
  than shallow across all 258; a follow-up should extend breadth.
- **Official-store long tail for the 25 covered brands**: only the top ~8 products per brand by GMV
  were decomposed into taxonomy entries; each brand's official store has more products (e.g. Cosrx
  186, medicube 131, VT COSMETICS 206) that didn't make the top-8 cutoff and remain unmapped.
- **Ambiguous multi-product bundles/kits deferred**: same-brand cross-line kits (e.g. Dr. Althea
  Skin Relief & Barrier DUO, Centellian24 Brand Box, GLAD2GLOW Morning C Night A Set) were given
  conservative low-confidence single entries rather than decomposed — a follow-up with more time
  budget could split these into their component products if the map grain allows it.
- **15 Pass 2 ambiguous ties**: products matching two Pass-1 entries of equal specificity were left
  unmapped rather than guessed — a follow-up could resolve these with targeted vision reads.
- **NULL-coverage pass**: not run this session — `docs/quality-standards.md` §3 D6 (in-scope NULLs
  ranked by GMV) should be the first task of the next session.
- **Brands in scope with no discoverable official store** (~67 per the Brand Scope section):
  Pass 2 only, not attempted this session for brands outside the top 25.
- **Universe refresh**: not run this session (deliberately) — per the task instructions this session
  writes to `product_taxonomy`/`product_taxonomy_map` only; the `universe_taxonomy_overlay` MERGE
  and any HUMAN-row cleanup are separate, later steps.
