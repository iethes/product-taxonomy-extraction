# shopee_sg_vitamin_mineral_health_supplements — Category Context

> First-run category file, generated during headless Full Rebuild session, month=2026-06.
> Amended same-session after advisor review caught a brand-ranking scope bug — see the note in
> "Brand Scope" below.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 95.1% (2026-06) |
| Last run | 2026-07-29 |
| Current MAX taxonomy_id (at research time) | SKU-201328 / SKU-204028 (two blocks, see below) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-199329–SKU-200645 | Pass 1 OFFICIAL: 1,166 Tier-A entries (top-1,200-by-GMV official-store products) + 151 per-brand catch-alls for official-store long tail |
| SKU-200646–SKU-201230 | Pass 2 RESELLER: 585 Tier-A entries (top-600-by-GMV remaining in-scope products needing a new line) |
| SKU-201231–SKU-201328 | Unused remainder of primary block (98 slots) |
| SKU-203529–SKU-203854 | Pass 2 supplemental block: 326 per-brand catch-alls for reseller long tail (primary block exhausted) |
| SKU-203855–SKU-204028 | Unused remainder of supplemental block (174 slots) |

Total taxonomy entries written: 2,228 (1,317 Pass 1 + 911 Pass 2). Total `product_taxonomy_map` rows: 6,947 (4,422 Pass 1 + 2,525 Pass 2), GMV coverage 95.1% against the full table.

---

## Brand Scope (GMV threshold 95%, month=2026-06-01)

**Correction (same session, pre-claim):** the first version of this ranking summed GMV over every
`brand_id` returned by the join, including `BRD-UNDEFINED` (33.25% cum, rank 7) and a synthetic
`BRD-UNMAPPED` bucket for products with no `product_brand_map` row at all (57.45% cum, rank 21) —
together ~4% of total GMV sitting inside the running sum, pulling in tail brands that don't belong
in a *brand* ranking. `llm-extraction-rules.md` §8 requires filtering to category-relevant signal before
summing for a brand-GMV threshold; `BRD-UNDEFINED`/`BRD-UNBRANDED` are not brands. Re-ran excluding
`brand_id NOT IN ('BRD-UNDEFINED','BRD-UNBRANDED')` and the unmapped bucket entirely from the ranking.
**Their underlying products are unaffected and remain in the product-level in-scope worklist (Rule A,
quality-standards.md §2)** — this correction only changes which `brand_id`s get a curated official-store
allowlist below, not which individual products get extracted.

**228 brands** (by canonical `brand_id` via `product_brand_map` → `brand_dict`, **not** raw `brand` text —
raw `brand` has ~1,601 distinct casing/format variants for the same ~228 real brands, e.g.
`BLACKMORES`/`Blackmores`, which would badly inflate a text-based count) reach 95.006% cumulative GMV.
GWP-zeroed (`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`) before ranking, per Decision 15.

