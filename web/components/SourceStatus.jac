"""Provider mode, freshness and caveats for a search, so partial or stale data
is only ever shown with where it came from and when."""

import from .comparison_view { SourceLine }
import from ..client.planning_states { DataNotice }

def:pub SourceStatus(sources: list[SourceLine], notices: list[DataNotice], onRetry: Callable[[], None] | None = None) -> JsxElement {
    retryable = `any([notice.retry for notice in notices]);
    return <section className="mb-6 grid gap-2" aria-label="Data sources">
        {for notice in notices {
            <p key={notice.kind} className="m-0 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900" role="status">{notice.message}</p>
        }}
        {(<button type="button" className="inline-flex h-11 w-fit cursor-pointer items-center rounded-full border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700 hover:border-gray-500" onClick={lambda { if onRetry is not None { onRetry(); } }}>Check again</button> if retryable and onRetry is not None else None)}
        <details className="text-sm text-gray-600">
            <summary className="cursor-pointer">Data sources: {" · ".join([line.provider + " (" + line.status + ")" for line in sources]) if len(sources) > 0 else "unknown"}</summary>
            <ul className="mt-2 grid gap-1 pl-5">
                {for line in sources {
                    <li key={line.kind + line.provider}>{("Routes" if line.kind == "routes" else "Weather") + ": " + line.provider + " · " + line.status + " · fetched " + line.fetched}</li>
                }}
            </ul>
        </details>
    </section>;
}
