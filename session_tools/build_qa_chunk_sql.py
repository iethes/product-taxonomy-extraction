#!/usr/bin/env python3
import datetime, json, sys

chunk_path, out_path = sys.argv[1:3]
work = {str(x['product_id']): x for x in map(json.loads, open('/tmp/breakfastcereal_shopee_ID_v2_full_worklist.jsonl'))}
rows = list(map(json.loads, open(chunk_path)))
if len(rows) > 10:
    raise SystemExit('chunk exceeds 10 products')

def q(v):
    if v is None: return 'NULL'
    return "'" + str(v).replace('\\','\\\\').replace("'", "\\'") + "'"

def qs(v):
    return 'CAST(NULL AS STRING)' if v is None else q(v)

stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
sql = []
dicts = []
qas = []
filters = []
for d in rows:
    intent = d.get('intended_table_values') or {}
    w = work[str(d['product_id'])]
    if intent.get('dict'):
        dicts.append(intent['dict'])
    qa = intent.get('qa') if 'qa' in intent else (intent if intent.get('table') == 'product_id_dict_qa' else None)
    if qa:
        meta = {'source':'codex','qa_confidence':qa['qa_confidence'],'timestamp':stamp}
        if qa['qa_confidence'] == 'unconfident': meta['human_review'] = bool(qa.get('human_review',False))
        qas.append((w, qa, json.dumps(meta,separators=(',',':'))))
    if intent.get('table') == 'filter_breakfastcereal':
        meta = json.dumps({'source':'codex','timestamp':stamp},separators=(',',':'))
        filters.append((w, meta))

if len(dicts) > 10: raise SystemExit('chunk exceeds 10 dictionary identities')
if dicts:
    vals=[]
    cols=['keywords','keyword_typo','sku_type_complete','sub_brand','brand','flavour','kemasan','gramasi','units','bundling','bundle','pack_type','sub_segment','sub_category','manufacture','agegroup']
    seen=set()
    for d in dicts:
        key=(d['brand'],d['sku_type_complete'])
        if key in seen: continue
        seen.add(key)
        vals.append('STRUCT(' + ','.join(qs(d.get(c))+' AS '+c for c in cols) + ')')
    sql.append(f'''INSERT INTO `sincere-hearth-273704.breakfastcereal.breakfastcereal_dict` ({','.join(cols)})\nSELECT {','.join('s.'+c for c in cols)} FROM UNNEST([{','.join(vals)}]) s\nWHERE NOT EXISTS (SELECT 1 FROM `sincere-hearth-273704.breakfastcereal.breakfastcereal_dict` d WHERE d.brand=s.brand AND d.sku_type_complete=s.sku_type_complete);''')

if qas:
    structs=[]
    for w,qa,meta in qas:
        fields=[qs(w.get('image'))+' AS url',qs(w.get('sku_name'))+' AS keywords',qs(qa['brand'])+' AS brand',qs(str(w['product_id']))+' AS product_id',qs(w['ecommerce_platform'])+' AS ecommerce_platform',qs(w['sku_name'])+' AS sku_name',qs(qa['sku_type_complete'])+' AS sku_type_complete','CAST(NULL AS STRING) AS vlookup',qs(meta)+' AS _meta']
        structs.append('STRUCT(' + ','.join(fields) + ')')
    sql.append(f'''MERGE `sincere-hearth-273704.breakfastcereal.product_id_dict_qa` t\nUSING (SELECT * FROM UNNEST([{','.join(structs)}])) s\nON CAST(t.product_id AS STRING)=s.product_id AND t.ecommerce_platform=s.ecommerce_platform\n AND REGEXP_REPLACE(TRIM(t.sku_name), r'\\s+', ' ')=REGEXP_REPLACE(TRIM(s.sku_name), r'\\s+', ' ')\nWHEN MATCHED THEN UPDATE SET url=s.url,keywords=s.keywords,brand=s.brand,sku_type_complete=s.sku_type_complete,vlookup=s.vlookup,_meta=s._meta\nWHEN NOT MATCHED THEN INSERT (url,keywords,brand,product_id,ecommerce_platform,sku_name,sku_type_complete,vlookup,_meta) VALUES(s.url,s.keywords,s.brand,s.product_id,s.ecommerce_platform,s.sku_name,s.sku_type_complete,s.vlookup,s._meta);''')

if filters:
    structs=[]
    for w,meta in filters:
        structs.append('STRUCT('+','.join([qs(w['ecommerce_platform'])+' AS ecommerce',qs(str(w['product_id']))+' AS product_id',qs(w['sku_name'])+' AS sku_name',qs(w.get('merchant_id'))+' AS merchant_id',qs(meta)+' AS _meta'])+')')
    sql.append(f'''MERGE `sincere-hearth-273704.breakfastcereal.filter_breakfastcereal` t\nUSING (SELECT * FROM UNNEST([{','.join(structs)}])) s\nON CAST(t.product_id AS STRING)=s.product_id AND t.ecommerce=s.ecommerce\n AND REGEXP_REPLACE(TRIM(t.sku_name), r'\\s+', ' ')=REGEXP_REPLACE(TRIM(s.sku_name), r'\\s+', ' ')\nWHEN MATCHED THEN UPDATE SET merchant_id=s.merchant_id,_meta=s._meta\nWHEN NOT MATCHED THEN INSERT(ecommerce,product_id,sku_name,merchant_id,_meta) VALUES(s.ecommerce,s.product_id,s.sku_name,s.merchant_id,s._meta);''')

open(out_path,'w').write('\n'.join(sql)+'\n')
print(json.dumps({'products':len(rows),'dict_identities':len(dicts),'qa_rows':len(qas),'filter_rows':len(filters),'sql_file':out_path}))
