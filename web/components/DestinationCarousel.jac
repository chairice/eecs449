"""Cylinder carousel of destination photos for the home page.

Twelve cards sit at fixed, even angles around one ring, and only the ring
turns, so every card travels the same curve together; cards facing away are
hidden rather than passing behind the others, and cards fade with distance
from the front. It advances on its own unless
the viewer prefers reduced motion, and pauses while pointed at or focused.
Photos are free-licence Unsplash images; each location was checked against
the photo's own Unsplash page.
"""

import "../home.css";
import from "react" { useEffect }
import from ..browser { mediaMatches }
import from ..theme { REDUCED_MOTION_QUERY }
import from .Icon { Icon }

obj:pub DestinationPhoto {
    has city: str, region: str, photo: str, photographer: str, page: str, alt: str;
}

glob:pub DESTINATIONS: list[DestinationPhoto] = [
    DestinationPhoto(city="Chicago", region="Illinois", photo="photo-1531001142232-7d7aac16a63e", photographer="Muzammil Soorma", page="people-gathering-on-cloud-gate-chicago-illinois-near-buildings-ayV1mD3HGyg", alt="Visitors at Cloud Gate in Millennium Park, Chicago"),
    DestinationPhoto(city="Ann Arbor", region="Michigan", photo="photo-1780104966799-c6d946ad5791", photographer="Peggy Paulson", page="historic-stone-building-and-tower-against-a-clear-blue-sky-1ZpjYnLymEE", alt="A historic stone tower against a clear blue sky in Ann Arbor"),
    DestinationPhoto(city="Toronto", region="Ontario", photo="photo-1517935706615-2717063c2225", photographer="mwangi gatheca", page="cn-tower-skyline-in-toronto-qlKaN7eqay8", alt="The CN Tower and downtown Toronto at golden hour"),
    DestinationPhoto(city="Milwaukee", region="Wisconsin", photo="photo-1658605567772-6d51f2bc0807", photographer="Karson", page="a-river-with-tall-buildings-along-it-za0oC4r-_C4", alt="Tall buildings along the Milwaukee Riverwalk"),
    DestinationPhoto(city="New York", region="New York", photo="photo-1541336032412-2048a678540d", photographer="Timo Wagner", page="empire-state-building-new-york-at-night-fT6-YkB0nfg", alt="The Empire State Building at night, seen from Top of the Rock"),
    DestinationPhoto(city="Grand Rapids", region="Michigan", photo="photo-1584553505423-123599ea2472", photographer="Kari Shea", page="blue-bridge-over-river-near-city-buildings-during-daytime-koxByITzIUg", alt="A blue bridge over the Grand River beside downtown Grand Rapids"),
    DestinationPhoto(city="Detroit", region="Michigan", photo="photo-1475552196046-a1b5ed257646", photographer="Caleb George", page="low-angle-photo-of-high-rise-building-aYKmTNQg0zU", alt="Looking up at a high-rise in downtown Detroit"),
    DestinationPhoto(city="Cleveland", region="Ohio", photo="photo-1614482108527-936a3b7f99cb", photographer="Halle Parks", page="cars-on-road-near-high-rise-building-during-daytime-1oUkud_nquo", alt="Traffic below high-rise buildings in Cleveland"),
    DestinationPhoto(city="Minneapolis", region="Minnesota", photo="photo-1610631210464-d3df3b970de4", photographer="Kevin Nalty", page="city-skyline-under-blue-sky-during-night-time-oXmVuJ8t20A", alt="The Minneapolis skyline at night"),
    DestinationPhoto(city="Pittsburgh", region="Pennsylvania", photo="photo-1761405378305-d23ec430c0b2", photographer="Zach Miller", page="yellow-bridge-with-city-skyline-under-blue-sky-b_CgkOuSYK8", alt="A yellow bridge leading to the Pittsburgh skyline"),
    DestinationPhoto(city="Indianapolis", region="Indiana", photo="photo-1745097752885-217f4c9f0cf4", photographer="TROY ALLEN", page="indianapolis-skyline-at-dusk-with-a-waterway-SSkx6BhKumo", alt="The Indianapolis skyline at dusk beside a canal"),
    DestinationPhoto(city="St. Louis", region="Missouri", photo="photo-1675906798406-f609bc8a0168", photographer="Kenny Nguyễn", page="the-st-louis-arch-is-lit-up-at-night-Xuu-R6v8HCA", alt="The Gateway Arch lit up at night in St. Louis")
];

