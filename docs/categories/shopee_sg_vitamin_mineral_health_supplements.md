# shopee_sg_vitamin_mineral_health_supplements — Category Context

> First-run category file, generated during headless Full Rebuild session, month=2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — measured after Pass 1 + Pass 2 |
| Last run | 2026-07-29 |
| Current MAX taxonomy_id (at research time) | SKU-137195 (see docs/categories/STATUS.md; re-verified live before claim in Step 3) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| TBD | Claimed atomically in Step 3 via `sku_block_registry` — see `sku_block_registry` table for the authoritative live range, this file is updated post-claim. |

---

## Brand Scope (GMV threshold 95%, month=2026-06-01)

225 brands (by canonical `brand_id` via `product_brand_map` → `brand_dict`, **not** raw `brand` text —
raw `brand` has ~1,601 distinct casing/format variants for the same 225-ish real brands, e.g.
`BLACKMORES`/`Blackmores`, which would badly inflate a text-based count) reach 95.017% cumulative GMV.
GWP-zeroed (`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`) before ranking, per Decision 15.

Two rows are **not real brands** and are excluded from the Official Store Allowlist below (no per-brand
store exists for them), but their underlying **products remain in scope** and must still be extracted
individually per §5 of `llm-extraction-rules.md`:
- `BRD-UNDEFINED` (rank 7, cum 33.25%) — brand undeterminable from any signal in `product_brand_map`
- `BRD-UNMAPPED` (rank 21, cum 57.45%) — product has no `product_brand_map` row at all for this table/platform/country

Full ranked list (225 brands, cumulative GMV crosses 95% at rank 225 / Now Foods):

