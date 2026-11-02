"""Input frame with a floating label, after Airbnb's: the label rests inside the
field and lifts to its top edge once the field has focus or a value. The blank
placeholder lets `:placeholder-shown` tell an empty field from a filled one."""

def:pub FloatingField(
    id: str,
    label: str,
    value: str,
    onChange: Callable[[str], None],
    kind: str = "text",
    autoComplete: str = "off",
    invalid: bool = False
) -> JsxElement {
    tone = "border-red-500 focus:border-red-600 focus:ring-red-500/20" if invalid else "border-gray-300 hover:border-gray-500 focus:border-gray-900 focus:ring-emerald-600/25";
    return <div className="relative">
        <input id={id} name={id} type={kind} value={value} placeholder=" " autoComplete={autoComplete}
            aria-invalid={invalid}
            onChange={lambda (e: ChangeEvent) { onChange(str(e.target.value)); }}
            className={"peer block h-14 w-full rounded-xl border bg-white px-4 pt-5 pb-1.5 text-base text-gray-900 outline-none transition-[border-color,box-shadow] duration-150 focus:ring-4 disabled:bg-gray-50 " + tone}/>
        <label htmlFor={id}
            className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-base text-gray-500 transition-all duration-150 peer-focus:top-4 peer-focus:text-xs peer-focus:font-medium peer-focus:text-gray-700 peer-[:not(:placeholder-shown)]:top-4 peer-[:not(:placeholder-shown)]:text-xs">
            {label}
        </label>
    </div>;
}
