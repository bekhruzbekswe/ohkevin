// The 1930s rubber-hose cartoon cat from GAHI (gahi/site/cat.js), copied here for Oh Kevin's homepage and repainted:
// its lemon yellow is now a warm yolk that sits beside Oh Kevin's gold, and its ink is Oh Kevin's ink.
// The cat's body, limbs and face are unchanged, and so is its walk, apart from where it starts.
// Its GAHI scenes are gone and an evening in a kitchen is added at the end.
// Nothing here is a recording. Every frame is drawn from the time `t`, so any moment can be shown still.
const NS = 'http://www.w3.org/2000/svg';
const TAU = Math.PI * 2;
const rad = d => (d * Math.PI) / 180;
const lerp = (a, b, u) => a + (b - a) * u;
const frac = v => v - Math.floor(v);
const ease = u => u * u * (3 - 2 * u);
const clamp01 = v => Math.max(0, Math.min(1, v));
const rot = (p, deg) => { const r = rad(deg), c = Math.cos(r), s = Math.sin(r); return [p[0] * c - p[1] * s, p[0] * s + p[1] * c]; };
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const f = p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`;

// A noodle limb: one smooth arc from a to b with no joint. The shorter the reach, the deeper the bow.
function hose(a, b, len, side, min, loose = 1) {
  const dx = b[0] - a[0], dy = b[1] - a[1], d = Math.hypot(dx, dy) || 1;
  const sag = 2 * Math.sqrt((3 * d * Math.max(0, len - d) * loose) / 8) + min;
  const c = [(a[0] + b[0]) / 2 + (side * dy / d) * sag, (a[1] + b[1]) / 2 - (side * dx / d) * sag];
  return { d: `M${f(a)} Q${f(c)} ${f(b)}`, c };
}
const setHose = (g, h) => { g.children[0].setAttribute('d', h.d); g.children[1].setAttribute('d', h.d); };

// ---------- the cat ----------
const pie = (cx, cy, rx, ry) => {      // a pie-cut pupil: an oval with a wedge bitten out of the top
  const a = rad(-84), b = rad(-22);
  return `M${cx},${cy} L${f([cx + rx * Math.cos(b), cy + ry * Math.sin(b)])} A${rx},${ry} 0 1 1 ${f([cx + rx * Math.cos(a), cy + ry * Math.sin(a)])} Z`;
};
const skull = (en, ef) => `M-31,-9 C-36,-24 -35,-40 ${f(en)} C-21,-47 -11,-40 -6,-30 Q3,-34 12,-31 C14,-40 19,-48 ${f(ef)} C31,-43 34,-32 33,-19 C38,-12 41,-4 40,4 Q45,3 48,6 Q44,9 42,11 Q46,13 47,17 Q42,17 39,19 C34,31 19,38 3,38 C-15,38 -30,32 -35,19 Q-40,20 -44,18 Q-40,14 -37,12 Q-42,10 -45,6 Q-40,5 -36,4 C-36,-1 -34,-5 -31,-9 Z`;
const MOUTH = {
  // The wide open grin it walks around with.
  glad: '<path fill="#1a1a18" d="M9,22 C16,26 29,26 35,21 C34,31 27,35 22,35 C15,35 10,30 9,22 Z"/><path fill="#b9b5aa" d="M15,30.5 C18,28 25,28 28.5,30.5 C26,33.5 18,33.5 15,30.5 Z"/><path class="line" d="M2,17 C8,27 33,28 40,15 M39,12.5 q3.5,1 3,4.5"/>',
  // Gritted teeth and worried brows, for hanging on.
  tense: '<path class="wht" stroke-width="2.2" d="M7,20 C15,16 29,16 37,20 C36,28 30,31 22,31 C14,31 8,28 7,20 Z"/><path class="line" stroke-width="1.6" d="M14,18.5 v11 M22,17.5 v13.5 M30,18.5 v11 M8,24.5 h28"/><path class="line" stroke-width="2.8" d="M-9,-31 L10,-38 M36,-33 L19,-39"/>',
  // A small closed smile, for sitting at rest.
  calm: '<path class="line" d="M8,22 C15,29 28,29 35,21"/>',
};
// The doorkeeper has two faces and shows one at a time: the grin, and a firm mouth under lowered brows.
MOUTH.guard = `<g data-p="yes">${MOUTH.glad}</g><g data-p="no"><path class="line" stroke-width="3" d="M10,25 C17,21 28,21 35,25"/><path class="line" stroke-width="3" d="M-8,-35 L11,-26 M36,-34 L20,-27"/></g>`;
const limb = (name, wide, extra = '') => `<g data-p="${name}"><path class="ho" stroke-width="${wide ? 15.8 : 14}"/><path class="hf" stroke-width="${wide ? 9.4 : 7.8}"/>${extra}</g>`;
const catArt = mood => `<g data-p="cat">
<ellipse data-p="shadow" cx="0" cy="2" rx="44" ry="6" fill="#000" opacity=".3"/>
${limb('tail', true)}${limb('armF', false, '<use href="#rh-glove"/>')}${limb('legF', true, '<use href="#rh-foot"/>')}${limb('legN', true, '<use href="#rh-foot"/>')}
<g data-p="torso"><path class="cel" d="M-6,-41 C-17,-36 -25,-21 -25,-9 C-25,3 -14,10 0,10 C15,10 25,3 24,-9 C23,-22 14,-36 7,-41 Z"/></g>
${limb('armN', false, '<circle r="7.5" fill="#F7B733"/><use href="#rh-glove"/>')}
<g data-p="head"><g data-p="face">
<path data-p="skull" class="cel"/><path class="line" stroke-width="1.8" d="M-27,-43 C-28,-36 -27,-30 -25,-24"/>
<g data-p="eyes"><path class="wht" stroke-width="2.6" d="M3,-28 C10,-28 15,-20 15,-10 C15,1 10,8 3,8 C-4,8 -9,1 -9,-10 C-9,-20 -4,-28 3,-28 Z"/><path class="wht" stroke-width="2.6" d="M25,-28 C31,-28 35,-20 35,-11 C35,-1 31,6 25,6 C19,6 15,-1 15,-11 C15,-20 19,-28 25,-28 Z"/><g data-p="pupils"><path fill="#1a1a18" d="${pie(8.5, -5, 6, 9)}"/><path fill="#1a1a18" d="${pie(28.5, -6, 5, 8.2)}"/></g></g>
<path class="line" stroke-width="1.6" d="M-5,18 L-24,13 M-5,22 L-24,25 M42,16 L58,10 M42,21 L59,22"/>
<path class="wht" stroke-width="2.6" d="M-4,16 C-4,8 5,6 14,9 C20,5 32,5 39,10 C45,14 45,23 40,29 C32,39 9,41 1,32 C-3,27 -5,22 -4,16 Z"/>
${MOUTH[mood]}
<path fill="#1a1a18" d="M17,8 C17,3.5 29,3.5 29,8 C29,12 25,14 23,14 C21,14 17,12 17,8 Z"/><path fill="none" stroke="#fffdf8" stroke-width="1.6" stroke-linecap="round" d="M20,7 q2,-1.5 5,-1"/>
</g></g></g>`;

function makeCat(mood = 'glad') {
  const root = document.createElementNS(NS, 'g');
  root.innerHTML = catArt(mood);
  const part = name => root.querySelector(`[data-p="${name}"]`);
  return Object.fromEntries(['cat', 'shadow', 'tail', 'armF', 'legF', 'legN', 'torso', 'armN', 'head', 'face', 'eyes', 'pupils', 'skull', 'yes', 'no'].map(n => [n, part(n)]));
}

// Places the cat and its torso, and returns the map from torso space to cat space that the limbs hang from.
function trunk(c, at, hip, lean, sq, k = 1) {
  c.cat.setAttribute('transform', `translate(${at[0].toFixed(2)},${at[1].toFixed(2)}) scale(${k})`);
  c.torso.setAttribute('transform', `translate(${f(hip)}) rotate(${lean.toFixed(2)}) scale(${(1 + sq).toFixed(3)},${(1 - sq).toFixed(3)})`);
  return p => add(hip, rot([p[0] * (1 + sq), p[1] * (1 - sq)], lean));
}
function legTo(g, from, ankle, deg, loose = 0, len = 74) {
  setHose(g, hose(from, add(ankle, rot([1, 2], deg)), len, 1, 7, loose));
  g.children[2].setAttribute('transform', `translate(${f(ankle)}) rotate(${deg.toFixed(1)})`);
}
function armTo(g, shoulder, hand, twist, side = -1, len = 51) {
  const h = hose(shoulder, hand, len, side, 4);
  setHose(g, h);
  const ang = (Math.atan2(hand[1] - h.c[1], hand[0] - h.c[0]) * 180) / Math.PI + twist;
  g.lastElementChild.setAttribute('transform', `translate(${f(hand)}) rotate(${ang.toFixed(1)})`);
  if (g.children.length === 4) g.children[2].setAttribute('transform', `translate(${f(shoulder)})`);   // the near arm's shoulder cap
}
function headTo(c, at, turn, blink, ears) {
  c.head.setAttribute('transform', `translate(${f(at)}) rotate(${turn.toFixed(2)})`);
  c.eyes.setAttribute('transform', `translate(0,${(7 * (1 - blink)).toFixed(1)}) scale(1,${blink})`);
  c.skull.setAttribute('d', skull([-29 - 1.5 * ears, -52 + 4 * ears], [26 - 1.5 * ears, -52 + 4 * ears]));
}
// The tail held up and happy, with the swish running along it a beat behind the hips.
function tailUp(c, b, w, down) {
  const p1 = add(b, [-24, 7 + 3 * down]), p2 = add(b, [-44 + 4 * Math.sin(w - 0.8), -14]), p3 = add(b, [-38 + 5 * Math.sin(w - 1.4), -46 + 3 * down]);
  const p4c = add(b, [-44 + 8 * Math.sin(w - 2.2), -84 - 2 * down]), p4 = add(b, [-52 + 9 * Math.sin(w - 2.6), -72 + 4 * Math.cos(w - 2.6)]);
  setHose(c.tail, { d: `M${f(b)} C${f(p1)} ${f(p2)} ${f(p3)} S${f(p4c)} ${f(p4)}` });
}

// Walking: one stride a second at V px a second, so a planted foot never slides.
const V = 148, STANCE = 0.52, HALF = (V * STANCE) / 2;
const HEEL = [-7, 10], BALL = [19, 10];
function plant(u) {
  const fx = HALF - 2 * HALF * u;
  let deg = 0, piv = HEEL;
  if (u < 0.2) deg = -28 * (1 - u / 0.2);
  else if (u > 0.62) { deg = 48 * ease((u - 0.62) / 0.38); piv = BALL; }
  const r = rot(piv, deg);
  return [fx + piv[0] - r[0], -10 + piv[1] - r[1], deg];
}
function foot(p) {                     // the last value is 0 while planted and up to 1 in mid swing
  if (p < STANCE) return [...plant(p / STANCE), 0];
  const w = (p - STANCE) / (1 - STANCE), a = plant(1), b = plant(0), e = ease(w), lift = Math.sin(Math.PI * w);
  return [lerp(a[0], b[0], e), lerp(a[1], b[1], e) - 24 * lift, lerp(a[2], b[2], e) + 12 * lift, lift];
}
function walk(c, t, x0) {
  const ph = t - 0.05, x = x0 + V * t;
  const down = Math.cos(2 * TAU * (ph - 0.09));         // +1 just after each foot lands
  const lean = -6 + 2.5 * Math.sin(TAU * ph);
  const P = trunk(c, [x, 0], [0, -70 + 5.5 * down], lean, 0.05 * down);
  c.shadow.setAttribute('rx', (44 + 4 * down).toFixed(1));
  [[c.legN, 0, [-8, 1]], [c.legF, 0.5, [8, 0]]].forEach(([g, off, at]) => {
    const [ax, ay, deg, swing] = foot(frac(ph + off));
    legTo(g, P(at), [ax, ay], deg, swing);
  });
  [[c.armN, -1, [-2, -30]], [c.armF, 1, [8, -30]]].forEach(([g, sign, at]) => {
    const sh = P(at), th = sign * 0.95 * Math.cos(TAU * ph - 0.35) + 0.08;
    armTo(g, sh, add(sh, [46 * Math.sin(th), 46 * Math.cos(th) - 6 * Math.max(0, Math.sin(th))]), -14 + 10 * Math.sin(2 * TAU * ph - 1.2));
  });
  tailUp(c, P([-19, -4]), TAU * ph, down);
  const late = Math.cos(2 * TAU * (ph - 0.17)), ears = Math.cos(2 * TAU * (ph - 0.27));
  headTo(c, add(P([2, -39]), [9, -31 + 3 * late]), lean * 0.5 - 2 + 3 * late, 1, ears);
  return x;
}

// Shared drawings, added to the page once: the glove, the shoe, and the wobble that makes the room look hand-drawn.
const DEFS = `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
<filter id="rough" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency=".03" numOctaves="2" seed="4" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="5" xChannelSelector="R" yChannelSelector="G"/></filter>
<g id="rh-glove"><path class="wht" d="M4,-6 C5,-13 11,-15 13,-9.5 C17,-13.5 25,-11 24,-5.5 C29.5,-5 30,1.5 24.5,2.5 C27,7.5 22,11.5 17,9 C12,12 6,10 4,6 Z"/><path class="line" stroke-width="1.6" d="M11,-3.5 L16,-4.5 M11,0 L17,0 M11,3.5 L16,4.5"/><path class="wht" d="M-3,-7.5 C0,-9 3,-9 5,-7.5 C6.5,-3 6.5,3 5,7.5 C3,9 0,9 -3,7.5 C-4.5,3 -4.5,-3 -3,-7.5 Z"/></g>
<g id="rh-foot"><path class="wht" d="M-9,2 C-10,-5 -4,-8 2,-6 C9,-8 21,-7 27,-1 C32,4 30,10 24,10 L-5,10 C-9,10 -10,6 -9,2 Z"/><path class="line" stroke-width="1.6" d="M20,-3 q3,3 2,7 M25,0 q2,3 1,6"/></g>
</defs></svg>`;


// ---------- Oh Kevin's evening ----------
// Everything above is the GAHI cat as it was drawn, repainted. Below is what it does here: one evening in one room,
// told by how far the page has been scrolled. The cat talks with the Mac, walks to the stove, hands off a job without
// looking up, says yes when it is called, and ends the day standing over its dinner.
const span = (u, a, b) => ease(clamp01((u - a) / (b - a)));
const pulse = (u, a, b, e = 0.2) => span(u, a, a + e) * (1 - span(u, b - e, b));
const ink = (d, w = 4.5) => `<path d="${d}" fill="none" stroke="#1a1a18" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const ramp = (stops, u) => {                             // a colour somewhere along a row of colours
  const n = stops.length - 1, i = Math.min(n - 1, Math.floor(clamp01(u) * n)), a = rgb(stops[i]), b = rgb(stops[i + 1]);
  return `rgb(${a.map((v, j) => Math.round(lerp(v, b[j], clamp01(u) * n - i))).join(',')})`;
};