| Rank | Brand | brand_id | GMV (SGD, GWP-zeroed) | Cum % |
|---|---|---|---|---|
| 1 | BioFinest | BRD-SG-00212 | 728,831.91 | 9.985% |
| 2 | BLACKMORES | BRD-SG-00413 | 391,894.60 | 15.354% |
| 3 | Moom Health | BRD-SG-00498 | 332,842.26 | 19.914% |
| 4 | Holistic Way | BRD-SG-00405 | 297,589.66 | 23.991% |
| 5 | Swisse | BRD-GLOBAL-00198 | 280,692.76 | 27.836% |
| 6 | The Purest Co | BRD-SG-00411 | 207,586.18 | 30.68% |
| 7 | Undefined | BRD-UNDEFINED | 187,713.56 | 33.252% |
| 8 | LABO Nutrition | BRD-SG-00536 | 187,190.40 | 35.816% |
| 9 | Nano Singapore | BRD-SG-00549 | 151,171.55 | 37.887% |
| 10 | Caltrate | BRD-TH-00221 | 149,921.02 | 39.941% |
| 11 | Ocean Health | BRD-SG-00602 | 148,650.34 | 41.978% |
| 12 | Estalife | BRD-SG-00539 | 139,283.82 | 43.886% |
| 13 | Brand's | BRD-GLOBAL-00103 | 126,781.81 | 45.623% |
| 14 | Nordic Naturals | BRD-GLOBAL-00827 | 122,802.65 | 47.305% |
| 15 | 21st Century | BRD-TH-00673 | 116,112.24 | 48.896% |
| 16 | Xandro | BRD-SG-00714 | 114,739.58 | 50.468% |
| 17 | AFC | BRD-SG-00682 | 109,854.38 | 51.973% |
| 18 | Now | BRD-GLOBAL-00779 | 105,189.64 | 53.414% |
| 19 | Eu Yan Sang | BRD-SG-00522 | 105,117.13 | 54.854% |
| 20 | GreenLife | BRD-SG-00772 | 98,790.81 | 56.208% |
| 21 | (unmapped - no product_brand_map row) | BRD-UNMAPPED | 90,864.05 | 57.452% |
| 22 | Vitahealth | BRD-TH-02770 | 87,741.91 | 58.655% |
| 23 | Lac | BRD-TH-03046 | 76,924.77 | 59.708% |
| 24 | SSBB | BRD-SG-01083 | 72,723.14 | 60.705% |
| 25 | Ensure | BRD-GLOBAL-00005 | 71,754.79 | 61.688% |
| 26 | Centrum | BRD-GLOBAL-00104 | 62,593.14 | 62.545% |
| 27 | KINOHIMITSU | BRD-SG-00684 | 61,957.04 | 63.394% |
| 28 | ARK+ | BRD-SG-03639 | 61,951.32 | 64.243% |
| 29 | Redoxon | BRD-SG-01036 | 53,166.27 | 64.971% |
| 30 | Nutri Botanics | BRD-SG-00577 | 45,585.56 | 65.596% |
| 31 | Nuskin | BRD-GLOBAL-00872 | 44,255.97 | 66.202% |
| 32 | Kordel's | BRD-SG-01299 | 42,736.09 | 66.788% |
| 33 | Herbal Pharm | BRD-SG-01063 | 41,529.39 | 67.356% |
| 34 | QN Wellness | BRD-SG-01461 | 38,753.90 | 67.887% |
| 35 | ZIEHA | BRD-SG-00695 | 37,680.00 | 68.404% |
| 36 | Herb Terra | BRD-SG-01164 | 37,104.45 | 68.912% |
| 37 | USANA | BRD-SG-01070 | 36,613.39 | 69.414% |
| 38 | Recogen | BRD-SG-01623 | 36,531.72 | 69.914% |
| 39 | Little Taiwan Store | BRD-SG-01112 | 35,571.00 | 70.401% |
| 40 | US Clinicals | BRD-SG-01280 | 34,136.17 | 70.869% |
| 41 | Duolac | BRD-SG-01258 | 33,295.17 | 71.325% |
| 42 | Thorne | BRD-GLOBAL-01772 | 32,895.47 | 71.776% |
| 43 | Red Sun | BRD-SG-01236 | 32,530.36 | 72.221% |
| 44 | For Youth | BRD-SG-01567 | 32,339.00 | 72.665% |
| 45 | Abbott | BRD-GLOBAL-00056 | 32,204.85 | 73.106% |
| 46 | Herbase | BRD-GLOBAL-01303 | 31,585.32 | 73.538% |
| 47 | Nature's Farm | BRD-SG-01624 | 31,521.88 | 73.97% |
| 48 | Olly | BRD-SG-01323 | 30,758.26 | 74.392% |
| 49 | LactoGG | BRD-SG-01324 | 28,265.65 | 74.779% |
| 50 | Heliocare | BRD-GLOBAL-00419 | 27,647.98 | 75.158% |
| 51 | Bounceback | BRD-SG-01476 | 26,973.12 | 75.527% |
| 52 | Thomson | BRD-GLOBAL-01752 | 23,670.96 | 75.852% |
| 53 | Nature's Key | BRD-GLOBAL-00596 | 23,640.85 | 76.175% |
| 54 | Nestle | BRD-GLOBAL-00059 | 22,986.44 | 76.49% |
| 55 | Borsch Med | BRD-SG-01608 | 22,527.40 | 76.799% |
| 56 | BBLAB | BRD-GLOBAL-01633 | 22,200.24 | 77.103% |
| 57 | Revit | BRD-SG-01529 | 20,080.38 | 77.378% |
| 58 | Balance | BRD-GLOBAL-00459 | 20,016.14 | 77.652% |
| 59 | Principle Nutrition | BRD-SG-01584 | 19,319.78 | 77.917% |
| 60 | TS6 | BRD-SG-01689 | 18,409.55 | 78.169% |
| 61 | Unichi | BRD-GLOBAL-01642 | 18,387.10 | 78.421% |
| 62 | HypoCol | BRD-SG-01401 | 18,104.57 | 78.669% |
| 63 | Nature's Green | BRD-SG-01639 | 18,015.93 | 78.916% |
| 64 | Movefree | BRD-GLOBAL-01345 | 17,617.73 | 79.157% |
| 65 | goli NUTRITION | BRD-SG-01794 | 17,361.04 | 79.395% |
| 66 | Shaklee | BRD-SG-01729 | 17,250.03 | 79.632% |
| 67 | Oxyenergy | BRD-SG-01528 | 16,307.20 | 79.855% |
| 68 | Ginflex | BRD-SG-01960 | 16,260.66 | 80.078% |
| 69 | Green Kare | BRD-SG-01725 | 16,208.00 | 80.3% |
| 70 | Purtier | BRD-SG-02099 | 15,798.39 | 80.516% |
| 71 | DrinkAid | BRD-SG-02018 | 15,788.08 | 80.733% |
| 72 | Vitanad+ | BRD-GLOBAL-01221 | 15,650.02 | 80.947% |
| 73 | life.space | BRD-GLOBAL-01236 | 15,607.80 | 81.161% |
| 74 | Doctor's Best | BRD-GLOBAL-00884 | 15,561.85 | 81.374% |
| 75 | Bilberry | BRD-SG-08352 | 14,696.05 | 81.575% |
| 76 | Vivomixx | BRD-SG-02117 | 14,305.63 | 81.771% |
| 77 | Pro-Uro | BRD-SG-02102 | 14,188.16 | 81.966% |
| 78 | Men+ | BRD-SG-09828 | 14,186.00 | 82.16% |
| 79 | BioGaia | BRD-TH-00797 | 13,699.30 | 82.348% |
| 80 | Bioglan | BRD-TH-00919 | 13,612.90 | 82.534% |
| 81 | Lacteol Fort | BRD-SG-02141 | 13,457.96 | 82.719% |
| 82 | Heart | BRD-TH-00817 | 13,396.97 | 82.902% |
| 83 | Jung Kwan Jang | BRD-SG-02029 | 13,283.40 | 83.084% |
| 84 | Dr GET IT | BRD-SG-02045 | 12,765.49 | 83.259% |
| 85 | Jeunesse | BRD-GLOBAL-01476 | 12,403.17 | 83.429% |
| 86 | mskinny | BRD-SG-02444 | 12,362.88 | 83.598% |
| 87 | ZzzQuil | BRD-SG-01988 | 12,214.73 | 83.766% |
| 88 | NE:AR | BRD-SG-01693 | 12,036.64 | 83.931% |
| 89 | Vita Green | BRD-SG-02066 | 11,972.34 | 84.095% |
| 90 | New Moon | BRD-SG-00719 | 11,637.91 | 84.254% |
| 91 | Helmig's | BRD-SG-03068 | 11,443.80 | 84.411% |
| 92 | ADVAGEN | BRD-SG-02138 | 11,358.32 | 84.566% |
| 93 | Leading Edge Health | BRD-SG-02300 | 11,253.70 | 84.721% |
| 94 | LACTOFIT | BRD-GLOBAL-01096 | 11,092.82 | 84.873% |
| 95 | NYO3 | BRD-SG-01781 | 11,055.88 | 85.024% |
| 96 | Voost | BRD-GLOBAL-01804 | 11,044.95 | 85.175% |
| 97 | Lactomin | BRD-SG-02303 | 10,945.78 | 85.325% |
| 98 | Yi Shi Yuan | BRD-SG-01924 | 10,917.82 | 85.475% |
| 99 | MEI HUA BRAND | BRD-SG-02154 | 10,902.00 | 85.624% |
| 100 | VitaRealm | BRD-SG-01919 | 10,409.35 | 85.767% |
| 101 | Efamol | BRD-SG-02285 | 10,259.54 | 85.907% |
| 102 | GNC | BRD-GLOBAL-01628 | 10,195.05 | 86.047% |
| 103 | Sports Research | BRD-GLOBAL-01440 | 10,109.93 | 86.186% |
| 104 | Healthy Care | BRD-GLOBAL-01087 | 9,923.98 | 86.321% |
| 105 | Trorexl | BRD-SG-01694 | 9,725.12 | 86.455% |
| 106 | VIT | BRD-SG-09662 | 9,698.15 | 86.588% |
| 107 | herbsofgold | BRD-SG-02166 | 9,375.49 | 86.716% |
| 108 | Himalaya | BRD-GLOBAL-00470 | 9,324.37 | 86.844% |
| 109 | Jungwonsam | BRD-SG-02116 | 9,312.72 | 86.971% |
| 110 | Fast | BRD-SG-04063 | 9,040.94 | 87.095% |
| 111 | Natrol | BRD-TH-01004 | 8,792.97 | 87.216% |
| 112 | THE PERFECT HEARTIO | BRD-SG-02800 | 8,779.00 | 87.336% |
| 113 | HANJAN | BRD-SG-02201 | 8,722.84 | 87.455% |
| 114 | Asxence | BRD-SG-02656 | 8,713.00 | 87.575% |
| 115 | UJUWON | BRD-SG-02236 | 8,654.14 | 87.693% |
| 116 | CareLeaf | BRD-SG-02039 | 8,581.82 | 87.811% |
| 117 | Dr. LEAN | BRD-GLOBAL-02172 | 8,532.79 | 87.928% |
| 118 | Nature's Way | BRD-GLOBAL-01105 | 8,486.24 | 88.044% |
| 119 | BesaPure | BRD-SG-02328 | 8,375.34 | 88.159% |
| 120 | Sangobion | BRD-SG-02259 | 8,336.75 | 88.273% |
| 121 | Thera Tears | BRD-SG-02418 | 8,305.76 | 88.387% |
| 122 | CH-Alpha | BRD-SG-02610 | 8,064.66 | 88.497% |
| 123 | Life Extension | BRD-GLOBAL-01081 | 8,051.07 | 88.608% |
| 124 | Optibac | BRD-SG-03171 | 8,017.70 | 88.717% |
| 125 | PHYTOTICS | BRD-SG-02316 | 7,738.96 | 88.823% |
| 126 | Tian Yang | BRD-SG-03042 | 7,731.00 | 88.929% |
| 127 | Morishita Jintan | BRD-SG-02499 | 7,580.31 | 89.033% |
| 128 | XEMENRY | BRD-GLOBAL-01616 | 7,422.25 | 89.135% |
| 129 | UNICITY | BRD-SG-02180 | 7,416.40 | 89.237% |
| 130 | Dr OatCare | BRD-SG-01699 | 7,339.95 | 89.337% |
| 131 | Equalpy | BRD-SG-04025 | 7,284.85 | 89.437% |
| 132 | California Gold Nutrition | BRD-GLOBAL-00695 | 7,130.34 | 89.535% |
| 133 | Huiji | BRD-SG-01486 | 7,124.00 | 89.632% |
| 134 | New Look | BRD-GLOBAL-03088 | 7,024.30 | 89.728% |
| 135 | OLIVAZUMO | BRD-SG-02184 | 6,986.70 | 89.824% |
| 136 | Empath | BRD-SG-02665 | 6,776.69 | 89.917% |
| 137 | NANO JAPAN | BRD-SG-02128 | 6,746.08 | 90.009% |
| 138 | ALXFRESH | BRD-GLOBAL-02052 | 6,681.92 | 90.101% |
| 139 | Berocca | BRD-GLOBAL-01475 | 6,429.15 | 90.189% |
| 140 | Manuka South | BRD-SG-02863 | 6,312.12 | 90.275% |
| 141 | Fybogel | BRD-SG-02757 | 6,168.70 | 90.36% |
| 142 | Funcare | BRD-SG-02696 | 6,089.66 | 90.443% |
| 143 | All Link Medical | BRD-SG-02861 | 6,063.70 | 90.527% |
| 144 | Bragg | BRD-GLOBAL-01777 | 5,999.20 | 90.609% |
| 145 | AVEA | BRD-SG-02430 | 5,820.41 | 90.688% |
| 146 | TruLife | BRD-SG-02397 | 5,667.70 | 90.766% |
| 147 | Pure Nutrition | BRD-SG-02932 | 5,648.29 | 90.843% |
| 148 | Jamu Ratu Malaya | BRD-SG-01830 | 5,620.50 | 90.92% |
| 149 | Pslalae | BRD-GLOBAL-01657 | 5,612.59 | 90.997% |
| 150 | Q'SAI | BRD-SG-02908 | 5,584.60 | 91.074% |
| 151 | Fruiting Body | BRD-TH-00544 | 5,413.07 | 91.148% |
| 152 | Afyaa | BRD-SG-02541 | 5,398.00 | 91.222% |
| 153 | HQ Lingzhi Singapore | BRD-SG-02442 | 5,392.20 | 91.296% |
| 154 | I-Defence | BRD-SG-03034 | 5,351.50 | 91.369% |
| 155 | Nutricost | BRD-GLOBAL-00924 | 5,310.26 | 91.442% |
| 156 | BAEBEAR | BRD-SG-02904 | 5,133.95 | 91.512% |
| 157 | Solaray | BRD-GLOBAL-01110 | 5,095.49 | 91.582% |
| 158 | Ali King | BRD-SG-02494 | 5,084.98 | 91.652% |
| 159 | Biomiii | BRD-SG-02701 | 5,056.00 | 91.721% |
| 160 | Neurobion | BRD-SG-02491 | 4,968.21 | 91.789% |
| 161 | Pro-Gut | BRD-SG-03017 | 4,906.58 | 91.856% |
| 162 | Moller’s | BRD-SG-02811 | 4,762.99 | 91.922% |
| 163 | NF369 | BRD-SG-02752 | 4,694.00 | 91.986% |
| 164 | DR.BERG | BRD-TH-03623 | 4,621.20 | 92.049% |
| 165 | swanson | BRD-GLOBAL-01517 | 4,594.80 | 92.112% |
| 166 | VALENS | BRD-SG-02783 | 4,582.04 | 92.175% |
| 167 | Care | BRD-GLOBAL-00623 | 4,561.26 | 92.237% |
| 168 | HQ | BRD-SG-05907 | 4,542.07 | 92.3% |
| 169 | ROOT KING | BRD-SG-03271 | 4,488.00 | 92.361% |
| 170 | Wellness Arc | BRD-SG-02555 | 4,471.10 | 92.422% |
| 171 | Vitabiotics | BRD-TH-01664 | 4,449.10 | 92.483% |
| 172 | Puritan’s Pride | BRD-TH-00196 | 4,438.98 | 92.544% |
| 173 | Natures Aid | BRD-GLOBAL-02232 | 4,412.53 | 92.605% |
| 174 | FANCL | BRD-GLOBAL-00856 | 4,380.90 | 92.665% |
| 175 | Miriqa | BRD-SG-01107 | 4,366.20 | 92.724% |
| 176 | @once | BRD-SG-03159 | 4,347.25 | 92.784% |
| 177 | LIPASCOR | BRD-SG-04505 | 4,249.68 | 92.842% |
| 178 | Get | BRD-TH-01966 | 4,093.28 | 92.898% |
| 179 | Biocalth | BRD-SG-03210 | 4,064.68 | 92.954% |
| 180 | Biyode | BRD-TH-01089 | 4,061.45 | 93.01% |
| 181 | G-NiiB | BRD-SG-03692 | 3,979.10 | 93.064% |
| 182 | BioHealing Naturals | BRD-SG-02943 | 3,961.76 | 93.118% |
| 183 | C&S | BRD-SG-05041 | 3,957.00 | 93.173% |
| 184 | EVERIGHT | BRD-SG-03166 | 3,940.42 | 93.227% |
| 185 | Kirkland Signature | BRD-GLOBAL-00921 | 3,792.97 | 93.279% |
| 186 | Omical | BRD-SG-03556 | 3,747.60 | 93.33% |
| 187 | GENACOL | BRD-SG-02851 | 3,704.50 | 93.381% |
| 188 | JML | BRD-SG-01647 | 3,695.27 | 93.431% |
| 189 | DHC | BRD-GLOBAL-00397 | 3,690.02 | 93.482% |
| 190 | Swissoats A111 | BRD-SG-02799 | 3,669.90 | 93.532% |
| 191 | Nov | BRD-GLOBAL-02688 | 3,599.20 | 93.581% |
| 192 | Fairhaven Health | BRD-GLOBAL-02130 | 3,536.50 | 93.63% |
| 193 | NOTO 樂道 | BRD-SG-03116 | 3,511.07 | 93.678% |
| 194 | URAH | BRD-SG-03232 | 3,460.35 | 93.725% |
| 195 | Totaria | BRD-GLOBAL-01788 | 3,427.20 | 93.772% |
| 196 | HYPHENS | BRD-SG-03296 | 3,414.56 | 93.819% |
| 197 | Nature's Nutrition | BRD-SG-01894 | 3,390.00 | 93.866% |
| 198 | SINGCHOICE | BRD-SG-03209 | 3,370.15 | 93.912% |
| 199 | STRAITS WHOLEFOODS | BRD-SG-02885 | 3,355.00 | 93.958% |
| 200 | Bausch + Lomb | BRD-SG-02306 | 3,347.24 | 94.003% |
| 201 | Culturelle | BRD-GLOBAL-02372 | 3,259.49 | 94.048% |
| 202 | Polleney | BRD-SG-03437 | 3,239.90 | 94.093% |
| 203 | Optimum Nutrition | BRD-GLOBAL-02165 | 3,237.21 | 94.137% |
| 204 | Apple | BRD-SG-05608 | 3,185.90 | 94.181% |
| 205 | Maltofer | BRD-SG-03236 | 3,163.70 | 94.224% |
| 206 | Naturally Plus | BRD-SG-04353 | 3,153.00 | 94.267% |
| 207 | UITC | BRD-SG-02512 | 3,100.20 | 94.31% |
| 208 | DR PPARS | BRD-SG-03537 | 3,045.00 | 94.351% |
| 209 | PreserVision | BRD-SG-12543 | 3,028.00 | 94.393% |
| 210 | Youguth | BRD-SG-03218 | 3,024.00 | 94.434% |
| 211 | andSons | BRD-SG-01523 | 3,023.00 | 94.476% |
| 212 | Noah | BRD-SG-01420 | 3,013.20 | 94.517% |
| 213 | CONDITION | BRD-SG-02831 | 3,003.17 | 94.558% |
| 214 | Naturelo | BRD-TH-02915 | 2,991.41 | 94.599% |
| 215 | Joli Fruits | BRD-SG-03511 | 2,971.80 | 94.64% |
| 216 | URAL | BRD-SG-04984 | 2,924.30 | 94.68% |
| 217 | Viviscal | BRD-GLOBAL-01112 | 2,887.10 | 94.719% |
| 218 | Ultravite | BRD-SG-03005 | 2,834.50 | 94.758% |
| 219 | MyLustre | BRD-SG-02522 | 2,773.94 | 94.796% |
| 220 | HF | BRD-SG-03283 | 2,748.54 | 94.834% |
| 221 | Denps | BRD-SG-04081 | 2,746.00 | 94.871% |
| 222 | Byherbs | BRD-SG-04335 | 2,664.50 | 94.908% |
| 223 | HERBALIFE | BRD-SG-02998 | 2,654.75 | 94.944% |
| 224 | Live | BRD-GLOBAL-01397 | 2,649.10 | 94.981% |
| 225 | Now Foods | BRD-GLOBAL-00271 | 2,648.21 | 95.017% |

