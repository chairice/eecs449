"""Warped carousel of destination photos for the home page.

Cards sit on a curved arc: the centred card faces forward and its neighbours
turn and recede on either side. It advances on its own unless the viewer
prefers reduced motion, and pauses while pointed at or focused. Photos are
from Unsplash, each credited to its photographer, with locations checked
against the photo's own Unsplash page.
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
    DestinationPhoto(city="Cleveland", region="Ohio", photo="photo-1614482108527-936a3b7f99cb", photographer="Halle Parks", page="cars-on-road-near-high-rise-building-during-daytime-1oUkud_nquo", alt="Traffic below high-rise buildings in Cleveland")
];

# Seconds each destination holds the centre before the next turns in.
glob ADVANCE_MS: int = 4000;
# Cards further than this from the centre are hidden.
glob VISIBLE_REACH: int = 3;
glob UTM: str = "?utm_source=detour&utm_medium=referral";

def photo_url(photo: str, width: int) -> str {
    return "https://images.unsplash.com/" + photo + "?auto=format&fit=crop&w=" + str(width) + "&h=" + str(int(width * 4 / 3)) + "&q=70";
}

"""Shortest signed distance from the centred card, wrapping around the ring."""
def ring_offset(index: int, active: int, count: int) -> int {
    offset = (index - active) % count;
    return offset - count if offset > count // 2 else offset;
}

"""Place a card on the arc: sideways, back, and turned to follow the curve."""
def card_style(offset: int) -> dict[str, str] {
    reach = abs(offset);
    return {
        "transform": "translateX(calc(" + str(offset) + " * var(--dt-card-step))) translateZ(" + str(-120 * reach) + "px) rotateY(" + str(24 * offset) + "deg) scale(" + str(1 - 0.06 * reach) + ")",
        "zIndex": str(10 - reach),
        "opacity": "0" if reach > VISIBLE_REACH else "1"
    };
}

def:pub DestinationCarousel -> JsxElement {
    has active: int = 0, paused: bool = False;
    count = len(DESTINATIONS);
    current = DESTINATIONS[active];

    def show(index: int) { active = index % count; }

    useEffect(lambda {
        if paused or mediaMatches(REDUCED_MOTION_QUERY) { return lambda { }; }
        timer: any = window.setInterval(lambda { active = (active + 1) % count; }, ADVANCE_MS);
        return lambda { window.clearInterval(timer); };
    }, [paused, active]);

    return <section className="dt-carousel" aria-roledescription="carousel" aria-label="Destinations"
        onMouseEnter={lambda { paused = True; }} onMouseLeave={lambda { paused = False; }}
        onFocus={lambda { paused = True; }} onBlur={lambda { paused = False; }}
        onKeyDown={lambda (e: KeyboardEvent) {
            if e.key == "ArrowRight" { show(active + 1); }
            elif e.key == "ArrowLeft" { show(active - 1 + count); }
        }}>
        <div className="dt-carousel-stage">
            {for (index, place) in enumerate(DESTINATIONS) {
                <button key={place.photo} type="button" className={"dt-card" + (" is-active" if index == active else "")}
                    style={card_style(ring_offset(index, active, count))}
                    tabIndex={0 if abs(ring_offset(index, active, count)) <= VISIBLE_REACH else -1}
                    aria-current={"true" if index == active else None}
                    aria-label={place.city + ", " + place.region}
                    onClick={lambda { show(index); }}>
                    <img src={photo_url(place.photo, 600)} srcSet={photo_url(place.photo, 600) + " 600w, " + photo_url(place.photo, 900) + " 900w"} sizes="300px" alt={place.alt} loading={"eager" if index < 3 else "lazy"} draggable={False}/>
                    <span className="dt-card-caption" aria-hidden="true"><span className="dt-card-city">{place.city}</span><span>{place.region}</span></span>
                </button>
            }}
        </div>
        <div className="dt-carousel-controls">
            <button type="button" className="dt-carousel-arrow" aria-label="Previous destination" onClick={lambda { show(active - 1 + count); }}><Icon name="chevron.left" size={16}/></button>
            <p className="dt-carousel-credit" aria-live="polite">
                {current.city + ", " + current.region + " · Photo by "}
                <a href={"https://unsplash.com/photos/" + current.page + UTM}>{current.photographer}</a>
                {" on "}<a href={"https://unsplash.com/" + UTM}>Unsplash</a>
            </p>
            <button type="button" className="dt-carousel-arrow" aria-label="Next destination" onClick={lambda { show(active + 1); }}><Icon name="chevron.right" size={16}/></button>
        </div>
    </section>;
}
