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
| 2026-07-23 | Top-up coverage session #2 (month 2026-06, same-day follow-up) | Re-ran STEP 0's live worklist query independently rather than trusting the wrapper's "3 products still gap" pre-check. Result: 3 model-grain rows / **2 distinct product_ids**, both already known — `10981756831` (Assos Chamois Creme, cycling chafing cream) and `29292218697` (AYUNCHE Pro Care haircare bundle). These are the exact 2 products the earlier same-day session (row above) identified as OOS and deliberately deleted from `product_taxonomy`/`product_taxonomy_map`; they reappear in the worklist purely because "deleted → back to NULL → still within 95% cumulative GMV" is expected, correct behavior for genuinely out-of-scope products, not a new coverage gap. Re-verified both against sku_name text (no image read needed — text is unambiguous): Assos is a cycling-saddle anti-chafing product, no skincare/moisturizer/toner/mask/mist term anywhere; AYUNCHE is an all-hair-care bundle (shampoo/polish oil/volumizing fluid/bond enhancer/grease wax). Both confirmed OOS again — correctly left NULL, not minted. **Net action this session: 0 rows created, 0 rows mapped, no SKU block claimed** (nothing to write; matches `docs/headless-runbook.md`'s Full Rebuild top-up scenario's documented behavior for a live gap that resolves to 0 after the category's own match-or-create gate). **Full QA gate self-check re-run (per this session's STEP 5), scoped correctly to `source='LLM'` per `run_qa_gates()`'s own methodology — not just the prior session's own new rows:** G1 (dual-mapped LLM)=0 ✅. G2 (HUMAN+LLM coexistence, unscoped by source per the exact gate query)=794 — still RED, unchanged, same pre-existing gap noted in the row above (wrapper-side HUMAN-row cleanup still not run). G4 (cross-category, LLM rows outside this table's own SKU blocks 74001–76000/122056–124555)=0 ✅. G5 (provenance)=0 ✅. **G3 (placeholder-leak) is RED at 634 LLM map rows / 36 distinct taxonomy entries — this is a genuine finding, not previously caught**: all 36 entries are original 2026-07-16 Pass-1 `is_multi_size=TRUE` entries using the canonical-name suffix "Multiple Sizes" (e.g. `SKU-074026` "Biodance Bio-Collagen Real Deep Mask Multiple Sizes", 86 mapped products; `SKU-074096` "Laneige Water Sleeping Mask Multiple Sizes", 73 mapped products). This phrasing was compliant with `llm-extraction-rules.md` at build time (2026-07-16) but was retroactively banned unconditionally by the 2026-07-22 rule change documented in that file's changelog ("'Multiple Sizes'/'Multiple Variants' banned unconditionally... the flag column already conveys that semantic"). The prior same-day session's G3=0 result (row above) only checked its own 2,361 newly-minted entries, which don't use this phrasing — it never re-scanned the category's full existing LLM population, so this pre-existing defect went unflagged until this session's broader gate re-run. **Not fixed here** — renaming 36 canonical_name entries is a D1/D3 precision fix (exact wording), explicitly out of this top-up session's scope per its own instructions; flagging for `script/targeted_qa_fix.sh`, prioritized by the mapped-product counts above (Biodance/Laneige/Dr. Althea/Cerave entries are the highest-impact). Universe refresh **not run** this session (out of scope). |

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
