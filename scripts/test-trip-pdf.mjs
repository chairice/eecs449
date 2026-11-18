// Real renderer coverage; no browser print dialog, network, worker or user records.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,mkdirSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {build} from '../web/.jac/client/node_modules/esbuild/lib/main.js';
import {tripPdfFixture} from './fixtures/trip-pdf.mjs';

const temporary=mkdtempSync(join(tmpdir(),'detour-pdf-test-'));
const root=fileURLToPath(new URL('..',import.meta.url));
await build({stdin:{contents:"export * from './trip_pdf'; export * from './trip_pdf_render';",resolveDir:join(root,'web/client'),loader:'ts'},
  bundle:true,platform:'browser',format:'esm',outfile:join(temporary,'export.mjs'),
  nodePaths:[join(root,'web/.jac/client/node_modules'),...String(process.env.DETOUR_PDF_NODE_PATH || '').split(':').filter(Boolean)],logLevel:'silent'});
const {build_trip_document,render_trip_pdf,pdf_money,pdf_public_url,pdf_observed_date}=await import(pathToFileURL(join(temporary,'export.mjs')));
process.on('exit',()=>rmSync(temporary,{recursive:true,force:true}));
const workerPython=join(root,'workers/.venv/bin/python');
function extractedPages(pdf){
  const file=join(temporary,'read-back.pdf');writeFileSync(file,new Uint8Array(pdf.output('arraybuffer')));
  return JSON.parse(execFileSync(workerPython,['-c','from pypdf import PdfReader;import json,sys;print(json.dumps([p.extract_text() for p in PdfReader(sys.argv[1]).pages]))',file],{encoding:'utf8'}));
}

