import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toUS } from '../src/units.js';

test('HbA1c 48 mmol/mol → 6.5 %', () => {
  const r = toUS('59261-8', 48, 'mmol/mol');
  assert.equal(r.unit, '%');
  assert.equal(r.value, 6.5);
});

test('glucose 5.5 mmol/L → 99 mg/dL', () => {
  assert.deepEqual(toUS('15074-8', 5.5, 'mmol/L'), { value: 99, unit: 'mg/dL' });
});

test('unknown code → null', () => {
  assert.equal(toUS('0000-0', 1, 'x'), null);
});
