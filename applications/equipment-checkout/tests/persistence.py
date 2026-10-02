import os,json,re,sys
from pathlib import Path
import requests
os.environ.setdefault('DJANGO_SETTINGS_MODULE','config.settings')
import django
django.setup()
from board.models import Item,Loan
from django.contrib.auth import get_user_model
p=Path('.deployment/persistence.json')
s=requests.Session();base='http://127.0.0.1:8000'
if sys.argv[1]=='before':
 page=s.get(base+'/accounts/login/',timeout=20)
 token=re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"',page.text).group(1)
 response=s.post(base+'/accounts/login/',data={'username':'alex','password':os.environ['DEMO_PASSWORD'],'csrfmiddlewaretoken':token},timeout=20,allow_redirects=False)
 assert response.status_code==302
 item=Item.objects.get(asset_tag='MIC-01')
 response=s.post(base+f'/items/{item.pk}/borrow/',data={'csrfmiddlewaretoken':s.cookies['csrftoken']},headers={'HX-Request':'true'},timeout=20)
 assert response.status_code==200
 loan=Loan.objects.get(item=item,returned_at__isnull=True)
 p.write_text(json.dumps({'cookies':s.cookies.get_dict(),'loan':loan.pk,'checked_out_at':loan.checked_out_at.isoformat()}));p.chmod(0o600)
 print('Before restart: authenticated session and active microphone loan recorded.')
else:
 state=json.loads(p.read_text())
 for name,value in state['cookies'].items():
  s.cookies.set(name,value,domain='127.0.0.1',path='/')
 response=s.get(base+'/',timeout=20,allow_redirects=False)
 assert response.status_code==200
 assert f'data-loan="{state["loan"]}"' in response.text
 loan=Loan.objects.get(pk=state['loan'])
 assert loan.checked_out_at.isoformat()==state['checked_out_at'] and loan.returned_at is None
 response=s.post(base+f'/loans/{loan.pk}/return/',data={'csrfmiddlewaretoken':s.cookies['csrftoken']},headers={'HX-Request':'true'},timeout=20)
 assert response.status_code==200
 p.unlink()
 print('After process restart: same session authorized, same loan/timestamp persisted; return succeeded.')
