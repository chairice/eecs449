import test from 'node:test';
import assert from 'node:assert/strict';
import { leg_details, leg_title, itinerary_signature, is_finalized } from '../web/.jac/client/compiled/client/atlas_flow.js';

const trip = () => ({title:'Demo',status:'PLANNED',unresolved:[],stops:[
  {query:'DTW',place:{id:'a',code:'DTW',name:'Detroit Metropolitan'}},
  {query:'SFO',place:{id:'b',code:'SFO',name:'San Francisco International'}}],
  legs:[{mode:'FLIGHT',departDate:'2026-11-15',arriveDate:'',departTime:'',arriveTime:'',timingNote:'',route:{status:'UNROUTED'}}]});

test('leg details expose airports and dates without inventing missing times',()=>{
  const t=trip();
  assert.equal(leg_title(t,0),'DTW → SFO');
  const detail=leg_details(t,0);
  assert.match(detail,/Detroit Metropolitan/);
  assert.match(detail,/2026-11-15/);
  assert.match(detail,/Time not set/);
  assert.match(detail,/Arrival: Date not set/);
});
test('finalization remains valid across chat-only changes, invalidates route/date edits',()=>{
  const t=trip();
  assert.equal(is_finalized(t),false);
  t.finalizedSignature=itinerary_signature(t);
  assert.equal(is_finalized(t),true);
  t.conversation=[{role:'user',content:'hello'}];
  assert.equal(is_finalized(t),true);
  t.legs[0].departDate='2026-11-16';
  assert.equal(is_finalized(t),false);
});
test('drive details use provider distance and duration',()=>{
  const t=trip();t.legs[0].mode='DRIVE';t.legs[0].route={status:'READY',distanceMeters:16093.44,durationSeconds:3600};
  assert.match(leg_details(t,0),/10 miles/);
  assert.match(leg_details(t,0),/60 min/);
});
