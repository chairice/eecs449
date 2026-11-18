/** Paginated vector PDF; deliberately independent of the DOM, map tiles and network. */
import {jsPDF} from 'jspdf';
import {regular,bold} from './pdf_assets/fonts';
import {pdf_text} from './trip_pdf';

const ink=[28,43,37],muted=[91,106,99],green=[58,91,74],line=[218,226,220],paper=[242,246,241],gold=[177,141,70];
const M=44,W=595.28,H=841.89,CW=W-2*M,BOTTOM=H-58;
type Value=Record<string,any>;

export function render_trip_pdf(model: Value): jsPDF {
  const doc=new jsPDF({unit:'pt',format:'a4',compress:true,putOnlyUsedFonts:true});
  doc.addFileToVFS('LiberationSans-Regular.ttf',regular);
  doc.addFont('LiberationSans-Regular.ttf','Detour','normal');
  doc.addFileToVFS('LiberationSans-Bold.ttf',bold);
  doc.addFont('LiberationSans-Bold.ttf','Detour','bold');
  doc.setProperties({title:model.title,subject:'Saved trip itinerary',author:'Detour',creator:'Detour local PDF export'});
  let y=78;
  const font=(size=10,strong=false,color=ink)=>{doc.setFont('Detour',strong?'bold':'normal');doc.setFontSize(size);doc.setTextColor(color[0],color[1],color[2]);};
  const header=()=>{
    font(16,true,green);doc.text('detour',M,31);
    font(8,false,muted);doc.text('YOUR TRIP, TO GO',W-M,29,{align:'right'});
    doc.setDrawColor(...line as [number,number,number]);doc.line(M,45,W-M,45);y=75;
  };
  const next=()=>{doc.addPage();header();};
  const ensure=(height:number)=>{if(y+height>BOTTOM)next();};
  const space=(height=10)=>{y+=height;};
  const text=(value:unknown,size=10,strong=false,color=ink,indent=0,trailing=0)=>{
    const content=pdf_text(value).trim();if(!content)return;
    font(size,strong,color);
    const lines=doc.splitTextToSize(content,CW-indent);
    const leading=size*1.42;
    for(const [index,row] of lines.entries()){ensure(leading+(index===lines.length-1?trailing:0));font(size,strong,color);doc.text(row,M+indent,y);y+=leading;}
  };
  const textHeight=(value:unknown,size=10,strong=false)=>{
    const content=pdf_text(value).trim();if(!content)return 0;
    font(size,strong);return doc.splitTextToSize(content,CW).length*size*1.42;
  };
  const section=(title:string,kicker='')=>{
    ensure(72);space(8);
    if(kicker){text(kicker.toUpperCase(),8,true,green);space(9);}
    text(title,19,true);space(8);
  };
  const rule=()=>{ensure(12);doc.setDrawColor(...line as [number,number,number]);doc.line(M,y,W-M,y);space(10);};
  const links=(values:Value[])=>{
    let x=M,occupied=false;
    for(const link of values || []){
      if(!link.url)continue;
      font(9,true,green);
      const label=pdf_text(link.label),width=Math.min(CW,doc.getTextWidth(label));
      if(occupied && x+width>W-M){y+=14;x=M;occupied=false;}
      const wrapped=doc.splitTextToSize(label,CW);
      for(const [index,row] of wrapped.entries()){
        if(index){y+=14;x=M;occupied=false;}
        ensure(15);font(9,true,green);doc.textWithLink(row,x,y,{url:link.url});
      }
      x+=width+16;occupied=true;
    }
    if(occupied)y+=15;
  };
  const linksHeight=(values:Value[])=>{
    let x=M,occupied=false,extraRows=0;font(9,true,green);
    for(const value of values || []){
      if(!value.url)continue;
      const label=pdf_text(value.label),width=Math.min(CW,doc.getTextWidth(label));
      if(occupied && x+width>W-M){extraRows++;x=M;occupied=false;}
      const wrapped=doc.splitTextToSize(label,CW);
      for(let index=1;index<wrapped.length;index++){extraRows++;x=M;}
      x+=width+16;occupied=true;
    }
    return occupied?15+extraRows*14:0;
  };
  const tag=(value:string)=>text(value,9,true,green);
  const paragraph=(value:string)=>{if(value){text(value,10,false,muted);space(5);}};
  const note=(value:string)=>{text(value,9,false,muted);space(4);};
  const money=(value:string)=>{if(value){space(3);text(value,12,true);space(3);}};
  const flightSequence=(segments:Value[])=>{
    if(!segments.length)return;
    const codes=[segments[0].fromCode,...segments.map(segment=>segment.toCode)];
    if(codes.some(code=>!code))return;
    ensure(65);space(6);text('Flight sequence',9,true,green);space(4);
    text(codes.join('  >  '),17,true);space(7);
  };

  header();
  text(model.title,28,true);space(4);text(model.dates,12,false,muted);text(model.party,10,false,muted);space(11);
  if(model.timezone)note(`Trip time zone: ${model.timezone}. Travel times use each location's local time.`);
  note('This is a copy of your saved plan. Selected options are not bookings. Quotes and schedules can change.');
  paragraph(model.notes);
  if(model.travel.length){section('Getting there & around');for(const leg of model.travel){ensure(70);text(leg.title,12,true);text([leg.carrier,leg.schedule].filter(Boolean).join(' · '),9,false,muted);tag(leg.status);space(9);}}
  if(model.stays.length){section('Where you are staying');for(const stay of model.stays){ensure(65);text(stay.title,12,true);text(stay.dates,9,false,muted);tag(stay.status);space(8);}}
  if(model.costs.length || model.budget){section('Known costs');if(model.budget)text(`Budget ${model.budget}`,11,true);for(const cost of model.costs)text(`${cost.label}: ${cost.value}`,11,true);space(5);note('Partial costs. Selected quotes, estimates and bookings are separate; unpriced arrangements and daily spending are excluded.');}
  if(model.unresolved.length){section('Still to arrange');model.unresolved.forEach((value:string)=>{text(`- ${value}`);space(4);});}
  if(model.constraints.length){section('Planning notes');model.constraints.forEach((value:string)=>text(`- ${value}`));}
  if(model.warnings.length){section('Weather warnings');for(const warning of model.warnings){ensure(60);text(warning.title,12,true);paragraph(warning.details);links(warning.url?[{label:'Official alert',url:warning.url}]:[]);space(8);}}

  if(model.travel.length){
    next();section('Travel details','Flights & connections');
    for(const leg of model.travel){
      ensure(125);text(leg.title,16,true);tag([leg.mode,leg.status].filter(Boolean).join(' · '));
      text([leg.carrier,leg.summary].filter(Boolean).join(' · '),11);text(leg.schedule,10,false,muted);money(leg.bookedAmount?`Booking amount: ${leg.bookedAmount}`:leg.price);
      if(leg.bookedAmount && leg.price)note(`Researched quote: ${leg.price}`);
      if(leg.observed)note(leg.observed);
      if(leg.segments.length){
        flightSequence(leg.segments);space(4);
        for(const segment of leg.segments){ensure(74);text(`${segment.index+1}. ${segment.route}`,12,true);text([segment.title,segment.duration].filter(Boolean).join(' · '),10);text(segment.schedule,9,false,muted);if(segment.sourceUrl)links([{label:'Flight details',url:segment.sourceUrl}]);if(segment.layover){space(3);tag(`Connection · ${segment.layover} layover`);}space(9);}
      }else if(leg.connectionPending){space(3);note('Connecting airport and individual flight details still need to be confirmed.');}
      paragraph(leg.notes);if(leg.details && leg.details!==leg.notes){if(leg.detailsLabel)text(leg.detailsLabel,9,true,muted);paragraph(leg.details);}links(leg.links);space(12);rule();
    }

  }
  if(model.stays.length || model.rentals.length){
    next();section('Stays & rentals');
    for(const stay of model.stays){ensure(110);text(stay.title,16,true);tag(stay.status);text(stay.dates,10);paragraph(stay.address);money(stay.bookedAmount?`Booking amount: ${stay.bookedAmount}`:stay.price);if(stay.bookedAmount && stay.price)note(`Researched quote: ${stay.price}`);paragraph(stay.notes);if(stay.details!==stay.notes)paragraph(stay.details);links(stay.links);space(12);rule();}
    for(const rental of model.rentals){ensure(110);text(rental.title,15,true);tag(rental.status);text(rental.pickup,10);text(rental.dropoff,10);money(rental.price);paragraph(rental.notes);links(rental.links);space(12);rule();}
  }
  for(const day of model.days){
    next();section(day.title,day.dateLabel || 'Your itinerary');
    if(day.overnight)tag(`Overnight · ${day.overnight}`);
    paragraph(day.notes);
    if(day.commitments.length){space(4);text('Travel & stay for this day',11,true);space(5);for(const commitment of day.commitments){ensure(45);text(commitment.title,10,true);note(commitment.details);}space(6);rule();}
    for(const [index,item] of day.items.entries()){
      const address=item.address && item.address!==item.place?item.address:'';
      const meta=[item.duration,item.fixed?'Fixed':'',item.optional?'Optional':'',item.timing].filter(Boolean).join(' · ');
      const actionHeight=linksHeight(item.links),noteHeight=textHeight(item.notes,10);
      const blockHeight=textHeight(item.time,10,true)+textHeight(item.title,14,true)+textHeight(item.place,10,true)+textHeight(address,9)+textHeight(meta,8)+5+noteHeight+(noteHeight?5:0)+actionHeight+9+(index<day.items.length-1?12:0);
      // Keep ordinary activities intact. Exceptionally long notes still flow
      // across pages, with their final line kept beside the source actions.
      ensure(blockHeight<=BOTTOM-77?blockHeight+2:75);
      text(item.time,10,true,green);text(item.title,14,true);text(item.place,10,true);text(address,9,false,muted);
      text(meta,8,false,muted,0,noteHeight?0:5+actionHeight);space(5);
      if(item.notes){text(item.notes,10,false,muted,0,5+actionHeight);space(5);}
      links(item.links);space(9);if(index<day.items.length-1)rule();
    }
    if(!day.items.length)paragraph(day.commitments.length || day.overnight ? 'No additional activities planned.' : 'This day is open.');

  }
  if(model.bookings.length){next();section('Booking details','Added to your trip');for(const booking of model.bookings){ensure(85);text(booking.title,15,true);tag(booking.status);money(booking.amount);paragraph(booking.details);space(10);rule();}}
  const total=doc.getNumberOfPages();
  for(let page=1;page<=total;page++){
    doc.setPage(page);doc.setDrawColor(...line as [number,number,number]);doc.line(M,H-43,W-M,H-43);
    font(8,false,muted);const label=pdf_text(model.title);doc.text(doc.splitTextToSize(label,CW-70)[0],M,H-27);doc.text(`${page} / ${total}`,W-M,H-27,{align:'right'});
  }
  return doc;
}