---

## Official Store Allowlist (Pass 1)

Built by querying `DISTINCT merchant_name WHERE merchant_badge = 'Shopee Mall'` per in-scope `brand_id`
(joined via `product_brand_map` → `brand_dict`, not the raw `brand` text field), then filtering out
multi-brand retailers.

**Methodology:** a merchant_name is treated as multi-brand/excluded if either:
1. It matches a known multi-brand pharmacy/retail-chain name (Watsons, Guardian, BIG Pharmacy, Sasa,
   Boots, BEAUTRIUM, Tsuruha per `llm-extraction-rules.md` §4, plus SG-supplement-specific chains found
   in this category's own data: Farmasi C S, P&Q Pharmacy Official, Ren Ren Pharmacy Official, Taihopai
   Mall, Global Buyer, Nana Mall Official Store, HEY SUP, and assorted unrelated beauty-boutique/
   cross-border-reseller storefronts), **or**
2. It sells products under **more than 6 distinct `brand_id`s** in this category's full Shopee-Mall-badged
   pool (a systematic proxy for "multi-brand retailer" — Decision 14: prefer an explicit per-brand query
   over a `LIKE '%official%'` heuristic). Genuine parent-company stores that legitimately carry a small
   family of owned brands (e.g. Bayer Consumer Health → Redoxon + Berocca, Lifestream Group → LABO
   Nutrition + AFC + Manuka South) stay under this threshold and are correctly kept as Pass-1-eligible for
   every brand they carry, not excluded.
