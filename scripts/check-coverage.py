#!/usr/bin/env python3
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
rows=json.loads((root/'Resources/features.json').read_text())
shares=json.loads((root/'Resources/category-weights.json').read_text())
assert len({r['id'] for r in rows}) == len(rows)
assert sum(shares.values()) == 100
assert all(r['status'] in ['planned','inherited','implemented','verified'] for r in rows)
assert all(r['acceptance'] and r['weight'] > 0 for r in rows)
score=0
for category,share in shares.items():
    group=[r for r in rows if r['category']==category]
    verified=sum(r['weight'] for r in group if r['status']=='verified' and r['evidence'])
    category_score=verified/sum(r['weight'] for r in group)
    score+=share*category_score
    print(f'{category}: {category_score*100:.1f}% ({share}% of total)')
print(f'Accepted coverage: {score:.2f}%; target >=90% plus per-category and critical gates')
if any(r['status']=='verified' and not r['evidence'] for r in rows): raise SystemExit('Missing evidence')
