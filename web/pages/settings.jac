"""Preference and source-status layout; controls stay disabled until storage exists."""

import from ..components.PageHeading { PageHeading }

def:pub SettingsPage -> JsxPage {
    return <>
        <PageHeading title="Make Detour yours." description="Defaults reduce repetition without hiding how a recommendation was made."/>
        <div className="dt-two-column">
            <section className="dt-panel">
                <h2>Trip preferences</h2>
                <p id="settings-status" className="dt-notice">Preferences cannot be saved yet. These are preview defaults.</p>
                <fieldset disabled={True} aria-describedby="settings-status" className="dt-preferences">
                    <legend className="dt-sr-only">Routing preferences preview</legend>
                    <label className="dt-field" htmlFor="priority"><span>Optimize for</span><select id="priority" defaultValue="balanced"><option value="balanced">Balanced</option><option value="fastest">Fastest</option><option value="lowest-cost">Lowest cost</option><option value="fewest-transfers">Fewest transfers</option><option value="most-reliable">Most reliable</option></select></label>
                    <label className="dt-field" htmlFor="max-price"><span>Maximum price (USD, optional)</span><input id="max-price" type="number" min="0" placeholder="No limit"/></label>
                    <label className="dt-field" htmlFor="transfer-buffer"><span>Minimum transfer buffer (minutes)</span><input id="transfer-buffer" type="number" min="0" defaultValue="30"/></label>
                    <button className="dt-primary" type="button">Save preferences</button>
                </fieldset>
            </section>
            <section className="dt-panel dt-sources">
                <h2>Data sources</h2>
                <dl><div><dt>Route provider</dt><dd>Not connected</dd></div><div><dt>National Weather Service</dt><dd>Not connected</dd></div><div><dt>Trip request assistant</dt><dd>Not connected</dd></div></dl>
            </section>
        </div>
    </>;
}
