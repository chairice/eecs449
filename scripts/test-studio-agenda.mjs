// Render the saved LOGISTICS plan, not just the transient post-agent focus.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import React from '../web/.jac/client/node_modules/react/index.js';
import {renderToStaticMarkup} from '../web/.jac/client/node_modules/react-dom/server.node.js';
import * as helpers from '../web/.jac/client/compiled/client/planning_state.js';
const jsx=(type,props,children)=>React.createElement(type??React.Fragment,props,...(children??[]));
const Icon=({name})=>React.createElement('svg',{'data-icon':name,'aria-hidden':true});
const money_label=(amount,currency)=>new Intl.NumberFormat('en-US',{style:'currency',currency}).format(amount/100);
function load(name,names,extra={}) {
 const source=readFileSync(new URL(`../web/.jac/client/compiled/components/${name}.js`,import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace(/^export .*;\n/gm,'');
 return runInNewContext(`${source}\n({${names}});`,{...helpers,__jacJsx:jsx,Icon,window:{Intl},money_label,useJacState:initial=>({val:initial,set(){}}),useEffect(){},...extra});
}
const offersUI=load('StudioOffers','FlightIdentity,FlightSchedule,flight_duration,flight_stops,offer_price,offer_basis');
const tripUI=load('StudioTripPlan','TripPhoto,PhotoCredit,TripChoiceCard,TripDayCard,FlightSegments',offersUI);
const views=load('TripStudio','StudioOverview,StudioDay',{...offersUI,...tripUI,StudioWeather:()=>null});
const {StudioDetails}=load('StudioDetails','StudioDetails',{...offersUI,...tripUI,StudioWeather:()=>null});
const noop=()=>{}, render=(Component,props)=>renderToStaticMarkup(React.createElement(Component,props));
const flight={id:'flight-quote',title:'Observed American option',category:'FLIGHT',provider:'Observed provider',sourceUrl:'https://example.com/observed-flight',query:{origin:'SFO',destination:'XNA',departDate:'2026-11-25'},flight:{airline:'American',departDate:'2026-11-25',arriveDate:'2026-11-25',departTime:'07:00',arriveTime:'15:28',durationMinutes:388,stops:1},price:{amountMinor:45300,currency:'USD',basis:'PER_PERSON'},details:'Connection airport was not captured.'};
const hotel={id:'hotel-quote',title:'Observed waterfront hotel',category:'STAY',sourceUrl:'https://example.com/observed-hotel',location:'Fisherman’s Wharf',price:{amountMinor:24500,currency:'USD',basis:'PER_NIGHT'}};
const day={id:'offsite',date:'2026-11-23',title:'Team bike day: Golden Gate & Sausalito',overnightPlaceId:'SF',notes:'Rental, ferry schedule and rain backup still to confirm.',items:[{id:'bikes',title:'Group bike pickup',kind:'ACTIVITY',placeId:'WHARF',startTime:'09:30',endTime:'10:15',notes:'Reserve bikes for 8 ahead of time.',locked:true},{id:'ride',title:'Ride to Golden Gate Bridge and Sausalito',kind:'ACTIVITY',placeId:'BRIDGE',startTime:'10:15',endTime:'12:30',notes:'Placeholder timing.'}]};
const snapshot={title:'San Francisco offsite',detail:'LOGISTICS',startDate:'2026-11-22',endDate:'2026-11-25',places:[{id:'SF',label:'San Francisco',kind:'CITY'},{id:'WHARF',label:'Fisherman’s Wharf',kind:'PLACE'},{id:'BRIDGE',label:'Golden Gate Bridge',kind:'PLACE'},{id:'SFO',label:'San Francisco (SFO)',kind:'AIRPORT'},{id:'XNA',label:'Northwest Arkansas (XNA)',kind:'AIRPORT'}],legs:[{id:'return',fromId:'SFO',toId:'XNA',mode:'FLIGHT',...flight.flight,offerId:flight.id}],stays:[{id:'stay',placeId:'SF',checkIn:'2026-11-22',checkOut:'2026-11-25',propertyName:'',offerId:hotel.id,status:'SELECTED'}],rentals:[],days:[day,{id:'return-day',date:'2026-11-25',title:'Heading home',items:[],overnightPlaceId:''}],bookings:[],unresolved:[],budget:{amountMinor:null}};
const resources={offers:[flight,hotel],comparisonOffers:[],researchSources:[]};

test('LOGISTICS overview exposes all saved days and actual commitments after reopening',()=>{
 const html=render(views.StudioOverview,{snapshot,resources,onDay:noop,onContext:noop,onCompare:noop});
 assert.match(html,/Team bike day: Golden Gate &amp; Sausalito/);assert.match(html,/9:30 am/);assert.match(html,/Group bike pickup/);assert.match(html,/data-plan-item="offsite"/);
 assert.match(html,/Heading home/);assert.match(html,/Observed waterfront hotel/);assert.match(html,/\$245/);assert.match(html,/per night/);
 assert.match(html,/American/);assert.match(html,/7:00 am/);assert.match(html,/3:28 pm/);assert.match(html,/\$453/);assert.match(html,/Selected/);
 assert.doesNotMatch(html,/Stay to find/);
});

test('day agenda adds related travel/stay context without changing persisted days',()=>{
 const before=JSON.stringify(snapshot);const html=render(views.StudioDay,{day:snapshot.days[1],snapshot,resources,onBack:noop,onContext:noop,onCompare:noop,onMap:noop,onDiscuss:noop,onDay:noop});
 assert.match(html,/Check out/);assert.match(html,/Observed waterfront hotel/);assert.match(html,/American/);assert.match(html,/View day map/);assert.doesNotMatch(html,/Day details/);
 assert.equal(JSON.stringify(snapshot),before);assert.equal(helpers.day_context(day,snapshot).stays.length,1);
 assert.deepEqual(Array.from(helpers.day_focus_ids(snapshot.days[1],snapshot)),['SFO','XNA','SF']);
});

test('status joins distinguish cancelled, user-reported, confirmed and fixed records',()=>{
 const value={...snapshot,bookings:[{id:'b',status:'CANCELLED'}]};const item={bookingId:'b',status:'BOOKED',locked:true,offerId:flight.id};
 assert.equal(helpers.trip_item_status(item,value),'Cancelled');value.bookings[0].status='USER_REPORTED';assert.equal(helpers.trip_item_status(item,value),'User reported');
 value.bookings[0].status='BOOKED';assert.equal(helpers.trip_item_status(item,value),'Booked');
 assert.equal(helpers.trip_item_status({locked:true},value),'Fixed');assert.equal(helpers.trip_item_status({offerId:'quote'},value),'Selected');
});

test('selected flight details keep captured descriptions and never invent a connection',()=>{
 const html=render(StudioDetails,{item:{id:'return',kind:'legs',label:'SFO → XNA',value:snapshot.legs[0]},snapshot,resources,onBack:noop,onContext:noop,onCompare:noop,onResearch:noop});
 assert.match(html,/Connection airport was not captured/);assert.match(html,/Check connection details/);assert.doesNotMatch(html,/Dallas|Denver/);
});

test('captured segments become a complete ordered journey with explicit layover',()=>{
 const html=render(tripUI.FlightSegments,{flight:{segments:[{fromCode:'SFO',toCode:'DFW',airline:'American',flightNumber:'AA123',departDate:'2026-11-25',departTime:'07:00',arriveDate:'2026-11-25',arriveTime:'12:30',layoverMinutes:80},{fromCode:'DFW',toCode:'XNA',airline:'American',departDate:'2026-11-25',departTime:'13:50',arriveDate:'2026-11-25',arriveTime:'15:28',layoverMinutes:null}]}});
 assert.match(html,/SFO → DFW/);assert.match(html,/DFW → XNA/);assert.match(html,/1h 20m connection in DFW/);assert.match(html,/AA123/);
});

test('photo resolution never uses a city image as a selected hotel photograph',()=>{
 const value={...snapshot,places:snapshot.places.map(p=>p.id==='SF'?{...p,photoUrl:'https://example.com/city-photo'}:p)};
 assert.equal(helpers.trip_photo(value,snapshot.stays[0],hotel).photoUrl,undefined);
 assert.equal(helpers.day_photo(day,value).photoUrl,'https://example.com/city-photo');
 const html=render(tripUI.TripPhoto,{photo:{photoUrl:'https://example.com/actual-photo',photoAttribution:'Example photographer · CC BY',photoSourceUrl:'https://example.com/photo-source'}});
 assert.match(html,/Example photographer/);assert.match(html,/href="https:\/\/example.com\/photo-source"/);
});

test('a captured unpriced journey enriches only its exact saved leg identity and schedule',()=>{
 const captured=JSON.parse(readFileSync(new URL('./fixtures/studio-agenda-journey.json',import.meta.url),'utf8'));
 const leg={...snapshot.legs[0],offerId:'',bookingId:''};const value={...snapshot,legs:[leg]};
 const signature=Object.fromEntries(['fromId','toId','mode','departDate','arriveDate','departTime','arriveTime','durationMinutes','offerId','bookingId'].map(key=>[key,leg[key]]));
 Object.assign(signature,{fromQuery:undefined,fromLabel:'San Francisco (SFO)',toQuery:undefined,toLabel:'Northwest Arkansas (XNA)'});
 const state={...resources,flightJourneys:[{...captured,legId:leg.id,legSignature:signature}]};
 assert.equal(helpers.trip_flight(state,leg,value),state.flightJourneys[0].flight);assert.equal(helpers.selected_offer(state,leg),null);
 assert.equal(helpers.trip_flight(state,{...leg,fromId:'XNA'},value).segments,undefined);
 assert.equal(helpers.trip_flight(state,{...leg,departTime:'06:38'},value).segments,undefined);
 const changed={...value,places:value.places.map(p=>p.id==='SFO'?{...p,query:'A different airport'}:p)};
 assert.equal(helpers.trip_flight(state,leg,changed).segments,undefined);
});

test('selected-offer journey segments cannot override a conflicting saved schedule',()=>{
 const state={offers:[{...flight,flight:{...flight.flight,departTime:'06:38',segments:[{fromCode:'SFO',toCode:'DFW'}]}}]};
 assert.equal(helpers.trip_flight(state,snapshot.legs[0],snapshot).segments,undefined);
});

test('overnight arrival day focuses its arrival airport and excludes unrelated future journeys',()=>{
 const arrival={id:'night-arrival',fromId:'DTW',toId:'SFO',departDate:'2026-11-22',arriveDate:'2026-11-23'};
 const value={...snapshot,legs:[arrival,...snapshot.legs]};const before=JSON.stringify(value);
 const ids=Array.from(helpers.day_focus_ids(day,value));assert.ok(ids.includes('SFO'));assert.ok(!ids.includes('DTW'));assert.ok(!ids.includes('XNA'));
 const mapped=helpers.day_map_snapshot(value,day);assert.deepEqual(Array.from(mapped.legs,l=>l.id),['night-arrival']);
 assert.equal(mapped.places.length,value.places.length);assert.equal(JSON.stringify(value),before);
});

test('travel-only day cards show their saved schedule instead of suggesting an empty day',()=>{
 const html=render(tripUI.TripDayCard,{day:snapshot.days[1],index:1,snapshot,onDay:noop});
 assert.match(html,/Depart/);assert.match(html,/7:00 am/);assert.match(html,/San Francisco \(SFO\) → Northwest Arkansas \(XNA\)/);assert.doesNotMatch(html,/Room to explore|No plans added/);
 const empty=render(tripUI.TripDayCard,{day:{id:'empty',date:'2026-12-01',title:'Free day',items:[]},index:2,snapshot,onDay:noop});assert.match(empty,/No plans added/);
});

test('long planning notes stay fully available without crowding the activity timeline',()=>{
 const notes='User-supplied planning context. '.repeat(40);const html=render(views.StudioDay,{day:{...day,notes},snapshot,resources,onBack:noop,onContext:noop,onCompare:noop,onMap:noop,onDiscuss:noop,onDay:noop});
 assert.match(html,/<details class="studio-day-planning-notes"><summary>Planning notes/);assert.ok(html.includes(notes));assert.match(html,/Group bike pickup/);
});

test('activity previews expose practical links without nested controls or raw credit boilerplate',()=>{
 const notes='Full supplier and group logistics context. '.repeat(20);
 const action={label:'Bike rental rates',url:'https://example.com/bikes'};
 const value={...day,items:[{...day.items[0],notes,actions:[action]}]};
 const html=render(views.StudioDay,{day:value,snapshot,resources,onBack:noop,onContext:noop,onCompare:noop,onMap:noop,onDiscuss:noop,onDay:noop});
 assert.match(html,/class="studio-timeline-note-preview"/);assert.ok(html.includes(notes));assert.match(html,/Read details/);assert.match(html,/href="https:\/\/example.com\/bikes"/);
 assert.doesNotMatch(html,/<button\b[^>]*>(?:(?!<\/button>)[\s\S])*<a\b/);
 const credit=render(tripUI.PhotoCredit,{photo:{photoSourceUrl:'https://example.com/source',photoAttribution:'No machine-readable author provided. Assumed based on copyright claims.',photoLicense:'CC BY-SA 4.0'}});
 const visible=credit.replace(/<[^>]+>/g,'');assert.match(visible,/Photo credit/);assert.doesNotMatch(visible,/machine-readable|assumed/i);assert.match(credit,/title="No machine-readable/);
});
