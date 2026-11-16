"""Render conversation Markdown as React elements, without executing raw HTML."""
import from "react-markdown" { `default as Markdown }
import from "remark-gfm" { `default as remarkGfm }

def:pub ChatLink(href: str = "", children: any = None) -> JsxElement {
    if not href { return <span>{children}</span>; }
    return <a href={href} target="_blank" rel="noopener noreferrer">{children}</a>;
}

def:pub ChatMarkdown(content: str) -> JsxElement {
    return <div className="studio-message-body"><Markdown
        remarkPlugins={[remarkGfm]} skipHtml={True}
        disallowedElements={["img"]} components={{"a": ChatLink}}
    >{content}</Markdown></div>;
}
