// Render the emitted Jac component with React, including its real SVG symbols.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import React from '../web/.jac/client/node_modules/react/index.js';
import {renderToStaticMarkup} from '../web/.jac/client/node_modules/react-dom/server.node.js';

const source=readFileSync(new URL('../web/.jac/client/compiled/components/StudioWeather.js',import.meta.url),'utf8')
  .replace(/^import .*;\n/gm,'').replace(/^export .*;\n/gm,'');
const {StudioWeather,weather_kind,weather_forecasts,weather_warnings}=runInNewContext(`${source}\n({StudioWeather,weather_kind,weather_forecasts,weather_warnings});`,{
  date_label:raw=>new Date(raw+'T12:00:00Z').toLocaleDateString('en-US',{timeZone:'UTC',month:'short',day:'numeric'}),
  __jacJsx:(type,props,children)=>React.createElement(type??React.Fragment,props,...(children??[])),
});
const sample=(extra={})=>({id:'dtw-weather',targetId:'flight-out',placeId:'DTW',label:'Detroit (DTW)',date:'2026-11-22',
  role:'DEPARTURE_GROUND',status:'READY',forecastAvailable:true,summary:'Slight Chance Light Rain',forecastSummary:'Slight Chance Light Rain',
  temperature:51,temperatureUnit:'F',precipitation:29,wind:'14 mph',alerts:[],
  sourceUrl:'https://api.weather.gov/gridpoints/DTX/56,28/forecast/hourly',checkedAt:'2026-11-16T15:57:51.000000Z',...extra});
const render=(weather,props={})=>renderToStaticMarkup(React.createElement(StudioWeather,{weather,...props}));
const ready=(samples)=>({status:'READY',samples});

test('the reported weather renders as an icon and temperature, without source/update boilerplate',()=>{
  const html=render(ready([sample()]));
  assert.match(html,/data-weather-icon="rain"/);
  assert.match(html,/>51<span>°F<\/span>/);
  assert.match(html,/Light rain possible/);
  assert.match(html,/data-weather-icon="drop"/);assert.match(html,/29%/);assert.match(html,/14 mph/);
  assert.doesNotMatch(html,/Updated|National Weather Service|api\.weather\.gov|<a\b|<img\b/);
});

test('selected-flight weather isolates departure and arrival from other dates and legs',()=>{
  const html=render(ready([
    sample(),
    sample({id:'arrival',placeId:'SFO',label:'San Francisco (SFO)',role:'ARRIVAL_GROUND',forecastSummary:'Sunny',temperature:64}),
    sample({id:'other-leg',targetId:'flight-home',placeId:'XNA',label:'Northwest Arkansas',date:'2026-11-25'}),
  ]),{targetId:'flight-out',dayDate:'2026-11-22'});
  assert.match(html,/Departure/);assert.match(html,/Arrival/);assert.match(html,/Detroit/);assert.match(html,/San Francisco/);
  assert.doesNotMatch(html,/Northwest Arkansas/);
  assert.equal((html.match(/class="studio-weather-tile"/g)??[]).length,2);
  assert.match(html,/<strong title="San Francisco \(SFO\)">SFO<\/strong>/);
});

test('airport captions preserve an actual code while nonairport names remain complete',()=>{
  const html=render(ready([
    sample({id:'uuid-airport',placeId:'place_263',label:'San Francisco International Airport (SFO)'}),
    sample({id:'city',targetId:'stay',placeId:'city-sf',role:'BASE',label:'San Francisco waterfront'}),
  ]));
  assert.match(html,/<strong title="San Francisco International Airport \(SFO\)">SFO<\/strong>/);
  assert.match(html,/<strong title="San Francisco waterfront">San Francisco waterfront<\/strong>/);
});

test('one warning stays visible through forecast failure and is not repeated for overlapping trip samples',()=>{
  const alert={id:'official-warning',event:'Winter Storm Warning',headline:'Heavy snow expected Sunday.',description:'Official detailed bulletin.',instruction:'Avoid travel.',severity:'Severe',url:'https://www.weather.gov/alert'};
  const unavailable=sample({status:'UNAVAILABLE',forecastAvailable:false,summary:'Winter Storm Warning',forecastSummary:'',temperature:null,precipitation:null,wind:'',alerts:[alert]});
  const weather={status:'UNAVAILABLE',samples:[unavailable,{...unavailable,id:'day-sample',targetId:'day',role:'DAY'}]};
  const html=render(weather);
  assert.equal((html.match(/class="studio-weather-alert is-high"/g)??[]).length,1);
  assert.match(html,/Winter Storm Warning/);assert.match(html,/Avoid travel/);assert.match(html,/Full advisory/);
  assert.equal((html.match(/class="studio-weather-tile"/g)??[]).length,0);
  assert.doesNotMatch(html,/<a\b|Forecast closer|°F/);
});

test('future and missing forecasts use quiet availability without invented conditions or zero values',()=>{
  const distant=render({status:'FUTURE',samples:[]});
  assert.match(distant,/Forecast closer to departure/);assert.match(distant,/data-weather-icon="later"/);
  assert.doesNotMatch(distant,/°|data-weather-icon="sun"|data-weather-icon="rain"|Updated/);
  const unavailable=render({status:'UNAVAILABLE',samples:[sample({status:'UNAVAILABLE',forecastAvailable:false,summary:'',forecastSummary:'',temperature:null,precipitation:null,wind:''})]});
  assert.match(unavailable,/Forecast not available yet/);assert.doesNotMatch(unavailable,/0%|°|class="studio-weather-tile"/);
  assert.equal(render({status:'FUTURE',samples:[]},{targetId:'not-in-weather'}),'');
});

test('zero degrees and zero precipitation remain actual values; unknown values are omitted',()=>{
  const html=render(ready([sample({temperature:0,temperatureUnit:'C',precipitation:0,wind:''})]));
  assert.match(html,/>0<span>°C<\/span>/);assert.match(html,/0%/);
  const conditionOnly=render(ready([sample({temperature:null,precipitation:null,wind:''})]));
  assert.match(conditionOnly,/Light rain possible/);assert.doesNotMatch(conditionOnly,/°|studio-weather-metrics/);
});

test('overview forecasts deduplicate place/day and keep the primary strip to four cards',()=>{
  const values=Array.from({length:7},(_,i)=>sample({id:'day-'+i,targetId:'stay',placeId:'DTW',role:'BASE',date:`2026-11-${String(22+i).padStart(2,'0')}`}));
  values.push({...values[0],id:'duplicate-day',role:'DAY'});
  const html=render(ready(values)),beforeDisclosure=html.split('class="studio-weather-more"')[0];
  assert.equal((beforeDisclosure.match(/class="studio-weather-tile"/g)??[]).length,4);
  assert.match(html,/\+3 more forecasts/);
  assert.equal(weather_forecasts(values).length,7);
});

test('weather presentation preserves its original source resource and keeps distinct warning identities',()=>{
  const first={id:'first',event:'Wind Advisory',severity:'Moderate'},second={id:'second',event:'Flood Watch',severity:'Moderate'};
  const weather=ready([sample({alerts:[first,second]})]),before=JSON.stringify(weather);
  render(weather);assert.equal(JSON.stringify(weather),before);assert.equal(weather_warnings(weather.samples).length,2);
  assert.equal(weather_kind('Freezing Rain'),'ice');assert.equal(weather_kind('Thunderstorms'),'storm');assert.equal(weather_kind('Snow Showers'),'snow');
});