// Standing. With `talk` it faces the Mac and thinks out loud, waving its spoon. Without, it is at the stove: the near
// hand stirs and never stops, and `look` is 1 for eyes on the pot and -1 for looking back over its shoulder at the Mac.
const K = 0.78, POT = [72, -72];                         // the cat's size in the room, and the pot's rim in the cat's own space
function cook(c, t, x, look, talk) {
  const beat = Math.sin(TAU * t / 1.6), w = TAU * t / 1.3;
  const P = trunk(c, [x, 0], [0, -70 + 1.5 * beat], talk ? 3 + 3 * Math.sin(w / 2) : 6, 0.02 * beat);
  if (talk) c.cat.setAttribute('transform', `translate(${x.toFixed(2)},0) scale(-1,1)`);
  c.shadow.setAttribute('rx', 40);
  legTo(c.legN, P([-8, 1]), [-18, -10], 0);
  legTo(c.legF, P([8, 0]), [8, -10], 0);
  const sn = P([-2, -30]), sf = P([8, -30]);
  const hand = talk ? [sn[0] + 66 + 5 * Math.sin(w), sn[1] + 12 - 10 * Math.cos(w)] : [POT[0] + 9 * Math.cos(w), POT[1] - 20 + 3 * Math.sin(w)];
  armTo(c.armN, sn, hand, -30, -1, 80);
  c.spoon.setAttribute('d', talk ? `M${f(hand)} L${f(add(hand, rot([0, -40], 30 + 22 * Math.sin(w))))}` : `M${f(hand)} L${f([POT[0] - 5 * Math.cos(w), POT[1] + 8])}`);
  armTo(c.armF, sf, talk ? [sf[0] + 26 + 5 * Math.sin(w + 2), sf[1] + 34 + 7 * Math.sin(w + 2)] : [sf[0] + 16, sf[1] + 44 + beat], talk ? -40 : 0, 1);
  tailUp(c, P([-19, -4]), TAU * t / 1.6, 0);
  headTo(c, add(P([2, -39]), [9 * look, -31 + beat]), 4 * look, frac(t / 3.7) > 0.96 ? 0.12 : 1, look < 0 ? 1 : 0);
  c.face.setAttribute('transform', `scale(${(Math.abs(look) < 0.08 ? 0.08 : look).toFixed(3)},1)`);
  c.pupils.setAttribute('transform', talk ? '' : look < 0 ? 'translate(4,-1)' : 'translate(2,4)');   // on the Mac, or down at the pot
}