3. Additionally dropped as noise: rows with `GMV = 0` **and** `< 3` distinct products (coincidental
   single-listing matches to an otherwise-unrelated small reseller, not a genuine brand-owned store —
   e.g. `77 Boutique Pavilion2`, `qa_ckahdo_`, `8dhvoxks70`).

**101 of the 225 in-scope brands have at least one genuine official store** (122 brand↔store pairs, some
brands have 2+ legitimate stores e.g. a local SG store + an "Overseas"/parallel-import store under the
same brand). No known parent-company-store rebrand patterns (Biore→KAO, Dove/Sunsilk/Clear→Unilever,
Salz/Systema/Zact→Lion) were found in this category's top brands — supplement brands mostly run
brand-name-matching official stores directly.

| Brand | brand_id | Official Store Merchant Name | GMV (SGD) | Distinct Products |
|---|---|---|---|---|
| Ensure | BRD-GLOBAL-00005 | `Abbott's Nutrition Official Store` | 16,942.00 | 4 |
| Nestle | BRD-GLOBAL-00059 | `Nestle Health Science Official SG` | 19,308.82 | 14 |
| Brand's | BRD-GLOBAL-00103 | `BRAND'S Health Supplements Store` | 97,740.50 | 74 |
| Brand's | BRD-GLOBAL-00103 | `BRAND'S ® OFFICIAL STORE` | 22,581.63 | 31 |
| Centrum | BRD-GLOBAL-00104 | `Haleon Official Store` | 43,177.00 | 43 |
| Swisse | BRD-GLOBAL-00198 | `Swisse Singapore Official Store` | 90,672.77 | 153 |
| Swisse | BRD-GLOBAL-00198 | `Swisse Overseas` | 89,842.58 | 132 |
| DHC | BRD-GLOBAL-00397 | `BEAUTY U & ME.SG Official Store` | 39.24 | 13 |
| Heliocare | BRD-GLOBAL-00419 | `Dermaskinshop Official Store` | 12,996.78 | 1 |
| Balance | BRD-GLOBAL-00459 | `BioFinest Official Store` | 19,418.40 | 1 |
| Himalaya | BRD-GLOBAL-00470 | `Himalaya Official Store` | 8,881.33 | 85 |
| Himalaya | BRD-GLOBAL-00470 | `Himalaya Wellness Official Store` | 0.00 | 63 |
| Nature's Key | BRD-GLOBAL-00596 | `Nature's Key Store` | 20,985.35 | 74 |
| Nature's Key | BRD-GLOBAL-00596 | `Nature's Key Singapore` | 2,655.50 | 16 |
| Care | BRD-GLOBAL-00623 | `Dr.Lean Korea SG ` | 192.51 | 1 |
| Care | BRD-GLOBAL-00623 | `Himalaya Official Store` | 28.75 | 1 |
| Now | BRD-GLOBAL-00779 | `Now Foods Official Store` | 46,335.76 | 312 |
| Now | BRD-GLOBAL-00779 | `Dr.Elizabeth's` | 485.86 | 17 |
| Doctor's Best | BRD-GLOBAL-00884 | `Doctor's Best Official Store` | 0.00 | 27 |
| Healthy Care | BRD-GLOBAL-01087 | `Healthy Care` | 803.27 | 32 |
| Healthy Care | BRD-GLOBAL-01087 | `Healthy Care Official Store` | 0.00 | 28 |
| Healthy Care | BRD-GLOBAL-01087 | `J-Mart Official` | 0.00 | 3 |
| LACTOFIT | BRD-GLOBAL-01096 | `iQueen Official Store` | 330.00 | 13 |
| Nature's Way | BRD-GLOBAL-01105 | `Nature's Way Offical Store` | 3,154.40 | 17 |
| life.space | BRD-GLOBAL-01236 | `Life-Space Offical Store` | 9,484.96 | 11 |
| life.space | BRD-GLOBAL-01236 | `Life-Space Overseas` | 209.28 | 11 |
| Movefree | BRD-GLOBAL-01345 | `Move Free Official Store` | 14,242.88 | 48 |
| Movefree | BRD-GLOBAL-01345 | `Move Free Flagship Store` | 83.43 | 14 |
| Berocca | BRD-GLOBAL-01475 | `Bayer Consumer Health Official Store` | 248.10 | 8 |
| BBLAB | BRD-GLOBAL-01633 | `Nutrione Official Store` | 22,200.24 | 25 |
| Unichi | BRD-GLOBAL-01642 | `Teddi Lab by Unichi` | 18,277.87 | 12 |
| Thomson | BRD-GLOBAL-01752 | `Thomson Health SG Official Store` | 13,645.45 | 44 |
| Thorne | BRD-GLOBAL-01772 | `Thorne Research SG Official Store` | 32,895.47 | 60 |
| Voost | BRD-GLOBAL-01804 | `P&G Official Store` | 4,922.90 | 27 |
| Optimum Nutrition | BRD-GLOBAL-02165 | `Optimum Nutrition Official Store` | 527.67 | 1 |
| Dr. LEAN | BRD-GLOBAL-02172 | `Dr.Lean Korea SG ` | 8,532.79 | 9 |
| BioFinest | BRD-SG-00212 | `BioFinest Official Store` | 727,453.17 | 128 |
| Holistic Way | BRD-SG-00405 | `Holistic Way Official Store` | 293,063.04 | 144 |
| The Purest Co | BRD-SG-00411 | `The Purest Co Official Store` | 206,066.98 | 23 |
| BLACKMORES | BRD-SG-00413 | `Blackmores Official Store` | 280,483.70 | 160 |
| Moom Health | BRD-SG-00498 | `Moom Health` | 331,159.75 | 56 |
| Eu Yan Sang | BRD-SG-00522 | `Eu Yan Sang Official Store` | 98,309.20 | 35 |
| LABO Nutrition | BRD-SG-00536 | `Lifestream Group Official Store` | 184,303.03 | 136 |
| Nano Singapore | BRD-SG-00549 | `Nano Singapore Official Store` | 134,149.43 | 51 |
| Ocean Health | BRD-SG-00602 | `Ocean Health Official Store` | 135,800.47 | 69 |
| Ocean Health | BRD-SG-00602 | `myCK_online` | 0.00 | 5 |
| AFC | BRD-SG-00682 | `Lifestream Group Official Store` | 107,085.29 | 53 |
| KINOHIMITSU | BRD-SG-00684 | `Kinohimitsu Official Store` | 61,332.50 | 45 |
| Xandro | BRD-SG-00714 | `Xandro Lab Official Store` | 114,739.58 | 90 |
| New Moon | BRD-SG-00719 | `New Moon Official Store` | 11,196.09 | 15 |
| Redoxon | BRD-SG-01036 | `Bayer Consumer Health Official Store` | 31,538.53 | 87 |
| Miriqa | BRD-SG-01107 | `MIRIQA Official Store` | 4,366.20 | 2 |
| Herb Terra | BRD-SG-01164 | `Herb Terra Official Store` | 37,104.45 | 35 |
| Red Sun | BRD-SG-01236 | `RED SUN Official Store` | 19,174.73 | 18 |
| US Clinicals | BRD-SG-01280 | `US Clinicals Official Store` | 32,607.50 | 82 |
| US Clinicals | BRD-SG-01280 | `AVALON Official Store` | 837.15 | 26 |
| Kordel's | BRD-SG-01299 | `Kordel's Official Store` | 20,195.30 | 78 |
| Kordel's | BRD-SG-01299 | `Suitable for Vegetarians By Nuvanta` | 192.00 | 22 |
| Olly | BRD-SG-01323 | `OLLY Supplements` | 28,695.09 | 91 |
| HypoCol | BRD-SG-01401 | `HypoCol Official Store` | 2,016.00 | 1 |
| Noah | BRD-SG-01420 | `Noah Official Store ` | 3,013.20 | 5 |
| QN Wellness | BRD-SG-01461 | `QN Wellness Official Store` | 32,571.41 | 58 |
| Bounceback | BRD-SG-01476 | `bback official (prev. BounceBack)` | 23,576.76 | 7 |
| Huiji | BRD-SG-01486 | `Huiji Singapore Official Store` | 5,150.00 | 4 |
| Oxyenergy | BRD-SG-01528 | `Oxyenergy SG` | 16,307.20 | 26 |
| Revit | BRD-SG-01529 | `Revit Official Store` | 19,780.88 | 2 |
| Revit | BRD-SG-01529 | `BEAUBIT Official Store` | 299.50 | 1 |
| For Youth | BRD-SG-01567 | `For Youth` | 32,339.00 | 11 |
| Principle Nutrition | BRD-SG-01584 | `Principle Nutrition Official Store` | 19,193.68 | 51 |
| Borsch Med | BRD-SG-01608 | `Borsch Med Official Store` | 17,959.49 | 12 |
| Recogen | BRD-SG-01623 | `NCI HEALTH Official Store` | 29,034.20 | 31 |
| Nature's Farm | BRD-SG-01624 | `Nature's Farm Official Store` | 31,521.88 | 31 |
| NE:AR | BRD-SG-01693 | `NE:AR Official Store` | 12,036.64 | 3 |
| Green Kare | BRD-SG-01725 | `AuSin Mediheal` | 11,381.52 | 20 |
| Green Kare | BRD-SG-01725 | `GreenKare Offical Store` | 4,826.48 | 9 |
| NYO3 | BRD-SG-01781 | `NYO3NORWAY.sg` | 11,055.88 | 22 |
| Nature's Nutrition | BRD-SG-01894 | `Nature's Nutrition Official Store` | 1,225.40 | 9 |
| VitaRealm | BRD-SG-01919 | `vitarealm_official` | 8,222.23 | 54 |
| ZzzQuil | BRD-SG-01988 | `P&G Official Store` | 10,506.80 | 8 |
| DrinkAid | BRD-SG-02018 | `DrinkAid Official Store` | 15,639.58 | 5 |
| Jung Kwan Jang | BRD-SG-02029 | `Jung Kwan Jang Official Store` | 7,506.55 | 47 |
| CareLeaf | BRD-SG-02039 | `CareLeaf SG Store` | 8,000.44 | 20 |
| CareLeaf | BRD-SG-02039 | `Nature's Key Singapore` | 464.32 | 4 |
| Dr GET IT | BRD-SG-02045 | `Dr.GET IT Official Store` | 12,765.49 | 6 |
| NANO JAPAN | BRD-SG-02128 | `NANO JAPAN OFFICIAL STORE` | 6,746.08 | 19 |
| MEI HUA BRAND | BRD-SG-02154 | `Science Arts Official Store` | 966.00 | 17 |
| herbsofgold | BRD-SG-02166 | `Herbs of Gold Official Store` | 9,160.06 | 23 |
| herbsofgold | BRD-SG-02166 | `VitaHealth Official Store` | 94.00 | 7 |
| UJUWON | BRD-SG-02236 | `iQueen Official Store` | 8,654.14 | 5 |
| Efamol | BRD-SG-02285 | `WellbeingSG ActivHealth Official ` | 118.00 | 5 |
| Leading Edge Health | BRD-SG-02300 | `Leading Edge Health` | 11,253.70 | 10 |
| PHYTOTICS | BRD-SG-02316 | `PHYTOTICS Official Store` | 7,738.96 | 27 |
| BesaPure | BRD-SG-02328 | `BesaPure ` | 8,375.34 | 4 |
| AVEA | BRD-SG-02430 | `AVEA Official Store` | 5,820.41 | 8 |
| mskinny | BRD-SG-02444 | `MSkinny Official Store` | 12,362.88 | 2 |
| Ali King | BRD-SG-02494 | `AuSin Mediheal` | 3,648.68 | 16 |
| Ali King | BRD-SG-02494 | `GreenKare Offical Store` | 1,436.30 | 7 |
| MyLustre | BRD-SG-02522 | `MyLustre Official Store` | 2,773.94 | 6 |
| CH-Alpha | BRD-SG-02610 | `360ACTIV Official Store` | 8,064.66 | 7 |
| Funcare | BRD-SG-02696 | `iQueen Official Store` | 6,007.86 | 10 |
| NF369 | BRD-SG-02752 | `Natural Factory Official` | 3,974.00 | 16 |
| Moller’s | BRD-SG-02811 | `ORKLA Official Store` | 4,762.99 | 11 |
| CONDITION | BRD-SG-02831 | `Condition Official Store` | 2,653.97 | 27 |
| CONDITION | BRD-SG-02831 | `K-Market by Koryo Trading` | 60.80 | 1 |
| GENACOL | BRD-SG-02851 | `GENACOL Singapore Official Store` | 1,427.00 | 10 |
| Manuka South | BRD-SG-02863 | `Lifestream Group Official Store` | 5,220.64 | 6 |
| Q'SAI | BRD-SG-02908 | `BEME Japan Official Store` | 5,584.60 | 5 |
| Optibac | BRD-SG-03171 | `Healthiforte` | 7,835.00 | 13 |
| Youguth | BRD-SG-03218 | `Youguth Probiotics Official Store` | 2,912.00 | 5 |
| HF | BRD-SG-03283 | `Arumi Health` | 162.00 | 5 |
| G-NiiB | BRD-SG-03692 | `G-Niib Official Store` | 2,981.99 | 12 |
| Equalpy | BRD-SG-04025 | `Equalibrium` | 7,194.00 | 4 |
| Denps | BRD-SG-04081 | `Denps Official Store` | 2,746.00 | 9 |
| Caltrate | BRD-TH-00221 | `Haleon Official Store` | 108,166.71 | 34 |
| Fruiting Body | BRD-TH-00544 | `Fruiting Body` | 5,413.07 | 10 |
| 21st Century | BRD-TH-00673 | `21st Century Official Store` | 104,941.42 | 148 |
| Bioglan | BRD-TH-00919 | `Bioglan SG` | 6,942.75 | 34 |
| Bioglan | BRD-TH-00919 | `Nature's Way Offical Store` | 0.00 | 5 |
| Biyode | BRD-TH-01089 | `BIYODE WELLNESS` | 1,905.35 | 14 |
| Vitahealth | BRD-TH-02770 | `VitaHealth Official Store` | 76,359.82 | 53 |
| Vitahealth | BRD-TH-02770 | `Green Earth Organic Official Store` | 47.90 | 20 |
| Lac | BRD-TH-03046 | `LAC OFFICIAL STORE` | 75,669.75 | 148 |

