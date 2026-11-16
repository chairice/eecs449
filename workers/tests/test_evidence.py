import copy
import pytest
from atlas_runtime.browser import verified_offers, allowed_url


def evidence():
    query = {"category": "HOTEL", "checkIn": "2026-12-26", "checkOut": "2026-12-28", "adults": 2, "childrenAges": [], "rooms": 1}
    source = {"url": "https://example.com/stay", "observedAt": 123, "text": "2026-12-26 to 2026-12-28 · 2 adults · 0 children · 1 room. Available. Total $450.00 USD includes taxes and mandatory fees.", "controls": []}
    offer = {"captureId": "source1", "title": "Test stay", "provider": "Example", "total": "450.00", "currency": "USD", "bookingUrl": source["url"],
      "availabilityExcerpt": "Available.", "totalExcerpt": "Total $450.00", "feesExcerpt": "includes taxes and mandatory fees.",
      "currencyExcerpt": "USD", "queryEvidence": {"checkIn": "2026-12-26", "checkOut": "2026-12-28", "adults": "2 adults", "childrenAges": "0 children", "rooms": "1 room"}}
    return query, {"source1": source}, offer


def test_observed_offer_retains_exact_total_and_evidence():
    query, sources, offer = evidence()
    accepted, rejected = verified_offers([offer], sources, query)
    assert not rejected and accepted[0]["totalMinor"] == 45000
    assert accepted[0]["evidence"] == offer and accepted[0]["query"] == query


@pytest.mark.parametrize("change", ["wrong_price", "no_dates", "search_snippet", "invented_excerpt", "no_fees"])
def test_unverified_results_never_become_offer_cards(change):
    query, sources, offer = evidence()
    if change == "wrong_price": offer["total"] = "45"
    if change == "no_dates": del offer["queryEvidence"]["checkOut"]
    if change == "search_snippet": sources["source1"]["url"] = "https://www.google.com/search?q=hotels"
    if change == "invented_excerpt": offer["availabilityExcerpt"] = "Only 3 rooms left"
    if change == "no_fees": offer["feesExcerpt"] = ""
    accepted, rejected = verified_offers([offer], sources, query)
    assert not accepted and rejected


@pytest.mark.parametrize("url", ["http://127.0.0.1/a", "http://169.254.169.254/latest/meta-data", "http://localhost", "file:///etc/passwd", "https://user:pass@example.com"])
def test_browser_blocks_private_targets(url):
    assert not allowed_url(url)


def test_incomplete_search_cannot_masquerade_as_exact_party_verification():
    query, sources, offer = evidence()
    del query["adults"]
    assert not verified_offers([offer], sources, query)[0]


def test_two_travelers_does_not_match_twelve_travelers():
    query, sources, offer = evidence()
    sources["source1"]["text"] = sources["source1"]["text"].replace("2 adults", "12 adults")
    offer["queryEvidence"]["adults"] = "12 adults"
    assert not verified_offers([offer], sources, query)[0]


def test_excluded_fees_or_sold_out_text_never_qualify():
    query, sources, offer = evidence()
    sources["source1"]["text"] += " Taxes and mandatory fees are not included. Sold out."
    offer["feesExcerpt"] = "Taxes and mandatory fees are not included."
    assert not verified_offers([offer], sources, query)[0]
    offer["feesExcerpt"] = "includes taxes and mandatory fees."
    offer["availabilityExcerpt"] = "Sold out."
    assert not verified_offers([offer], sources, query)[0]


def starting_evidence():
    query, sources, offer = evidence()
    query["location"] = "San Francisco"
    offer["queryEvidence"]["location"] = "San Francisco"
    sources["source1"]["text"] += " Test stay. From $150 USD per night. San Francisco"
    offer.update(nameExcerpt="Test stay", priceExcerpt="From $150 USD per night", price={"amount": "150", "currency": "USD", "basis": "PER_NIGHT", "from": True, "feesIncluded": None}, query=query, observedQuery=copy.deepcopy(query))
    offer.pop("bookingUrl")
    return query, sources, offer


