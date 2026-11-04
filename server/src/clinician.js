// Server-rendered, read-only clinician view (decision.md D7). Only shared categories are rendered.
import { CATEGORY_TITLES } from './source/display.js';

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// "22 Sep 2026": unambiguous for both UK (d/m) and US (m/d) readers.
const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }) : '');
const fmtDateTime = (iso) => new Date(iso).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
const age = (dob) => Math.floor((Date.now() - Date.parse(dob)) / 3.15576e10);

const STYLE = `
:root{--bg:#F2F2F7;--card:#fff;--text:#1C1C1E;--muted:#6C6C70;--line:#E5E5EA;--accent:#5856D6;--red:#D70015;--redbg:#FFEDEE;--amber:#8A5300;--amberbg:#FFF4DB}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1C1C1E;--text:#F2F2F7;--muted:#98989F;--line:#38383A;--accent:#7D7AFF;--red:#FF6961;--redbg:#3A1214;--amber:#FFD27A;--amberbg:#33270B}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:16px 16px 48px}
.top{display:flex;align-items:center;gap:10px;margin:4px 0 16px}
.mark{width:28px;height:28px;border-radius:8px;background:linear-gradient(135deg,#5AC8FA,#5856D6 55%,#AF52DE)}
.brand{font-weight:600}.ro{margin-left:auto;font-size:13px;color:var(--muted);border:1px solid var(--line);border-radius:999px;padding:3px 10px}
.hero{border-radius:20px;padding:20px;color:#fff;background:linear-gradient(135deg,#3A7BD5 0%,#5856D6 55%,#8E4EC6 100%);margin-bottom:12px}
.hero .k{font-size:12px;letter-spacing:.06em;text-transform:uppercase;opacity:.8}
.hero h1{margin:4px 0 10px;font-size:28px;line-height:1.15}
.facts{display:flex;flex-wrap:wrap;gap:6px 18px;font-size:14px;opacity:.95}
.banner{display:flex;flex-wrap:wrap;gap:4px 12px;align-items:center;background:var(--card);border-radius:14px;padding:12px 16px;font-size:14px;color:var(--muted);margin-bottom:8px}
.banner b{color:var(--text)}.dot{width:8px;height:8px;border-radius:50%;background:#34C759;display:inline-block;margin-right:6px}
.note{font-size:13px;color:var(--amber);background:var(--amberbg);border-radius:12px;padding:10px 14px;margin:8px 0 4px}
h2{font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin:24px 4px 8px}
.card{background:var(--card);border-radius:14px;overflow:hidden}
.row{display:flex;gap:12px;padding:12px 16px;border-top:1px solid var(--line)}.row:first-child{border-top:0}
.row .main{flex:1;min-width:0}.t{font-weight:500}.d{font-size:14px;color:var(--muted)}.date{font-size:13px;color:var(--muted);white-space:nowrap}
.allergy.high{background:var(--redbg)}.allergy.high .t{color:var(--red)}
.val{text-align:right;white-space:nowrap}.val .us{font-size:13px;color:var(--muted)}
footer{margin-top:28px;font-size:13px;color:var(--muted);text-align:center}
.ended{min-height:80vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px}
.ended .icon{width:64px;height:64px;border-radius:50%;background:var(--card);display:flex;align-items:center;justify-content:center;font-size:30px;margin-bottom:16px}
.ended h1{margin:0 0 8px;font-size:24px}.ended p{margin:0;color:var(--muted);max-width:340px}
`;

const page = (title, body) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><meta name="referrer" content="no-referrer">
<title>${esc(title)}</title><style>${STYLE}</style></head><body>${body}</body></html>`;

const ENDED_BODY = `<div class="ended"><div class="icon">🔒</div><h1>Access ended</h1>
<p>This shared record is no longer available. The patient may have revoked access, or the link has expired. Ask the patient to share again if you still need it.</p></div>`;

export const renderEnded = () => page('Access ended · Consentra', ENDED_BODY);

function rowsFor(category, items) {
  if (category === 'labs') {
    return items.map((i) => `<div class="row"><div class="main"><div class="t">${esc(i.title)}</div><div class="d">${esc(i.detail)}</div></div>
<div class="val"><div class="t">${esc(i.value)} ${esc(i.unit)}</div>${i.usValue != null ? `<div class="us">US: ${esc(i.usValue)} ${esc(i.usUnit)}</div>` : ''}<div class="date">${esc(fmtDate(i.date))}</div></div></div>`).join('');
  }
  return items.map((i) => {
    const high = category === 'allergies' && /severe/i.test(i.detail);
    return `<div class="row${category === 'allergies' ? ` allergy${high ? ' high' : ''}` : ''}"><div class="main"><div class="t">${esc(i.title)}</div><div class="d">${esc(i.detail)}</div></div>
<div class="date">${esc(category === 'medications' ? (i.date ? `since ${fmtDate(i.date)}` : '') : fmtDate(i.date))}</div></div>`;
  }).join('');
}

/** @param record {patient, source, categories} where categories holds ONLY the shared ones. */
export function renderShare(record, share) {
  const { patient: p, source: s, categories } = record;
  const sections = share.categories.map((c) => `<h2>${esc(CATEGORY_TITLES[c])}</h2><div class="card">${rowsFor(c, categories[c])}</div>`).join('');
  const hasLabs = share.categories.includes('labs');
  const body = `<main>
<div class="top"><div class="mark"></div><div class="brand">Consentra</div><div class="ro">Read-only</div></div>
<section class="hero"><div class="k">Shared health record</div><h1>${esc(p.name)}</h1>
<div class="facts"><span>DOB ${esc(fmtDate(p.birthDate))} (${age(p.birthDate)} y)</span><span>Home country: ${esc(p.homeCountry)} 🇬🇧</span><span>NHS no. ${esc(p.nhsNumber)}</span></div></section>
<div class="banner"><span><span class="dot"></span><b>Shared by the patient</b></span>${share.label ? `<span>For: ${esc(share.label)}</span>` : ''}
<span>Expires <b id="exp" data-exp="${esc(share.expiresAt)}">${esc(fmtDateTime(share.expiresAt))}</b></span><span>Source: ${esc(s.name)}, ${esc(s.city)}</span></div>
${hasLabs ? '<div class="note">Lab values are shown in the original UK units, with US conventional units beneath.</div>' : ''}
${sections}
<footer>The patient controls this link and can revoke it at any time. Each view is logged and visible to the patient.</footer>
</main>
<script>
(function(){
  var ended=${JSON.stringify(ENDED_BODY)};
  var el=document.getElementById('exp'),exp=Date.parse(el.dataset.exp);
  function end(){document.body.innerHTML=ended;document.title='Access ended · Consentra';clearInterval(t);clearInterval(c);}
  function left(){var m=Math.max(0,Math.round((exp-Date.now())/6e4));var h=Math.floor(m/60),d=Math.floor(h/24);
    el.textContent='in '+(d>=1?d+' d '+(h%24)+' h':h>=1?h+' h '+(m%60)+' min':m+' min');if(Date.now()>=exp)end();}
  var c=setInterval(left,15000);left();
  var t=setInterval(function(){fetch(location.pathname+'/status',{cache:'no-store'}).then(function(r){if(r.status===410||r.status===404)end();}).catch(function(){});},5000);
})();
</script>`;
  return page(`${p.name} · Shared record · Consentra`, body);
}