// A speech bubble that pops out of whoever is talking: `to` is the tip of its tail. With no text it holds a scribble.
function bubble(id, text, cx, cy, to) {
  const w = text ? 30 + 8.4 * text.length : 92, x = cx - w / 2, by = cy + 19, tx = cx + (to[0] > cx ? 1 : -1) * Math.min(w / 2 - 22, 30);
  return `<g data-id="${id}" data-to="${to}"><g filter="url(#rough)" fill="#fffdf8" stroke="#1a1a18" stroke-width="3.6" stroke-linejoin="round"><path d="M${tx - 9} ${by}L${to[0]} ${to[1]}L${tx + 9} ${by}"/><rect x="${x}" y="${cy - 19}" width="${w}" height="38" rx="13"/><path stroke="#fffdf8" stroke-width="5" d="M${tx - 6} ${by}H${tx + 6}"/></g>${text ? `<text x="${cx}" y="${cy}">${text}</text>` : `<path class="line" stroke-width="2.6" d="M${cx - 30} ${cy - 5}q5-6 10 0t10 0t10 0t10 0t10 0t10 0M${cx - 30} ${cy + 7}q5-6 10 0t10 0t10 0t10 0"/>`}</g>`;
}

// The room: the Mac on a desk at one side, a window in the middle, the stove under a lamp at the other side.
// A ceiling line near the top of the screen runs in from the right to just past the lamp, which hangs from it.
const MAC = [125, 202], HOME = 245, STOVE = 438;         // the Mac's bubble tip; where the cat stands to talk, and to cook
const room = (key, bubbles = '', extra = '') => `<svg class="rh" viewBox="0 0 640 400" aria-hidden="true">
<defs><clipPath id="win-${key}"><path d="M292 46h88v100h-88z"/></clipPath><radialGradient id="glow-${key}"><stop offset="0" stop-color="#fff0b8" stop-opacity=".95"/><stop offset="1" stop-color="#fff0b8" stop-opacity="0"/></radialGradient></defs>
<rect data-id="wall" x="-700" y="-700" width="2040" height="1800"/>
<rect x="-700" y="340" width="2040" height="800" fill="#1a1a18" opacity=".07"/>
<g clip-path="url(#win-${key})"><rect data-id="sky" x="292" y="46" width="88" height="100"/><circle data-id="sun" cx="352" r="15"/><g data-id="stars" fill="#fdf6dc"><circle cx="308" cy="66" r="1.8"/><circle cx="324" cy="116" r="1.4"/><circle cx="366" cy="126" r="1.6"/><circle cx="312" cy="132" r="1.2"/></g></g>
<g filter="url(#rough)">${ink('M292 46h88v100h-88zM336 46v100M292 96h88', 4)}${ink('M284 150h104', 6)}</g>
<circle data-id="glow" cx="590" cy="104" r="170" fill="url(#glow-${key})"/>
<g filter="url(#rough)"><path data-id="ceiling" fill="none" stroke="#1a1a18" stroke-width="4.5" stroke-linecap="round"/><path data-id="cord" fill="none" stroke="#1a1a18" stroke-width="3" stroke-linecap="round"/><path data-id="shade" d="M566 96L578 66h24L614 96Z" stroke="#1a1a18" stroke-width="4" stroke-linejoin="round"/></g>
<path d="M-700 340H1340" stroke="#1a1a18" stroke-width="4.5"/>
<g transform="translate(30,340) scale(1.25) translate(0,-262)"><g filter="url(#rough)"><path data-id="screen" d="M38 158h76v52H38z" fill="#fffdf8"/>${ink('M38 158h76v52H38z')}${ink('M28 213h96', 6)}${ink('M20 219h112M32 219v43M120 219v43', 4)}</g>
<g data-id="mac" transform="translate(38,158)"><circle data-id="kevin" cx="12" cy="12" r="4.5" fill="#F4A62A"/>${[0, 1, 2].map(i => `<g data-id="job"><path d="M10 ${25 + 9 * i}h56" stroke="#d9d4c7" stroke-width="3.4" stroke-linecap="round"/><path data-id="bar" stroke="#1a1a18" stroke-width="3.4" stroke-linecap="round"/></g>`).join('')}<path data-id="tick" d="M24 27l10 10 18-21" fill="none" stroke="#F4A62A" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round" opacity="0"/></g></g>
<g transform="translate(240,78)"><g data-id="steam" fill="none" stroke="#1a1a18" stroke-width="2.4" stroke-linecap="round" opacity=".55">${[0, 1, 2].map(i => `<path d="M${244 + 12 * i} 0c-5-6 5-9 0-16"/>`).join('')}</g></g>
<g data-id="actor" transform="translate(0,340) scale(${K})"></g>
<g transform="translate(240,78)" filter="url(#rough)"><path d="M228 230h92v32h-92z" fill="#fffdf8"/>${ink('M224 230h100M230 230v32M318 230v32')}<circle cx="246" cy="246" r="3" fill="#1a1a18"/><circle cx="260" cy="246" r="3" fill="#1a1a18"/>
<path d="M232 208h46v14a8 8 0 0 1-8 8h-30a8 8 0 0 1-8-8z" fill="#fffdf8"/>${ink('M232 208h46v14a8 8 0 0 1-8 8h-30a8 8 0 0 1-8-8zM232 215h-8M278 215h8', 4)}</g>
${extra}${bubbles}</svg>`;

