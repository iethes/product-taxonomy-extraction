"""
Master list of source tables in sincere-hearth-273704.master_clean_niq
Used by all pipeline scripts to iterate over categories.
"""

BQ_PROJECT = 'sincere-hearth-273704'
BQ_SOURCE_DATASET = 'master_clean_niq'
BQ_REFERENCE_DATASET = 'magpie_reference'
BQ_UNIVERSE_DATASET = 'magpie_universe'

SHEETS_ID = '1faNuuyFlYz4v-MdJO6lOaS_OZr6TZCSaIozRJl5kn3I'

TABLES_SG = [
    'shopee_sg_baby_accessories',
    'shopee_sg_beer_and_lager',
    'shopee_sg_beverages',
    'shopee_sg_breakfast_cereals',
    'shopee_sg_carbonated_drink',
    'shopee_sg_coffee',
    'shopee_sg_diapers',
    'shopee_sg_fabric_softener',
    'shopee_sg_facial_cleanser',
    'shopee_sg_facial_moisturiser',
    'shopee_sg_hair_conditioner_or_treatment',
    'shopee_sg_hand_and_body_moisturiser',
    'shopee_sg_health_food_drink',
    'shopee_sg_household_cleaner',
    'shopee_sg_infant_milk',
    'shopee_sg_laundry_detergent',
    'shopee_sg_liquid_soap',
    'shopee_sg_pet_food',
    'shopee_sg_shampoo',
    'shopee_sg_spirits',
    'shopee_sg_toilet_rolls',
    'shopee_sg_toothpaste',
    'shopee_sg_vitamin_mineral_health_supplements',
]

TABLES_TH = [
    'shopee_th_adult_diapers',
    'shopee_th_baby_diapers',
    'shopee_th_body_wash',
    'shopee_th_cleanser',
    'shopee_th_coffee',
    'shopee_th_conditioner',
    'shopee_th_detergent',
    'shopee_th_drinking_water',
    'shopee_th_fabric_softener',
    'shopee_th_liquid_milk',
    'shopee_th_make_up_face',
    'shopee_th_milk_powder',
    'shopee_th_moisturizer_for_body',
    'shopee_th_moisturizer_for_face',
    'shopee_th_pet_food',
    'shopee_th_shampoo',
    'shopee_th_softdrink',
    'shopee_th_suncare',
    'shopee_th_toothbrush',
    'shopee_th_toothpaste',
]

TABLES_ALL = TABLES_SG + TABLES_TH

def country_of(table: str) -> str:
    """Return 'SG' or 'TH' for a given master table name."""
    if '_sg_' in table:
        return 'SG'
    if '_th_' in table:
        return 'TH'
    raise ValueError(f"Cannot determine country from table name: {table}")
