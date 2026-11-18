"""Isolated, labelled saved-trip browser QA. Never reads a real user's trip.

Uses public historical research fixtures unchanged, the user's quoted bike plan
as layout data (not a verified activity schedule/weather forecast), and actual
captured unpriced American journey/photos. Creates only its own browser context.
Run with workers/.venv/bin/python scripts/qa-studio-agenda.py --base http://127.0.0.1:8000.
--account also creates a new isolated local QA account and tests real trip switching.
"""
import argparse,copy,json,os,secrets,sys,time,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'web'),str(ROOT/'workers')]
from server.planning_api import fresh
from server.planning_core import validate_trip,budget_summary
from playwright.sync_api import sync_playwright
os.environ['PLAYWRIGHT_BROWSERS_PATH']=str(ROOT/'workers/.browsers')
FIX=ROOT/'scripts/fixtures'
HISTORY=json.loads((FIX/'studio-agenda-research.json').read_text())
JOURNEY=json.loads((FIX/'studio-agenda-journey.json').read_text())
PHOTOS=json.loads((FIX/'studio-agenda-photos.json').read_text())

def fixture(manual=False,title='San Francisco team offsite'):
 state=fresh();s=state['snapshot'];s.update(title=title,detail='LOGISTICS',intent='BUSINESS',startDate='2026-11-22',endDate='2026-11-25')
 s['party']={'adults':1,'childrenAges':[],'rooms':1,'driverAge':None}
 s['places']=[{'id':'DTW','label':'Detroit (DTW)','query':'Detroit Metropolitan Airport DTW','kind':'AIRPORT','lat':42.2124,'lon':-83.3534,'timezone':'America/Detroit'}, {'id':'SFO','label':'San Francisco (SFO)','query':'San Francisco International Airport SFO','kind':'AIRPORT','lat':37.6213,'lon':-122.379,'timezone':'America/Los_Angeles'}, {'id':'XNA','label':'Northwest Arkansas (XNA)','query':'Northwest Arkansas National Airport XNA','kind':'AIRPORT','lat':36.2819,'lon':-94.3068,'timezone':'America/Chicago'}, {'id':'SF','label':'San Francisco','query':'San Francisco, California','kind':'CITY','lat':37.7749,'lon':-122.4194,'timezone':'America/Los_Angeles'}]+copy.deepcopy(PHOTOS)
 for place in s['places']:
  if place['id'] not in ['DTW','XNA']:place.setdefault('timezone','America/Los_Angeles')
 offers=copy.deepcopy(HISTORY['offers']);out=next(o for o in offers if o['category']=='FLIGHT' and o['query']['origin']=='DTW');hotel=next(o for o in offers if o['category'] in ['HOTEL','STAY'])
 f=out['flight'];s['legs']=[{'id':'outbound-selected','fromId':'DTW','toId':'SFO','mode':'FLIGHT','departDate':f['departDate'],'arriveDate':f['arriveDate'],'departTime':f['departTime'],'arriveTime':f['arriveTime'],'durationMinutes':f['durationMinutes'],'offerId':'' if manual else out['id'],'notes':'Manual QA travel fixture.' if manual else ''}, {'id':'return-user','fromId':'SFO','toId':'XNA','mode':'FLIGHT','departDate':'2026-11-25','arriveDate':'2026-11-25','departTime':'07:00','arriveTime':'15:28','durationMinutes':388,'locked':True,'notes':'User-provided selection: American, 1 stop. Fare not supplied; not a booking.'}]
 s['stays']=[{'id':'hotel-selected','placeId':'SF','propertyName':'User-provided overnight base' if manual else '', 'checkIn':'2026-11-22','checkOut':'2026-11-25','status':'UNPLANNED' if manual else 'SELECTED','offerId':'' if manual else hotel['id']}]
 notes='Outdoor, active offsite for about 8 people. Sunset is about 4:53 PM, so the ride is planned for daylight. Group bike rental, ferry schedule and a rain backup still to confirm; Sunday’s forecast showed a chance of light rain.'
 # Exact user-quoted plan. Timings/forecast remain unverified fixture content.
 activities=[('bike-pickup','Group bike pickup at Fisherman’s Wharf','ACTIVITY','wharf','09:30','10:15','Reserve bikes for 8 ahead of time.'), ('bridge-ride','Ride to Golden Gate Bridge and over to Sausalito','ACTIVITY','golden-gate','10:15','12:30','Waterfront path to the bridge, then cross and descend into Sausalito. Placeholder timing.'), ('team-lunch','Team lunch in Sausalito','MEAL','sausalito','12:30','14:00','Restaurant TBD; group of 8 may need a reservation.'), ('return-ferry','Ferry back to San Francisco','TRAVEL','sausalito','14:30','15:30','Ferry times and bike-on-board rules not yet checked; confirm return of rental bikes.'), ('team-dinner','Team dinner (optional)','MEAL','SF','18:30','20:30','Restaurant TBD.')]
 items=[{'id':i,'title':title,'kind':kind,'placeId':place,'startTime':start,'endTime':end,'notes':note,'optional':i=='team-dinner'} for i,title,kind,place,start,end,note in activities]
 s['days']=[{'id':'arrival-day','date':'2026-11-22','title':'Travel to San Francisco','overnightPlaceId':'SF','items':[]}, {'id':'bike-day','date':'2026-11-23','title':'Team bike day: Golden Gate & Sausalito','overnightPlaceId':'SF','notes':notes,'items':items}, {'id':'open-day','date':'2026-11-24','title':'Room around the offsite','overnightPlaceId':'SF','items':[]}, {'id':'return-day','date':'2026-11-25','title':'Heading home','overnightPlaceId':'','items':[]}]
 state['snapshot']=validate_trip(s);s=state['snapshot'];state.update(offers=[] if manual else offers,comparisonOffers=[],researchLinks=[],conversation=[{'role':'assistant','content':'Your saved trip is ready to explore.','offerIds':[]}])
 state['budgetSummary']=budget_summary(s,state['offers'])
 if not manual:
  leg=next(l for l in s['legs'] if l['id']=='return-user');places={p['id']:p for p in s['places']}
  sig={k:leg.get(k) for k in ['fromId','toId','mode','departDate','arriveDate','departTime','arriveTime','durationMinutes','offerId','bookingId']}
  sig.update(fromQuery=places['SFO']['query'],fromLabel=places['SFO']['label'],toQuery=places['XNA']['query'],toLabel=places['XNA']['label'])
  state['flightJourneys']=[{**copy.deepcopy(JOURNEY),'id':'journey-return-user','legId':'return-user','legSignature':sig}]
  state['researchSources']=copy.deepcopy(HISTORY.get('researchSources',[]))
 return state