// Puts a room in `el` and returns what moves in it. `light` paints the hour: 0 is the afternoon, 1 the dusk, 2 the night.
function build(el, key, mood, bubbles, extra) {
  el.innerHTML = room(key, bubbles, extra);
  const q = id => el.querySelector(`[data-id="${id}"]`);
  const c = makeCat(mood);
  c.spoon = document.createElementNS(NS, 'path');
  c.spoon.setAttribute('class', 'line');
  c.spoon.setAttribute('stroke-width', 4);
  c.cat.append(c.spoon, c.armN);                         // in front of the head, so a waving spoon is never hidden
  q('actor').append(c.cat);
  const jobs = [...el.querySelectorAll('[data-id="job"]')], steam = [...q('steam').children], says = {};
  el.querySelectorAll('[data-to]').forEach(g => (says[g.dataset.id] = g));
  return {
    c, q, svg: el.firstChild,
    light(h) {
      const night = clamp01(h - 1);
      q('wall').setAttribute('fill', ramp(['#f8f3e7', '#f8ecd6', '#f3e0c2', '#e5d4b9'], h / 2));   // the night wall is the colour the page has under the story
      q('sky').setAttribute('fill', ramp(['#cfe6ea', '#f7dfae', '#f2ae78', '#8d789f', '#27314f'], h / 2));
      q('sun').setAttribute('cy', night > 0.5 ? 78 : lerp(84, 176, clamp01(h)));     // the sun goes down behind the sill; the moon is already up
      q('sun').setAttribute('fill', night > 0.5 ? '#fdf6dc' : ramp(['#fffbe6', '#ffd27a', '#ff9d5c'], h));
      q('sun').setAttribute('opacity', night > 0.5 ? span(night, 0.5, 1) : 1 - span(night, 0, 0.5));
      q('stars').setAttribute('opacity', span(night, 0.4, 1));
      const lamp = span(h, 0.9, 1.2);
      q('glow').setAttribute('opacity', (0.75 * lamp).toFixed(2));
      q('shade').setAttribute('fill', ramp(['#fffdf8', '#ffe08a'], lamp));
    },
    mac(list, ask, kevin, time) {                        // each job's progress (below 0 hides it), which one is asking, and Kevin's dot
      jobs.forEach((g, i) => {
        g.setAttribute('opacity', list[i] < 0 ? 0 : 1);
        g.lastElementChild.setAttribute('d', `M10 ${25 + 9 * i}h${(56 * Math.max(0.02, list[i])).toFixed(1)}`);
        g.lastElementChild.setAttribute('stroke', ask === i ? '#F4A62A' : '#1a1a18');
      });
      q('kevin').setAttribute('opacity', kevin < 0 ? 0 : 1);
      q('kevin').setAttribute('r', (4.5 + 1.6 * kevin * Math.abs(Math.sin(TAU * time / 1.1))).toFixed(2));
    },
    steam(time, on) {
      steam.forEach((g, i) => {
        const d = frac(time / 2.6 + i / 3);
        g.setAttribute('transform', `translate(${(3 * Math.sin(TAU * d)).toFixed(1)},${(186 - 34 * d).toFixed(1)})`);
        g.setAttribute('opacity', (on * Math.sin(Math.PI * d)).toFixed(2));
      });
    },
    say(show) {                                          // how far out each bubble is, 0 to 1
      for (const id in says) {
        const to = says[id].dataset.to.split(',');
        says[id].setAttribute('transform', `translate(${to[0]},${to[1]}) scale(${(show[id] || 0).toFixed(3)}) translate(${-to[0]},${-to[1]})`);
      }
    },
  };
}