**Brands with no official store (122 — Pass 2 only):**

@once (`BRD-SG-03159`), Abbott (`BRD-GLOBAL-00056`), ADVAGEN (`BRD-SG-02138`), Afyaa (`BRD-SG-02541`), All Link Medical (`BRD-SG-02861`), ALXFRESH (`BRD-GLOBAL-02052`), andSons (`BRD-SG-01523`), Apple (`BRD-SG-05608`), ARK+ (`BRD-SG-03639`), Asxence (`BRD-SG-02656`), BAEBEAR (`BRD-SG-02904`), Bausch + Lomb (`BRD-SG-02306`), Bilberry (`BRD-SG-08352`), Biocalth (`BRD-SG-03210`), BioGaia (`BRD-TH-00797`), BioHealing Naturals (`BRD-SG-02943`), Biomiii (`BRD-SG-02701`), Bragg (`BRD-GLOBAL-01777`), Byherbs (`BRD-SG-04335`), C&S (`BRD-SG-05041`), California Gold Nutrition (`BRD-GLOBAL-00695`), Culturelle (`BRD-GLOBAL-02372`), Dr OatCare (`BRD-SG-01699`), DR PPARS (`BRD-SG-03537`), DR.BERG (`BRD-TH-03623`), Duolac (`BRD-SG-01258`), Empath (`BRD-SG-02665`), Estalife (`BRD-SG-00539`), EVERIGHT (`BRD-SG-03166`), Fairhaven Health (`BRD-GLOBAL-02130`), FANCL (`BRD-GLOBAL-00856`), Fast (`BRD-SG-04063`), Fybogel (`BRD-SG-02757`), Get (`BRD-TH-01966`), Ginflex (`BRD-SG-01960`), GNC (`BRD-GLOBAL-01628`), goli NUTRITION (`BRD-SG-01794`), GreenLife (`BRD-SG-00772`), HANJAN (`BRD-SG-02201`), Heart (`BRD-TH-00817`), Helmig's (`BRD-SG-03068`), Herbal Pharm (`BRD-SG-01063`), HERBALIFE (`BRD-SG-02998`), Herbase (`BRD-GLOBAL-01303`), HQ (`BRD-SG-05907`), HQ Lingzhi Singapore (`BRD-SG-02442`), HYPHENS (`BRD-SG-03296`), I-Defence (`BRD-SG-03034`), Jamu Ratu Malaya (`BRD-SG-01830`), Jeunesse (`BRD-GLOBAL-01476`), JML (`BRD-SG-01647`), Joli Fruits (`BRD-SG-03511`), Jungwonsam (`BRD-SG-02116`), Kirkland Signature (`BRD-GLOBAL-00921`), Lacteol Fort (`BRD-SG-02141`), LactoGG (`BRD-SG-01324`), Lactomin (`BRD-SG-02303`), Life Extension (`BRD-GLOBAL-01081`), LIPASCOR (`BRD-SG-04505`), Little Taiwan Store (`BRD-SG-01112`), Live (`BRD-GLOBAL-01397`), Maltofer (`BRD-SG-03236`), Men+ (`BRD-SG-09828`), Morishita Jintan (`BRD-SG-02499`), Natrol (`BRD-TH-01004`), Naturally Plus (`BRD-SG-04353`), Nature's Green (`BRD-SG-01639`), Naturelo (`BRD-TH-02915`), Natures Aid (`BRD-GLOBAL-02232`), Neurobion (`BRD-SG-02491`), New Look (`BRD-GLOBAL-03088`), Nordic Naturals (`BRD-GLOBAL-00827`), NOTO 樂道 (`BRD-SG-03116`), Nov (`BRD-GLOBAL-02688`), Now Foods (`BRD-GLOBAL-00271`), Nuskin (`BRD-GLOBAL-00872`), Nutri Botanics (`BRD-SG-00577`), Nutricost (`BRD-GLOBAL-00924`), OLIVAZUMO (`BRD-SG-02184`), Omical (`BRD-SG-03556`), Polleney (`BRD-SG-03437`), PreserVision (`BRD-SG-12543`), Pro-Gut (`BRD-SG-03017`), Pro-Uro (`BRD-SG-02102`), Pslalae (`BRD-GLOBAL-01657`), Pure Nutrition (`BRD-SG-02932`), Puritan’s Pride (`BRD-TH-00196`), Purtier (`BRD-SG-02099`), ROOT KING (`BRD-SG-03271`), Sangobion (`BRD-SG-02259`), Shaklee (`BRD-SG-01729`), SINGCHOICE (`BRD-SG-03209`), Solaray (`BRD-GLOBAL-01110`), Sports Research (`BRD-GLOBAL-01440`), SSBB (`BRD-SG-01083`), STRAITS WHOLEFOODS (`BRD-SG-02885`), swanson (`BRD-GLOBAL-01517`), Swissoats A111 (`BRD-SG-02799`), THE PERFECT HEARTIO (`BRD-SG-02800`), Thera Tears (`BRD-SG-02418`), Tian Yang (`BRD-SG-03042`), Totaria (`BRD-GLOBAL-01788`), Trorexl (`BRD-SG-01694`), TruLife (`BRD-SG-02397`), TS6 (`BRD-SG-01689`), UITC (`BRD-SG-02512`), Ultravite (`BRD-SG-03005`), UNICITY (`BRD-SG-02180`), URAH (`BRD-SG-03232`), URAL (`BRD-SG-04984`), USANA (`BRD-SG-01070`), VALENS (`BRD-SG-02783`), VIT (`BRD-SG-09662`), Vita Green (`BRD-SG-02066`), Vitabiotics (`BRD-TH-01664`), Vitanad+ (`BRD-GLOBAL-01221`), Viviscal (`BRD-GLOBAL-01112`), Vivomixx (`BRD-SG-02117`), Wellness Arc (`BRD-SG-02555`), XEMENRY (`BRD-GLOBAL-01616`), Yi Shi Yuan (`BRD-SG-01924`), ZIEHA (`BRD-SG-00695`)

