// Deliberately marked QA input, never served as inventory or a runtime fallback.
// The connecting flight uses the user's aggregate example. Its airport is unknown.
export function tripPdfFixture(){
  const places=[
    {id:'sfo',label:'San Francisco (SFO)',query:'San Francisco International Airport, California',lat:37.6213,lon:-122.379,timezone:'America/Los_Angeles'},
    {id:'xna',label:'Northwest Arkansas (XNA)',query:'Northwest Arkansas National Airport',lat:36.2819,lon:-94.3068,timezone:'America/Chicago'},
    {id:'wharf',label:"Fisherman's Wharf",query:"Fisherman's Wharf, San Francisco, CA",lat:37.808,lon:-122.4177,sourceUrl:'https://www.fishermanswharf.org/'},
    {id:'bridge',label:'Golden Gate Bridge',query:'Golden Gate Bridge, San Francisco, CA',lat:37.8199,lon:-122.4783,sourceUrl:'https://www.goldengate.org/'},
    {id:'sausalito',label:'Sausalito',query:'Sausalito, CA',lat:37.8591,lon:-122.4853},
  ];
  const offer={id:'flight-quote',category:'FLIGHT',provider:'Historical example',title:'American SFO to XNA',
    flight:{airline:'American',departDate:'2026-11-25',arriveDate:'2026-11-25',departTime:'07:00',arriveTime:'15:28',durationMinutes:388,stops:1},
    details:'User-provided schedule. Connecting airport has not been researched.',sourceUrl:'https://www.aa.com/',observedAt:'2026-11-16T12:00:00Z'};
  return {id:'pdf-qa',revision:7,guestToken:'MUST_NOT_EXPORT_CAPABILITY',workingContext:{private:'MUST_NOT_EXPORT_CONTEXT'},
    conversation:[{role:'user',content:'MUST_NOT_EXPORT_CONVERSATION'}],pending:{snapshot:{title:'MUST_NOT_EXPORT_PENDING'}},
    offers:[offer,{id:'unused',title:'MUST_NOT_EXPORT_UNUSED_ALTERNATIVE',price:{amountMinor:99999}}],
    researchSources:[{captureId:'rental-evidence',title:'Rental arrangements',url:'https://www.fishermanswharf.org/'}],
    budgetSummary:{selectedQuoteSubtotals:{},selectedEstimateSubtotals:{},bookedSubtotals:{}},
    snapshot:{id:'pdf-qa',title:'QA sample - San Francisco team offsite',detail:'LOGISTICS',startDate:'2026-11-22',endDate:'2026-11-25',timezone:'America/Los_Angeles',
      notes:'Layout test using the user-described offsite and aggregate flight. This is not a confirmed itinerary or booking.',party:{adults:8,childrenAges:[],rooms:null},budget:{amountMinor:null,currency:'USD'},
      places,legs:[{id:'flight',fromId:'sfo',toId:'xna',mode:'FLIGHT',departDate:'2026-11-25',arriveDate:'2026-11-25',departTime:'07:00',arriveTime:'15:28',durationMinutes:388,offerId:'flight-quote',notes:''}],
      stays:[],rentals:[],bookings:[],constraints:['Plan the bike ride during daylight.'],unresolved:['Confirm group bike rental for eight people.','Check ferry departure times and bicycle rules.','Choose and reserve lunch; confirm a rain alternative.'],
      days:[{id:'bike-day',date:'2026-11-23',title:'Team bike day: Golden Gate & Sausalito',overnightPlaceId:'',notes:'Outdoor, active offsite for about eight people. All activity timing below remains provisional.',items:[
        {id:'pickup',title:"Group bike pickup at Fisherman's Wharf",placeId:'wharf',startTime:'09:30',endTime:'10:15',notes:'Reserve bikes for eight ahead of time.',timingState:'PROVISIONAL',sourceRefs:['rental-evidence']},
        {id:'ride',title:'Ride to Golden Gate Bridge and over to Sausalito',placeId:'bridge',startTime:'10:15',endTime:'12:30',notes:'Waterfront path to the bridge, then cross and descend into Sausalito. Placeholder timing.',timingState:'PROVISIONAL'},
        {id:'lunch',title:'Team lunch in Sausalito - Café Réveille typography check',placeId:'sausalito',startTime:'12:30',endTime:'14:00',notes:'Restaurant TBD; a group of eight may need a reservation. Café name here checks font rendering only.',timingState:'UNRESOLVED'},
        {id:'ferry',title:'Ferry back to San Francisco',placeId:'sausalito',startTime:'14:30',endTime:'15:30',notes:'Ferry times and bike-on-board rules not yet checked; confirm return of rental bikes.',timingState:'UNRESOLVED',actions:[{label:'Ferry information',url:'https://www.goldengate.org/ferry/'}]},
        {id:'dinner',title:'Team dinner',placeId:'',startTime:'18:30',endTime:'20:30',notes:'Restaurant to choose.',optional:true,timingState:'PROVISIONAL'},
      ]}],
    },
  };
}