// Standing at ease by the table, looking down at its dinner.
function stand(c, t, x) {
  const beat = Math.sin(TAU * t / 2.4);
  const P = trunk(c, [x, 0], [0, -70 + 1.2 * beat], 3, 0.02 * beat);
  c.shadow.setAttribute('rx', 40);
  legTo(c.legN, P([-8, 1]), [-14, -10], 0);
  legTo(c.legF, P([8, 0]), [10, -10], 0);
  const sn = P([-2, -30]), sf = P([8, -30]);
  armTo(c.armN, sn, add(sn, [-4, 50 + beat]), 0);
  armTo(c.armF, sf, add(sf, [24, 42 + beat]), 0, 1);
  tailUp(c, P([-19, -4]), TAU * t / 2.4, 0);
  headTo(c, add(P([2, -39]), [9, -31 + beat]), 5, frac(t / 3.7) > 0.96 ? 0.12 : 1, 0);
  c.pupils.setAttribute('transform', 'translate(3,4)');
}

// The room fills its whole stage. The camera `cam` ([left, width] in room units) is fitted above a band of floor
// `floor` px tall, where the words sit; the wall and the floor run on past every edge.
function frame(svg, el, cam, floor) {
  const W = el.clientWidth, H = el.clientHeight;
  floor = Math.min(floor, 0.45 * H);                     // on a very short screen the room keeps more than half
  const k = Math.min(W / cam[1], (H - floor) / 400), w = W / k, h = H / k;
  const top = 340 + floor / k - h, up = Math.min(20, top + 30 / k).toFixed(1);   // the ceiling sits just under the top edge
  svg.setAttribute('viewBox', `${(cam[0] + cam[1] / 2 - w / 2).toFixed(1)} ${top.toFixed(1)} ${w.toFixed(1)} ${h.toFixed(1)}`);
  svg.querySelector('[data-id="ceiling"]').setAttribute('d', `M556 ${up}H1340`);
  svg.querySelector('[data-id="cord"]').setAttribute('d', `M590 ${up}V66`);
}
const tall = el => el.clientWidth < 1.1 * el.clientHeight;   // a phone held upright: the camera stays with the cat