---

## Scale

| Metric | Value |
|--------|-------|
| Total rows (month=2026-06-01) | 179,584 |
| Total distinct products | 96,128 |
| Official-store (`Shopee Mall`-badged) rows, **full pool, all brands** | 22,562 |
| Official-store distinct products, **full pool, all brands** | 14,433 |
| Official-store rows, **scoped to this category's curated allowlist only** | 6,382 |
| Official-store distinct products, **scoped to this category's curated allowlist only** | 4,031 |

The full Mall-badged pool (22,562 rows / 14,433 products) is **not** tens-of-thousands-plus at the
row level in the sense that would make it infeasible to vision-read directly, but it is still large enough,
and — critically — includes the excluded multi-brand pharmacy chains (Watsons, Guardian, BIG Pharmacy
alone contribute ~350 brand-store pairs across unrelated brands per the multi-brand detection query).
**Pass 1 must scope strictly to the 122-pair / 6,382-row / 4,031-product curated allowlist above, never
the full Mall-badged pool.**

---

## Existing map rows (Step 1, live-queried 2026-07-29)

`product_taxonomy_map` has **zero rows** (LLM or HUMAN) for `master_table =
'shopee_sg_vitamin_mineral_health_supplements'`. This is a genuine first run — no prior keyword-seed
pass has been loaded for this table despite `docs/categories/STATUS.md` listing it as "⏳ Keyword only"
(that status line appears to describe the category's general pipeline stage/intent, not a literal existing
`product_taxonomy_map` row count — the live table itself is empty for this `master_table`).

