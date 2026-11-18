// Exercise emitted Jac handlers against the conversation-led state contract.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { randomUUID } from 'node:crypto';
import * as helpers from '../web/.jac/client/compiled/client/planning_state.js';

function fixture({pollResponse, authenticated=false, withUndo=false, savedView={}, rpcHook} = {}) {
  const snapshot = { schemaVersion: 1, id: 'trip_ui', title: 'My trip', startDate: '', endDate: '', detail:'DETAILED',
    places: [], stays: [], legs: [], rentals:[], bookings: [], unresolved: [], budget:{amountMinor:null,currency:'USD'},
    days: [{ id: 'day_1', date: '2026-12-26', title: 'An open day', overnightPlaceId: '', notes: '', items: [{id:'item_1',title:'Client meeting',kind:'ACTIVITY',placeId:'',startTime:'13:00',endTime:'14:00',notes:'',sourceRefs:[]}] }] };
  const state = { id: snapshot.id, snapshot, revision: 4, conversation: [], workingContext: {}, summary: '',
    jobs: {}, offers: [], comparisonOffers:[], researchLinks: [], nextDecision: {}, preferences: {},
    undo:withUndo?{revision:4,label:'Rest break'}:null,
    pending: { id: 'decision_1', baseRevision: 4, snapshot: {...snapshot,startDate:'2026-12-27'},question:'Move to Sunday?' } };
  const cells = [], refs = [], writes = [], calls = [], effects = [], listeners = new Map(), viewWrites=[];
  let cellIndex = 0, refIndex = 0;
  const trigger={isConnected:true,focused:false,focus(){this.focused=true;}};
  const document={activeElement:trigger,querySelector:()=>null,
    addEventListener:(name,handler)=>listeners.set(name,handler),
    removeEventListener:(name,handler)=>{if(listeners.get(name)===handler)listeners.delete(name);}};
  const source = readFileSync(new URL('../web/.jac/client/compiled/components/TripStudio.js', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
  const component = runInNewContext(`${source}\nTripStudio;`, {
    ...helpers,
    load_trip_view:()=>structuredClone(savedView),save_trip_view:(id,value)=>viewWrites.push({id,...structuredClone(value)}),
    export_trip_pdf:async value=>{calls.push({name:"local_pdf",id:value.id});},
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
    file_content:async()=>Buffer.from('draft notes').toString('base64'),
    guest_token:()=>'guest_test_capability', planner_id:prefix=>`${prefix}_${randomUUID()}`,
    planner_today:()=>'2026-11-15', planner_zone:()=>'America/Detroit',
    HEADER:'', Brand:function Brand(){}, StudioConfirmations:function StudioConfirmations(){}, PlannerMap:()=>{}, ChatMarkdown:()=>{}, StudioOffer:function StudioOffer(){},StudioOptions:function StudioOptions(){},StudioDetails:function StudioDetails(){},StudioWeather:()=>{},TripChoiceCard:()=>{},TripDayCard:()=>{},TripPhoto:()=>{},PhotoCredit:()=>{},
    conversation_offers:(turn,offers,fallback)=>Object.hasOwn(turn,"offerIds")?offers.filter(o=>(turn.offerIds??[]).includes(o.id)):fallback,
    offer_groups:offers=>offers.map(offer=>({id:offer.id,label:offer.title,date:offer.query?.departDate??"Nov 22",count:1,category:offer.category??"FLIGHT",offers:[offer]})),
    planner_list:async()=>JSON.stringify([{id:state.id,title:state.snapshot.title}]),planner_deleted:async()=>'[]',
    __jacCallFunction: async (name,args)=>{
      calls.push({name,args});
      if(rpcHook){const hooked=rpcHook(name,args);if(hooked!==undefined)return await hooked;}
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
      if(name==='planner_guest_confirmations') {
        const value=JSON.parse(args.state_json);value.confirmations=JSON.parse(args.confirmations_json);
        return JSON.stringify(value);
      }
      if(name==='planner_guest_rename') {
        const value=JSON.parse(args.state_json);
        value.undoHistory=[...(value.undoHistory??[]),{snapshot:structuredClone(value.snapshot)}];value.commands={...(value.commands??{}),[args.command_id]:'rename-signature'};value.updatedAt='2026-11-18T12:00:00Z';
        value.snapshot={...value.snapshot,title:args.title};value.revision++;value.undo={revision:value.revision,label:'Trip renamed'};
        return JSON.stringify(value);
      }
      throw Error(`Unexpected RPC ${name}`);
    },
  });
  const render = () => {cellIndex=0;refIndex=0;effects.length=0;const tree=component();refs[0].current=cells[0].val;return tree;};
  const send=async text=>{
    find(render(),e=>e.type==='textarea').props.onChange({target:{value:text}});
    find(render(),e=>e.type==='form'&&e.props?.className==='studio-composer').props.onSubmit({preventDefault(){}});
    await new Promise(resolve=>setImmediate(resolve));render();
  };
  return {render,state,cells,writes,calls,effects,send,listeners,trigger,viewWrites};
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
  await find(f.render(),e=>e.props?.['aria-label']==='Undo last trip change').props.onClick();
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
  assert.equal(f.cells[0].val.undoHistory.at(-1).snapshot.title,'My trip');
  assert.ok(Object.hasOwn(f.cells[0].val.commands,call.args.command_id));
  assert.equal(f.cells[0].val.updatedAt,'2026-11-18T12:00:00Z');
});
test('the Confirmations tab saves bookmarks beside the plan without changing its revision',async()=>{
  const f=fixture();
  button(f.render(),'Confirmations').props.onClick();
  const pane=component(f.render(),'StudioConfirmations');assert.equal(JSON.stringify(pane.props.entries),'[]');
  const entry={id:'c1',nickname:'Hotel',link:'https://mail.google.com/mail/u/0/#inbox/x'};
  assert.equal(await pane.props.onSave([entry]),true);
  const call=f.calls.find(c=>c.name==='planner_guest_confirmations');assert.ok(call);
  assert.equal(JSON.stringify(f.cells[0].val.confirmations),JSON.stringify([entry]));assert.equal(f.cells[0].val.revision,f.state.revision);
  assert.equal(JSON.stringify(component(f.render(),'StudioConfirmations').props.entries),JSON.stringify([entry]));
});
test('item detail replaces its day; Back restores the day without a trip write',()=>{
  const f=fixture();component(f.render(),'StudioOverview').props.onDay('day_1');
  component(f.render(),'StudioDay').props.onContext('item_1','Client meeting');
  let tree=f.render(),detail=component(tree,'StudioDetails');
  assert.equal(detail.props.item.id,'item_1');assert.equal(component(tree,'StudioDay'),null);
  detail.props.onBack();tree=f.render();assert.ok(component(tree,'StudioDay'));assert.equal(component(tree,'StudioDetails'),null);
  assert.equal(f.writes.length,0);assert.equal(f.calls.length,0);
});
test('selected context and pending decision accompany a conversation request',async()=>{
  const f=fixture();component(f.render(),'StudioOverview').props.onDay('day_1');
  component(f.render(),'StudioDay').props.onDiscuss('day_1','An open day');
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
test('chat result summaries stay anchored to their source turn without rendering duplicate full cards',()=>{
  const f=fixture();
  f.state.offers=[{id:'old-quote',title:'Earlier option'},{id:'new-quote',title:'Current option'}];
  f.state.comparisonOffers=[f.state.offers[1]];
  f.state.conversation=[{role:'assistant',content:'First search',offerIds:['old-quote']},
    {role:'user',content:'Try another'}, {role:'assistant',content:'Second search',offerIds:['new-quote']},
    {role:'user',content:'Compare them'}];
  let tree=f.render();
  assert.equal(component(tree,'StudioOffer'),null);
  assert.equal(component(tree,'StudioOptions'),null);
  const summaries=[];
  const visit=tree=>{if(!tree||typeof tree!=='object')return;if(tree.props?.className==='studio-research-summary')summaries.push(tree);for(const child of (tree.children??[]).flat(Infinity))visit(child);};
  visit(tree);assert.equal(summaries.length,2);
  find(summaries[0],e=>e.type==='button').props.onClick();
  const picker=component(f.render(),'StudioOptions');assert.ok(picker);
  assert.equal(picker.props.groupId,'old-quote');assert.deepEqual(Array.from(picker.props.offers,o=>o.id),['old-quote']);
  assert.equal(f.writes.length,0);assert.equal(f.calls.length,0);
});

test('older stored assistant messages get a latest-shortlist fallback without duplicating new turn cards',()=>{
  const select=componentModule('StudioOffers','conversation_offers');
  const offers=[{id:'earlier'},{id:'current'}],fallback=[offers[1]];
  assert.deepEqual(Array.from(select({role:'assistant',offerIds:['earlier']},offers,fallback),o=>o.id),['earlier']);
  assert.deepEqual(Array.from(select({role:'assistant',offerIds:[]},offers,fallback)),[]);
  assert.deepEqual(select({role:'assistant'},offers,fallback),fallback);
});


test('Choose sends the exact offer context immediately and preserves the options workspace while waiting',async()=>{
  const f=fixture();f.state.offers=[{id:'quote-return',title:'Return flight',category:'FLIGHT'}];
  f.state.comparisonOffers=f.state.offers;f.state.conversation=[{role:'assistant',content:'Here are your flights',offerIds:['quote-return']}];
  let tree=f.render();find(find(tree,e=>e.props?.className==='studio-research-summary'),e=>e.type==='button').props.onClick();
  component(f.render(),'StudioOptions').props.onChoose('quote-return','Return flight');await tick();
  const request=JSON.parse(f.calls.find(c=>c.name==='planner_guest_start').args.request_json);
  assert.equal(request.contextRefs[0].id,'quote-return');assert.equal(request.contextRefs[0].label,'Return flight');
  assert.equal(request.message,"Use this flight for my trip.");assert.equal(f.cells[0].val.snapshot.title,'My trip');
  assert.ok(component(f.render(),'StudioOptions'));assert.ok(f.render().props.className.includes('phone-trip'));
});

test('trip Undo stays an explicit workspace action and never creates a page banner or unrelated chat footer',()=>{
  const f=fixture({withUndo:true});f.state.conversation=[{role:'assistant',content:'Older trip edit'},{role:'user',content:'Thanks'},{role:'assistant',content:'Happy to help'}];
  const tree=f.render();assert.ok(find(tree,e=>e.props?.['aria-label']==='Undo last trip change'));
  assert.equal(find(tree,e=>e.props?.className==='studio-notice'),null);
  assert.equal(find(tree,e=>e.props?.className==='studio-inline-undo'),null);
  assert.equal(JSON.stringify(tree).includes('Trip updated.'),false);
});

test('an unplanned trip starts as one conversation instead of an empty map and itinerary',()=>{
  const f=fixture();f.state.snapshot.days=[];
  const tree=f.render();assert.ok(tree.props.className.includes('is-starting'));
  assert.equal(component(tree,'PlannerMap'),null);assert.equal(component(tree,'StudioOverview'),null);
  assert.ok(find(tree,e=>e.type==='textarea'));
});

test('choosing a quote does not send or discard an unrelated composer draft or attachment',async()=>{
  const f=fixture();f.state.offers=[{id:'quote-return',title:'Return flight',category:'FLIGHT'}];f.state.comparisonOffers=f.state.offers;
  f.state.conversation=[{role:'assistant',content:'Options',offerIds:['quote-return']}];
  component(f.render(),'StudioOverview').props.onDay('day_1');
  component(f.render(),'StudioDay').props.onDiscuss('day_1','An open day');
  find(f.render(),e=>e.type==='textarea').props.onChange({target:{value:'An unrelated question I have not sent'}});
  // Attachment state is declared third, after saved trips; use its actual upload UI
  // presence to verify this context is retained when the quote action completes.
  f.cells[2].val=[{id:'private-draft-file',name:'draft-notes.txt'}];
  find(find(f.render(),e=>e.props?.className==='studio-research-summary'),e=>e.type==='button').props.onClick();
  component(f.render(),'StudioOptions').props.onChoose('quote-return','Return flight');await tick();
  const request=JSON.parse(f.calls.find(c=>c.name==='planner_guest_start').args.request_json);
  assert.deepEqual(request.attachments,[]);assert.equal(request.contextRefs[0].id,'quote-return');
  const tree=f.render();assert.equal(find(tree,e=>e.type==='textarea').props.value,'An unrelated question I have not sent');
  assert.ok(find(tree,e=>e.props?.['aria-label']==='Remove draft-notes.txt'));
  assert.ok(find(tree,e=>e.props?.className==='studio-context-chip').children.flat(Infinity).some(x=>x?.children?.includes('An open day')));
  f.effects.find(effect=>effect.deps?.[0]==='job_ui').callback();await tick();
  const completed=f.render();assert.equal(find(completed,e=>e.type==='textarea').props.value,'An unrelated question I have not sent');
  assert.ok(find(completed,e=>e.props?.['aria-label']==='Remove draft-notes.txt'));
  assert.ok(find(completed,e=>e.props?.className==='studio-context-chip').children.flat(Infinity).some(x=>x?.children?.includes('An open day')));
  assert.ok(component(completed,'StudioOptions'));
});

test('source handoffs belong to their research turn and never reappear on an unrelated reply',()=>{
  const f=fixture();f.state.researchLinks=[{label:'Old global source',url:'https://example.com/old'}];
  f.state.conversation=[{role:'assistant',content:'No readable quotes; try the source.',offerIds:[],researchLinks:[{label:'Flight search',url:'https://example.com/flights'}]},
    {role:'user',content:'Keep tomorrow free'}, {role:'assistant',content:'Tomorrow is open.',offerIds:[],researchLinks:[]}];
  const tree=f.render(),handoff=find(tree,e=>e.props?.className==='studio-source-handoffs');assert.ok(handoff);
  assert.equal(find(handoff,e=>e.type==='a').props.href,'https://example.com/flights');
  assert.equal(find(tree,e=>e.type==='a'&&e.props?.href==='https://example.com/old'),null);
  assert.equal(find(tree,e=>e.props?.className==='studio-research-summary'),null);
  f.state.conversation.push({role:'assistant',content:'An older restored reply without metadata'});
  assert.equal(find(f.render(),e=>e.type==='a'&&e.props?.href==='https://example.com/old'),null);
});

test('phone chat keeps a direct Undo action without adding a banner',()=>{
  const f=fixture({withUndo:true}),tree=f.render();
  const undo=find(tree,e=>e.props?.className==='studio-phone-undo');assert.ok(undo);
  assert.equal(undo.props['aria-label'],'Undo last trip change');
  assert.equal(find(tree,e=>e.props?.className==='studio-notice'),null);
});


test('real file bytes produce nonempty exact base64 for attachment upload',async()=>{
  const previous=globalThis.window;globalThis.window={btoa:value=>Buffer.from(value,'binary').toString('base64')};
  try {const input=new TextEncoder().encode('Flight notes ✓');
    assert.equal(await helpers.file_content({arrayBuffer:async()=>input.buffer}),Buffer.from(input).toString('base64'));
  } finally {if(previous===undefined) delete globalThis.window;else globalThis.window=previous;}
});


test('upload failure keeps the draft and existing files with a friendly recovery message',async()=>{
  const f=fixture();let tree=f.render();
  find(tree,e=>e.type==='textarea').props.onChange({target:{value:'My unsent question'}});
  f.cells[2].val=[{id:'kept-file',name:'kept-notes.txt'}];
  tree=f.render();await find(tree,e=>e.type==='input'&&e.props?.type==='file').props.onChange({target:{files:[{name:'new-notes.txt',type:'text/plain',size:11}],value:'new-notes.txt'}});
  tree=f.render();assert.equal(find(tree,e=>e.type==='textarea').props.value,'My unsent question');
  assert.ok(find(tree,e=>e.props?.['aria-label']==='Remove kept-notes.txt'));
  const alert=find(tree,e=>e.props?.role==='alert');assert.ok(alert);
  assert.ok(JSON.stringify(alert).includes('Couldn’t attach that file.'));
  assert.equal(JSON.stringify(alert).includes('Unexpected RPC'),false);
});

test('a saved logistics day restores after reopening and remains selected across Map and Trip',()=>{
 const f=fixture({savedView:{dayId:'day_1',pane:'day',phoneTab:'trip'}});f.state.snapshot.detail='LOGISTICS';
 f.state.snapshot.days[0].overnightPlaceId='SF';f.state.snapshot.places=[{id:'SF',label:'San Francisco',lat:37.7,lon:-122.4}];
 f.render();f.effects.find(e=>e.deps?.length===1&&e.deps[0]===f.state.id).callback();let tree=f.render();
 assert.ok(component(tree,'StudioDay'));button(tree,'Map').props.onClick();tree=f.render();
 assert.deepEqual(Array.from(component(tree,'PlannerMap').props.focusIds),['SF']);
 button(tree,'Your trip').props.onClick();assert.equal(component(f.render(),'StudioDay').props.day.id,'day_1');
});

test('contextual comparison can reopen a selected historical offer when the active shortlist is empty',()=>{
 const f=fixture();f.state.offers=[{id:'chosen',title:'Selected quote',category:'FLIGHT'}];f.state.comparisonOffers=[];
 f.state.snapshot.legs=[{id:'leg',fromId:'SFO',toId:'XNA',offerId:'chosen'}];
 component(f.render(),'StudioOverview').props.onCompare('leg','SFO → XNA');const tree=f.render();
 assert.deepEqual(Array.from(component(tree,'StudioOptions').props.offers,o=>o.id),['chosen']);
 assert.equal(f.calls.length,0);assert.equal(button(tree,'Options'),null);
 find(tree,e=>e.type==='button'&&e.props?.className==='studio-back').props.onClick();assert.ok(component(f.render(),'StudioOverview'));
});

test('PDF export projects the full saved trip locally without a planning request',async()=>{
 const f=fixture();await button(f.render(),'Export PDF').props.onClick();
 assert.deepEqual(f.calls.map(c=>c.name),['local_pdf']);assert.equal(f.cells[0].val.pending.id,'decision_1');
});

test('confirmation responses preserve newer plan revisions and never cross trip boundaries',async()=>{
 let resolveSave;
 const f=fixture({rpcHook:(name,args)=>name==='planner_guest_confirmations'?new Promise(resolve=>{resolveSave=()=>resolve(JSON.stringify({...JSON.parse(args.state_json),confirmations:JSON.parse(args.confirmations_json)}));}):undefined});
 button(f.render(),'Confirmations').props.onClick();
 const entry={id:'email_one',nickname:'Hotel',link:'https://mail.google.com/mail/u/0/#inbox/message'};
 let save=component(f.render(),'StudioConfirmations').props.onSave([entry]);
 f.cells[0].val={...f.cells[0].val,revision:8,snapshot:{...f.cells[0].val.snapshot,title:'Newer planning result'}};f.render();
 resolveSave();await save;
 assert.equal(f.cells[0].val.revision,8);assert.equal(f.cells[0].val.snapshot.title,'Newer planning result');
 assert.equal(f.cells[0].val.confirmations[0].id,'email_one');
 save=component(f.render(),'StudioConfirmations').props.onSave([{...entry,nickname:'First trip only'}]);
 f.cells[0].val={...f.cells[0].val,id:'trip_other',snapshot:{...f.cells[0].val.snapshot,id:'trip_other'},confirmations:[]};f.render();
 resolveSave();await save;
 assert.equal(f.cells[0].val.id,'trip_other');assert.deepEqual(f.cells[0].val.confirmations,[]);
});

test('bookmark-only guest trips remain visible, exportable and protected before New trip',()=>{
 const f=fixture();f.render();
 f.cells[0].val={...f.cells[0].val,pending:null,conversation:[],snapshot:{...f.state.snapshot,days:[]},confirmations:[{id:'email_only',nickname:'Ticket',link:'https://outlook.live.com/mail/0/inbox/id/test'}]};
 let tree=f.render();assert.equal(button(tree,'Export PDF').props.disabled,false);
 assert.equal(tree.props.className.includes('is-starting'),false);
 button(tree,'Your trips').props.onClick();button(f.render(),'+ New trip').props.onClick();
 tree=f.render();assert.ok(find(tree,e=>e.props?.role==='dialog'&&e.props?.['aria-labelledby']==='studio-account-title'));
 assert.equal(f.calls.length,0);assert.equal(f.cells[0].val.confirmations[0].id,'email_only');
});

test('the saved confirmation view restores for its own trip without losing the selected day',()=>{
 const f=fixture({savedView:{pane:'confirmations',dayId:'day_1',phoneTab:'trip'}});f.render();
 const restore=f.effects.find(effect=>effect.deps?.length===1&&effect.deps[0]===f.state.id);assert.ok(restore);restore.callback();
 assert.ok(component(f.render(),'StudioConfirmations'));
 button(f.render(),'Your trip').props.onClick();assert.equal(component(f.render(),'StudioDay').props.day.id,'day_1');
});

test('failed rename keeps its editable draft and Escape cannot save through blur',async()=>{
 const f=fixture({rpcHook:name=>name==='planner_guest_rename'?Promise.reject(new Error('offline')):undefined});
 const title=()=>find(f.render(),e=>e.type==='button'&&e.props?.title==='Rename this trip'&&!e.props?.['aria-label']);
 const field=()=>find(f.render(),e=>e.type==='input'&&e.props?.id==='studio-trip-name');
 title().props.onClick();field().props.onChange({target:{value:'Keep this draft'}});
 await field().props.onKeyDown({key:'Enter',nativeEvent:{},preventDefault(){}});await tick();
 assert.equal(field().props.value,'Keep this draft');assert.equal(f.cells[0].val.snapshot.title,'My trip');
 const cancelled=field();cancelled.props.onKeyDown({key:'Escape',nativeEvent:{}});await cancelled.props.onBlur();
 assert.equal(field(),null);assert.equal(f.calls.filter(call=>call.name==='planner_guest_rename').length,1);
});