# Milliseconds each destination holds the front before the ring turns.
glob ADVANCE_MS: int = 2500;
# Cards within this many steps of the front are in the tab order.
glob VISIBLE_REACH: int = 2;
# Opacity by steps from the front; the furthest visible cards fade most.
glob FADE: list[str] = ["1", "0.75", "0.35"];

def photo_url(photo: str, width: int) -> str {
    return "https://images.unsplash.com/" + photo + "?auto=format&fit=crop&w=" + str(width) + "&h=" + str(int(width * 4 / 3)) + "&q=70";
}

"""Shortest signed distance from the front card, wrapping around the ring."""
def ring_offset(index: int, active: int, count: int) -> int {
    # Wrap with ((n % m) + m) % m so negatives behave the same in Python and JS.
    offset = (((index - active) % count) + count) % count;
    return offset - count if offset > count // 2 else offset;
}

def:pub DestinationCarousel -> JsxElement {
    # Turns of the ring so far, unbounded either way, so it never spins back
    # the long way round when it passes the last card.
    has turns: int = 0, paused: bool = False;
    count = len(DESTINATIONS);
    step = 360 / count;
    active = ((turns % count) + count) % count;
    current = DESTINATIONS[active];

    def show(index: int) { turns = turns + ring_offset(index, active, count); }

    useEffect(lambda {
        if paused or mediaMatches(REDUCED_MOTION_QUERY) { return lambda { }; }
        timer: any = window.setInterval(lambda { turns = turns + 1; }, ADVANCE_MS);
        return lambda { window.clearInterval(timer); };
    }, [paused, turns]);

    return <section className="dt-carousel" aria-roledescription="carousel" aria-label="Destinations"
        style={{"--dt-ring-count": str(count)}}
        onMouseEnter={lambda { paused = True; }} onMouseLeave={lambda { paused = False; }}
        onFocus={lambda { paused = True; }} onBlur={lambda { paused = False; }}
        onKeyDown={lambda (e: KeyboardEvent) {
            if e.key == "ArrowRight" { turns = turns + 1; }
            elif e.key == "ArrowLeft" { turns = turns - 1; }
        }}>
        <div className="dt-carousel-stage">
            <div className="dt-carousel-ring" style={{"transform": "translateZ(calc(-1 * var(--dt-ring-r))) rotateY(" + str(-step * turns) + "deg)"}}>
                {for (index, place) in enumerate(DESTINATIONS) {
                    <button key={place.photo} type="button" className={"dt-card" + (" is-active" if index == active else "")}
                        style={{"transform": "rotateY(" + str(step * index) + "deg) translateZ(var(--dt-ring-r))",
                            "opacity": FADE[abs(ring_offset(index, active, count))] if abs(ring_offset(index, active, count)) < len(FADE) else "0"}}
                        tabIndex={0 if abs(ring_offset(index, active, count)) <= VISIBLE_REACH else -1}
                        aria-current={"true" if index == active else None}
                        aria-label={place.city + ", " + place.region}
                        onClick={lambda { show(index); }}>
                        <img src={photo_url(place.photo, 600)} srcSet={photo_url(place.photo, 600) + " 600w, " + photo_url(place.photo, 900) + " 900w"} sizes="300px" alt={place.alt} loading="eager" draggable={False}/>
                        <span className="dt-card-caption" aria-hidden="true"><span className="dt-card-city">{place.city}</span><span>{place.region}</span></span>
                    </button>
                }}
            </div>
        </div>
        <div className="dt-carousel-controls">
            <button type="button" className="dt-carousel-arrow" aria-label="Previous destination" onClick={lambda { turns = turns - 1; }}><Icon name="chevron.left" size={16}/></button>
            <p className="dt-sr-only" aria-live="polite">{current.city + ", " + current.region}</p>
            <button type="button" className="dt-carousel-arrow" aria-label="Next destination" onClick={lambda { turns = turns + 1; }}><Icon name="chevron.right" size={16}/></button>
        </div>
    </section>;
}
