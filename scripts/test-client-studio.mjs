// Exercise emitted Jac handlers against the conversation-led state contract.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { randomUUID } from 'node:crypto';
import * as helpers from '../web/.jac/client/compiled/client/planning_state.js';

function fixture({pollResponse, authenticated=false, withUndo=false} = {}) {
  const snapshot = { schemaVersion: 1, id: 'trip_ui', title: 'My trip', startDate: '', endDate: '', detail:'DETAILED',
    places: [], stays: [], legs: [], rentals:[], bookings: [], unresolved: [], budget:{amountMinor:null,currency:'USD'},
    days: [{ id: 'day_1', date: '2026-12-26', title: 'An open day', overnightPlaceId: '', notes: '', items: [] }] };
  const state = { id: snapshot.id, snapshot, revision: 4, conversation: [], workingContext: {}, summary: '',
    jobs: {}, offers: [], comparisonOffers:[], researchLinks: [], nextDecision: {}, preferences: {},
    undo:withUndo?{revision:4,label:'Rest break'}:null,
    pending: { id: 'decision_1', baseRevision: 4, snapshot: {...snapshot,startDate:'2026-12-27'},question:'Move to Sunday?' } };
  const cells = [], refs = [], writes = [], calls = [], effects = [], listeners = new Map();
  let cellIndex = 0, refIndex = 0;
  const trigger={isConnected:true,focused:false,focus(){this.focused=true;}};
  const document={activeElement:trigger,querySelector:()=>null,
    addEventListener:(name,handler)=>listeners.set(name,handler),
    removeEventListener:(name,handler)=>{if(listeners.get(name)===handler)listeners.delete(name);}};
  const source = readFileSync(new URL('../web/.jac/client/compiled/components/TripStudio.js', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
  const component = runInNewContext(`${source}\nTripStudio;`, {
    ...helpers,
    __jacJsx: (type, props, children) => ({type, props, children}),
    useJacState(initial) {
      const i = cellIndex++;
      if (!cells[i]) cells[i] = {val: i === 0 ? structuredClone(state) : initial, set(value) {this.val=value;}};
      return cells[i];
    },
    useRef(initial) {return refs[refIndex++] ??= {current:initial};},
    useEffect(callback,deps) {effects.push({callback,deps});}, useMemo: callback=>callback(), useLocation:()=>({key:'test',state:null}),
    signed_in:()=>authenticated, account_email:()=>authenticated?'test@example.com':'',
    window: {setInterval:()=>1,clearInterval(){},navigator:{onLine:true}}, document, save_preferences:()=>{},
    save_session: (_,value)=>{writes.push(structuredClone(value));return '';},
    guest_token:()=>'guest_test_capability', planner_id:prefix=>`${prefix}_${randomUUID()}`,
    planner_today:()=>'2026-11-15', planner_zone:()=>'America/Detroit',
    HEADER:'', Brand:function Brand(){}, PlannerMap:()=>{}, ChatMarkdown:()=>{}, StudioOffer:function StudioOffer(){},StudioDetails:function StudioDetails(){},StudioWeather:()=>{},
    conversation_offers:(turn,offers,fallback)=>Object.hasOwn(turn,"offerIds")?offers.filter(o=>(turn.offerIds??[]).includes(o.id)):fallback,
    planner_list:async()=>JSON.stringify([{id:state.id,title:state.snapshot.title}]),planner_deleted:async()=>'[]',
    __jacCallFunction: async (name,args)=>{
      calls.push({name,args});
      if(name==='planner_guest_start') return JSON.stringify({jobId:'job_ui'});
      if(name==='planner_guest_poll') return JSON.stringify(pollResponse ? pollResponse() : {id:'job_ui',status:'SUCCEEDED',progress:'Complete',result:{}});
      if(name==='planner_guest_stage') return JSON.stringify({...state,activeJob:'',pending:null,revision:5,
        snapshot:{...snapshot,title:'Updated trip'},undo:{revision:5,label:'Updated trip'},preferences:{},offers:[],
        researchLinks:[{label:'Previous hotel search',url:'https://example.com/search'}],
        nextDecision:{focusPanel:'day',focusIds:['day_1']}});
      if(name==='planner_guest_undo') {
        const value=JSON.parse(args.state_json);
        value.snapshot=snapshot;value.pending=null;value.revision++;value.undo=null;
        return JSON.stringify(value);
      }
      if(name==='planner_guest_rename') {
        const value=JSON.parse(args.state_json);
        value.snapshot={...value.snapshot,title:args.title};value.revision++;value.undo={revision:value.revision,label:'Trip renamed'};
        return JSON.stringify(value);
      }
      throw Error(`Unexpected RPC ${name}`);
    },
  });
  const render = () => {cellIndex=0;refIndex=0;effects.length=0;return component();};
  const send=async text=>{
    find(render(),e=>e.type==='textarea').props.onChange({target:{value:text}});
    find(render(),e=>e.type==='form'&&e.props?.className==='studio-composer').props.onSubmit({preventDefault(){}});
    await new Promise(resolve=>setImmediate(resolve));render();
  };
  return {render,state,cells,writes,calls,effects,send,listeners,trigger};
}
function find(tree, predicate) {
  if (!tree || typeof tree!=='object') return null;
  if(predicate(tree))return tree;
  for(const child of (tree.children??[]).flat(Infinity)) {const match=find(child,predicate);if(match)return match;}
  return null;
}
const button = (tree,label)=>find(tree,e=>e.type==='button' && (e.children??[]).flat(Infinity).includes(label));
const component = (tree,name)=>find(tree,e=>typeof e.type==='function' && e.type.name===name);
const tick=()=>new Promise(resolve=>setImmediate(resolve));

test('pending conversational decision never introduces an approval or preview screen',()=>{
  const f=fixture(),tree=f.render();
  assert.equal(component(tree,'StudioOverview').props.snapshot.title,'My trip');
  assert.equal(button(tree,'Approve update'),null);assert.equal(button(tree,'Preview changes'),null);
  assert.equal(find(tree,e=>e.props?.['aria-label']==='Proposed trip changes'),null);
});
test('requested edit is displayed immediately after stage and is reversible with Undo',async()=>{
  const f=fixture();await f.send('Add a rest break to this day');
  f.effects.find(effect=>effect.deps?.[0]==='job_ui').callback();await tick();
  assert.equal(f.cells[0].val.snapshot.title,'Updated trip');
  assert.equal(f.cells[0].val.pending,null);assert.equal(f.cells[0].val.revision,5);
  assert.equal(component(f.render(),'StudioDay').props.day.id,'day_1');
  await button(f.render(),'Undo last update').props.onClick();
  const call=f.calls.find(c=>c.name==='planner_guest_undo');assert.ok(call);assert.equal(call.args.revision,5);
  assert.equal(f.cells[0].val.snapshot.title,'My trip');assert.equal(f.cells[0].val.undo,null);
});
test('the header renames the trip in place, trimming spaces, and Escape cancels',async()=>{
  const f=fixture();
  const title=()=>find(f.render(),e=>e.type==='button'&&e.props?.title==='Rename this trip');
  const field=()=>find(f.render(),e=>e.type==='input'&&e.props?.id==='studio-trip-name');
  title().props.onClick();
  field().props.onChange({target:{value:'Other'}});field().props.onKeyDown({key:'Escape',nativeEvent:{}});
  assert.equal(field(),null);assert.equal(f.calls.length,0);
  title().props.onClick();assert.equal(field().props.value,'My trip');
  field().props.onChange({target:{value:'  Chicago   weekend '}});
  await field().props.onKeyDown({key:'Enter',nativeEvent:{isComposing:false},preventDefault(){}});await tick();
  const call=f.calls.find(c=>c.name==='planner_guest_rename');assert.ok(call);
  assert.equal(call.args.title,'Chicago weekend');assert.equal(call.args.revision,f.state.revision);
  assert.equal(f.cells[0].val.snapshot.title,'Chicago weekend');assert.equal(field(),null);
});
test('item detail replaces its day; Back restores the day without a trip write',()=>{
  const f=fixture();component(f.render(),'StudioOverview').props.onDay('day_1');
  component(f.render(),'StudioDay').props.onContext('day_1','An open day');
  let tree=f.render(),detail=component(tree,'StudioDetails');
  assert.equal(detail.props.item.id,'day_1');assert.equal(component(tree,'StudioDay'),null);
  detail.props.onBack();tree=f.render();assert.ok(component(tree,'StudioDay'));assert.equal(component(tree,'StudioDetails'),null);
  assert.equal(f.writes.length,0);assert.equal(f.calls.length,0);
});
test('selected context and pending decision accompany a conversation request',async()=>{
  const f=fixture();component(f.render(),'StudioOverview').props.onContext('day_1','An open day');
  component(f.render(),'StudioDetails').props.onContext('day_1','An open day');
  assert.ok(find(f.render(),e=>e.props?.['aria-label']==='Remove selected context'));
  await f.send('Make this day quieter');
  const request=JSON.parse(f.calls.find(c=>c.name==='planner_guest_start').args.request_json);
  assert.equal(request.message,'Make this day quieter');assert.equal(request.contextRefs[0].id,'day_1');
  assert.equal(request.proposal.id,'decision_1');assert.equal(request.baseRevision,4);
  assert.equal(f.cells[0].val.snapshot.title,'My trip');
});
test('actual activity stays near composer, outside the scrolling transcript',async()=>{
  const f=fixture({pollResponse:()=>({id:'job_ui',status:'RUNNING',progress:'Searching DTW → SFO',result:{}})});
  await f.send('Find that flight');f.effects.find(effect=>effect.deps?.[0]==='job_ui').callback();await tick();
  const tree=f.render(),area=find(tree,e=>e.props?.className==='studio-composer-area');
  const progress=find(area,e=>e.props?.className==='studio-working');assert.ok(progress);
  assert.ok(progress.children.flat(Infinity).some(e=>e?.children?.includes('Searching DTW → SFO')));
  const log=find(tree,e=>e.props?.className==='studio-chat-log');assert.equal(find(log,e=>e.props?.className==='studio-working'),null);
  assert.ok(button(progress,'Stop'));assert.ok(tree.props.className.includes('phone-chat'));
});
test('trip switcher toggles, dismisses on Escape and outside click, and restores focus',async()=>{
  const f=fixture();await button(f.render(),'Your trips').props.onClick();let tree=f.render();
  assert.equal(button(tree,'Your trips').props['aria-expanded'],true);
  let effect=f.effects.find(e=>e.deps?.length===1&&e.deps[0]===true),cleanup=effect.callback();
  f.listeners.get('keydown')({key:'Escape',preventDefault(){}});assert.equal(button(f.render(),'Your trips').props['aria-expanded'],false);
  cleanup();assert.equal(f.trigger.focused,true);
  await button(f.render(),'Your trips').props.onClick();tree=f.render();
  const section=find(tree,e=>e.props?.id==='studio-trip-library');section.props.ref.current={contains:()=>false,querySelector:()=>null};
  effect=f.effects.find(e=>e.deps?.length===1&&e.deps[0]===true);cleanup=effect.callback();
  f.listeners.get('pointerdown')({target:{}});assert.equal(button(f.render(),'Your trips').props['aria-expanded'],false);cleanup();
  await button(f.render(),'Your trips').props.onClick();await button(f.render(),'Your trips').props.onClick();
  assert.equal(button(f.render(),'Your trips').props['aria-expanded'],false);
});
test('a failed job shows a recoverable message, preserves work, stops polling and allows retry',async()=>{
  let failed=true;
  const f=fixture({pollResponse:()=>({id:'job_ui',status:failed?'FAILED':'SUCCEEDED',progress:'Needs attention',error:'Detour\'s AI service is busy. Please wait a moment and try again.',result:{}})});
  await f.send('Plan a short work trip');const poll=f.effects.find(effect=>effect.deps?.[0]==='job_ui');poll.callback();await tick();
  let tree=f.render();assert.equal(f.cells[0].val.activeJob,'');assert.equal(f.cells[0].val.snapshot.title,'My trip');assert.equal(f.cells[0].val.pending.id,'decision_1');
  // The worker stores only public_error() text (workers/atlas_runtime/errors.py), so the reason is shown.
  assert.ok(JSON.stringify(find(tree,e=>e.props?.role==='alert')).includes('AI service is busy'));
  const polls=f.calls.filter(c=>c.name==='planner_guest_poll').length;poll.callback();await tick();assert.equal(f.calls.filter(c=>c.name==='planner_guest_poll').length,polls);
  failed=false;await f.send('Try planning the work trip again');assert.equal(find(f.render(),e=>e.props?.role==='alert'),null);
  f.effects.find(effect=>effect.deps?.[0]==='job_ui').callback();await tick();assert.equal(f.cells[0].val.snapshot.title,'Updated trip');
});
test('poll decoding distinguishes a cancelled task from an RPC failure',()=>{
  assert.equal(helpers.parse_job_response(JSON.stringify({id:'job_ui',status:'CANCELLED',error:'Stopped',result:{}})).status,'CANCELLED');
  assert.throws(()=>helpers.parse_job_response(JSON.stringify({error:'This planning task is unavailable.'})),/unavailable/);
});

function componentModule(name, expression, extra={}) {
  const source=readFileSync(new URL(`../web/.jac/client/compiled/components/${name}.js`,import.meta.url),'utf8')
    .replace(/^import .*;\n/gm,'').replace(/^export /gm,'');
  return runInNewContext(`${source}\n${expression};`,{
    ...helpers,__jacJsx:(type,props,children)=>({type,props,children}),
    money_label:(amount,currency)=>new Intl.NumberFormat('en-US',{style:'currency',currency}).format(amount/100),
    ...extra,
  });
}
test('real-source price bases distinguish starting nightly rates from all-in totals',()=>{
  const render=componentModule('StudioOffers','StudioOffer');
  const offer={id:'source-option',provider:'Provider',category:'HOTEL',title:'Observed hotel',details:'Observed details',
    query:{checkIn:'2026-11-22',checkOut:'2026-11-25',adults:1,childrenAges:[],rooms:1},
    observedAt:1794787200,sourceUrl:'https://example.com/property',bookingUrl:'',
    price:{amountMinor:14000,currency:'USD',basis:'PER_NIGHT',from:true,quantity:3,estimatedTotalMinor:42000,feesIncluded:null}};
  const tree=render({offer,onContext:()=>{},compact:true}),text=JSON.stringify(tree);
  assert.ok(text.includes('From $140.00'));assert.ok(text.includes('per night'));assert.ok(text.includes('Est. $420.00 for 3 nights'));
  assert.equal(text.includes('mandatory fees included'),false);
  assert.equal(find(tree,e=>e.type==='a').props.href,offer.sourceUrl);
});
test('official warnings remain visible when forecast retrieval is unavailable',()=>{
  const render=componentModule('StudioWeather','StudioWeather');
  const weather={status:'UNAVAILABLE',samples:[{id:'sample',targetId:'flight',placeId:'DTW',label:'Detroit airport',date:'2026-11-22',status:'UNAVAILABLE',sourceUrl:'https://api.weather.gov',
    alerts:[{id:'alert',event:'Winter Storm Warning',headline:'Official warning',description:'Heavy snow expected.',instruction:'Avoid travel.',url:'https://www.weather.gov/alert'}]}]};
  const tree=render({weather,targetId:'flight',dayDate:''});assert.ok(JSON.stringify(tree).includes('Winter Storm Warning'));
  assert.equal(find(tree,e=>e.type==='a').props.href,'https://www.weather.gov/alert');
  assert.equal(JSON.stringify(tree).includes('temperature'),false);
});
test('distant-trip weather is a quiet availability state with no invented conditions',()=>{
  const render=componentModule('StudioWeather','StudioWeather');
  const tree=render({weather:{status:'FUTURE',samples:[]},targetId:'',dayDate:''});
  assert.ok(JSON.stringify(tree).includes('Weather will be available closer to departure.'));
  assert.equal(find(tree,e=>e.type==='details'),null);
});

test('chat option cards stay anchored to their source turn after another user message',()=>{
  const f=fixture();
  f.state.offers=[{id:'old-quote',title:'Earlier option'},{id:'new-quote',title:'Current option'}];
  f.state.comparisonOffers=[f.state.offers[1]];
  f.state.conversation=[{role:'assistant',content:'First search',offerIds:['old-quote']},
    {role:'user',content:'Try another'}, {role:'assistant',content:'Second search',offerIds:['new-quote']},
    {role:'user',content:'Compare them'}];
  const ids=[];
  const visit=tree=>{if(!tree||typeof tree!=='object')return;if(tree.type?.name==='StudioOffer')ids.push(tree.props.offer.id);for(const child of (tree.children??[]).flat(Infinity))visit(child);};
  visit(f.render());assert.deepEqual(ids,['old-quote','new-quote']);
});
test('older stored assistant messages get a latest-shortlist fallback without duplicating new turn cards',()=>{
  const select=componentModule('StudioOffers','conversation_offers');
  const offers=[{id:'earlier'},{id:'current'}],fallback=[offers[1]];
  assert.deepEqual(Array.from(select({role:'assistant',offerIds:['earlier']},offers,fallback),o=>o.id),['earlier']);
  assert.deepEqual(Array.from(select({role:'assistant',offerIds:[]},offers,fallback)),[]);
  assert.deepEqual(select({role:'assistant'},offers,fallback),fallback);
});

test('NWS ISO update timestamps render without interrupting the trip',()=>{
  const render=componentModule('StudioWeather','StudioWeather');
  const weather={status:'READY',samples:[{id:'sample',targetId:'flight',placeId:'DTW',label:'Detroit airport',date:'2026-11-22',status:'READY',summary:'Partly cloudy',temperature:45,temperatureUnit:'F',precipitation:10,wind:'5 mph',alerts:[],sourceUrl:'https://api.weather.gov',checkedAt:'2026-11-16T02:04:34.477080+00:00'}]};
  const tree=render({weather,targetId:'flight',dayDate:''});
  assert.ok(JSON.stringify(tree).includes('Partly cloudy'));assert.ok(JSON.stringify(tree).includes('Updated '));
  assert.equal(JSON.stringify(tree).includes('Invalid Date'),false);
});
