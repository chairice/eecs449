import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import React from '../web/.jac/client/node_modules/react/index.js';
import {renderToStaticMarkup} from '../web/.jac/client/node_modules/react-dom/server.node.js';
import Markdown from '../web/.jac/client/node_modules/react-markdown/index.js';
import remarkGfm from '../web/.jac/client/node_modules/remark-gfm/index.js';

const source=readFileSync(new URL('../web/.jac/client/compiled/components/ChatMarkdown.js',import.meta.url),'utf8')
  .replace(/^import .*;\n/gm,'').replace(/^export .*;\n/gm,'');
const {ChatMarkdown}=runInNewContext(`${source}\n({ChatMarkdown});`,{
  Markdown,remarkGfm,
  __jacJsx:(type,props,children)=>React.createElement(type,props,...(children??[])),
});
const render=content=>renderToStaticMarkup(React.createElement(ChatMarkdown,{content}));

test('the reported bold heading and Markdown lists render as semantic HTML',()=>{
  const html=render('**Indoor and hands-on:**\n\n- Museum\n- *Cooking class*\n\n1. Morning\n2. Afternoon');
  assert.match(html,/<strong>Indoor and hands-on:<\/strong>/);
  assert.match(html,/<ul>/);assert.match(html,/<ol>/);assert.match(html,/<em>Cooking class<\/em>/);
  assert.doesNotMatch(html,/\*\*Indoor/);
});

test('tables, inline code and provider links render within the message',()=>{
  const html=render('| Option | Price |\n| --- | --- |\n| Hotel | $120 |\n\nUse `DTW` and [NWS](https://www.weather.gov/).');
  assert.match(html,/<table>/);assert.match(html,/<code>DTW<\/code>/);
  assert.match(html,/href="https:\/\/www.weather.gov\/"/);
  assert.match(html,/target="_blank" rel="noopener noreferrer"/);
});

test('untrusted messages cannot execute HTML, unsafe links or remote Markdown images',()=>{
  const html=render('[bad](javascript:alert%281%29)\n\n<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n![tracking](https://example.com/pixel.png)');
  assert.doesNotMatch(html,/<script|<img|onerror=|href="javascript:/);
  assert.doesNotMatch(html,/pixel\.png/);
});