---

## Scope — What's In vs Out

**In scope:** standalone dietary/nutritional supplements — vitamins (single or multi), minerals,
probiotics, fish oil/omega-3, collagen, joint/eye/liver/immune/gut-health supplements, herbal and
traditional wellness supplements, meal-replacement/nutritional drinks marketed as a supplement (e.g.
Ensure), protein/greens powders marketed as a dietary supplement.

**Out of scope (leave NULL):** prescription/TCM medicine, medical devices/equipment, weight-loss drugs
requiring a prescription, pet supplements (belong to a pet category, not human health), non-ingestible
wellness items (e.g. patches, aromatherapy oils) unless clearly a labeled ingestible supplement product.

**Edge cases:**
- `category_3_EN` only has two BE values for this table (`Well Being`, `Others`) — no finer BE
  granularity to pre-filter scope; rely on `sku_name`/image per product, per the standard
  match-or-create gate (never a pre-extraction keyword filter — `llm-extraction-rules.md` §8).
- Top-GMV sample (40 highest-GMV distinct `sku_name_EN` values) was spot-checked and is entirely
  clean genuine supplements (probiotics, omega-3, multivitamin, collagen/joint, liver support, gut
  health, meal-replacement drink) — no contamination detected in the high-GMV tail during this
  research pass; full contamination sweep still happens per-product during Pass 1/2 extraction.