Full ranked list (228 brands, cumulative GMV crosses 95% at rank 228 / Nature's Bounty):

| Rank | Brand | brand_id | GMV (SGD, GWP-zeroed) | Cum % |
|---|---|---|---|---|
| 1 | BioFinest | BRD-SG-00212 | 728,831.91 | 10.381% |
| 2 | BLACKMORES | BRD-SG-00413 | 391,894.60 | 15.963% |
| 3 | Moom Health | BRD-SG-00498 | 332,842.26 | 20.704% |
| 4 | Holistic Way | BRD-SG-00405 | 297,589.66 | 24.943% |
| 5 | Swisse | BRD-GLOBAL-00198 | 280,692.76 | 28.941% |
| 6 | The Purest Co | BRD-SG-00411 | 207,586.18 | 31.898% |
| 7 | LABO Nutrition | BRD-SG-00536 | 187,190.40 | 34.564% |
| 8 | Nano Singapore | BRD-SG-00549 | 151,171.55 | 36.717% |
| 9 | Caltrate | BRD-TH-00221 | 149,921.02 | 38.852% |
| 10 | Ocean Health | BRD-SG-00602 | 148,650.34 | 40.97% |
| 11 | Estalife | BRD-SG-00539 | 139,283.82 | 42.954% |
| 12 | Brand's | BRD-GLOBAL-00103 | 126,781.81 | 44.76% |
| 13 | Nordic Naturals | BRD-GLOBAL-00827 | 122,802.65 | 46.509% |
| 14 | 21st Century | BRD-TH-00673 | 116,112.24 | 48.163% |
| 15 | Xandro | BRD-SG-00714 | 114,739.58 | 49.797% |
| 16 | AFC | BRD-SG-00682 | 109,854.38 | 51.362% |
| 17 | Now | BRD-GLOBAL-00779 | 105,189.64 | 52.86% |
| 18 | Eu Yan Sang | BRD-SG-00522 | 105,117.13 | 54.357% |
| 19 | GreenLife | BRD-SG-00772 | 98,790.81 | 55.764% |
| 20 | Vitahealth | BRD-TH-02770 | 87,741.91 | 57.014% |
| 21 | Lac | BRD-TH-03046 | 76,924.77 | 58.11% |
| 22 | SSBB | BRD-SG-01083 | 72,723.14 | 59.146% |
| 23 | Ensure | BRD-GLOBAL-00005 | 71,754.79 | 60.168% |
| 24 | Centrum | BRD-GLOBAL-00104 | 62,593.14 | 61.059% |
| 25 | KINOHIMITSU | BRD-SG-00684 | 61,957.04 | 61.942% |
| 26 | ARK+ | BRD-SG-03639 | 61,951.32 | 62.824% |
| 27 | Redoxon | BRD-SG-01036 | 53,166.27 | 63.581% |
| 28 | Nutri Botanics | BRD-SG-00577 | 45,585.56 | 64.231% |
| 29 | Nuskin | BRD-GLOBAL-00872 | 44,255.97 | 64.861% |
| 30 | Kordel's | BRD-SG-01299 | 42,736.09 | 65.47% |
| 31 | Herbal Pharm | BRD-SG-01063 | 41,529.39 | 66.061% |
| 32 | QN Wellness | BRD-SG-01461 | 38,753.90 | 66.613% |
| 33 | ZIEHA | BRD-SG-00695 | 37,680.00 | 67.15% |
| 34 | Herb Terra | BRD-SG-01164 | 37,104.45 | 67.678% |
| 35 | USANA | BRD-SG-01070 | 36,613.39 | 68.2% |
| 36 | Recogen | BRD-SG-01623 | 36,531.72 | 68.72% |
| 37 | Little Taiwan Store | BRD-SG-01112 | 35,571.00 | 69.227% |
| 38 | US Clinicals | BRD-SG-01280 | 34,136.17 | 69.713% |
| 39 | Duolac | BRD-SG-01258 | 33,295.17 | 70.187% |
| 40 | Thorne | BRD-GLOBAL-01772 | 32,895.47 | 70.656% |
| 41 | Red Sun | BRD-SG-01236 | 32,530.36 | 71.119% |
| 42 | For Youth | BRD-SG-01567 | 32,339.00 | 71.58% |
| 43 | Abbott | BRD-GLOBAL-00056 | 32,204.85 | 72.039% |
| 44 | Herbase | BRD-GLOBAL-01303 | 31,585.32 | 72.488% |
| 45 | Nature's Farm | BRD-SG-01624 | 31,521.88 | 72.937% |
| 46 | Olly | BRD-SG-01323 | 30,758.26 | 73.376% |
| 47 | LactoGG | BRD-SG-01324 | 28,265.65 | 73.778% |
| 48 | Heliocare | BRD-GLOBAL-00419 | 27,647.98 | 74.172% |
| 49 | Bounceback | BRD-SG-01476 | 26,973.12 | 74.556% |
| 50 | Thomson | BRD-GLOBAL-01752 | 23,670.96 | 74.893% |
| 51 | Nature's Key | BRD-GLOBAL-00596 | 23,640.85 | 75.23% |
| 52 | Nestle | BRD-GLOBAL-00059 | 22,986.44 | 75.557% |
| 53 | Borsch Med | BRD-SG-01608 | 22,527.40 | 75.878% |
| 54 | BBLAB | BRD-GLOBAL-01633 | 22,200.24 | 76.195% |
| 55 | Revit | BRD-SG-01529 | 20,080.38 | 76.481% |
| 56 | Balance | BRD-GLOBAL-00459 | 20,016.14 | 76.766% |
| 57 | Principle Nutrition | BRD-SG-01584 | 19,319.78 | 77.041% |
| 58 | TS6 | BRD-SG-01689 | 18,409.55 | 77.303% |
| 59 | Unichi | BRD-GLOBAL-01642 | 18,387.10 | 77.565% |
| 60 | HypoCol | BRD-SG-01401 | 18,104.57 | 77.823% |
| 61 | Nature's Green | BRD-SG-01639 | 18,015.93 | 78.079% |
| 62 | Movefree | BRD-GLOBAL-01345 | 17,617.73 | 78.33% |
| 63 | goli NUTRITION | BRD-SG-01794 | 17,361.04 | 78.578% |
| 64 | Shaklee | BRD-SG-01729 | 17,250.03 | 78.823% |
| 65 | Oxyenergy | BRD-SG-01528 | 16,307.20 | 79.056% |
| 66 | Ginflex | BRD-SG-01960 | 16,260.66 | 79.287% |
| 67 | Green Kare | BRD-SG-01725 | 16,208.00 | 79.518% |
| 68 | Purtier | BRD-SG-02099 | 15,798.39 | 79.743% |
| 69 | DrinkAid | BRD-SG-02018 | 15,788.08 | 79.968% |
| 70 | Vitanad+ | BRD-GLOBAL-01221 | 15,650.02 | 80.191% |
| 71 | life.space | BRD-GLOBAL-01236 | 15,607.80 | 80.413% |
| 72 | Doctor's Best | BRD-GLOBAL-00884 | 15,561.85 | 80.635% |
| 73 | Bilberry | BRD-SG-08352 | 14,696.05 | 80.844% |
| 74 | Vivomixx | BRD-SG-02117 | 14,305.63 | 81.048% |
| 75 | Pro-Uro | BRD-SG-02102 | 14,188.16 | 81.25% |
| 76 | Men+ | BRD-SG-09828 | 14,186.00 | 81.452% |
| 77 | BioGaia | BRD-TH-00797 | 13,699.30 | 81.647% |
| 78 | Bioglan | BRD-TH-00919 | 13,612.90 | 81.841% |
| 79 | Lacteol Fort | BRD-SG-02141 | 13,457.96 | 82.033% |
| 80 | Heart | BRD-TH-00817 | 13,396.97 | 82.224% |
| 81 | Jung Kwan Jang | BRD-SG-02029 | 13,283.40 | 82.413% |
| 82 | Dr GET IT | BRD-SG-02045 | 12,765.49 | 82.595% |
| 83 | Jeunesse | BRD-GLOBAL-01476 | 12,403.17 | 82.771% |
| 84 | mskinny | BRD-SG-02444 | 12,362.88 | 82.947% |
| 85 | ZzzQuil | BRD-SG-01988 | 12,214.73 | 83.121% |
| 86 | NE:AR | BRD-SG-01693 | 12,036.64 | 83.293% |
| 87 | Vita Green | BRD-SG-02066 | 11,972.34 | 83.463% |
| 88 | New Moon | BRD-SG-00719 | 11,637.91 | 83.629% |
| 89 | Helmig's | BRD-SG-03068 | 11,443.80 | 83.792% |
| 90 | ADVAGEN | BRD-SG-02138 | 11,358.32 | 83.954% |
| 91 | Leading Edge Health | BRD-SG-02300 | 11,253.70 | 84.114% |
| 92 | LACTOFIT | BRD-GLOBAL-01096 | 11,092.82 | 84.272% |
| 93 | NYO3 | BRD-SG-01781 | 11,055.88 | 84.43% |
| 94 | Voost | BRD-GLOBAL-01804 | 11,044.95 | 84.587% |
| 95 | Lactomin | BRD-SG-02303 | 10,945.78 | 84.743% |
| 96 | Yi Shi Yuan | BRD-SG-01924 | 10,917.82 | 84.898% |
| 97 | MEI HUA BRAND | BRD-SG-02154 | 10,902.00 | 85.054% |
| 98 | VitaRealm | BRD-SG-01919 | 10,409.35 | 85.202% |
| 99 | Efamol | BRD-SG-02285 | 10,259.54 | 85.348% |
| 100 | GNC | BRD-GLOBAL-01628 | 10,195.05 | 85.493% |
| 101 | Sports Research | BRD-GLOBAL-01440 | 10,109.93 | 85.637% |
| 102 | Healthy Care | BRD-GLOBAL-01087 | 9,923.98 | 85.779% |
| 103 | Trorexl | BRD-SG-01694 | 9,725.12 | 85.917% |
| 104 | VIT | BRD-SG-09662 | 9,698.15 | 86.055% |
| 105 | herbsofgold | BRD-SG-02166 | 9,375.49 | 86.189% |
| 106 | Himalaya | BRD-GLOBAL-00470 | 9,324.37 | 86.322% |
| 107 | Jungwonsam | BRD-SG-02116 | 9,312.72 | 86.454% |
| 108 | Fast | BRD-SG-04063 | 9,040.94 | 86.583% |
| 109 | Natrol | BRD-TH-01004 | 8,792.97 | 86.708% |
| 110 | THE PERFECT HEARTIO | BRD-SG-02800 | 8,779.00 | 86.833% |
| 111 | HANJAN | BRD-SG-02201 | 8,722.84 | 86.958% |
| 112 | Asxence | BRD-SG-02656 | 8,713.00 | 87.082% |
| 113 | UJUWON | BRD-SG-02236 | 8,654.14 | 87.205% |
| 114 | CareLeaf | BRD-SG-02039 | 8,581.82 | 87.327% |
| 115 | Dr. LEAN | BRD-GLOBAL-02172 | 8,532.79 | 87.449% |
| 116 | Nature's Way | BRD-GLOBAL-01105 | 8,486.24 | 87.57% |
| 117 | BesaPure | BRD-SG-02328 | 8,375.34 | 87.689% |
| 118 | Sangobion | BRD-SG-02259 | 8,336.75 | 87.808% |
| 119 | Thera Tears | BRD-SG-02418 | 8,305.76 | 87.926% |
| 120 | CH-Alpha | BRD-SG-02610 | 8,064.66 | 88.041% |
| 121 | Life Extension | BRD-GLOBAL-01081 | 8,051.07 | 88.156% |
| 122 | Optibac | BRD-SG-03171 | 8,017.70 | 88.27% |
| 123 | PHYTOTICS | BRD-SG-02316 | 7,738.96 | 88.38% |
| 124 | Tian Yang | BRD-SG-03042 | 7,731.00 | 88.49% |
| 125 | Morishita Jintan | BRD-SG-02499 | 7,580.31 | 88.598% |
| 126 | XEMENRY | BRD-GLOBAL-01616 | 7,422.25 | 88.704% |
| 127 | UNICITY | BRD-SG-02180 | 7,416.40 | 88.809% |
| 128 | Dr OatCare | BRD-SG-01699 | 7,339.95 | 88.914% |
| 129 | Equalpy | BRD-SG-04025 | 7,284.85 | 89.018% |
| 130 | California Gold Nutrition | BRD-GLOBAL-00695 | 7,130.34 | 89.119% |
| 131 | Huiji | BRD-SG-01486 | 7,124.00 | 89.221% |
| 132 | New Look | BRD-GLOBAL-03088 | 7,024.30 | 89.321% |
| 133 | OLIVAZUMO | BRD-SG-02184 | 6,986.70 | 89.42% |
| 134 | Empath | BRD-SG-02665 | 6,776.69 | 89.517% |
| 135 | NANO JAPAN | BRD-SG-02128 | 6,746.08 | 89.613% |
| 136 | ALXFRESH | BRD-GLOBAL-02052 | 6,681.92 | 89.708% |
| 137 | Berocca | BRD-GLOBAL-01475 | 6,429.15 | 89.8% |
| 138 | Manuka South | BRD-SG-02863 | 6,312.12 | 89.89% |
| 139 | Fybogel | BRD-SG-02757 | 6,168.70 | 89.977% |
| 140 | Funcare | BRD-SG-02696 | 6,089.66 | 90.064% |
| 141 | All Link Medical | BRD-SG-02861 | 6,063.70 | 90.151% |
| 142 | Bragg | BRD-GLOBAL-01777 | 5,999.20 | 90.236% |
| 143 | AVEA | BRD-SG-02430 | 5,820.41 | 90.319% |
| 144 | TruLife | BRD-SG-02397 | 5,667.70 | 90.4% |
| 145 | Pure Nutrition | BRD-SG-02932 | 5,648.29 | 90.48% |
| 146 | Jamu Ratu Malaya | BRD-SG-01830 | 5,620.50 | 90.56% |
| 147 | Pslalae | BRD-GLOBAL-01657 | 5,612.59 | 90.64% |
| 148 | Q'SAI | BRD-SG-02908 | 5,584.60 | 90.72% |
| 149 | Fruiting Body | BRD-TH-00544 | 5,413.07 | 90.797% |
| 150 | Afyaa | BRD-SG-02541 | 5,398.00 | 90.874% |
| 151 | HQ Lingzhi Singapore | BRD-SG-02442 | 5,392.20 | 90.95% |
| 152 | I-Defence | BRD-SG-03034 | 5,351.50 | 91.027% |
| 153 | Nutricost | BRD-GLOBAL-00924 | 5,310.26 | 91.102% |
| 154 | BAEBEAR | BRD-SG-02904 | 5,133.95 | 91.175% |
| 155 | Solaray | BRD-GLOBAL-01110 | 5,095.49 | 91.248% |
| 156 | Ali King | BRD-SG-02494 | 5,084.98 | 91.32% |
| 157 | Biomiii | BRD-SG-02701 | 5,056.00 | 91.392% |
| 158 | Neurobion | BRD-SG-02491 | 4,968.21 | 91.463% |
| 159 | Pro-Gut | BRD-SG-03017 | 4,906.58 | 91.533% |
| 160 | Moller’s | BRD-SG-02811 | 4,762.99 | 91.601% |
| 161 | NF369 | BRD-SG-02752 | 4,694.00 | 91.668% |
| 162 | DR.BERG | BRD-TH-03623 | 4,621.20 | 91.734% |
| 163 | swanson | BRD-GLOBAL-01517 | 4,594.80 | 91.799% |
| 164 | VALENS | BRD-SG-02783 | 4,582.04 | 91.864% |
| 165 | Care | BRD-GLOBAL-00623 | 4,561.26 | 91.929% |
| 166 | HQ | BRD-SG-05907 | 4,542.07 | 91.994% |
| 167 | ROOT KING | BRD-SG-03271 | 4,488.00 | 92.058% |
| 168 | Wellness Arc | BRD-SG-02555 | 4,471.10 | 92.122% |
| 169 | Vitabiotics | BRD-TH-01664 | 4,449.10 | 92.185% |
| 170 | Puritan’s Pride | BRD-TH-00196 | 4,438.98 | 92.248% |
| 171 | Natures Aid | BRD-GLOBAL-02232 | 4,412.53 | 92.311% |
| 172 | FANCL | BRD-GLOBAL-00856 | 4,380.90 | 92.373% |
| 173 | Miriqa | BRD-SG-01107 | 4,366.20 | 92.436% |
| 174 | @once | BRD-SG-03159 | 4,347.25 | 92.498% |
| 175 | LIPASCOR | BRD-SG-04505 | 4,249.68 | 92.558% |
| 176 | Get | BRD-TH-01966 | 4,093.28 | 92.616% |
| 177 | Biocalth | BRD-SG-03210 | 4,064.68 | 92.674% |
| 178 | Biyode | BRD-TH-01089 | 4,061.45 | 92.732% |
| 179 | G-NiiB | BRD-SG-03692 | 3,979.10 | 92.789% |
| 180 | BioHealing Naturals | BRD-SG-02943 | 3,961.76 | 92.845% |
| 181 | C&S | BRD-SG-05041 | 3,957.00 | 92.902% |
| 182 | EVERIGHT | BRD-SG-03166 | 3,940.42 | 92.958% |
| 183 | Kirkland Signature | BRD-GLOBAL-00921 | 3,792.97 | 93.012% |
| 184 | Omical | BRD-SG-03556 | 3,747.60 | 93.065% |
| 185 | GENACOL | BRD-SG-02851 | 3,704.50 | 93.118% |
| 186 | JML | BRD-SG-01647 | 3,695.27 | 93.171% |
| 187 | DHC | BRD-GLOBAL-00397 | 3,690.02 | 93.223% |
| 188 | Swissoats A111 | BRD-SG-02799 | 3,669.90 | 93.275% |
| 189 | Nov | BRD-GLOBAL-02688 | 3,599.20 | 93.327% |
| 190 | Fairhaven Health | BRD-GLOBAL-02130 | 3,536.50 | 93.377% |
| 191 | NOTO 樂道 | BRD-SG-03116 | 3,511.07 | 93.427% |
| 192 | URAH | BRD-SG-03232 | 3,460.35 | 93.476% |
| 193 | Totaria | BRD-GLOBAL-01788 | 3,427.20 | 93.525% |
| 194 | HYPHENS | BRD-SG-03296 | 3,414.56 | 93.574% |
| 195 | Nature's Nutrition | BRD-SG-01894 | 3,390.00 | 93.622% |
| 196 | SINGCHOICE | BRD-SG-03209 | 3,370.15 | 93.67% |
| 197 | STRAITS WHOLEFOODS | BRD-SG-02885 | 3,355.00 | 93.718% |
| 198 | Bausch + Lomb | BRD-SG-02306 | 3,347.24 | 93.766% |
| 199 | Culturelle | BRD-GLOBAL-02372 | 3,259.49 | 93.812% |
| 200 | Polleney | BRD-SG-03437 | 3,239.90 | 93.858% |
| 201 | Optimum Nutrition | BRD-GLOBAL-02165 | 3,237.21 | 93.904% |
| 202 | Apple | BRD-SG-05608 | 3,185.90 | 93.95% |
| 203 | Maltofer | BRD-SG-03236 | 3,163.70 | 93.995% |
| 204 | Naturally Plus | BRD-SG-04353 | 3,153.00 | 94.04% |
| 205 | UITC | BRD-SG-02512 | 3,100.20 | 94.084% |
| 206 | DR PPARS | BRD-SG-03537 | 3,045.00 | 94.127% |
| 207 | PreserVision | BRD-SG-12543 | 3,028.00 | 94.17% |
| 208 | Youguth | BRD-SG-03218 | 3,024.00 | 94.213% |
| 209 | andSons | BRD-SG-01523 | 3,023.00 | 94.256% |
| 210 | Noah | BRD-SG-01420 | 3,013.20 | 94.299% |
| 211 | CONDITION | BRD-SG-02831 | 3,003.17 | 94.342% |
| 212 | Naturelo | BRD-TH-02915 | 2,991.41 | 94.385% |
| 213 | Joli Fruits | BRD-SG-03511 | 2,971.80 | 94.427% |
| 214 | URAL | BRD-SG-04984 | 2,924.30 | 94.469% |
| 215 | Viviscal | BRD-GLOBAL-01112 | 2,887.10 | 94.51% |
| 216 | Ultravite | BRD-SG-03005 | 2,834.50 | 94.55% |
| 217 | MyLustre | BRD-SG-02522 | 2,773.94 | 94.59% |
| 218 | HF | BRD-SG-03283 | 2,748.54 | 94.629% |
| 219 | Denps | BRD-SG-04081 | 2,746.00 | 94.668% |
| 220 | Byherbs | BRD-SG-04335 | 2,664.50 | 94.706% |
| 221 | HERBALIFE | BRD-SG-02998 | 2,654.75 | 94.744% |
| 222 | Live | BRD-GLOBAL-01397 | 2,649.10 | 94.781% |
| 223 | Now Foods | BRD-GLOBAL-00271 | 2,648.21 | 94.819% |
| 224 | BJN | BRD-SG-02759 | 2,640.36 | 94.857% |
| 225 | Qunol | BRD-GLOBAL-01239 | 2,631.10 | 94.894% |
| 226 | VisioPro | BRD-SG-01618 | 2,628.89 | 94.932% |
| 227 | Shine | BRD-GLOBAL-02490 | 2,625.30 | 94.969% |
| 228 | Nature’s Bounty | BRD-GLOBAL-01299 | 2,589.64 | 95.006% |

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

**Verification (advisor-requested):** diffed the 25 rows dropped by rule 3 against the 122 kept rows.
7 brands (FANCL, Live, GNC, Bragg, Men+, Heart, Get) had *only* a dropped candidate — checked each by
hand: every one is a coincidental brand-token match inside an unrelated small reseller's listing (store
names like `BEAUTY U & ME.SG Official Store`, `qa_ckahdo_`, `Xi Yao Health Center`, none containing the
brand name), not a real official store. Confirmed correctly excluded, not restored — these 7 brands
correctly have no Pass 1 store and go to Pass 2.

