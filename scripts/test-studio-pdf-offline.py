#!/usr/bin/env python3
"""Cold production-client PDF regression; run preview-studio.py on localhost first.

Uses a fresh browser context and a labelled fixture, never existing accounts or
trip storage. All API responses are intercepted; no backend/model calls occur.
"""
import argparse,json,os,sys,subprocess,tempfile
from urllib.parse import urlparse
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'web'),str(ROOT/'workers')]
from server.planning_core import validate_trip,journey_signature
os.environ['PLAYWRIGHT_BROWSERS_PATH']=str(ROOT/'workers/.browsers')
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base',default='http://127.0.0.1:8002')
parser.add_argument('--output',type=Path,default=None)
args=parser.parse_args()
parsed=urlparse(args.base)
if parsed.scheme!='http' or parsed.hostname not in {'127.0.0.1','localhost'} or parsed.path not in {'','/'}:
 parser.error('--base must be a local HTTP production preview')
BASE=args.base.rstrip('/')
OUTPUT=args.output or Path(tempfile.mkdtemp(prefix='detour-pdf-offline-'))
OUTPUT.mkdir(parents=True,exist_ok=True)
fixture_code="""
import {tripPdfFixture} from './scripts/fixtures/trip-pdf.mjs';
const state=tripPdfFixture();state.snapshot.schemaVersion=1;
state.snapshot.days.push({id:'return-day',date:'2026-11-25',title:'Return travel',overnightPlaceId:'',notes:'Return flight appears in this day’s travel commitments.',items:[]});
state.offers=state.offers.filter(offer=>offer.id==='flight-quote');
Object.assign(state,{pending:null,activeJob:'',nextDecision:{},researchLinks:[],comparisonOffers:[],routes:[],daylight:[],mapLocations:[],preferences:{values:{},forgotten:[],applied:[]}});
console.log(JSON.stringify(state));
"""
state=json.loads(subprocess.check_output(['node','--input-type=module','-e',fixture_code],cwd=ROOT,text=True))
state['snapshot']=validate_trip(state['snapshot']);state['undo']=None
state['weather']={'status':'READY','samples':[],'refreshing':False}
journey=json.loads((ROOT/'scripts/fixtures/studio-agenda-journey.json').read_text())
leg=state['snapshot']['legs'][0]
state['flightJourneys']=[{'id':'qa-offline-journey','legId':leg['id'],'legSignature':journey_signature(state['snapshot'],leg),'flight':journey['flight'],'sourceUrl':journey['sourceUrl'],'captureId':journey['captureId'],'observedAt':journey['observedAt']}]
state['updatedAt']='2026-11-16T17:00:00Z'
results=[];errors=[];console=[];requests=[]
def check(name,ok):
 results.append({'name':name,'passed':bool(ok)})
 if not ok:raise AssertionError(name)
