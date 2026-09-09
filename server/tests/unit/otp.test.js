'use strict';

const { generateCode, hashCode, timingSafeEqualHex } = require('../../src/utils/otp');
const { parseUtc } = require('../../src/utils/time');

describe('otp util', () => {
  it('generates a 4-digit numeric code', () => {
    for (let i = 0; i < 50; i++) {
      expect(generateCode()).toMatch(/^\d{4}$/);
    }
  });

  it('hash is stable for the same inputs and bound to mobile+role', () => {
    const a = hashCode('1234', '9876543210', 'customer');
    const b = hashCode('1234', '9876543210', 'customer');
    const c = hashCode('1234', '9876543210', 'driver');
    const d = hashCode('1234', '9999999999', 'customer');
    expect(a).toBe(b);
    expect(a).not.toBe(c);
    expect(a).not.toBe(d);
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });

  it('timingSafeEqualHex compares correctly', () => {
    const h = hashCode('1234', '9876543210', 'customer');
    expect(timingSafeEqualHex(h, h)).toBe(true);
    expect(timingSafeEqualHex(h, hashCode('9999', '9876543210', 'customer'))).toBe(false);
    expect(timingSafeEqualHex(h, 'zz')).toBe(false);
  });
});

describe('parseUtc', () => {
  it('interprets a bare MySQL datetime string as UTC', () => {
    const d = parseUtc('2026-09-08 06:26:27');
    expect(d.toISOString()).toBe('2026-09-08T06:26:27.000Z');
  });

  it('passes through an explicit-offset string', () => {
    expect(parseUtc('2026-09-08T06:26:27Z').toISOString()).toBe('2026-09-08T06:26:27.000Z');
  });

  it('returns null for null', () => {
    expect(parseUtc(null)).toBeNull();
  });
});
