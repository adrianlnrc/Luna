'use strict';
// Subconjunto minimo do DateTime do Luxon (so o que os nos Code usam), sem dependencias.
const DAY = 86400000;

function parts(ms, zone) {
  const f = new Intl.DateTimeFormat('en-US', { timeZone: zone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const o = {};
  f.formatToParts(new Date(ms)).forEach(function (p) { o[p.type] = Number(p.value); });
  return { y: o.year, mo: o.month, d: o.day, h: o.hour, mi: o.minute, s: o.second };
}
function offsetMin(ms, zone) {
  const p = parts(ms, zone);
  const asUtc = Date.UTC(p.y, p.mo - 1, p.d, p.h, p.mi, p.s);
  return Math.round((asUtc - Math.floor(ms / 1000) * 1000) / 60000);
}
function fromLocal(y, mo, d, h, mi, s, zone) {
  const guess = Date.UTC(y, mo - 1, d, h, mi, s);
  let ms = guess - offsetMin(guess, zone) * 60000;
  ms = guess - offsetMin(ms, zone) * 60000;
  return ms;
}
const p2 = function (n) { return String(n).padStart(2, '0'); };

class DateTime {
  constructor(ms, zone, locale, valid) { this._ms = ms; this._zone = zone || 'UTC'; this._loc = locale || 'en-US'; this._valid = valid !== false && !isNaN(ms); }
  static now() { return new DateTime(Date.now(), 'UTC'); }
  static fromISO(s, opt) {
    const zone = (opt && opt.zone) || 'UTC';
    const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$/.exec(String(s));
    if (!m) { return new DateTime(NaN, zone, null, false); }
    const [y, mo, d, h, mi, sec] = [m[1], m[2], m[3], m[4] || 0, m[5] || 0, m[6] || 0].map(Number);
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 24 || mi > 59) { return new DateTime(NaN, zone, null, false); }
    const chk = new Date(Date.UTC(y, mo - 1, d));
    if (chk.getUTCMonth() !== mo - 1) { return new DateTime(NaN, zone, null, false); }
    if (m[7]) {
      const off = m[7] === 'Z' ? 0 : (m[7][0] === '-' ? -1 : 1) * (Number(m[7].slice(1, 3)) * 60 + Number(m[7].slice(-2)));
      return new DateTime(Date.UTC(y, mo - 1, d, h, mi, sec) - off * 60000, zone);
    }
    return new DateTime(fromLocal(y, mo, d, h, mi, sec, zone), zone);
  }
  get isValid() { return this._valid; }
  setZone(z) { return new DateTime(this._ms, z, this._loc, this._valid); }
  setLocale(l) { return new DateTime(this._ms, this._zone, l, this._valid); }
  toMillis() { return this._ms; }
  valueOf() { return this._ms; }
  toUTC() { return this.setZone('UTC'); }
  plus(o) {
    let ms = this._ms;
    const p = parts(ms, this._zone);
    let y = p.y, mo = p.mo, d = p.d;
    const days = (o.days || 0) + (o.weeks || 0) * 7;
    if (o.months || o.years) {
      const t = (mo - 1) + (o.months || 0) + (o.years || 0) * 12;
      y += Math.floor(t / 12); mo = (((t % 12) + 12) % 12) + 1;
      const last = new Date(Date.UTC(y, mo, 0)).getUTCDate();
      d = Math.min(d, last);
    }
    if (days || o.months || o.years) {
      const base = new Date(Date.UTC(y, mo - 1, d + days));
      ms = fromLocal(base.getUTCFullYear(), base.getUTCMonth() + 1, base.getUTCDate(), p.h, p.mi, p.s, this._zone);
    }
    ms += (o.hours || 0) * 3600000 + (o.minutes || 0) * 60000 + (o.seconds || 0) * 1000;
    return new DateTime(ms, this._zone, this._loc, this._valid);
  }
  minus(o) {
    const n = {};
    Object.keys(o).forEach(function (k) { n[k] = -o[k]; });
    return this.plus(n);
  }
  startOf(unit) {
    const p = parts(this._ms, this._zone);
    let y = p.y, mo = p.mo, d = p.d, h = p.h, mi = p.mi, s = p.s;
    if (unit === 'week') { d -= (new Date(Date.UTC(y, mo - 1, d)).getUTCDay() + 6) % 7; }
    if (unit === 'month') { d = 1; }
    if (unit === 'week' || unit === 'day' || unit === 'month') { h = 0; mi = 0; s = 0; }
    else if (unit === 'hour') { mi = 0; s = 0; }
    else if (unit === 'minute') { s = 0; }
    const b = new Date(Date.UTC(y, mo - 1, d));
    return new DateTime(fromLocal(b.getUTCFullYear(), b.getUTCMonth() + 1, b.getUTCDate(), h, mi, s, this._zone), this._zone, this._loc, this._valid);
  }
  toISO() {
    if (!this._valid) { return null; }
    const p = parts(this._ms, this._zone);
    const off = offsetMin(this._ms, this._zone);
    const sign = off < 0 ? '-' : '+';
    const a = Math.abs(off);
    const ms3 = String(((this._ms % 1000) + 1000) % 1000).padStart(3, '0');
    const tz = (this._zone === 'UTC' && off === 0) ? 'Z' : sign + p2(Math.floor(a / 60)) + ':' + p2(a % 60);
    return p.y + '-' + p2(p.mo) + '-' + p2(p.d) + 'T' + p2(p.h) + ':' + p2(p.mi) + ':' + p2(p.s) + '.' + ms3 + tz;
  }
  toFormat(fmt) {
    if (!this._valid) { return 'Invalid DateTime'; }
    const p = parts(this._ms, this._zone);
    const loc = this._loc;
    const wd = function (st, ms, z) { return new Intl.DateTimeFormat(loc, { timeZone: z, weekday: st }).format(new Date(ms)); };
    const self = this;
    return String(fmt).replace(/'([^']*)'|yyyy|MM|dd|HH|mm|ss|cccc|ccc/g, function (t, lit) {
      if (lit !== undefined) { return lit; }
      switch (t) {
        case 'yyyy': return String(p.y);
        case 'MM': return p2(p.mo);
        case 'dd': return p2(p.d);
        case 'HH': return p2(p.h);
        case 'mm': return p2(p.mi);
        case 'ss': return p2(p.s);
        case 'cccc': return wd('long', self._ms, self._zone);
        case 'ccc': return wd('short', self._ms, self._zone);
        default: return t;
      }
    });
  }
}
module.exports = { DateTime };