// The story, pinned while the page scrolls past it. `p` is how far through, and everything that happens is tied to
// it, so no stretch of scroll leaves the room unchanged: talk, walk over, hand it off, say yes. Time only keeps the
// cat alive (stirring, steam, its tail, a blink).
const TALK = 0.2, OVER = 0.42, HAND = 0.7, SAID = 0.87;  // where the talk and the walk end, where Kevin calls, where the yes lands
const CAMS = [[30, 360], [272, 360], [52, 562]];         // upright-phone cameras: at the Mac, at the stove, both
function story(track, frozen) {
  const stage = track.querySelector('[data-stage]'), words = track.querySelector('[data-words]'), caps = [...track.querySelectorAll('[data-cap]')];
  const r = build(stage, 'day', 'glad', bubble('cat', '', 268, 152, [258, 190]) + bubble('mac', '', 130, 150, MAC)
    + bubble('run', 'Run the tests.', 456, 138, [444, 186]) + bubble('ask', 'Commit your changes?', 160, 138, MAC) + bubble('yes', 'Yes.', 476, 142, [448, 184]));
  const to = (a, b) => v => clamp01((v - a) / (b - a));
  return time => {
    const box = track.getBoundingClientRect(), p = clamp01(-box.top / Math.max(1, box.height - innerHeight));
    const part = p < (TALK + OVER) / 2 ? 0 : p < HAND ? 1 : 2;
    caps.forEach((n, i) => n.classList.toggle('on', i === part));
    if (frozen !== undefined) time = Number.isNaN(frozen) ? 1.4 : frozen;
    r.light(1.25 * p);
    r.steam(time, 1);
    const show = {};
    let x = STOVE;
    if (p < TALK) {                                      // the cat, the Mac, the cat again
      x = HOME;
      cook(r.c, time, HOME / K, 1, true);
      show.cat = pulse(p, -1, 0.07, 0.02) + pulse(p, 0.13, 1, 0.02);
      show.mac = pulse(p, 0.06, 0.14, 0.02);
      r.mac([-1, -1, -1], -1, show.mac, time);
    } else if (p < OVER) {                               // every step is scrolled, so no foot slides
      const u = to(TALK, OVER)(p);
      x = lerp(HOME, STOVE, u);
      walk(r.c, (u * (STOVE - HOME)) / K / V, HOME / K);
      r.c.spoon.setAttribute('d', '');
      r.c.face.setAttribute('transform', '');
      r.c.pupils.setAttribute('transform', '');
      r.mac([-1, -1, -1], -1, 0, time);
    } else {
      // At the stove. Eyes on the pot while it hands the job off; when Kevin calls, the same hands keep stirring and
      // only its eyes go to the Mac, where they stay.
      cook(r.c, time, STOVE / K, 1 - 2 * span(p, HAND, HAND + 0.03), false);
      show.run = pulse(p, OVER, 0.54, 0.02);
      show.ask = pulse(p, HAND - 0.01, SAID + 0.04, 0.02);
      show.yes = pulse(p, 0.8, 0.96, 0.02);
      const held = p < HAND ? 0.55 * to(0.57, HAND)(p) : 0.55 + 0.45 * to(SAID, 0.99)(p);   // the job that stops to ask
      r.mac([p < 0.47 ? -1 : to(0.47, 0.8)(p), p < 0.57 ? -1 : held, p < 0.63 ? -1 : 0.85 * to(0.63, 1)(p)], p >= HAND && p < SAID ? 1 : -1, show.run || (p >= HAND && p < SAID) ? 1 : 0, time);
    }
    r.say(show);
    const go = (a, b, u) => [lerp(CAMS[a][0], CAMS[b][0], u), lerp(CAMS[a][1], CAMS[b][1], u)];
    const cam = !tall(stage) ? [0.22 * (x - 340) + 24 * (p - 0.5), 640] : p < OVER ? go(0, 1, span(p, TALK, OVER)) : go(1, 2, span(p, HAND - 0.05, HAND + 0.01));
    frame(r.svg, stage, cam, words.offsetHeight + 0.09 * stage.clientHeight);
  };
}

