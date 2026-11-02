"""Asks before something that can't be undone. Built on the browser's modal
<dialog>, which keeps focus inside it and closes on Escape; clicking the dimmed
backdrop also cancels. Focus starts on Cancel, so a stray Enter changes nothing."""

import from "react" { useEffect, useRef }

def:pub ConfirmDialog(open: bool, title: str, message: str, confirmLabel: str, onConfirm: Callable[[], None], onCancel: Callable[[], None]) -> JsxElement {
    box = useRef(None);
    cancel = useRef(None);
    useEffect(lambda {
        dialog: any = box.current;
        if dialog and open and not dialog.open {
            dialog.showModal();
            first: any = cancel.current;
            if first { first.focus(); }
        }
        if dialog and not open and dialog.open { dialog.close(); }
        return lambda { };
    }, [open]);
    return <dialog ref={box} aria-labelledby="confirm-title" aria-describedby="confirm-message"
        className="m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border-0 bg-white p-0 text-left shadow-xl backdrop:bg-gray-900/40 backdrop:backdrop-blur-sm"
        onCancel={lambda (e: any) { e.preventDefault(); onCancel(); }}
        onClick={lambda (e: any) { if e.target == box.current { onCancel(); } }}>
        <div className="p-6">
            <h2 id="confirm-title" className="m-0 text-xl font-semibold tracking-tight text-gray-900">{title}</h2>
            <p id="confirm-message" className="mt-2 mb-0 text-sm text-gray-500">{message}</p>
            <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
                <button ref={cancel} type="button" onClick={lambda { onCancel(); }}
                    className="inline-flex h-11 cursor-pointer items-center justify-center rounded-xl border border-gray-300 bg-white px-5 text-sm font-medium text-gray-900 transition-transform duration-150 hover:border-gray-900 active:scale-98">Cancel</button>
                <button type="button" onClick={lambda { onConfirm(); }}
                    className="inline-flex h-11 cursor-pointer items-center justify-center rounded-xl border-0 bg-red-600 px-5 text-sm font-semibold text-white transition-transform duration-150 hover:bg-red-700 active:scale-98">{confirmLabel}</button>
            </div>
        </div>
    </dialog>;
}
