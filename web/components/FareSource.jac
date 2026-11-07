"""Who sells a fare, shown under its price on the results and Trips pages.
Each company gets an initials chip rather than its trademarked logo."""

import from .comparison_view { fare_source, operator_initials }

def:pub FareSource(operators: list[str], align: str = "end") -> JsxElement {
    if len(operators) == 0 { return <></>; }
    return <span className={"flex flex-wrap items-center gap-1 " + ("justify-end" if align == "end" else "justify-start")} title={fare_source(operators)}>
        <span className="dt-sr-only">{fare_source(operators)}</span>
        {for name in operators {
            <span key={name} className="inline-flex items-center gap-1 text-xs text-gray-500" aria-hidden="true">
                <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-md bg-gray-100 px-1 text-[0.625rem] font-semibold tracking-tight text-gray-700 ring-1 ring-gray-200">{operator_initials(name)}</span>
                <span>{name}</span>
            </span>
        }}
    </span>;
}
