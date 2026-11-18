// Execute the compiler-emitted map join; fixtures here are structural examples.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
const source=readFileSync(new URL('../web/.jac/client/compiled/components/PlannerMap.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace(/^export \{.*\};?$/gm,'');
const join=runInNewContext(`${source}\njourney_map_snapshot;`,{});
const plain=v=>JSON.parse(JSON.stringify(v));
function fixture(){
 const snapshot={id:'trip',places:[{id:'sfo',query:'SFO',label:'SFO',lat:37.6,lon:-122.3},{id:'xna',query:'XNA',label:'XNA',lat:36.2,lon:-94.3}],legs:[{id:'leg',fromId:'sfo',toId:'xna',mode:'FLIGHT',offerId:'quote'}]};
 const flight={segments:[{fromAirport:{code:'SFO',lat:37.6,lon:-122.3},toAirport:{code:'LAX',label:'Los Angeles International Airport',lat:33.9,lon:-118.4}},{fromAirport:{code:'LAX',lat:33.9,lon:-118.4},toAirport:{code:'XNA',lat:36.2,lon:-94.3}}]};
 return {snapshot,resources:{offers:[{id:'quote',flight}]},flight};
}
test('selected connecting journey draws each sourced airport and preserves original saved plan',()=>{
 const {snapshot,resources}=fixture(),before=JSON.stringify(snapshot); const mapped=plain(join(snapshot,resources));
 assert.equal(mapped.places.length,3);assert.equal(mapped.places[2].label,'Los Angeles International Airport (LAX)');
 assert.deepEqual(mapped.legs.map(l=>[l.fromId,l.toId]),[['sfo','leg-connection-0'],['leg-connection-0','xna']]);
 assert.equal(mapped.places[2].mapSelectId,'leg');assert.equal(JSON.stringify(snapshot),before);
});
test('an old aggregate stop count never invents a connection',()=>{
 const {snapshot,resources}=fixture();resources.offers[0].flight={stops:1};
 assert.deepEqual(plain(join(snapshot,resources)),snapshot);
});
test('an unpriced sourced manual-flight journey works without a quote',()=>{
 const {snapshot,flight}=fixture();snapshot.legs[0].offerId='';
 const mapped=plain(join(snapshot,{offers:[],flightJourneys:[{legId:'leg',legSignature:{...snapshot.legs[0],fromQuery:'SFO',fromLabel:'SFO',toQuery:'XNA',toLabel:'XNA'},flight}]}));
 assert.equal(mapped.legs.length,2);assert.equal(mapped.places[2].label,'Los Angeles International Airport (LAX)');
});
test('missing airport coordinates retain the existing connection instead of making up a map stop',()=>{
 const {snapshot,resources}=fixture();delete resources.offers[0].flight.segments[0].toAirport.lat;
 assert.deepEqual(plain(join(snapshot,resources)),snapshot);
});

test('reusing a leg ID for another airport never draws the old connection',()=>{
 const {snapshot,flight}=fixture();snapshot.legs[0].offerId='';
 const journey={legId:'leg',legSignature:{...snapshot.legs[0],fromQuery:'SFO',fromLabel:'SFO',toQuery:'XNA',toLabel:'XNA'},flight};
 snapshot.places[1].query='DEN';snapshot.places[1].label='DEN';
 assert.deepEqual(plain(join(snapshot,{offers:[],flightJourneys:[journey]})),snapshot);
});

test('a legacy selected quote with a conflicting flight schedule does not draw old segments',()=>{
 const {snapshot,resources}=fixture();snapshot.legs[0].departTime='08:00';resources.offers[0].flight.departTime='07:00';
 assert.deepEqual(plain(join(snapshot,resources)),snapshot);
 snapshot.legs[0].departTime='07:00';snapshot.legs[0].durationMinutes=400;resources.offers[0].flight.durationMinutes=388;
 assert.deepEqual(plain(join(snapshot,resources)),snapshot);
});

test('actual drawn routes and active pins share the landing brand with readable light-map contrast',()=>{
 const effects=[],lines=[],pins=[];
 const layer=()=>({addTo(){return this;},bindTooltip(){return this;},on(){return this;}});
 const map={setView(){},remove(){},invalidateSize(){},fitBounds(){}};
 const component=runInNewContext(`${source}\nPlannerMap;`,{
  __jacJsx:(type,props,children)=>({type,props,children}),useRef:initial=>({current:initial}),
  useJacState:initial=>({val:initial,set(){}}),useEffect:callback=>effects.push(callback),
  createMap:()=>map,tileLayer:()=>layer(),layerGroup:()=>({...layer(),clearLayers(){}}),
  polyline:(points,options)=>{lines.push(options);return layer();},
  circleMarker:(point,options)=>{pins.push(options);return layer();},
  ResizeObserver:function(){this.observe=()=>{};this.disconnect=()=>{};},document:{createElement:()=>({})},
 });
 const {snapshot}=fixture();component({snapshot,focusIds:['sfo'],selectedId:'sfo',onSelect(){},resources:{}});
 for(const effect of effects)effect();
 const css=readFileSync(new URL('../web/styles.css',import.meta.url),'utf8');
 const rgb=color=>{
  if(color.startsWith('var(')){const name=color.slice(4,-1);color=css.match(new RegExp(`${name}:\\s*(#[0-9a-f]{6})`,'i'))[1];}
  return [1,3,5].map(index=>parseInt(color.slice(index,index+2),16));
 };
 const luminance=value=>value.map(n=>n/255).map(n=>n<=.04045?n/12.92:((n+.055)/1.055)**2.4).reduce((sum,n,index)=>sum+n*[.2126,.7152,.0722][index],0);
 const contrast=(first,second)=>{const [low,high]=[luminance(first),luminance(second)].sort((a,b)=>a-b);return (high+.05)/(low+.05);};
 const background=[232,238,232],brand=rgb('var(--dt-accent)');
 assert.ok(lines.length>0&&pins.length>0);
 for(const line of lines){const color=rgb(line.color);assert.deepEqual(color,brand);assert.ok(contrast(color.map((n,i)=>n*line.opacity+background[i]*(1-line.opacity)),background)>=3);}
 assert.deepEqual(rgb(pins[0].fillColor),brand);assert.ok(contrast(brand,background)>=3);
});
