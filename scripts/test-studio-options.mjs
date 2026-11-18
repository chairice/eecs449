// Exercise the emitted Jac picker and its real rendered information hierarchy.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import React from '../web/.jac/client/node_modules/react/index.js';
import {renderToStaticMarkup} from '../web/.jac/client/node_modules/react-dom/server.node.js';
import * as helpers from '../web/.jac/client/compiled/client/planning_state.js';

const source = readFileSync(new URL('../web/.jac/client/compiled/components/StudioOffers.js', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '').replace(/^export .*;\n/gm, '');
const ui = runInNewContext(`${source}\n({StudioOffer,StudioOptions,FlightSchedule,FlightIdentity,offer_groups,offer_group_id,offer_price,offer_basis,airline_identity,flight_day_offset,flight_duration,flight_stops,conversation_offers});`, {
  ...helpers, window:{Intl},
  useJacState:initial=>({val:initial,set(){}}),useEffect(){},
  Icon:({name})=>React.createElement('svg',{'data-icon':name,'aria-hidden':true}),
  __jacJsx:(type,props,children)=>React.createElement(type??React.Fragment,props,...(children??[])),
});
const tripSource=readFileSync(new URL('../web/.jac/client/compiled/components/StudioTripPlan.js',import.meta.url),'utf8')
  .replace(/^import .*;\n/gm,'').replace(/^export .*;\n/gm,'');
const tripUI=runInNewContext(`${tripSource}\n({TripPhoto,FlightSegments});`,{
  ...helpers,...ui,Icon:({name})=>React.createElement('svg',{'data-icon':name,'aria-hidden':true}),
  __jacJsx:(type,props,children)=>React.createElement(type??React.Fragment,props,...(children??[])),
});
const detailSource=readFileSync(new URL('../web/.jac/client/compiled/components/StudioDetails.js',import.meta.url),'utf8')
  .replace(/^import .*;\n/gm,'').replace(/^export .*;\n/gm,'');
const StudioDetails=runInNewContext(`${detailSource}\nStudioDetails;`,{
  ...helpers,...ui,...tripUI,StudioWeather:()=>null,
  Icon:({name})=>React.createElement('svg',{'data-icon':name,'aria-hidden':true}),
  __jacJsx:(type,props,children)=>React.createElement(type??React.Fragment,props,...(children??[])),
});
const noop=()=>{};
const render=(component,props)=>renderToStaticMarkup(React.createElement(component,props));
const text=html=>html.replace(/<details\b[^>]*>[\s\S]*?<\/details>/g,'').replace(/<[^>]+>/g,' ');
const plain=value=>JSON.parse(JSON.stringify(value));
const flight=(id,overrides={})=>({
  id,category:'FLIGHT',title:'Frontier DTW → SFO via Denver (late arrival)',provider:'Google Travel',
  query:{category:'FLIGHT',origin:'DTW',destination:'SFO',departDate:'2026-11-22',adults:1,childrenAges:[]},
  flight:{airline:'Frontier',departDate:'2026-11-22',arriveDate:'2026-11-23',departTime:'20:31',arriveTime:'00:43',durationMinutes:432,stops:1},
  price:{amountMinor:28000,currency:'USD',basis:'PER_PERSON',from:true,quantity:1,estimatedTotalMinor:null,feesIncluded:null},
  bookingUrl:'https://www.google.com/travel/flights?test=observed',sourceUrl:'https://www.google.com/travel/flights?test=observed',
  details:'A researched Frontier connection via Denver.',location:'',photoUrl:'',...overrides,
});
const offers=[flight('out1'),flight('out2',{flight:{airline:'Delta',stops:0}}),
  flight('back',{query:{category:'FLIGHT',origin:'SFO',destination:'XNA',departDate:'2026-11-25',adults:1,childrenAges:[]}})];

function find(tree,predicate) {
  if(!tree||typeof tree!=='object')return null;
  if(predicate(tree))return tree;
  for(const child of React.Children.toArray(tree.props?.children)) {const found=find(child,predicate);if(found)return found;}
  return null;
}

test('different flight legs, travel dates, and parties remain separate; repeated carrier results share their leg',()=>{
  const values=[...offers,
    flight('party',{query:{...offers[0].query,adults:2}}),
    flight('date',{query:{...offers[0].query,departDate:'2026-11-23'}})];
  const before=JSON.stringify(values),groups=plain(ui.offer_groups(values));
  assert.equal(groups.length,4);
  assert.deepEqual(groups[0].offers.map(o=>o.id),['out1','out2']);
  assert.equal(groups[0].label,'DTW → SFO');assert.equal(groups[1].label,'SFO → XNA');
  assert.equal(JSON.stringify(values),before);
});

test('child-age ordering does not create duplicate searches or mutate source evidence',()=>{
  const first=flight('family1',{query:{...offers[0].query,childrenAges:[12,8]}});
  const next=flight('family2',{query:{...offers[0].query,childrenAges:[8,12]}});
  assert.equal(ui.offer_group_id(first),ui.offer_group_id(next));
  assert.deepEqual(first.query.childrenAges,[12,8]);
});

test('hotels and vacation stays share their dated stay search; cars remain distinct',()=>{
  const stay={...flight('hotel'),category:'HOTEL',query:{location:'San Francisco',checkIn:'2026-11-22',checkOut:'2026-11-25',adults:1,rooms:1,childrenAges:[]}};
  const groups=plain(ui.offer_groups([stay,{...stay,id:'home',category:'STAY'},
    {...flight('car'),category:'CAR',query:{pickupLocation:'SFO',dropoffLocation:'SFO',pickupDate:'2026-11-22',dropoffDate:'2026-11-25',pickupTime:'12:00',dropoffTime:'12:00',driverAge:30}}]));
  assert.deepEqual(groups.map(g=>[g.category,g.count]),[['STAY',2],['CAR',1]]);
});

test('the controlled picker renders only the selected flight leg and exposes the other as a tab',()=>{
  let chosenGroup='';const groupId=ui.offer_group_id(offers[2]);
  const tree=ui.StudioOptions({offers,links:[],groupId,onGroup:id=>chosenGroup=id,onChoose:noop,onContext:noop,selectedOfferIds:[],busy:false});
  const html=renderToStaticMarkup(tree);
  assert.equal((html.match(/class="studio-offer studio-flight-offer/g)||[]).length,1);
  assert.match(html,/SFO → XNA/);assert.match(html,/DTW → SFO/);
  assert.ok(!html.includes('aria-label="Departure time"')||html.includes('studio-flight-schedule'));
  const tab=find(tree,e=>e.type==='button'&&e.props.role==='tab'&&e.props['aria-selected']===false);
  assert.ok(tab);tab.props.onClick();assert.equal(chosenGroup,ui.offer_group_id(offers[0]));
});

test('primary flight row shows the airline once, actual schedule, stop count and next-day arrival without provider/route repetition',()=>{
  const html=render(ui.StudioOffer,{offer:offers[0],onContext:noop,onChoose:noop});
  const visible=text(html);
  assert.equal((visible.match(/Frontier/g)||[]).length,1);
  assert.doesNotMatch(visible,/Google Travel|DTW|SFO|late arrival|Discuss option|stop\(s\)/);
  assert.match(html,/src="\/static\/assets\/airlines\/f9\.png"/);
  assert.match(visible,/8:31 pm/);assert.match(visible,/12:43 am/);
  assert.match(visible,/7h 12m/);assert.match(visible,/1 stop/);assert.match(html,/<sup[^>]*>\+1<\/sup>/);
  assert.match(visible,/From \$280/);assert.doesNotMatch(visible,/\$280\.00/);
  assert.match(html,/aria-label="View flight on Google Travel"/);
  assert.match(html,/<summary aria-label="Details for [^"]+"[^>]*><svg/);
});

test('next-day indication uses actual dates and duration/stops never infer missing research',()=>{
  assert.equal(ui.flight_day_offset({departDate:'2026-10-31',arriveDate:'2026-11-01'}),'+1');
  assert.equal(ui.flight_day_offset({departDate:'2026-11-22',arriveDate:'2026-11-22'}),'');
  assert.equal(ui.flight_day_offset({departTime:'20:31',arriveTime:'00:43'}),'');
  assert.equal(ui.flight_duration({departTime:'20:31',arriveTime:'00:43'}),'');
  assert.equal(ui.flight_stops({}),'');
  const html=render(ui.StudioOffer,{offer:flight('incomplete',{flight:{airline:'United'}}),onContext:noop});
  assert.doesNotMatch(html,/NaN|Nonstop|\+1/);
});

test('real marks are local assets and unknown or mixed airlines use a neutral fallback',()=>{
  for(const name of ['Frontier Airlines','United','Delta Air Lines','American (Envoy)','Alaska','Southwest']) {
    const identity=ui.airline_identity({airline:name});
    assert.ok(identity.logo.startsWith('/static/assets/airlines/'));
    assert.ok(existsSync(new URL('../web/assets/'+identity.logo.replace('/static/assets/',''),import.meta.url)));
  }
  for(const name of ['Cape Air','United + Delta','']) {
    assert.equal(ui.airline_identity({airline:name}).logo,'');
    const html=render(ui.FlightIdentity,{flight:{airline:name}});
    assert.doesNotMatch(html,/<img/);assert.match(html,/<svg/);
  }
});

test('choosing passes the exact offer reference without mutating it or marking it booked',()=>{
  const offer=flight('selected'),before=JSON.stringify(offer),calls=[];
  const tree=ui.StudioOffer({offer,onContext:noop,onChoose:(...args)=>calls.push(args),selected:false,busy:false});
  find(tree,e=>e.type==='button'&&e.props.className==='studio-option-choose').props.onClick();
  assert.deepEqual(calls,[['selected',offer.title]]);assert.equal(JSON.stringify(offer),before);
  const selected=ui.StudioOffer({offer,onContext:noop,onChoose:noop,selected:true,busy:false});
  assert.equal(find(selected,e=>e.type==='button'&&e.props.className==='studio-option-choose').props.disabled,true);
});

test('unit price basis and sourced estimated totals remain distinct, while cent precision is retained',()=>{
  const stay=flight('stay',{category:'STAY',title:'A real place',flight:null,price:{amountMinor:12000,currency:'USD',basis:'PER_NIGHT',from:true,quantity:3,estimatedTotalMinor:36000,feesIncluded:null}});
  const html=render(ui.StudioOffer,{offer:stay,onContext:noop,onChoose:noop});
  assert.match(text(html),/From \$120/);assert.match(text(html),/per night/);assert.match(text(html),/≈ \$360 for 3 nights/);
  assert.equal(ui.offer_price(flight('car',{price:{amountMinor:26994,currency:'USD',basis:'TOTAL',from:false}})),'$269.94');
  assert.equal(ui.offer_price({price:null,totalMinor:null}),'Price on request');
});

test('historical messages resolve only their own source-backed offers, including an explicitly empty set',()=>{
  assert.deepEqual(plain(ui.conversation_offers({offerIds:['back']},offers,[])).map(o=>o.id),['back']);
  assert.deepEqual(plain(ui.conversation_offers({offerIds:[]},offers,offers)),[]);
});

test('focused flight detail uses the itinerary schedule and one carrier identity without provider-button bloat',()=>{
  const value={...offers[0].flight,id:'leg1',mode:'FLIGHT',offerId:'out1',fromId:'dtw',toId:'sfo',locked:true,notes:'Keep this commitment.',sourceRefs:[]};
  const html=render(StudioDetails,{item:{id:'leg1',label:'DTW → SFO',kind:'legs',value},snapshot:{places:[]},resources:{offers},weather:null,onBack:noop,onContext:noop});
  const visible=text(html);
  assert.equal((visible.match(/DTW → SFO/g)||[]).length,1);
  assert.equal((html.match(/class="studio-airline"/g)||[]).length,1);
  assert.match(html,/A researched Frontier connection via Denver/);
  assert.match(visible,/8:31 pm/);assert.match(visible,/Nov 23/);assert.match(visible,/Fixed/);
  assert.doesNotMatch(visible,/Google Travel|View on|stop\(s\)/);
  assert.match(html,/class="studio-detail-discuss"/);
  assert.doesNotMatch(html,/studio-primary/);
  const quote=html.match(/<div class="studio-detail-quote">([\s\S]*?)<\/div>/)?.[1]??'';
  assert.match(quote,/Ask Detour/);assert.match(quote,/View fare/);
});

test('booking details and original notes remain accessible after simplifying the inspector',()=>{
  const details='Confirmation EXAMPLE-BOOKING\nCheck-in after 3 PM.';
  const html=render(StudioDetails,{item:{id:'booking1',label:'Hotel booking',kind:'bookings',value:{id:'booking1',details,notes:'Supplied cancellation terms.',sourceRefs:[]}},snapshot:{places:[]},resources:{offers:[]},weather:null,onBack:noop,onContext:noop});
  assert.ok(html.includes(details));assert.match(html,/Supplied cancellation terms\./);assert.match(html,/class="studio-detail-notes"/);
});