def test_starting_nightly_price_uses_observed_page_and_correct_arithmetic():
    query, sources, offer = starting_evidence()
    accepted, rejected = verified_offers([offer], sources, None)
    assert not rejected
    quote = accepted[0]
    assert quote["price"] == {"amountMinor": 15000, "currency": "USD", "basis": "PER_NIGHT", "from": True, "quantity": 2, "estimatedTotalMinor": 30000, "feesIncluded": None}
    assert "totalMinor" not in quote
    assert quote["bookingUrl"] == sources["source1"]["url"]


def test_missing_fee_statement_does_not_erase_a_real_option():
    query, sources, offer = starting_evidence()
    offer["feesExcerpt"] = ""
    assert verified_offers([offer], sources, query)[0]
    offer["price"]["feesIncluded"] = True
    assert not verified_offers([offer], sources, query)[0]


def test_known_wrong_date_or_party_never_matches_even_with_price():
    query, sources, offer = starting_evidence()
    offer["observedQuery"]["checkIn"] = "2026-12-30"
    assert not verified_offers([offer], sources, query)[0]
    offer["observedQuery"] = dict(query, adults=1)
    assert not verified_offers([offer], sources, query)[0]


def test_each_option_carries_independent_search_context():
    query, sources, offer = starting_evidence()
    other = copy.deepcopy(offer)
    other["query"]["checkOut"] = "2026-12-29"
    other["observedQuery"]["checkOut"] = "2026-12-29"
    other["queryEvidence"]["checkOut"] = "2026-12-29"
    sources["source1"]["text"] += " Other search: 2026-12-29"
    accepted, rejected = verified_offers([offer, other], sources, None)
    assert not rejected
    assert [item["price"]["quantity"] for item in accepted] == [2, 3]


def test_calculation_cannot_override_requested_night_count():
    query, sources, offer = starting_evidence()
    offer["price"]["quantity"] = 9
    assert not verified_offers([offer], sources, query)[0]


def test_option_name_and_price_both_need_observed_evidence():
    query, sources, offer = starting_evidence()
    offer["nameExcerpt"] = "Imaginary hotel"
    assert not verified_offers([offer], sources, query)[0]


def test_refs_from_previous_page_cannot_retarget_new_controls():
    from atlas_runtime.browser import ResearchBrowser
    browser = ResearchBrowser()
    browser.refs = {}
    with pytest.raises(Exception, match="expired"):
        browser.element("p1-0")


def test_explicit_wrong_year_cannot_match_a_month_day_excerpt():
    query, sources, offer = starting_evidence()
    sources['source1']['text'] += ' Dec 26, 2025'
    offer['queryEvidence']['checkIn'] = 'Dec 26, 2025'
    assert not verified_offers([offer], sources, query)[0]


def test_flight_fields_require_a_real_schedule_excerpt():
    query, sources, offer = starting_evidence()
    offer['flight'] = {'departTime':'14:30','arriveTime':'17:00','stops':0}
    assert not verified_offers([offer], sources, query)[0]


def test_compact_dates_and_unicode_spacing_are_real_evidence():
    query, sources, offer = starting_evidence()
    sources['source1']['text'] += ' Dec\u00a026\u2009–\u200928\n2\u00a0adults'
    offer['queryEvidence'].update(checkIn='Dec 26 – 28', checkOut='Dec 26 – 28', adults='2 adults')
    assert verified_offers([offer], sources, query)[0]
    offer['observedQuery']['checkOut'] = '2026-12-29'
    assert not verified_offers([offer], sources, query)[0]


def test_driver_age_can_match_actual_pricing_age_bracket_but_party_cannot():
    from atlas_runtime.browser import _fact_matches
    assert _fact_matches(30,'Driver age 25–65','driverAge')
    assert not _fact_matches(23,'Driver age 25–65','driverAge')
    assert not _fact_matches(2,'1–4 adults','adults')
    assert not _fact_matches(2,'12 adults','adults')


def test_cross_month_range_does_not_relabel_the_day_as_wrong_month():
    from atlas_runtime.browser import _fact_matches
    assert not _fact_matches('2026-11-01', 'Nov 30–Dec 1')
    assert _fact_matches('2026-12-01', 'Nov 30–Dec 1')


def test_accessible_us_dollars_currency_text_is_valid_evidence():
    query, sources, offer = starting_evidence()
    sources['source1']['text'] += ' 150 US dollars'
    offer['currencyExcerpt'] = '150 US dollars'
    assert verified_offers([offer],sources,query)[0]