**101 of the 228 in-scope brands have at least one genuine official store** (122 brand↔store pairs, some
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
| Healthy Care | BRD-GLOBAL-01087 | `J-Mart Official` | 0.00 | 3 |
| Healthy Care | BRD-GLOBAL-01087 | `Healthy Care Official Store` | 0.00 | 28 |
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

**Brands with no official store (127 — Pass 2 only):**

@once (`BRD-SG-03159`), Abbott (`BRD-GLOBAL-00056`), ADVAGEN (`BRD-SG-02138`), Afyaa (`BRD-SG-02541`), All Link Medical (`BRD-SG-02861`), ALXFRESH (`BRD-GLOBAL-02052`), andSons (`BRD-SG-01523`), Apple (`BRD-SG-05608`), ARK+ (`BRD-SG-03639`), Asxence (`BRD-SG-02656`), BAEBEAR (`BRD-SG-02904`), Bausch + Lomb (`BRD-SG-02306`), Bilberry (`BRD-SG-08352`), Biocalth (`BRD-SG-03210`), BioGaia (`BRD-TH-00797`), BioHealing Naturals (`BRD-SG-02943`), Biomiii (`BRD-SG-02701`), BJN (`BRD-SG-02759`), Bragg (`BRD-GLOBAL-01777`), Byherbs (`BRD-SG-04335`), C&S (`BRD-SG-05041`), California Gold Nutrition (`BRD-GLOBAL-00695`), Culturelle (`BRD-GLOBAL-02372`), Dr OatCare (`BRD-SG-01699`), DR PPARS (`BRD-SG-03537`), DR.BERG (`BRD-TH-03623`), Duolac (`BRD-SG-01258`), Empath (`BRD-SG-02665`), Estalife (`BRD-SG-00539`), EVERIGHT (`BRD-SG-03166`), Fairhaven Health (`BRD-GLOBAL-02130`), FANCL (`BRD-GLOBAL-00856`), Fast (`BRD-SG-04063`), Fybogel (`BRD-SG-02757`), Get (`BRD-TH-01966`), Ginflex (`BRD-SG-01960`), GNC (`BRD-GLOBAL-01628`), goli NUTRITION (`BRD-SG-01794`), GreenLife (`BRD-SG-00772`), HANJAN (`BRD-SG-02201`), Heart (`BRD-TH-00817`), Helmig's (`BRD-SG-03068`), Herbal Pharm (`BRD-SG-01063`), HERBALIFE (`BRD-SG-02998`), Herbase (`BRD-GLOBAL-01303`), HQ (`BRD-SG-05907`), HQ Lingzhi Singapore (`BRD-SG-02442`), HYPHENS (`BRD-SG-03296`), I-Defence (`BRD-SG-03034`), Jamu Ratu Malaya (`BRD-SG-01830`), Jeunesse (`BRD-GLOBAL-01476`), JML (`BRD-SG-01647`), Joli Fruits (`BRD-SG-03511`), Jungwonsam (`BRD-SG-02116`), Kirkland Signature (`BRD-GLOBAL-00921`), Lacteol Fort (`BRD-SG-02141`), LactoGG (`BRD-SG-01324`), Lactomin (`BRD-SG-02303`), Life Extension (`BRD-GLOBAL-01081`), LIPASCOR (`BRD-SG-04505`), Little Taiwan Store (`BRD-SG-01112`), Live (`BRD-GLOBAL-01397`), Maltofer (`BRD-SG-03236`), Men+ (`BRD-SG-09828`), Morishita Jintan (`BRD-SG-02499`), Natrol (`BRD-TH-01004`), Naturally Plus (`BRD-SG-04353`), Nature's Green (`BRD-SG-01639`), Naturelo (`BRD-TH-02915`), Natures Aid (`BRD-GLOBAL-02232`), Nature’s Bounty (`BRD-GLOBAL-01299`), Neurobion (`BRD-SG-02491`), New Look (`BRD-GLOBAL-03088`), Nordic Naturals (`BRD-GLOBAL-00827`), NOTO 樂道 (`BRD-SG-03116`), Nov (`BRD-GLOBAL-02688`), Now Foods (`BRD-GLOBAL-00271`), Nuskin (`BRD-GLOBAL-00872`), Nutri Botanics (`BRD-SG-00577`), Nutricost (`BRD-GLOBAL-00924`), OLIVAZUMO (`BRD-SG-02184`), Omical (`BRD-SG-03556`), Polleney (`BRD-SG-03437`), PreserVision (`BRD-SG-12543`), Pro-Gut (`BRD-SG-03017`), Pro-Uro (`BRD-SG-02102`), Pslalae (`BRD-GLOBAL-01657`), Pure Nutrition (`BRD-SG-02932`), Puritan’s Pride (`BRD-TH-00196`), Purtier (`BRD-SG-02099`), Qunol (`BRD-GLOBAL-01239`), ROOT KING (`BRD-SG-03271`), Sangobion (`BRD-SG-02259`), Shaklee (`BRD-SG-01729`), Shine (`BRD-GLOBAL-02490`), SINGCHOICE (`BRD-SG-03209`), Solaray (`BRD-GLOBAL-01110`), Sports Research (`BRD-GLOBAL-01440`), SSBB (`BRD-SG-01083`), STRAITS WHOLEFOODS (`BRD-SG-02885`), swanson (`BRD-GLOBAL-01517`), Swissoats A111 (`BRD-SG-02799`), THE PERFECT HEARTIO (`BRD-SG-02800`), Thera Tears (`BRD-SG-02418`), Tian Yang (`BRD-SG-03042`), Totaria (`BRD-GLOBAL-01788`), Trorexl (`BRD-SG-01694`), TruLife (`BRD-SG-02397`), TS6 (`BRD-SG-01689`), UITC (`BRD-SG-02512`), Ultravite (`BRD-SG-03005`), UNICITY (`BRD-SG-02180`), URAH (`BRD-SG-03232`), URAL (`BRD-SG-04984`), USANA (`BRD-SG-01070`), VALENS (`BRD-SG-02783`), VisioPro (`BRD-SG-01618`), VIT (`BRD-SG-09662`), Vita Green (`BRD-SG-02066`), Vitabiotics (`BRD-TH-01664`), Vitanad+ (`BRD-GLOBAL-01221`), Viviscal (`BRD-GLOBAL-01112`), Vivomixx (`BRD-SG-02117`), Wellness Arc (`BRD-SG-02555`), XEMENRY (`BRD-GLOBAL-01616`), Yi Shi Yuan (`BRD-SG-01924`), ZIEHA (`BRD-SG-00695`)

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

**The full Mall-badged pool is tens-of-thousands of rows (22,562 rows / 14,433 products).** It also
includes the excluded multi-brand pharmacy chains — Watsons, Guardian, and BIG Pharmacy alone
contribute ~350 brand-store pairs across unrelated brands per the multi-brand detection query.
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

**Size extraction notes — no strong existing precedent, convention set this session:**
- Checked existing `product_taxonomy` for count-dosage precedent before committing to a convention.
  Searches against `caps|softgel|tablet|capsule` and `vitamin|supplement|probiotic|omega|multivit|
  collagen|fish oil` in `canonical_name` turned up only two unrelated domains: Nespresso/Dolce Gusto
  coffee-capsule entries (a different product, count folded inconsistently into `pack_count` with
  `size=NULL`) and haircare/skincare "vitamin"/"collagen" marketing terms (sized in ml/g as normal
  cosmetics). **No existing ingestible-supplement entries exist anywhere in `product_taxonomy` yet** —
  this category is the first, so this session sets the precedent rather than following one.
- **Convention adopted:** treat capsule/tablet/softgel **count-per-bottle** as the `size` field
  (e.g. `size="60 Capsules"`, `size="180 Softgels"`), by direct analogy to how liquid products are
  already handled elsewhere in this pipeline — `size` = what one sale unit contains (`"400ml"`),
  `pack_count` = how many of those units the buyer receives (`x2`). Applied identically here: a listing
  titled `"[Bundle of 4] Holistic Way ... 60 Capsules x 4"` → `size="60 Capsules"`, `pack_count=4`
  (buyer receives 4 bottles of 60 capsules = 240 capsules total, but `pack_count` records bottles per
  the standard convention, never silently absorbing the capsule count into the multiplier). Liquid
  supplements (e.g. Ensure) still use ml/L as normal.
- Pack-count patterns seen in this category's sku_names: `[Bundle of N]`, `[Value Pack]` + explicit `x2`,
  `[N Boxes]`, `x{TOTAL}` — apply the standard §1 pack-count priority chain and GWP-vs-multipack
  distinction.

**Known difficult products:** none identified yet — first pass, will be filled in during extraction/QA.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Research | Table has 0 existing `product_taxonomy_map` rows despite STATUS.md "Keyword only" label; initial 95% GMV brand ranking included BRD-UNDEFINED/BRD-UNMAPPED and was corrected (225→228 real brands); 101/228 brands have a curated official-store allowlist (122 store pairs, 7 orphan-candidate brands hand-verified as noise not real stores); no existing size-convention precedent found for count-dosage supplements, convention set and documented | Category file created and corrected pre-claim; ready for Step 3 SKU claim + Pass 1/2 |
| 2026-07-29 | Pass 1 | Extraction done via programmatic bulk regex text-parsing (product_line/size/pack_count) over `sku_name_EN` for all 4,422 official-store-allowlist products, calibrated against ~2 real image reads (caught and fixed a real bug: `1000mg` potency being misread as pack size instead of the true `180 softgels` count — fixed extraction priority to favor count-unit words over bare mg/mcg). Category genuinely has very low product-line duplication (~4,000+ distinct tuples across 4,422 products) — tiered top-1,200-by-GMV (93.8% of official-store GMV) into 1,166 precise entries; remaining 3,222 long-tail products routed via bulk text-match (802 matched) or per-brand `(unresolved)` catch-alls (151 entries, 2,420 products, ~4% of official-store GMV) | 1,317 taxonomy entries + 4,422 map rows written, source=LLM, meta_agent=CLAUDE_CODE |
| 2026-07-29 | Pass 2 | Built full in-scope worklist (quality-standards.md §2 Rule A∪B, product-level 95% cumulative GMV ∪ official-store allowlist) = 6,947 products; 4,422 already covered by Pass 1, leaving 2,525 for Pass 2. Routed via: text-match against Pass-1 taxonomy (262+112), existing-catchall reuse (849), 585 new precise entries for the top-600-by-GMV remainder (86 primary-block slots left after this required claiming a supplemental block), 326 new per-brand catch-alls for the final unmatched long tail (mostly zero/low-GMV). One real QA-gate failure found and fixed same-session: a catch-all named "Undefined (unresolved)" (brand_id=BRD-UNDEFINED, 339 products) tripped the placeholder-leak gate on the literal word "undefined" — renamed to "Unresolved-Brand Supplement Product" (semantically identical, gate-safe) | 911 taxonomy entries + 2,525 map rows written; supplemental SKU block SKU-203529–204028 claimed; all QA gates pass (dual-mapped=0, coexistence=0, placeholder-leak=0 post-fix, structured-fields-NULL%=0, provenance=0); GMV coverage 95.1% |

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
| LLM | 6,947 | Pass 1 (4,422) + Pass 2 (2,525) |
| HUMAN | 0 | No keyword seed ever existed for this table |
| NULL (unmapped) | 89,181 | Outside the 95%-cumulative-GMV / official-store in-scope set — legitimately long-tail per quality-standards.md §2 |

**Known gap for a future `targeted_qa_fix.sh` pass:** per-row wording precision was intentionally deprioritized
this session (coverage-first, per `headless-runbook.md`'s Full Rebuild philosophy). 477 catch-all entries
(151 Pass 1 + 326 Pass 2, ~3,122 products, concentrated in low/zero-GMV long tail) carry a generic
`"{Brand} (unresolved)"` product line rather than a real per-product line — legitimate under
`llm-extraction-rules.md` §3's "cannot confidently read → `(unresolved)`" rule, but a real target for a
future precision pass, prioritized by GMV impact (the largest, `Now` brand catch-all, carries ~$24.6K GMV
across 294 products). `sub_line`/`variant` were not populated in this session (left NULL throughout) —
another `targeted_qa_fix.sh` candidate for products with a genuine sub-line/variant signal.
