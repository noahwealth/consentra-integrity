// UK (SI) → US conventional lab units, keyed by LOINC code. See decision.md D3.
const round = (v, dp) => Math.round(v * 10 ** dp) / 10 ** dp;

const CONVERSIONS = {
  '15074-8': { from: 'mmol/L', unit: 'mg/dL', fn: (v) => v * 18.016, dp: 0 }, // glucose
  '59261-8': { from: 'mmol/mol', unit: '%', fn: (v) => 0.0915 * v + 2.15, dp: 1 }, // HbA1c (IFCC → NGSP)
  '14647-2': { from: 'mmol/L', unit: 'mg/dL', fn: (v) => v * 38.67, dp: 0 }, // total cholesterol
  '14682-9': { from: 'µmol/L', unit: 'mg/dL', fn: (v) => v / 88.4, dp: 2 }, // creatinine
};

/** @returns {{value:number, unit:string} | null} */
export function toUS(loincCode, value, unit) {
  const c = CONVERSIONS[loincCode];
  if (!c || unit !== c.from || typeof value !== 'number') return null;
  return { value: round(c.fn(value), c.dp), unit: c.unit };
}
