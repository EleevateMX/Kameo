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

interface Neighbour { profile: { n: string; c: string; h: number; l: number[] }; x: number; y: number; z: number; r: number }

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
            for (const [num, x, y, z, r] of m.p) {
              const nb = this.near.get(num);
              if (!nb) continue;
              Object.assign(nb, { x, y, z, r });
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
        }
      };
    });
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
    this.send({ t: 'in', s: this.seq, x: mx, z: mz, j: jump ? 1 : 0, r: Math.atan2(mx, mz) });
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
    while (Date.now() < end && this.ack < this.seq) {
      await sleep(50);
      if (this.ack < this.seq - 8) break;   // el servidor descartó entradas viejas: no van a llegar
    }
    await sleep(350);
  }

  /** Anda en línea recta hacia un punto (resbalando por los obstáculos). */
  async walkTo(x: number, z: number, timeoutMs = 40_000) {
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
    await this.settle();
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