---

## Taxonomy Design Notes

**Product line extraction approach:** read the real on-label product line per `llm-extraction-rules.md`
§3 — supplement listings are typically title-heavy with the real line name up front (e.g. "Ultimate
Omega", "Joint Health UCII Collagen") followed by marketing/keyword-stuffed claims; do not fold the
claims text into `product_line`.

**Size extraction notes:**
- Primary unit for this category is **count** (capsules/tablets/softgels/caps — "60 Capsules", "180s",
  "30 Veg Capsules"), not weight/volume — this differs from most other categories in this pipeline.
  Treat count-based sizing as the `size` field value (e.g. `"60 caps"`, `"180 softgels"`).
  Liquid supplements (e.g. Ensure) still use ml/L as normal.
- Pack-count patterns seen in this category's sku_names: `[Bundle of N]`, `[Value Pack]` + explicit `x2`,
  `[N Boxes]`, `x{TOTAL}` — apply the standard §1 pack-count priority chain and GWP-vs-multipack
  distinction.

**Known difficult products:** none identified yet — first pass, will be filled in during extraction/QA.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Research | Table has 0 existing `product_taxonomy_map` rows despite STATUS.md "Keyword only" label; 225-brand 95% GMV scope (canonical brand_id, not raw text) built; 101/225 brands have a curated official-store allowlist (122 store pairs) | Category file created; ready for Step 3 SKU claim + Pass 1/2 |

---

## Targeted QA Fix Brief

> Not applicable yet — no existing taxonomy entries to review. This section applies once Pass 1/2 has run
> and a later `targeted_qa_fix.sh` session needs a hand-written brief (auto-discovery mode is the default
> otherwise).

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_shopee_sg_vitamin_mineral_health_supplements/build_taxonomy.py` | Pass 1 extraction (not used this session — extraction performed directly by the Claude Code session per headless-runbook.md) |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Pre-extraction |
| HUMAN | 0 | Pre-extraction — no keyword seed loaded despite STATUS.md label |
| NULL (unmapped) | 96,128 (all distinct products) | Pre-extraction |