def run(args):
 target=Path(args.output);target.mkdir(parents=True,exist_ok=True)
 checks={};errors=[];args.api_urls={};cap='guest_'+secrets.token_hex(32)
 def check(name,condition):
  assert condition,name
  checks[name]=True;print('PASS',name,flush=True)
 def rpc(route,value):route.fulfill(status=200,content_type='application/json',body=json.dumps({'ok':True,'type':'response','data':{'result':json.dumps(value),'reports':[]},'error':None}))
 def routes(page):
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('request',lambda request:args.api_urls.__setitem__(id(page),request.url.split('/function/')[0]) if '/function/' in request.url else None)
  page.route('**/function/planner_guest_weather',lambda route:rpc(route,{'status':'UNAVAILABLE','samples':[]}))
  page.route('**/function/planner_weather',lambda route:rpc(route,{'status':'UNAVAILABLE','samples':[]}))
  page.route('**/function/planner_guest_media',lambda route:rpc(route,{'tripId':json.loads(route.request.post_data_json['state_json'])['id'],'locations':[],'pending':False}))
  page.route('**/function/planner_media',lambda route:rpc(route,{'tripId':route.request.post_data_json['trip_id'],'locations':[],'pending':False}))
 def seed(page,state):
  page.goto(args.base+'/studio',wait_until='networkidle');page.wait_for_selector('#studio-prompt')
  page.evaluate('([state,cap])=>{localStorage.setItem("atlas.studio.v1.guest",JSON.stringify(state));localStorage.setItem("atlas.guest.capability.v1",cap);localStorage.setItem("atlas.studio.view.v1."+state.id,JSON.stringify({pane:"overview",phoneTab:"trip"}))}',[state,cap])
  page.reload(wait_until='networkidle');page.wait_for_selector('.studio-overview')
 def photo_wait(page):
  page.wait_for_function('Array.from(document.querySelectorAll("img")).every(e=>e.complete)',timeout=30000)
 def shot(page,name):page.screenshot(path=str(target/name),full_page=False)
 with sync_playwright() as p:
  browser=p.chromium.launch(headless=True);context=browser.new_context(viewport={'width':1440,'height':1000},accept_downloads=True,reduced_motion='reduce');page=context.new_page();routes(page)
  state=fixture();seed(page,state)
  check('logistics_days_visible',page.locator('[data-plan-item="bike-day"]').count()==1)
  check('full_saved_selected_hotel',HISTORY['offers'][6]['title'] in page.locator('.studio-overview').inner_text())
  check('selected_source_price_visible',page.locator('.studio-choice-footer strong').count()>=2)
  check('no_global_options_tab',page.get_by_role('navigation',name='Trip views').get_by_role('button',name='Options',exact=True).count()==0)
  check('empty_current_shortlist_does_not_hide_selected_choices',not state['comparisonOffers'] and page.locator('.studio-choice-card').count()>=3)
  photo_wait(page);check('verified_place_photo_loaded',page.locator('.studio-trip-photo img').evaluate_all('(images)=>images.some(image=>image.complete&&image.naturalWidth>0)'));shot(page,'32-detour-useful-trip-desktop.jpg')
  page.locator('[data-plan-item="outbound-selected"]').click();page.wait_for_selector('.studio-inspector');page.get_by_role('button',name='Compare alternatives',exact=True).click();page.wait_for_selector('.studio-flight-offer')
  check('comparison_from_selected_historical_choice',page.locator('.studio-flight-offer').count()==3)
  page.get_by_role('button',name='← Back to your trip',exact=True).click();page.wait_for_selector('.studio-inspector');page.get_by_role('button',name='Trip overview',exact=True).click()
  page.locator('[data-plan-item="bike-day"]').click();page.wait_for_selector('.studio-day-detail')
  check('offsite_practical_notes_visible','Reserve bikes for 8' in page.locator('.studio-day-detail').inner_text() and 'bike-on-board' in page.locator('.studio-day-detail').inner_text())
  check('unknown_restaurant_has_no_city_photo',page.locator('[data-plan-item="team-lunch"]').locator('xpath=ancestor::article[1]').locator('img').count()==0)
  check('day_stay_context_visible','Travel & stay this day' in page.locator('.studio-day-detail').inner_text())
  photo_wait(page);shot(page,'33-detour-bike-day-desktop.jpg')
  page.get_by_role('button',name='View day map ↗',exact=True).click();page.wait_for_selector('.studio-map');check('day_map_context_retained','Team bike day' in page.locator('.studio-map-day-context').inner_text());page.wait_for_function('Array.from(document.querySelectorAll(".leaflet-tile")).some(image=>image.complete&&image.naturalWidth>0)',timeout=15000);check('real_basemap_tiles_loaded',page.locator('.leaflet-tile').evaluate_all('(images)=>images.some(image=>image.complete&&image.naturalWidth>0)'));check('bike_map_excludes_other_day_airports',page.locator('.studio-map-label').filter(has_text='Detroit').count()==0 and page.locator('.studio-map-label').filter(has_text='(LAX)').count()==0);shot(page,'34-detour-bike-map-desktop.jpg')
  if args.layout_only:
   (target/'layout-results.json').write_text(json.dumps({'checks':checks,'errors':errors},indent=2));browser.close();return
  page.get_by_role('button',name='Your trip',exact=True).click();check('map_returns_to_same_day',page.locator('.studio-day-detail h2').inner_text().startswith('Team bike day'))
  page.reload(wait_until='networkidle');page.wait_for_selector('.studio-day-detail');check('day_survives_reload',page.locator('.studio-day-detail h2').inner_text().startswith('Team bike day'))
  page.locator('[data-plan-item="bridge-ride"]').click();page.wait_for_selector('.studio-inspector');photo_wait(page);check('actual_place_photo_in_item_detail',page.locator('.studio-detail-photo img').evaluate('(image)=>image.complete&&image.naturalWidth>0'))
  page.get_by_role('button',name='Day plan',exact=True).click();check('item_back_restores_day',page.locator('.studio-day-detail').count()==1)
  page.get_by_role('button',name='← Trip overview',exact=True).click();page.locator('[data-plan-item="return-user"]').click();page.wait_for_selector('.studio-inspector')
  check('actual_unpriced_connection_visible','LAX' in page.locator('.studio-flight-segments').inner_text() and '1h 26m connection' in page.locator('.studio-flight-segments').inner_text())
  check('unpriced_journey_has_no_invented_fare',page.locator('.studio-detail-quote').count()==0);shot(page,'35-detour-sourced-connection-desktop.jpg')
  with page.expect_download(timeout=30000) as download:page.get_by_role('button',name='Export PDF',exact=True).click()
  pdf=target/'detour-whole-trip.pdf';download.value.save_as(str(pdf));check('pdf_real_download',pdf.read_bytes().startswith(b'%PDF-') and pdf.stat().st_size>5000)
  if shutil.which('pdftotext'):
   text=subprocess.run(['pdftotext',str(pdf),'-'],capture_output=True,text=True,check=True).stdout
   check('pdf_contains_whole_saved_trip','Team bike day' in text and 'Group bike pickup' in text and 'Touchstone' in text and 'LAX' in text)
   check('pdf_excludes_conversation','Your saved trip is ready to explore' not in text)
  else:
   from pypdf import PdfReader
   text='\n'.join(p.extract_text() or '' for p in PdfReader(pdf).pages)
   check('pdf_contains_whole_saved_trip','Team bike day' in text and 'Group bike pickup' in text and 'Touchstone' in text and 'LAX' in text)
   check('pdf_excludes_conversation','Your saved trip is ready to explore' not in text)
  context.set_offline(True)
  with page.expect_download(timeout=30000) as offline_download:page.get_by_role('button',name='Export PDF',exact=True).click()
  offline_pdf=target/'detour-whole-trip-offline.pdf';offline_download.value.save_as(str(offline_pdf));context.set_offline(False)
  check('cached_offline_pdf_download',offline_pdf.read_bytes().startswith(b'%PDF-') and offline_pdf.stat().st_size>5000)

  page.get_by_role('button',name='Trip overview',exact=True).click();page.locator('[data-plan-item="bike-day"]').click();page.set_viewport_size({'width':390,'height':844});page.get_by_role('navigation',name='Mobile workspace').get_by_role('button',name='Trip',exact=True).click();page.wait_for_selector('.studio-day-detail')
  check('phone_no_outer_overflow',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
  check('phone_export_reachable',page.get_by_role('button',name='Export PDF',exact=True).is_visible());shot(page,'36-detour-bike-day-phone.jpg')
  page.get_by_role('navigation',name='Mobile workspace').get_by_role('button',name='Chat',exact=True).click();check('phone_composer_reachable',page.locator('#studio-prompt').is_visible());shot(page,'37-detour-conversation-phone.jpg')
  if args.account:
   account_test(browser,args,state,checks,errors,check,routes,target)
  check('no_browser_errors',not errors)
  result={'checks':checks,'errors':errors,'provenance':HISTORY['fixtureProvenance'],'activityWarning':'User-quoted plan layout fixture; rental/ferry/forecast claims are not live verified.','journeySource':JOURNEY['sourceUrl']}
  (target/'results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True);browser.close()

def account_test(browser,args,guest,checks,errors,check,routes,target):
 # New isolated account only. Import plan-only manual fixtures, never unowned
 # historical offers/journeys. Browser token stays inside its own context.
 context=browser.new_context(viewport={'width':1440,'height':1000});page=context.new_page();routes(page);manual=fixture(manual=True,title='QA bike offsite - first trip')
 page.goto(args.base+'/studio',wait_until='networkidle');page.evaluate('(state)=>localStorage.setItem("atlas.studio.v1.guest",JSON.stringify(state))',manual);page.reload(wait_until='networkidle');page.wait_for_selector('#studio-prompt')
 page.get_by_role('button',name='Save trip',exact=True).click();page.get_by_role('button',name='New here? Create an account',exact=True).click()
 email='detour-agenda-qa-'+secrets.token_hex(8)+'@example.invalid';password=secrets.token_urlsafe(24)
 page.get_by_label('Email',exact=True).fill(email);page.get_by_label('Password',exact=True).fill(password);page.get_by_role('button',name='Create account & save trip',exact=True).click();page.get_by_role('button',name='Sign out',exact=True).wait_for(timeout=30000)
 page.get_by_role('navigation',name='Mobile workspace').get_by_role('button',name='Trip',exact=True).click() if page.viewport_size['width']<760 else None
 page.get_by_role('button',name='Your trip',exact=True).click();page.locator('[data-plan-item="bike-day"]').click();page.wait_for_selector('.studio-day-detail')
 second=fixture(manual=True,title='QA second manual trip');second['snapshot']['days'][1]['title']='Second trip day'
 response=page.evaluate('''async ([state,api])=>{const token=localStorage.getItem('jac_token');const r=await fetch(api+'/function/planner_import',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify({state_json:JSON.stringify(state),token:''})});return {status:r.status,body:await r.text()}}''',[second,args.api_urls.get(id(page),args.base)])
 payload=json.loads(response['body']);value=payload.get('data',{}).get('result',payload);value=json.loads(value) if isinstance(value,str) else value
 check('isolated_second_manual_trip_imported',response['status']==200 and value.get('id')==second['id'])
 page.reload(wait_until='networkidle');page.wait_for_selector('.studio-day-detail')
 page.get_by_role('button',name='Your trips',exact=True).click();page.get_by_role('button',name=second['snapshot']['title']+' →',exact=True).click();page.wait_for_function('(title)=>document.querySelector(".studio-section-heading h2")?.textContent===title',arg=second['snapshot']['title'])
 check('account_switch_opens_other_trip',page.locator('.studio-section-heading h2').inner_text()==second['snapshot']['title'])
 page.get_by_role('button',name='Your trips',exact=True).click();page.get_by_role('button',name=manual['snapshot']['title']+' →',exact=True).click();page.wait_for_selector('.studio-day-detail')
 check('account_switch_restores_first_day','Team bike day' in page.locator('.studio-day-detail h2').inner_text());page.reload(wait_until='networkidle');page.wait_for_selector('.studio-day-detail');check('account_reopen_restores_day','Team bike day' in page.locator('.studio-day-detail h2').inner_text());page.screenshot(path=str(target/'38-detour-account-trip-reopen.jpg'))
 context.close()

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--base',default='http://127.0.0.1:8000');parser.add_argument('--output',default='/tmp/detour-agenda-browser');parser.add_argument('--account',action='store_true');parser.add_argument('--layout-only',action='store_true');run(parser.parse_args())
