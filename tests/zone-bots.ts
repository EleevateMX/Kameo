// Aluxes simulados para el servidor de zonas (la plaza): hablan su protocolo por WebSocket.
// Los usan zone.test.ts (reglas) y zone-load.ts (carga).
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function until(what: string, fn: () => boolean, timeoutMs = 5000) {
  const end = Date.now() + timeoutMs;
  while (!fn()) {
    if (Date.now() > end) throw new Error(`Tiempo agotado esperando: ${what}`);
    await sleep(40);
  }
}

interface Neighbour { profile: { n: string; c: string; h: number; l: number[] }; x: number; y: number; z: number; r: number; down?: boolean }
/** Criatura del mundo abierto tal como llega en los estados. `st`: idle, chase, windup, recover, weak, return. */
export interface Creature { id: number; x: number; z: number; r: number; hp: number; st: string; target: number; seen: number }
const CREATURE_STATES = ['idle', 'chase', 'windup', 'recover', 'weak', 'return'];

export class ZBot {
  ws!: WebSocket;
  welcome: any = null;
  error: { code: string } | null = null;
  /** Perfil propio según el servidor (el del ticket, o el releído de la API). */
  me: { n: string; c: string; h: number; l: number[] } | null = null;
  closed = false;
  seq = 0;
  ack = 0;
  total = 0;
  enters: string[] = [];
  leaves = 0;
  /** Lo más que trajo un solo estado. */
  maxPerState = 0;
  bytesIn = 0;
  statesIn = 0;
  stats: any = null;
  // ── Mundo abierto ──
  /** Zona en la que está según el servidor, y cuántas veces lo ha movido de sitio (viaje o reaparición). */
  zone = '';
  epoch = 0;
  zoneMsgs: any[] = [];
  hp = 0;
  maxHp = 0;
  known: string[] = [];
  quest: { st: string; n: number; need: number } | null = null;
  creatures = new Map<number, Creature>();
  /** Todo lo demás que manda el servidor, por tipo: ev, disc, reward, atk_no, travel_no, quest. */
  events: any[] = [];
  private near = new Map<number, Neighbour>();
  private counts = new Map<string, number>();
  private s = { x: 0, y: 0, z: 0, vy: 0 };
  private keepalive: ReturnType<typeof setInterval> | null = null;

  constructor(public id: string, public name: string, private url: string) {}

  private open(first: object) {
    this.welcome = null;
    this.error = null;
    this.closed = false;
    this.seq = 0;
    this.near.clear();
    return new Promise<void>((resolve) => {
      const done = () => resolve();
      this.ws = new WebSocket(this.url);
      const timer = setTimeout(done, 6000);
      this.ws.onopen = () => this.ws.send(JSON.stringify(first));
      this.ws.onclose = () => { this.closed = true; clearTimeout(timer); if (this.keepalive) clearInterval(this.keepalive); done(); };
      this.ws.onerror = () => { /* onclose lo cuenta */ };
      this.ws.onmessage = (ev) => {
        const text = String(ev.data);
        this.bytesIn += text.length;
        const m = JSON.parse(text);
        switch (m.t) {
          case 'welcome':
            this.welcome = m;
            this.me = m.me;
            this.s = { x: m.pos[0], y: m.pos[1], z: m.pos[2], vy: 0 };
            this.enterZone(m);
            clearTimeout(timer);
            this.keepalive = setInterval(() => this.send({ t: 'ping', c: 0 }), 5000);
            done();
            break;
          case 'error':
            this.error = { code: m.code };
            break;
          case 's': {
            this.statesIn++;
            this.ack = m.a;
            this.total = m.n;
            this.s = { x: m.m[0], y: m.m[1], z: m.m[2], vy: m.m[3] };
            this.maxPerState = Math.max(this.maxPerState, m.p.length);
            if (typeof m.h === 'number') this.hp = m.h;
            for (const [id, x, z, r, hp, st, target] of m.c ?? []) {
              this.creatures.set(id, { id, x, z, r, hp, st: CREATURE_STATES[st], target, seen: Date.now() });
            }
            for (const [num, x, y, z, r, down] of m.p) {
              const nb = this.near.get(num);
              if (!nb) continue;
              Object.assign(nb, { x, y, z, r, down: down === 1 });
              this.counts.set(nb.profile.n, (this.counts.get(nb.profile.n) ?? 0) + 1);
            }
            break;
          }
          case 'enter':
            this.near.set(m.i, { profile: { n: m.n, c: m.c, h: m.h, l: m.l }, x: m.x, y: m.y, z: m.z, r: m.r });
            this.enters.push(m.n);
            break;
          case 'leave':
            this.near.delete(m.i);
            this.leaves++;
            break;
          case 'me':
            this.me = m.me;
            break;
          case 'stats':
            this.stats = m;
            break;
          case 'zone':
            this.zoneMsgs.push(m);
            this.s = { x: m.pos[0], y: m.pos[1], z: m.pos[2], vy: 0 };
            this.near.clear();
            this.enterZone(m);
            break;
          case 'quest':
            this.quest = { st: m.st, n: m.n, need: m.need };
            this.events.push(m);
            break;
          case 'ev':
            if (m.e === 'die') this.creatures.delete(m.c);
            this.events.push(m);
            break;
          case 'disc':
            if (!this.known.includes(m.id)) this.known.push(m.id);
            this.events.push(m);
            break;
          case 'reward': case 'atk_no': case 'travel_no':
            this.events.push(m);
            break;
        }
      };
    });
  }

