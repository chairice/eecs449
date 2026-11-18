/** Local-only PDF export. This projects the saved trip, never pending edits/chat. */
type RecordValue = Record<string, any>;
const rows = (value: unknown): RecordValue[] => Array.isArray(value) ? value.filter(v => v && typeof v === 'object') : [];
export const pdf_text = (value: unknown): string => value == null ? '' : String(value)
  .normalize('NFC').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '')
  .replace(/[\u2010-\u2015\u2212]/g, '-').replace(/\u2192/g, ' > ').replace(/\u2197/g, '');

/** Only public web links can leave the state boundary. Reject capability URLs. */
export function pdf_public_url(value: unknown): string {
  if (typeof value !== 'string' || value.length > 4000) return '';
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || !host.includes('.') ||
      host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') ||
      /^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|0\.)/.test(host) || host.includes(':')) return '';
    for (const key of url.searchParams.keys()) {
      if (/(?:^|[_-])(token|secret|password|credential|auth|authorization|key|api[_-]?key|session|signature)(?:$|[_-])/i.test(key)) return '';
    }
    url.hash = '';
    return url.href;
  } catch { return ''; }
}
/** Explicit email bookmarks keep message-navigation fragments, unlike sources. */
export function pdf_confirmation_url(value: unknown): string {
  const safe=pdf_public_url(value);
  if(!safe || typeof value!=='string')return '';
  try {
    const original=new URL(value),result=new URL(safe);
    const fragment=decodeURIComponent(original.hash.slice(1));
    if(/(?:^|[?&#;])(?:access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|password|credential|auth|authorization|key|api[_-]?key|session|signature)\s*=/i.test(fragment))return '';
    result.hash=original.hash;
    return result.href;
  } catch { return ''; }
}
export function pdf_money(amount: unknown, currency = 'USD'): string {
  if (!Number.isSafeInteger(amount) || Number(amount) < 0) return '';
  try { return new Intl.NumberFormat('en-US', {style:'currency',currency,minimumFractionDigits:Number(amount)%100 ? 2 : 0}).format(Number(amount)/100); }
  catch { return `${currency} ${(Number(amount)/100).toFixed(2)}`; }
}
const date = (value: unknown) => {
  const text = pdf_text(value);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return text;
  const valueDate = new Date(`${text}T12:00:00Z`);
  return Number.isNaN(valueDate.getTime()) ? text : valueDate.toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'});
};
const time = (value: unknown) => {
  const text = pdf_text(value), match = /^(\d{2}):(\d{2})$/.exec(text);
  return match ? `${Number(match[1])%12 || 12}:${match[2]} ${Number(match[1])<12?'am':'pm'}` : text;
};
const duration = (minutes: unknown) => Number.isInteger(minutes) && Number(minutes)>=0 ? `${Math.floor(Number(minutes)/60) ? `${Math.floor(Number(minutes)/60)}h `:''}${Number(minutes)%60}m`.trim() : '';
export function pdf_observed_date(value: unknown): string {
  let stamp: Date;
  if(typeof value==='number' && Number.isFinite(value))stamp=new Date(Math.abs(value)<1e11?value*1000:value);
  else if(typeof value==='string' && /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2}))?$/.test(value)){
    const [year,month,day]=value.slice(0,10).split('-').map(Number);
    if(new Date(Date.UTC(year,month-1,day)).toISOString().slice(0,10)!==value.slice(0,10))return '';
    stamp=new Date(value.length===10?`${value}T00:00:00Z`:value);
  }else return '';
  return Number.isNaN(stamp.getTime())?'':stamp.toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric',timeZone:'UTC'});
}
const join = (...values: unknown[]) => values.map(pdf_text).filter(Boolean).join(' · ');
const coordinates = (place: RecordValue = {}) => Number.isFinite(place.lat) && Number.isFinite(place.lon) && Math.abs(place.lat)<=90 && Math.abs(place.lon)<=180 ? {lat:place.lat,lon:place.lon} : null;
const maps = (place: RecordValue = {}) => {
  const point = coordinates(place);
  return point ? `https://www.google.com/maps/search/?api=1&query=${point.lat},${point.lon}` : '';
};
const price = (offer: RecordValue = {}) => {
  const value = offer.price || {}, amount = value.amountMinor ?? offer.totalMinor;
  const money = pdf_money(amount, value.currency || offer.currency || 'USD');
  if (!money) return '';
  const basis = ({PER_PERSON:'per person',PER_NIGHT:'per night',PER_DAY:'per day',TOTAL:'total'} as Record<string,string>)[value.basis] || 'total';
  return join(`${value.from?'From ':''}${money}`, basis, value.feesIncluded === false ? 'fees extra' : value.feesIncluded === true ? 'includes fees' : 'fees not confirmed');
};
const link = (label: string, url: unknown) => ({label:pdf_text(label),url:pdf_public_url(url)});