def test_airbnb_single_listing_can_represent_one_hotel_room_without_room_counter():
    query, sources, offer = starting_evidence()
    sources['source1']['url'] = 'https://www.airbnb.com/s/San-Francisco/homes'
    offer['queryEvidence']['rooms'] = offer['nameExcerpt']
    assert not verified_offers([offer],sources,query)[0]
    offer['roomBasis'] = 'SINGLE_LISTING'
    assert verified_offers([offer],sources,query)[0]
    offer['query']['rooms'] = 2
    offer['observedQuery']['rooms'] = 2
    assert not verified_offers([offer],sources,query)[0]


def test_option_query_is_bound_to_registered_search_not_self_chosen():
    query, sources, offer = starting_evidence()
    offer['componentId'] = 'sf_stay'
    components = {'sf_stay': {'query':copy.deepcopy(query)}}
    assert verified_offers([offer],sources,None,components)[0]
    components['sf_stay']['query']['checkOut'] = '2026-12-30'
    assert not verified_offers([offer],sources,None,components)[0]
    offer['componentId'] = 'unknown'
    assert not verified_offers([offer],sources,None,components)[0]


def test_modern_stay_option_needs_observed_search_location():
    query, sources, offer = starting_evidence()
    del offer['queryEvidence']['location']
    assert not verified_offers([offer],sources,None)[0]
    offer['queryEvidence']['location'] = 'San Francisco'
    offer['query']['location'] = 'New York'
    assert not verified_offers([offer],sources,None)[0]


def test_date_or_night_count_cannot_become_the_displayed_price():
    query, sources, offer = starting_evidence()
    sources['source1']['text'] += ' Dec 26 price $150 for 2 nights'
    offer['priceExcerpt'] = 'Dec 26 price $150 for 2 nights'
    offer['price']['amount'] = '26'
    assert not verified_offers([offer],sources,None)[0]
    offer['price']['amount'] = '2'
    assert not verified_offers([offer],sources,None)[0]


def test_dollar_symbol_alone_does_not_relabel_canadian_dollars_usd():
    query, sources, offer = starting_evidence()
    sources['source1']['text'] = sources['source1']['text'].replace('USD','CAD')
    offer['priceExcerpt'] = 'From $150 CAD per night'
    offer['currencyExcerpt'] = '$150'
    assert not verified_offers([offer],sources,None)[0]
    sources['source1']['controls'].append({'text':'CurrencyUSD','label':'Selected currency'})
    assert not verified_offers([offer],sources,None)[0]
    sources['source1']['text'] = sources['source1']['text'].replace('CAD','')
    offer['priceExcerpt'] = 'From $150 per night'
    assert verified_offers([offer],sources,None)[0]


def test_open_driver_age_bracket_accepts_thirty_but_not_under_twenty_five():
    from atlas_runtime.browser import _fact_matches
    assert _fact_matches(30,'Driver age 25+','driverAge')
    assert not _fact_matches(23,'Driver age 25+','driverAge')


def test_unobserved_deep_link_keeps_real_option_with_observed_provider_page():
    query, sources, offer = starting_evidence()
    offer['bookingUrl'] = 'https://not-observed.example/book'
    accepted, rejected = verified_offers([offer],sources,None)
    assert not rejected and accepted[0]['bookingUrl'] == sources['source1']['url']


@pytest.mark.parametrize('excerpt',['12:00 PM','Pickup at 12:00PM','12:00','12:00:00','noon'])
def test_noon_clock_evidence_matches_only_actual_noon(excerpt):
    from atlas_runtime.browser import _fact_matches
    assert _fact_matches('12:00',excerpt,'pickupTime')


@pytest.mark.parametrize('excerpt',['12:00 AM','12:00AM','midnight','13:00','112:00','x12:00y'])
def test_midnight_or_embedded_off_time_cannot_masquerade_as_noon(excerpt):
    from atlas_runtime.browser import _fact_matches
    assert not _fact_matches('12:00',excerpt,'pickupTime')


def test_twelve_hour_and_twenty_four_hour_time_forms_agree():
    from atlas_runtime.browser import _fact_matches
    assert _fact_matches('13:05','1:05 PM','dropoffTime')
    assert _fact_matches('00:00','12:00 AM','dropoffTime')
    assert not _fact_matches('13:05','11:05 PM','dropoffTime')
