import { chromium } from "playwright-core";
import { writeFileSync } from "node:fs";

const PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAEACAYAAAByPhyYAAAAMUlEQVR42mNgYGBQY2JgYGCAE/+xsCjhjpoyuE1hRhEb9oARNQwYsbAo4Y6aMqRMAQCmoyXOYoOl8wAAAABJRU5ErkJggg==";
const CSS_GRAD = "linear-gradient(to bottom, rgba(0,0,0,.15) 0%, rgba(0,0,0,0) 42%, rgba(0,0,0,0) 58%, rgba(0,0,0,.15) 100%)";
const SVG_INLINE = `<svg class="veil" preserveAspectRatio="none" viewBox="0 0 10 100" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="v" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#000" stop-opacity=".15"/>
    <stop offset=".42" stop-color="#000" stop-opacity="0"/>
    <stop offset=".58" stop-color="#000" stop-opacity="0"/>
    <stop offset="1" stop-color="#000" stop-opacity=".15"/>
  </linearGradient></defs>
  <rect width="10" height="100" fill="url(#v)"/></svg>`;

const cases = [
  ["A_fond_css", `background-image:${CSS_GRAD};`, ""],
  ["B_svg_inline", "", SVG_INLINE],
  ["C_img_png", "", `<img class="veil" src="${PNG}" alt="">`],
];

const pages = cases.map(([n, css, html]) => `
<div class="page"><img class="photo" src="${PNG}" alt=""><div class="veil-box v-${n}" style="${css}">${html}</div></div>`).join("");

const doc = `<!doctype html><meta charset="utf-8"><style>
*{box-sizing:border-box}@page{size:420pt 595pt;margin:0}
body{margin:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.page{position:relative;width:420pt;height:595pt;background:#cfe3f5;break-after:page;overflow:hidden}
.page:last-child{break-after:auto}
.photo{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;z-index:0}
.veil-box{position:absolute;inset:0;z-index:1}
.veil{position:absolute;inset:0;width:100%;height:100%}
</style>${pages}`;

writeFileSync(".render-out/veil.html", doc);
const b = await chromium.launch();
const p = await b.newPage();
await p.emulateMedia({ media: "print" });
await p.setContent(doc, { waitUntil: "load" });
await p.pdf({ path: ".render-out/veil.pdf", printBackground: true, preferCSSPageSize: true });
await b.close();
console.log("veil.pdf écrit");
