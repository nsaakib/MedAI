import pytest
from app import brand_options as b

@pytest.mark.parametrize('name,strength,form',[
 ('Empatab M','5mg/500mg','Tablet'),('Empatab M','5 mg+500 mg','Tab'),
 ('Empatab M','5/500 mg','tablet'),('Empatab M 5mg/500mg','','tablet'),
 ('Nabuflex','500 mg','tablet'),('Delanix','30 mg','capsule'),
 ('Delanix','30 mg','Enteric-coated capsule'),
 ('Napa 500','500 mg','tablet'),('Zopride 50mg','50 mg','Tab'),
])
def test_supported(name,strength,form):
 original,choices=b.options(dict(name=name,strength=strength,form=form,verified=True),b.load_catalog())
 assert original and len(choices)==4
 assert all(b.formulation(x)==b.formulation(original) for x in choices)

@pytest.mark.parametrize('changes',[
 {'strength':'12.5mg/500mg'},{'strength':'500mg/5mg'}, {'strength':'5mg/1000mg'},
 {'strength':'5/500'},{'strength':'5mg/ml'}, {'form':'capsule'}, {'form':'XR tablet'},
 {'name':'Empatab M XR'},{'name':'Empatab M 12.5mg/500mg'},
 {'instruction':'extended release'}, {'route':'injection'}, {'verified':False},
])
def test_reject(changes):
 m=dict(name='Empatab M',strength='5mg/500mg',form='tablet',verified=True)
 m.update(changes)
 assert b.options(m,b.load_catalog())==(None,[])

def test_catalog():
 rows=b.load_catalog()
 assert len(rows)==50 and len({r['id'] for r in rows})==50
 for r in rows:
  original, choices=b.options(dict(r,verified=True),rows)
  assert original==r and len(choices)==4,r
  assert all(b.formulation(x)==b.formulation(r) for x in choices)
