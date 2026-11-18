"""Bookmarked confirmation emails for one trip: a nickname and a link to the message.

Saving is the parent's job (TripStudio.saveConfirmations); it resolves True once the
list is stored, so the form keeps what was typed when a save fails.
"""
import from ..client.planning_state { planner_id }

glob FIELD: str = "w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/30";

def:pub StudioConfirmations(entries: any, busy: bool, onSave: any) -> JsxElement {
    has nickname: str = "", link: str = "", editingId: str = "", problem: str = "", saving: bool = False;

    def reset { nickname = ""; link = ""; editingId = ""; problem = ""; }
    def startEdit(item: any) { nickname = str(item["nickname"]); link = str(item["link"]); editingId = str(item["id"]); problem = ""; }
    async def store(updated: any) -> bool {
        saving = True;
        stored: bool = bool(await onSave(updated));
        saving = False;
        return stored;
    }
    async def submit {
        name = " ".join(nickname.split());
        url = link.strip();
        lowered = url.lower();
        if not name { problem = "Give it a nickname, like “Hotel confirmation”."; return; }
        if not (lowered.startswith("https://") or lowered.startswith("http://")) {
            problem = "Paste the full link to the email, starting with https://.";
            return;
        }
        updated: any = [];
        if editingId {
            updated = [({"id": item["id"], "nickname": name, "link": url} if item["id"] == editingId else item) for item in entries];
        } else {
            updated = entries + [{"id": planner_id("confirmation"), "nickname": name, "link": url}];
        }
        if await store(updated) { reset(); }
    }
    async def remove(item_id: str) {
        await store([item for item in entries if item["id"] != item_id]);
        if editingId == item_id { reset(); }
    }

    locked = busy or saving;
    return <section className="space-y-5 px-6 py-7" aria-labelledby="studio-confirmations-title">
        <header className="space-y-2">
            <p className="studio-eyebrow">KEEP IT HANDY</p>
            <h2 id="studio-confirmations-title">Confirmations</h2>
            <p className="text-sm text-gray-500">Bookmark this trip’s booking emails, so a flight, hotel or ticket confirmation is one click away instead of buried in your inbox.</p>
        </header>
        {if len(entries) == 0 {
            <p className="rounded-xl border border-dashed border-gray-300 bg-white/60 p-4 text-sm text-gray-500">No confirmations saved yet. Open the email in Gmail or Outlook on the web, copy the link from your browser’s address bar, and paste it below.</p>
        } else {
            <table className="w-full table-fixed text-sm">
                <thead><tr className="text-left text-xs text-gray-500"><th className="w-[45%] pb-2 font-medium">Nickname</th><th className="pb-2 font-medium">Email</th><th className="w-[38%] pb-2"><span className="studio-sr-only">Actions</span></th></tr></thead>
                <tbody>
                    {for item in entries {
                        <tr key={item["id"]} className={"border-t border-gray-200" + (" bg-emerald-50" if editingId == item["id"] else "")}>
                            <td className="py-2.5 pr-2 align-top font-medium break-words text-gray-900">{str(item["nickname"])}</td>
                            <td className="py-2.5 pr-2 align-top"><a className="whitespace-nowrap text-emerald-700 hover:underline" href={item["link"]} target="_blank" rel="noopener noreferrer" aria-label={"Open " + str(item["nickname"]) + " email in a new tab"}>Open ↗</a></td>
                            <td className="py-2.5 text-right align-top whitespace-nowrap">
                                <button type="button" className="rounded px-1.5 text-xs text-gray-500 hover:text-gray-900" disabled={locked} onClick={lambda { startEdit(item); }} aria-label={"Edit " + str(item["nickname"])}>Edit</button>
                                <button type="button" className="rounded px-1.5 text-xs text-gray-500 hover:text-red-600" disabled={locked} onClick={lambda { remove(str(item["id"])); }} aria-label={"Remove " + str(item["nickname"])}>Remove</button>
                            </td>
                        </tr>
                    }}
                </tbody>
            </table>
        }}
        <form className="space-y-3 rounded-xl border border-gray-200 bg-white p-4 shadow-sm" onSubmit={lambda (e: FormEvent) { e.preventDefault(); submit(); }} aria-label={"Edit confirmation" if editingId else "Add a confirmation"}>
            <p className="text-sm font-semibold text-gray-900">{"Edit confirmation" if editingId else "Add a confirmation"}</p>
            <label className="block space-y-1 text-xs text-gray-500">
                <span>Nickname</span>
                <input className={FIELD} value={nickname} maxLength={120} placeholder="Hotel confirmation" onChange={lambda (e: ChangeEvent) { nickname = str(e.target.value); problem = ""; }}/>
            </label>
            <label className="block space-y-1 text-xs text-gray-500">
                <span>Email link</span>
                <input className={FIELD} type="url" inputMode="url" value={link} maxLength={4096} placeholder="https://mail.google.com/mail/u/0/#inbox/…" onChange={lambda (e: ChangeEvent) { link = str(e.target.value); problem = ""; }}/>
            </label>
            {if problem { <p className="text-sm text-red-700" role="alert">{problem}</p> }}
            <div className="flex items-center gap-2">
                <button type="submit" className="studio-primary" disabled={locked}>{"Saving…" if saving else "Save changes" if editingId else "Add confirmation"}</button>
                {if editingId { <button type="button" className="px-2 text-sm text-gray-500 hover:text-gray-900" onClick={reset}>Cancel</button> }}
            </div>
        </form>
    </section>;
}