  private enterZone(m: any) {
    if (m.zone !== this.zone) this.creatures.clear();
    this.zone = m.zone;
    this.epoch = m.e ?? 0;
    if (typeof m.hp === 'number') this.hp = m.hp;
    if (typeof m.maxhp === 'number') this.maxHp = m.maxhp;
    if (Array.isArray(m.known)) this.known = [...m.known];
    if (m.quest) this.quest = { st: m.quest.st, n: m.quest.n, need: m.quest.need };
  }

  connect(token: string) { return this.open({ t: 'hello', ticket: token }); }
  /** Abre la conexión mandando otra cosa en vez del ticket. */
  connectRaw(first: object) { return this.open(first); }
  send(msg: object) { if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg)); }
  close() { if (this.keepalive) clearInterval(this.keepalive); try { this.ws.close(); } catch { /* ya estaba */ } }

  pos() { return { ...this.s }; }
  sees(name: string) { return [...this.near.values()].some((n) => n.profile.n === name); }
  neighbour(name: string) { return [...this.near.values()].find((n) => n.profile.n === name); }
  visible() { return this.near.size; }
  /** Estados recibidos de ese alux desde el principio. */
  statesFrom(name: string) { return this.counts.get(name) ?? 0; }

  private input(mx: number, mz: number, jump = false) {
    this.seq++;
    this.send({ t: 'in', s: this.seq, x: mx, z: mz, j: jump ? 1 : 0, r: Math.atan2(mx, mz), e: this.epoch });
  }

  // ── Mundo abierto ──
  /** Sucesos recibidos de un tipo (y, si se dice, de una clase: ev.e). */
  got(t: string, e?: string) { return this.events.filter((m) => m.t === t && (e === undefined || m.e === e)); }
  /** Criatura con ese id si ha llegado en un estado hace poco (las lejanas o muertas dejan de llegar). */
  creature(id: number) { const c = this.creatures.get(id); return c && Date.now() - c.seen < 1500 ? c : undefined; }
  /** Pide pasar a otra zona y espera la respuesta: el mensaje `zone` si se pudo, o null si el servidor dijo que no. */
  async travel(to: string) {
    const before = this.zoneMsgs.length, refused = this.got('travel_no').length;
    this.send({ t: 'travel', to });
    const end = Date.now() + 4000;
    while (Date.now() < end && this.zoneMsgs.length === before && this.got('travel_no').length === refused) await sleep(30);
    return this.zoneMsgs.length > before ? this.zoneMsgs[this.zoneMsgs.length - 1] : null;
  }
  /** Ataque básico apuntando a un punto. */
  attackAt(x: number, z: number, extra: object = {}) { this.send({ t: 'atk', r: Math.atan2(x - this.s.x, z - this.s.z), ...extra }); }
  purify() { this.send({ t: 'purify' }); }
  /** Anda por una lista de puntos (para seguir un camino con curvas). */
  async walkPath(points: [number, number][], timeoutMs = 90_000) {
    for (const [x, z] of points) await this.walkTo(x, z, timeoutMs, false);
    await this.settle();
  }

  /** Mantiene una dirección `ms` milisegundos. `rate`: veces el ritmo normal (20 entradas por segundo). */
  async hold(mx: number, mz: number, ms: number, rate = 1) {
    const end = Date.now() + ms;
    let next = Date.now();
    while (Date.now() < end) {
      this.input(mx, mz);
      next += 50 / rate;
      await sleep(Math.max(0, next - Date.now()));
    }
  }

  /** Espera a que el servidor haya aplicado todo lo enviado y el alux esté quieto. */
  async settle() {
    const end = Date.now() + 3000;
    // El servidor conserva siempre las entradas más recientes (descarta las viejas si se le mandan
    // más de las que caben), así que acaba confirmando la última enviada: se espera a eso. Salir
    // antes dejaba la cola a medio vaciar y el alux todavía andando.
    while (Date.now() < end && this.ack < this.seq) await sleep(50);
    await sleep(350);
  }

  /** Anda en línea recta hacia un punto (resbalando por los obstáculos). */
  async walkTo(x: number, z: number, timeoutMs = 40_000, settle = true) {
    const end = Date.now() + timeoutMs;
    let next = Date.now();
    while (Date.now() < end) {
      const dx = x - this.s.x, dz = z - this.s.z;
      const d = Math.hypot(dx, dz);
      if (d < 0.7) break;
      this.input(dx / d, dz / d);
      next += 50;
      await sleep(Math.max(0, next - Date.now()));
    }
    if (settle) await this.settle();
  }

  /** Salta en el sitio y devuelve la altura máxima que dijo el servidor. */
  async jump() {
    let top = 0;
    const end = Date.now() + 1400;
    let n = 0;
    while (Date.now() < end) {
      this.input(0, 0, n < 2);
      n++;
      top = Math.max(top, this.s.y);
      await sleep(50);
    }
    return top;
  }
}
