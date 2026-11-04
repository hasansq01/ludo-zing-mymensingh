// Small seeded PRNG for the server's bots (pickAi jitter / easy picks) and tests. Not cryptographic.

export interface Rng {
  /** A float in [0, 1). */
  randf(): number;
}

/** mulberry32: 32-bit state, good enough for game AI jitter and reproducible tests. */
export class Mulberry32 implements Rng {
  private a: number;

  constructor(seed: number) {
    this.a = seed >>> 0;
  }

  /** The next raw 32-bit unsigned value. */
  next(): number {
    this.a = (this.a + 0x6d2b79f5) >>> 0;
    let t = this.a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  }

  randf(): number {
    return this.next() / 4294967296;
  }

  /** An int in [lo, hi] (both inclusive), like RandomNumberGenerator.randi_range. */
  randiRange(lo: number, hi: number): number {
    return lo + Math.min(Math.floor(this.randf() * (hi - lo + 1)), hi - lo);
  }

  /** The current state, to persist a bot's RNG between Durable Object wake-ups. */
  get state(): number {
    return this.a;
  }

  set state(v: number) {
    this.a = v >>> 0;
  }
}

/** An Rng backed by Math.random (unseeded; what GDScript's global randf() is when no rng is passed). */
export const mathRandom: Rng = { randf: () => Math.random() };