export function build_trip_document(state: RecordValue): RecordValue {
  if (!state?.snapshot || typeof state.snapshot !== 'object') throw new Error('There is no saved trip to export.');
  const trip = state.snapshot, offers = rows(state.offers);
  // Location research is auxiliary data. Bind it to the unchanged saved place,
  // and project only verified coordinates and public, useful location fields.
  const places = rows(trip.places).map(place=>{
    const merged={...place};
    for(const located of rows(state.mapLocations)){
      if(located.id!==place.id || located.query!==place.query ||
        (Object.hasOwn(located,'label') && located.label!==place.label) || !coordinates(located))continue;
      merged.lat=located.lat;merged.lon=located.lon;
      if(typeof located.address==='string')merged.address=located.address;
      if(typeof located.timezone==='string')merged.timezone=located.timezone;
      const source=pdf_public_url(located.sourceUrl);if(source)merged.sourceUrl=source;
    }
    return merged;
  });
  const placeById = new Map(places.map(p=>[p.id,p]));
  const offerById = new Map(offers.map(o=>[o.id,o]));
  const bookingById = new Map(rows(trip.bookings).map(b=>[b.id,b]));
  const place = (id: string) => placeById.get(id) || {};
  const placeName = (id: string) => pdf_text(place(id).label || place(id).query || 'Location to confirm');
  const selected = (item: RecordValue) => offerById.get(item.offerId) || {};
  const status = (item: RecordValue) => {
    const booking=bookingById.get(item.bookingId);
    if(booking?.status==='CANCELLED')return 'Cancelled booking';
    if(booking?.status==='USER_REPORTED')return 'Reported booking';
    return item.bookingId || item.status==='BOOKED' ? 'Booked' : item.status==='SELECTED' || item.offerId ? 'Selected - not booked' : item.locked ? 'Fixed' : 'Planned';
  };
  const publicLinks = (item: RecordValue, offer: RecordValue = {}) => {
    const values = [link('View selected option',offer.bookingUrl || offer.sourceUrl),link('Location details',item.sourceUrl),link('Open in maps',maps(item)),...rows(item.actions || item.links).map(l=>link(l.label || l.title || 'Details',l.url))];
    for (const reference of Array.isArray(item.sourceRefs) ? item.sourceRefs : []) {
      const source = rows(state.researchSources).find(s=>s.captureId===reference || s.id===reference);
      if(source) values.push(link(source.title || 'Research source',source.url));
    }
    const unique = new Set();
    return values.filter(v=>v.url && !unique.has(v.url) && unique.add(v.url));
  };
  const travel = rows(trip.legs).map(leg=>{
    const offer = selected(leg);
    // Old saved offers can outlive a schedule edit. Keep their price separate;
    // never join a different flight's segment timeline onto the current leg.
    const flightMatches = (flight: RecordValue = {}) => ['departDate','arriveDate','departTime','arriveTime','durationMinutes'].every(field=>
      leg[field] == null || leg[field] === '' || flight[field] == null || flight[field] === '' || leg[field] === flight[field]);
    const selectedFlight = offer.flight && flightMatches(offer.flight) ? offer.flight : null;
    const signatureFields = ['fromId','toId','mode','departDate','arriveDate','departTime','arriveTime','durationMinutes','offerId','bookingId'];
    const signature: RecordValue = Object.fromEntries(signatureFields.map(field=>[field,leg[field] ?? (field==='durationMinutes'?null:'')]));
    signature.fromQuery=place(leg.fromId).query ?? '';signature.fromLabel=place(leg.fromId).label ?? '';
    signature.toQuery=place(leg.toId).query ?? '';signature.toLabel=place(leg.toId).label ?? '';
    const journey = rows(state.flightJourneys).find(value=>value.legId===leg.id && value.legSignature && value.flight &&
      Object.entries(signature).every(([field,expected])=>Object.hasOwn(value.legSignature,field) &&
        (value.legSignature[field] ?? (field==='durationMinutes'?null:''))===expected) && flightMatches(value.flight));
    const flight = selectedFlight?.segments?.length ? selectedFlight : journey?.flight || selectedFlight || leg.flight || {};
    const segments = rows(flight.segments).map((segment,index)=>({
      title:join(segment.airline || flight.airline,segment.flightNumber),
      fromCode:pdf_text(segment.fromCode || segment.origin),toCode:pdf_text(segment.toCode || segment.destination),
      route:`${pdf_text(segment.origin || segment.from || segment.fromCode || segment.fromAirport || '')} > ${pdf_text(segment.destination || segment.to || segment.toCode || segment.toAirport || '')}`,
      schedule:join(`${date(segment.departDate)} ${time(segment.departTime)}`.trim(),`${date(segment.arriveDate)} ${time(segment.arriveTime)}`.trim(),'local times'),
      duration:duration(segment.durationMinutes),
      layover:duration(segment.layoverMinutes ?? segment.layoverAfterMinutes),
      sourceUrl:pdf_public_url(segment.sourceUrl || journey?.sourceUrl),
      from:coordinates(segment.fromAirport)?{...segment.fromAirport,label:segment.fromAirport.label || segment.fromCode}:null,
      to:coordinates(segment.toAirport)?{...segment.toAirport,label:segment.toAirport.label || segment.toCode}:null,
      index,
    }));
    const stopCount=Number.isInteger(flight.stops)?flight.stops:null;
    return {id:leg.id,mode:pdf_text(leg.mode || 'Travel'),title:`${placeName(leg.fromId)} > ${placeName(leg.toId)}`,carrier:pdf_text(flight.airline),
      departDate:leg.departDate || flight.departDate || '',arriveDate:leg.arriveDate || flight.arriveDate || '',
      schedule:join(`${date(leg.departDate || flight.departDate)} ${time(leg.departTime || flight.departTime)}`.trim(),`${date(leg.arriveDate || flight.arriveDate)} ${time(leg.arriveTime || flight.arriveTime)}`.trim(),'local times'),
      summary:join(duration(leg.durationMinutes ?? flight.durationMinutes),stopCount===0?'Nonstop':stopCount===null?'':`${stopCount} stop${stopCount===1?'':'s'}`),
      status:status(leg),price:price(offer),bookedAmount:bookingById.get(leg.bookingId)?.status!=='CANCELLED'?pdf_money(bookingById.get(leg.bookingId)?.amountMinor,bookingById.get(leg.bookingId)?.currency || 'USD'):'',observed:pdf_observed_date(offer.observedAt)?`Quote observed ${pdf_observed_date(offer.observedAt)}`:'',
      notes:pdf_text(leg.notes),details:pdf_text(offer.details),detailsLabel:journey && flight===journey.flight ? 'Original quote notes' : '',segments,
      connectionPending:leg.mode==='FLIGHT' && stopCount>0 && segments.length<2,
      links:[...publicLinks(leg,offer),...(journey?.sourceUrl?[link('Sourced flight details',journey.sourceUrl)].filter(value=>value.url):[])],from:place(leg.fromId),to:place(leg.toId)};
  });
  const stays = rows(trip.stays).map(stay=>{
    const offer=selected(stay), location=place(stay.placeId);
    return {id:stay.id,title:pdf_text(stay.propertyName || offer.title || placeName(stay.placeId)),place:placeName(stay.placeId),
      address:pdf_text(location.address || location.query),checkIn:stay.checkIn,checkOut:stay.checkOut,
      dates:join(stay.checkIn?`Check-in ${date(stay.checkIn)}`:'',stay.checkOut?`Check-out ${date(stay.checkOut)}`:''),
      status:status(stay),price:price(offer),bookedAmount:bookingById.get(stay.bookingId)?.status!=='CANCELLED'?pdf_money(bookingById.get(stay.bookingId)?.amountMinor,bookingById.get(stay.bookingId)?.currency || 'USD'):'',notes:pdf_text(stay.notes),details:pdf_text(offer.details),links:publicLinks(location,offer)};
  });
  const rentals = rows(trip.rentals).map(rental=>({id:rental.id,title:join(rental.provider || selected(rental).title || 'Car rental',rental.vehicle),
    pickup:join('Pickup',placeName(rental.pickupPlaceId),date(rental.pickupDate),time(rental.pickupTime)),
    dropoff:join('Drop-off',placeName(rental.dropoffPlaceId),date(rental.dropoffDate),time(rental.dropoffTime)),
    status:status(rental),price:price(selected(rental)),notes:pdf_text(rental.notes),links:publicLinks(rental,selected(rental))}));
  const days = rows(trip.days).map(day=>({id:day.id,date:day.date,dateLabel:date(day.date),title:pdf_text(day.title),notes:pdf_text(day.notes),
    overnight:day.overnightPlaceId?placeName(day.overnightPlaceId):'',
    commitments:[...travel.filter(l=>l.departDate===day.date || l.arriveDate===day.date).map(l=>({title:l.title,details:join(l.schedule,l.status,l.price)})),
      ...stays.filter(s=>(s.checkIn && s.checkIn<=day.date) && (!s.checkOut || s.checkOut>=day.date)).map(s=>({title:s.title,details:join(s.checkIn===day.date?'Check in':s.checkOut===day.date?'Check out':'Overnight stay',s.status)}))],
    items:rows(day.items).map(item=>{
      const location=place(item.placeId);
      return {id:item.id,title:pdf_text(item.title),time:join(time(item.startTime) || 'Flexible',time(item.endTime)),
        place:item.placeId?placeName(item.placeId):'',address:pdf_text(location.address || location.query),point:coordinates(location),
        duration:duration(item.durationMinutes),notes:pdf_text(item.notes),optional:Boolean(item.optional),
        timing:item.timingState==='CHECKED'?'Timing checked':item.timingState==='CONFLICT'?'Timing to resolve':item.timingState==='UNRESOLVED'?'Details to confirm':'Suggested timing',
        fixed:Boolean(item.locked),links:publicLinks({...location,...item,sourceUrl:item.sourceUrl || location.sourceUrl})};
    })})).sort((a,b)=>(a.date || '9999').localeCompare(b.date || '9999'));
  const costs = [];
  for(const [key,label] of [['bookedSubtotals','Bookings added'],['selectedQuoteSubtotals','Selected quotes'],['selectedEstimateSubtotals','Selected estimates']]) {
    for(const [currency,amount] of Object.entries(state.budgetSummary?.[key] || {})) {
      const value=pdf_money(amount,currency); if(value) costs.push({label,value});
    }
  }
  const budget=pdf_money(trip.budget?.amountMinor,trip.budget?.currency || 'USD');
  const warnings=[],warningIds=new Set();
  for(const sample of rows(state.weather?.samples)) for(const alert of rows(sample.alerts)) {
    const id=alert.id || `${alert.event}|${alert.headline}`;
    if(!warningIds.has(id)) { warningIds.add(id); warnings.push({title:pdf_text(alert.headline || alert.event),details:pdf_text(alert.instruction || alert.description),url:pdf_public_url(alert.url),place:pdf_text(sample.label)}); }
  }
  return {title:pdf_text(trip.title || 'Your trip'),dates:join(date(trip.startDate),date(trip.endDate)),
    party:join(trip.party?.adults?`${trip.party.adults} adult${trip.party.adults===1?'':'s'}`:'',trip.party?.childrenAges?.length?`${trip.party.childrenAges.length} children`:'',trip.party?.rooms?`${trip.party.rooms} room${trip.party.rooms===1?'':'s'}`:''),
    timezone:pdf_text(trip.timezone),notes:pdf_text(trip.notes),constraints:(Array.isArray(trip.constraints)?trip.constraints:[]).map(pdf_text),
    unresolved:(Array.isArray(trip.unresolved)?trip.unresolved:[]).map(pdf_text),travel,stays,rentals,days,
    bookings:rows(trip.bookings).map(b=>({title:pdf_text(b.title),status:pdf_text(b.status).replaceAll('_',' '),amount:pdf_money(b.amountMinor,b.currency || 'USD'),details:pdf_text(b.details)})),
    confirmations:rows(state.confirmations).map(entry=>({title:pdf_text(entry.nickname).trim(),url:pdf_confirmation_url(entry.link)})).filter(entry=>entry.title),
    costs,budget,warnings,places:places.map(p=>({label:pdf_text(p.label),...coordinates(p)})).filter(p=>Number.isFinite(p.lat)),
  };
}

/** Export a single immutable view of committed state; no backend calls or remote assets. */
export async function export_trip_pdf(state: RecordValue): Promise<string> {
  const documentModel = build_trip_document(state);
  const {render_trip_pdf} = await import('./trip_pdf_render');
  const pdf = render_trip_pdf(documentModel);
  const basename = documentModel.title.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9 -]/g,'').trim().replace(/\s+/g,'-').slice(0,90) || 'Detour-trip';
  const filename = `${basename}.pdf`;
  await pdf.save(filename, {returnPromise:true});
  return filename;
}