def envelope(value):return {'ok':True,'type':'response','data':{'result':json.dumps(value),'reports':[]},'error':None}
with sync_playwright() as playwright:
 browser=playwright.chromium.launch(headless=True,args=['--disable-dev-shm-usage'])
 context=browser.new_context(accept_downloads=True,viewport={'width':1440,'height':1000})
 page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)));page.on('console',lambda m:console.append({'type':m.type,'text':m.text}) if m.type=='error' else None)
 page.on('request',lambda r:requests.append(r.url))
 def api(route):
  name=route.request.url.rsplit('/',1)[-1]
  if name=='planner_status':value={'workerReady':True}
  elif name=='planner_guest_weather':value=state['weather']
  elif name=='planner_guest_media':value={'tripId':state['id'],'status':'READY','locations':[],'refreshing':False}
  else:raise AssertionError('Unexpected backend write/request '+name)
  route.fulfill(status=200,content_type='application/json',body=json.dumps(envelope(value)))
 context.route('**/function/**',api)
 page.add_init_script("if(!localStorage.getItem('detour.offline.qa.seeded')){localStorage.setItem('atlas.studio.v1.guest',"+json.dumps(json.dumps(state))+ ");localStorage.setItem('atlas.studio.view.v1.'+"+json.dumps(state['id'])+",JSON.stringify({pane:'day',dayId:'bike-day',selectedId:'bike-day'}));localStorage.setItem('detour.offline.qa.seeded','1');}")
 try:
  page.goto(BASE+'/studio',wait_until='networkidle')
  page.get_by_role('button',name='Export PDF',exact=True).wait_for()
  page.evaluate("async()=>{await navigator.serviceWorker.register('/sw.js');await navigator.serviceWorker.ready;}")
  page.wait_for_function('navigator.serviceWorker.controller !== null',timeout=30000)
  cached=page.evaluate("async()=>{let urls=[];for(const name of await caches.keys()){let c=await caches.open(name);urls.push(...(await c.keys()).map(r=>r.url));}return urls;}")
  check('lazy_pdf_renderer_precached',any('trip_pdf_render' in u for u in cached))
  check('first_export_not_loaded_online',not page.evaluate("performance.getEntriesByType('resource').some(e=>e.name.includes('trip_pdf_render'))"))
  # Keep a specific day open when exporting the entire saved plan.
  if page.locator('[data-plan-item="bike-day"]').count():page.locator('[data-plan-item="bike-day"]').click()
  page.get_by_role('button',name='Map',exact=True).first.click()
  check('map_open_before_offline',page.locator('.studio-map').count()==1)
  await_before=page.evaluate("JSON.parse(localStorage.getItem('atlas.studio.v1.guest'))")
  context.set_offline(True)
  page.reload(wait_until='domcontentloaded')
  page.get_by_role('button',name='Export PDF',exact=True).wait_for(timeout=30000)
  page.wait_for_timeout(500)
  check('offline_reload_preserves_day_map',page.locator('.studio-map').count()==1)
  before=page.evaluate("localStorage.getItem('atlas.studio.v1.guest')")
  before_view=page.evaluate("localStorage.getItem('atlas.studio.view.v1.'+"+json.dumps(state['id'])+")")
  check('first_export_still_lazy_offline',not page.evaluate("performance.getEntriesByType('resource').some(e=>e.name.includes('trip_pdf_render'))"))
  with page.expect_download(timeout=30000) as pending:page.get_by_role('button',name='Export PDF',exact=True).click()
  download=pending.value;path=OUTPUT/'download.pdf';download.save_as(str(path))
  check('real_pdf_downloaded_offline',Path(path).read_bytes().startswith(b'%PDF'))
  check('saved_state_unchanged',page.evaluate("localStorage.getItem('atlas.studio.v1.guest')")==before)
  check('view_state_unchanged',page.evaluate("localStorage.getItem('atlas.studio.view.v1.'+"+json.dumps(state['id'])+")")==before_view)
  check('no_uncaught_browser_errors',not errors)
  check('no_export_alert',page.get_by_role('alert').count()==0)
  from pypdf import PdfReader
  reader=PdfReader(path);contents='\n'.join(pdf_page.extract_text() for pdf_page in reader.pages)
  check('entire_trip_not_current_day',all(value in contents for value in ['Team bike day: Golden Gate & Sausalito','Return travel','Group bike pickup','Ride to Golden Gate','Team lunch','Ferry back','Team dinner']))
  check('actual_sourced_connection_in_pdf','SFO  >  LAX  >  XNA' in contents and 'AA 2211' in contents and 'AA 6348' in contents and '1h 26m layover' in contents)
  check('original_quote_context_labelled','Original quote notes' in contents)
  check('travel_day_not_called_empty','No additional activities planned.' in contents)
  check('accented_names_preserved','Café Réveille' in contents)
  check('no_invented_fare_or_private_context','$' not in contents and 'MUST_NOT_EXPORT' not in contents)
  embedded=[]
  for pdf_page in reader.pages:
   for reference in pdf_page['/Resources']['/Font'].values():
    for descendant in reference.get_object().get('/DescendantFonts',[]):
     descriptor=descendant.get_object().get('/FontDescriptor')
     if descriptor:embedded.append('/FontFile2' in descriptor.get_object())
  check('fonts_embedded',bool(embedded) and all(embedded))
  check('all_pages_numbered',all(f'{index+1} / {len(reader.pages)}' in pdf_page.extract_text() for index,pdf_page in enumerate(reader.pages)))
  page.screenshot(path=str(OUTPUT/'browser.png'),full_page=True)
 finally:
  (OUTPUT/'results.json').write_text(json.dumps({'results':results,'errors':errors,'console':console,'cached':locals().get('cached',[]),'requests':requests},indent=2))
  browser.close()
print(json.dumps({'passed':sum(r['passed'] for r in results),'total':len(results),'errors':errors,'output':str(OUTPUT)}))