test('PDF includes the entire committed logistics agenda and never mutates saved state',()=>{
  const state=tripPdfFixture();state.currentDay='not-the-offsite';state.snapshot.days.push({...state.snapshot.days[0],id:'last-day',date:'2026-11-25',title:'Last day',items:[]});
  const before=JSON.stringify(state),model=build_trip_document(state);
  assert.equal(model.days.length,2);assert.equal(model.days[0].items.length,5);assert.equal(model.travel[0].carrier,'American');
  assert.equal(model.travel[0].connectionPending,true);assert.equal(model.travel[0].price,'');assert.equal(JSON.stringify(state),before);
});
test('export projection excludes raw conversation, private context, pending edits, captures and unused alternatives',()=>{
  const state=tripPdfFixture();state.capturePath='/private/raw/capture';const model=JSON.stringify(build_trip_document(state));
  for(const value of ['MUST_NOT_EXPORT','/private/raw/capture','rental-evidence'])assert.ok(!model.includes(value),value);
});
test('amounts preserve unknown and actual zero, unit basis, starting prices and fee uncertainty',()=>{
  assert.equal(pdf_money(null),'');assert.equal(pdf_money(undefined),'');assert.equal(pdf_money(0),'$0');assert.equal(pdf_money(12345),'$123.45');
  const state=tripPdfFixture();state.offers[0].price={amountMinor:28000,currency:'USD',basis:'PER_PERSON',from:true,feesIncluded:null};
  assert.equal(build_trip_document(state).travel[0].price,'From $280 · per person · fees not confirmed');
});
test('observed quote dates render Unix seconds, milliseconds and ISO as dates, omitting invalid values',()=>{
  const instant=Date.parse('2026-11-16T12:34:56Z');
  for(const value of [instant/1000,instant,'2026-11-16T12:34:56Z','2026-11-16T12:34:56+00:00','2026-11-16'])assert.equal(pdf_observed_date(value),'Nov 16, 2026');
  for(const value of [null,undefined,'',NaN,Infinity,1e100,'not a date','1794795466','2026-02-30'])assert.equal(pdf_observed_date(value),'');
  const state=tripPdfFixture();state.offers[0].observedAt=instant/1000;
  assert.equal(build_trip_document(state).travel[0].observed,'Quote observed Nov 16, 2026');
  state.offers[0].observedAt='invalid';assert.equal(build_trip_document(state).travel[0].observed,'');
});
test('fixed, selected and booked arrangements retain distinct meaning and known costs remain separate',()=>{
  const state=tripPdfFixture();state.snapshot.legs.push({...state.snapshot.legs[0],id:'fixed',offerId:'',locked:true});
  state.budgetSummary={selectedQuoteSubtotals:{USD:28000},selectedEstimateSubtotals:{USD:40000},bookedSubtotals:{USD:12000}};
  let model=build_trip_document(state);assert.equal(model.travel[0].status,'Selected - not booked');assert.equal(model.travel[1].status,'Fixed');
  assert.deepEqual(model.costs.map(x=>x.label),['Bookings added','Selected quotes','Selected estimates']);
  state.snapshot.legs[0].bookingId='booking';state.snapshot.bookings=[{id:'booking',title:'User reported flight',status:'USER_REPORTED',details:'User supplied confirmation',amountMinor:0,currency:'USD'}];
  model=build_trip_document(state);assert.equal(model.travel[0].status,'Reported booking');assert.equal(model.bookings[0].amount,'$0');
  state.snapshot.bookings[0].status='CANCELLED';state.budgetSummary={bookedSubtotals:{},selectedQuoteSubtotals:{},selectedEstimateSubtotals:{}};
  state.snapshot.stays=[{id:'cancelled-stay',placeId:'sfo',status:'BOOKED',bookingId:'booking',checkIn:'2026-11-22',checkOut:'2026-11-25'}];
  model=build_trip_document(state);assert.equal(model.travel[0].status,'Cancelled booking');assert.equal(model.stays[0].status,'Cancelled booking');assert.equal(model.costs.length,0);
});
test('sourced segments preserve connection airports, flight duration, layover and dates',()=>{
  const state=tripPdfFixture();state.offers[0].flight.segments=[
    {fromCode:'SFO',toCode:'DEN',airline:'QA carrier',departDate:'2026-11-25',departTime:'07:00',arriveDate:'2026-11-25',arriveTime:'10:20',durationMinutes:140,layoverMinutes:75},
    {fromCode:'DEN',toCode:'XNA',departDate:'2026-11-25',departTime:'11:35',arriveDate:'2026-11-25',arriveTime:'14:00',durationMinutes:85,layoverMinutes:null},
  ];
  const model=build_trip_document(state);assert.equal(model.travel[0].connectionPending,false);
  assert.equal(model.travel[0].segments[0].route,'SFO > DEN');assert.equal(model.travel[0].segments[0].duration,'2h 20m');
  assert.equal(model.travel[0].segments[0].layover,'1h 15m');assert.match(model.travel[0].segments[1].schedule,/Nov 25, 2026 11:35 am/);
  state.offers[0].flight.segments[0].departTime='23:50';state.offers[0].flight.segments[0].arriveDate='2026-11-26';state.offers[0].flight.segments[0].arriveTime='03:10';
  const overnight=build_trip_document(state).travel[0].segments[0].schedule;assert.match(overnight,/Nov 25, 2026 11:50 pm/);assert.match(overnight,/Nov 26, 2026 3:10 am/);
});
test('activity actions and source references become public clickable links without capability URLs',()=>{
  const model=build_trip_document(tripPdfFixture());
  assert.ok(model.days[0].items[0].links.some(l=>l.url==='https://www.fishermanswharf.org/'));
  assert.ok(model.days[0].items[3].links.some(l=>l.label==='Ferry information'));
  for(const url of ['file:///private/secrets','javascript:alert(1)','https://localhost/test','http://127.0.0.1/','https://example.com/?guest_token=private','https://user:pass@example.com/'])assert.equal(pdf_public_url(url),'',url);
  assert.equal(pdf_public_url('https://example.com/flight?date=2026-11-25'),'https://example.com/flight?date=2026-11-25');
});
test('unpriced sourced journeys enrich only the exact saved leg and never synthesize a fare',()=>{
  const evidence=JSON.parse(readFileSync(new URL('./fixtures/studio-agenda-journey.json',import.meta.url),'utf8'));
  const state=tripPdfFixture(),leg=state.snapshot.legs[0];leg.offerId='';
  const signature=Object.fromEntries(['fromId','toId','mode','departDate','arriveDate','departTime','arriveTime','durationMinutes','offerId','bookingId'].map(field=>[field,leg[field] ?? (field==='durationMinutes'?null:'')]));
  const from=state.snapshot.places.find(p=>p.id===leg.fromId),to=state.snapshot.places.find(p=>p.id===leg.toId);
  Object.assign(signature,{fromQuery:from.query,fromLabel:from.label,toQuery:to.query,toLabel:to.label});
  state.flightJourneys=[{legId:leg.id,legSignature:signature,flight:evidence.flight,sourceUrl:evidence.sourceUrl,captureId:evidence.captureId}];
  const fresh=build_trip_document(state).travel[0];assert.equal(fresh.segments.length,2);assert.equal(fresh.segments[0].toCode,'LAX');assert.equal(fresh.price,'');
  assert.ok(fresh.links.some(link=>link.label==='Sourced flight details'));
  const original=structuredClone(state);
  for(const field of ['departTime','arriveTime','departDate','arriveDate','durationMinutes','fromId','toId','offerId','bookingId']){
    const changed=structuredClone(original);changed.snapshot.legs[0][field]=field==='durationMinutes'?500:'changed';
    assert.equal(build_trip_document(changed).travel[0].segments.length,0,field);
  }
  for(const field of ['query','label']){
    const changed=structuredClone(original);changed.snapshot.places[0][field]='Different airport identity';
    assert.equal(build_trip_document(changed).travel[0].segments.length,0,field);
  }
  delete state.flightJourneys[0].legSignature.bookingId;assert.equal(build_trip_document(state).travel[0].segments.length,0,'Incomplete signature');
  const selected=structuredClone(original);selected.snapshot.legs[0].offerId='flight-quote';selected.flightJourneys[0].legSignature.offerId='flight-quote';
  assert.equal(build_trip_document(selected).travel[0].detailsLabel,'Original quote notes');
});
test('legacy selected offer segments disappear after a conflicting known schedule edit',()=>{
  const state=tripPdfFixture(),evidence=JSON.parse(readFileSync(new URL('./fixtures/studio-agenda-journey.json',import.meta.url),'utf8'));
  state.offers[0].flight=evidence.flight;state.offers[0].price={amountMinor:28000,currency:'USD',basis:'PER_PERSON'};
  assert.equal(build_trip_document(state).travel[0].segments.length,2);
  state.snapshot.legs[0].departTime='08:00';const stale=build_trip_document(state).travel[0];
  assert.equal(stale.segments.length,0);assert.match(stale.price,/\$280/);assert.match(stale.schedule,/8:00 am/);
});
test('query-bound auxiliary locations supply PDF maps links and addresses without changing saved places',()=>{
  const state=tripPdfFixture(),place=state.snapshot.places.find(p=>p.id==='wharf');place.lat=null;place.lon=null;
  state.mapLocations=[{id:place.id,query:place.query,label:place.label,lat:37.808,lon:-122.4177,address:'Verified waterfront address',sourceUrl:'https://www.fishermanswharf.org/',private:'MUST_NOT_EXPORT_LOCATION_CONTEXT'}];
  const before=JSON.stringify(state),located=build_trip_document(state).days[0].items[0];
  assert.equal(located.address,'Verified waterfront address');assert.ok(located.links.some(link=>link.label==='Open in maps'));
  assert.equal(JSON.stringify(state),before);assert.ok(!JSON.stringify(build_trip_document(state)).includes('MUST_NOT_EXPORT_LOCATION_CONTEXT'));
  state.mapLocations[0].query='Different place';const stale=build_trip_document(state).days[0].items[0];
  assert.ok(!stale.links.some(link=>link.label==='Open in maps'));assert.notEqual(stale.address,'Verified waterfront address');
  state.mapLocations[0].query=place.query;state.mapLocations[0].label='Different identity';assert.ok(!build_trip_document(state).days[0].items[0].links.some(link=>link.label==='Open in maps'));
});
test('real PDF renders Unicode names, public source actions and numbered pages without remote assets',()=>{
  const model=build_trip_document(tripPdfFixture()),pdf=render_trip_pdf(model);
  assert.ok(pdf.getNumberOfPages()>=3);const bytes=new Uint8Array(pdf.output('arraybuffer'));
  assert.equal(Buffer.from(bytes.slice(0,4)).toString(),'%PDF');assert.ok(bytes.length>20000);
  if(process.env.DETOUR_PDF_SAMPLE){
    let sample=pdf;
    if(process.env.DETOUR_PDF_FLIGHT_EVIDENCE){
      const evidence=JSON.parse(readFileSync(process.env.DETOUR_PDF_FLIGHT_EVIDENCE,'utf8')),state=tripPdfFixture();
      const leg=state.snapshot.legs[0],from=state.snapshot.places.find(p=>p.id===leg.fromId),to=state.snapshot.places.find(p=>p.id===leg.toId);
      const signature=Object.fromEntries(['fromId','toId','mode','departDate','arriveDate','departTime','arriveTime','durationMinutes','offerId','bookingId'].map(field=>[field,leg[field] ?? (field==='durationMinutes'?null:'')]));
      Object.assign(signature,{fromQuery:from.query,fromLabel:from.label,toQuery:to.query,toLabel:to.label});
      state.flightJourneys=[{legId:leg.id,legSignature:signature,flight:evidence.flight,sourceUrl:evidence.sourceUrl,observedAt:evidence.observedAt,captureId:evidence.captureId}];
      state.snapshot.notes='QA sample combining the user-described offsite with live sourced flight connection details. Activity arrangements are provisional; this is not a booking.';
      sample=render_trip_pdf(build_trip_document(state));
    }
    mkdirSync(resolve(process.env.DETOUR_PDF_SAMPLE,'..'),{recursive:true});writeFileSync(process.env.DETOUR_PDF_SAMPLE,new Uint8Array(sample.output('arraybuffer')));
  }
});
test('short activities keep their title, notes and source actions on the same page in the actual offsite layout',()=>{
  const code="import importlib.util,json;spec=importlib.util.spec_from_file_location('qa_agenda','scripts/qa-studio-agenda.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);print(json.dumps(module.fixture()))";
  const state=JSON.parse(execFileSync(workerPython,['-c',code],{cwd:root,encoding:'utf8'}));
  if(process.env.DETOUR_PDF_FULL_SAMPLE)writeFileSync(process.env.DETOUR_PDF_FULL_SAMPLE,new Uint8Array(render_trip_pdf(build_trip_document(state)).output('arraybuffer')));
  const ferry=state.snapshot.days.find(day=>day.id==='bike-day').items.find(item=>item.id==='return-ferry');
  ferry.actions=[{label:'Ferry source regression',url:'https://www.goldengate.org/ferry/'}];
  const pages=extractedPages(render_trip_pdf(build_trip_document(state))).map(page=>page.replace(/\s+/g,' '));
  const titlePage=pages.findIndex(page=>page.includes(ferry.title));
  assert.ok(titlePage>=0);assert.ok(pages[titlePage].includes(ferry.notes));
  assert.equal(pages.findIndex(page=>page.includes('Ferry source regression')),titlePage,'Source action must stay with the activity.');
});
test('long trips and unbroken long text paginate completely instead of clipping the current view',()=>{
  const state=tripPdfFixture(),day=state.snapshot.days[0];
  state.snapshot.days=Array.from({length:30},(_,index)=>({...day,id:`day-${index}`,date:`2026-12-${String(index+1).padStart(2,'0')}`,title:`Day ${index+1}`,items:[{...day.items[0],notes:('Café Réveille has an intentionally long wrapping note. ').repeat(150)+ 'VERY_LONG_FINAL_STOP-'+ 'x'.repeat(300)}]}));
  const model=build_trip_document(state),pdf=render_trip_pdf(model);assert.equal(model.days.length,30);assert.ok(pdf.getNumberOfPages()>30);
  assert.ok(new Uint8Array(pdf.output('arraybuffer')).length>50000);
  const pages=extractedPages(pdf),whole=pages.join('').replace(/\s+/g,'');
  assert.equal(whole.split('VERY_LONG_FINAL_STOP').length-1,30,'All long notes must survive pagination.');
  assert.ok(whole.includes('Day30'));
  for(const page of pages){const body=page.split('\n').filter(Boolean).slice(1);assert.ok(!/^(?:Location details|Open in maps)/.test(body[0] || ''),'No orphan source action at the top of a continuation page.');}
  if(process.env.DETOUR_PDF_LONG_SAMPLE)writeFileSync(process.env.DETOUR_PDF_LONG_SAMPLE,new Uint8Array(pdf.output('arraybuffer')));
});