// The end of the day: the call is over. The Mac shows one gold tick for the finished job, the moon is up, and the
// cat stands by the table under the window, where its dinner is steaming.
const TABLE = `<g filter="url(#rough)">${ink('M296 270h104', 6)}${ink('M306 270v70M390 270v70', 4)}<path d="M326 245h44c0 14-9 22-22 22s-22-8-22-22z" fill="#fffdf8"/>${ink('M326 245h44c0 14-9 22-22 22s-22-8-22-22z', 4)}</g>
<g fill="none" stroke="#1a1a18" stroke-width="2.4" stroke-linecap="round" opacity=".55">${[0, 1].map(i => `<path data-id="waft" d="M${341 + 14 * i} 238c-5-6 5-9 0-16"/>`).join('')}</g>`;
function night(el) {
  const stage = el.querySelector('[data-stage]'), words = el.querySelector('[data-words]');
  const r = build(stage, 'night', 'glad', '', TABLE);
  const waft = [...stage.querySelectorAll('[data-id="waft"]')];
  r.c.spoon.remove();
  r.light(2);
  r.mac([-1, -1, -1], -1, -1, 0);
  r.q('tick').setAttribute('opacity', 1);
  r.steam(0, 0);
  return time => {
    stand(r.c, time, 250 / K);
    waft.forEach((g, i) => {
      const d = frac(time / 3 + i / 2);
      g.setAttribute('transform', `translate(${(2 * Math.sin(TAU * d)).toFixed(1)},${(-12 * d).toFixed(1)})`);
      g.setAttribute('opacity', Math.sin(Math.PI * d).toFixed(2));
    });
    frame(r.svg, stage, tall(stage) ? [36, 384] : [0, 640], words.offsetHeight + 0.17 * stage.clientHeight);
  };
}

// Draws the story and the ending and keeps them moving while they are on screen.
// "?t=2.5" in the address shows everything frozen at that moment; asking for reduced motion freezes the cat too, and
// the page still moves through the story as it is scrolled.
function draw() {
  document.documentElement.classList.add('js');
  document.body.insertAdjacentHTML('beforeend', DEFS);
  const still = new URLSearchParams(location.search).get('t');
  const frozen = still !== null ? parseFloat(still) : matchMedia('(prefers-reduced-motion: reduce)').matches ? NaN : undefined;
  const nodes = [...document.querySelectorAll('[data-story], [data-night]')];
  const acts = nodes.map(n => (n.dataset.night === undefined ? story(n, frozen) : night(n)));
  const seen = new Set(nodes);
  const watch = new IntersectionObserver(list => list.forEach(e => seen[e.isIntersecting ? 'add' : 'delete'](e.target)), { rootMargin: '120px' });
  nodes.forEach(n => watch.observe(n));
  const start = performance.now();
  (function tick(now) {
    nodes.forEach((n, i) => seen.has(n) && acts[i](frozen === undefined ? (now - start) / 1000 : Number.isNaN(frozen) ? 1.4 : frozen));
    requestAnimationFrame(tick);
  })(start);
}
draw();
