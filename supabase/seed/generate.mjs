#!/usr/bin/env node
// Deterministic synthetic seed for Consentra.
//
//   node supabase/seed/generate.mjs > supabase/seed.sql
//
// Produces three fictional providers, ~300 synthetic patients with records
// spread across them, and one demo patient (Noah Dixon) whose records carry
// deliberately planted faults so the integrity scan has something real to find.
//
// Everything is fictional. No real organisation, person or identifier.

const SEED = 20261104;
let s = SEED;
const rand = () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; };
const pick = (a) => a[Math.floor(rand() * a.length)];
const int = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));
const chance = (p) => rand() < p;

// Stable UUIDs: deterministic from a label, no crypto needed.
const uuid = (label) => {
  let h1 = 0x811c9dc5, h2 = 0x01000193;
  for (const ch of label) { h1 = Math.imul(h1 ^ ch.charCodeAt(0), 16777619) >>> 0; h2 = Math.imul(h2 ^ ch.charCodeAt(0), 2246822519) >>> 0; }
  const hex = (n) => n.toString(16).padStart(8, '0');
  const a = hex(h1), b = hex(h2), c = hex((h1 * 31 + h2) >>> 0), d = hex((h2 * 17 + h1) >>> 0);
  return `${a}-${b.slice(0,4)}-4${b.slice(5,8)}-8${c.slice(1,4)}-${c.slice(4)}${d.slice(0,8)}`;
};
const q = (v) => v === null || v === undefined ? 'null'
  : typeof v === 'number' ? String(v)
  : typeof v === 'boolean' ? String(v)
  : Array.isArray(v) ? `array[${v.map(q).join(',')}]::text[]`
  : typeof v === 'object' ? `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`
  : `'${String(v).replace(/'/g, "''")}'`;
const date = (y, m, d) => `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
const ts = (y, m, d, h = int(8, 17)) => `${date(y, m, d)}T${String(h).padStart(2,'0')}:${String(int(0,59)).padStart(2,'0')}:00Z`;
const randDate = (yLo, yHi) => date(int(yLo, yHi), int(1, 12), int(1, 28));
const randTs = (yLo, yHi) => ts(int(yLo, yHi), int(1, 12), int(1, 28));

// ---------------------------------------------------------------------------
// Providers (all fictional)
// ---------------------------------------------------------------------------
const P = {
  thameside: { id: uuid('provider:thameside'), name: 'Thameside General Hospital', short_name: 'Thameside General', country: 'GB', city: 'London', npi: null, ods_code: 'RTH01', fhir_base_url: 'https://fhir.thameside.example.nhs.uk/r4', ehr_vendor: 'Cerner Millennium' },
  harbor:    { id: uuid('provider:harbor'),    name: 'Harbor Point Medical Center', short_name: 'Harbor Point', country: 'US', city: 'Boston, MA', npi: '1932710485', ods_code: null, fhir_base_url: 'https://fhir.harborpoint.example.org/api/FHIR/R4', ehr_vendor: 'Epic' },
  // Planted fault #4: a connected provider with no identifier at all.
  lakeside:  { id: uuid('provider:lakeside'),  name: 'Lakeside Family Practice', short_name: 'Lakeside Family', country: 'US', city: 'Ithaca, NY', npi: null, ods_code: null, fhir_base_url: null, ehr_vendor: 'athenahealth' },
};
const providers = Object.values(P);

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------
const MEDS = [
  { name: 'lisinopril',   rx: '29046',  doses: [5, 10, 20, 40], unit: 'mg', brands: ['Lisinopril', 'Zestril'] },
  { name: 'metformin',    rx: '6809',   doses: [500, 850, 1000], unit: 'mg', brands: ['Metformin', 'Glucophage'] },
  { name: 'atorvastatin', rx: '83367',  doses: [10, 20, 40, 80], unit: 'mg', brands: ['Atorvastatin', 'Lipitor'] },
  { name: 'amlodipine',   rx: '17767',  doses: [2.5, 5, 10], unit: 'mg', brands: ['Amlodipine', 'Norvasc'] },
  { name: 'levothyroxine',rx: '10582',  doses: [25, 50, 75, 100], unit: 'mcg', brands: ['Levothyroxine', 'Synthroid'] },
  { name: 'omeprazole',   rx: '7646',   doses: [20, 40], unit: 'mg', brands: ['Omeprazole', 'Losec'] },
  { name: 'salbutamol',   rx: '435',    doses: [100], unit: 'mcg', brands: ['Salbutamol inhaler', 'Ventolin'] },
  { name: 'sertraline',   rx: '36437',  doses: [50, 100], unit: 'mg', brands: ['Sertraline', 'Zoloft'] },
  { name: 'ibuprofen',    rx: '5640',   doses: [200, 400], unit: 'mg', brands: ['Ibuprofen', 'Advil'] },
  { name: 'apixaban',     rx: '1364430',doses: [2.5, 5], unit: 'mg', brands: ['Apixaban', 'Eliquis'] },
];
const FREQ = ['once daily', 'twice daily', 'three times daily', 'at night', 'as needed'];
const ALLERGIES = [
  { substance: 'penicillin', display: 'Penicillin', crit: 'high', reaction: 'Anaphylaxis' },
  { substance: 'peanut',     display: 'Peanut', crit: 'low', reaction: 'Urticaria' },
  { substance: 'sulfonamide',display: 'Sulfonamide antibiotics', crit: 'high', reaction: 'Rash, fever' },
  { substance: 'latex',      display: 'Latex', crit: 'low', reaction: 'Contact dermatitis' },
  { substance: 'shellfish',  display: 'Shellfish', crit: 'high', reaction: 'Angioedema' },
  { substance: 'codeine',    display: 'Codeine', crit: 'low', reaction: 'Nausea' },
];
const CONDITIONS = [
  { name: 'type 2 diabetes mellitus', display: 'Type 2 diabetes mellitus', icd: 'E11.9' },
  { name: 'essential hypertension',   display: 'Essential hypertension', icd: 'I10' },
  { name: 'asthma',                   display: 'Asthma, mild intermittent', icd: 'J45.20' },
  { name: 'hypothyroidism',           display: 'Hypothyroidism', icd: 'E03.9' },
  { name: 'gastro-oesophageal reflux',display: 'Gastro-oesophageal reflux disease', icd: 'K21.9' },
  { name: 'hyperlipidaemia',          display: 'Hyperlipidaemia', icd: 'E78.5' },
  { name: 'atrial fibrillation',      display: 'Atrial fibrillation', icd: 'I48.91' },
];
// Labs carry provider-native units; UK uses mmol, US uses mg/dL.
const LABS = [
  { loinc: '4548-4', name: 'HbA1c', gb: ['mmol/mol', 38, 60], us: ['%', 5.5, 7.8] },
  { loinc: '2345-7', name: 'Glucose', gb: ['mmol/L', 4.5, 9.5], us: ['mg/dL', 80, 170] },
  { loinc: '2093-3', name: 'Total cholesterol', gb: ['mmol/L', 3.8, 6.5], us: ['mg/dL', 150, 250] },
  { loinc: '2160-0', name: 'Creatinine', gb: ['µmol/L', 60, 110], us: ['mg/dL', 0.7, 1.3] },
  { loinc: '718-7',  name: 'Haemoglobin', gb: ['g/L', 125, 165], us: ['g/dL', 12.5, 16.5] },
  { loinc: '3016-3', name: 'TSH', gb: ['mIU/L', 0.5, 4.5], us: ['mIU/L', 0.5, 4.5] },
];
const IMMS = [
  { cvx: '208', name: 'COVID-19 mRNA' }, { cvx: '150', name: 'Influenza, seasonal' },
  { cvx: '115', name: 'Tdap' }, { cvx: '33', name: 'Pneumococcal' }, { cvx: '03', name: 'MMR' },
];
const GIVEN = ['Amara','Ben','Chloe','Daniel','Elena','Farah','Gabriel','Hana','Isaac','Jun','Kofi','Leila','Mateo','Nadia','Oscar','Priya','Quinn','Rosa','Samir','Tara','Umar','Vera','Wes','Ximena','Yusuf','Zara'];
const FAMILY = ['Okafor','Lindqvist','Moreau','Tanaka','Petrov','Haddad','Silva','Nakamura','Osei','Fischer','Kowalski','Reyes','Mensah','Dubois','Ivanova','Chen','Larsen','Abebe','Romano','Patel'];

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------
const out = [];
const emit = (l) => out.push(l);
emit('-- Generated by supabase/seed/generate.mjs. Do not edit by hand; edit the generator.');
emit('-- Fictional data only.');
emit('begin;');
emit(`insert into providers (id, name, short_name, country, city, npi, ods_code, fhir_base_url, ehr_vendor) values`);
emit(providers.map(p => `  (${[p.id,p.name,p.short_name,p.country,p.city,p.npi,p.ods_code,p.fhir_base_url,p.ehr_vendor].map(q).join(', ')})`).join(',\n') + '\n  on conflict (id) do nothing;');

const rows = { patients: [], patient_providers: [], medications: [], allergies: [], conditions: [], observations: [], immunizations: [] };

function medRow(pid, prov, m, dose, extra = {}) {
  const started = extra.started_on ?? randDate(2019, 2025);
  const recorded = extra.recorded_at ?? randTs(2024, 2026);
  const brand = prov.country === 'GB' ? m.brands[0] : pick(m.brands);
  const freq = extra.frequency ?? pick(FREQ);
  const id = uuid(`med:${pid}:${prov.id}:${m.name}:${extra.suffix ?? ''}`);
  return {
    id, patient_id: pid, provider_id: prov.id, source_id: `MedicationStatement/${id.slice(0, 8)}`,
    rxnorm_code: m.rx, name: m.name, display_name: brand,
    dose_value: dose, dose_unit: m.unit, dose_text: `${dose} ${m.unit} ${freq}`, frequency: freq,
    route: m.name === 'salbutamol' ? 'inhalation' : 'oral',
    status: extra.status ?? 'active', started_on: started, ended_on: extra.ended_on ?? null, recorded_at: recorded,
    fhir: { resourceType: 'MedicationStatement', status: extra.status ?? 'active',
            medicationCodeableConcept: { coding: [{ system: 'http://www.nlm.nih.gov/research/umls/rxnorm', code: m.rx }], text: brand },
            dosage: [{ text: `${dose} ${m.unit} ${freq}` }], effectivePeriod: { start: started } },
  };
}
function allergyRow(pid, prov, a, extra = {}) {
  const id = uuid(`al:${pid}:${prov.id}:${a.substance}`);
  const recorded = extra.recorded_at ?? randTs(2005, 2024);
  return { id, patient_id: pid, provider_id: prov.id, source_id: `AllergyIntolerance/${id.slice(0, 8)}`,
    substance: a.substance, display_name: a.display, criticality: a.crit, reaction: a.reaction,
    verification: extra.verification ?? 'confirmed', recorded_at: recorded,
    fhir: { resourceType: 'AllergyIntolerance', criticality: a.crit, code: { text: a.display }, recordedDate: recorded.slice(0, 10),
            reaction: [{ manifestation: [{ text: a.reaction }] }] } };
}
function conditionRow(pid, prov, c, extra = {}) {
  const id = uuid(`cd:${pid}:${prov.id}:${c.name}`);
  const onset = extra.onset_on ?? randDate(2010, 2024);
  const status = extra.clinical_status ?? 'active';
  return { id, patient_id: pid, provider_id: prov.id, source_id: `Condition/${id.slice(0, 8)}`,
    icd10_code: c.icd, name: c.name, display_name: c.display, clinical_status: status,
    onset_on: onset, abated_on: extra.abated_on ?? null, recorded_at: extra.recorded_at ?? randTs(2023, 2026),
    fhir: { resourceType: 'Condition', clinicalStatus: { coding: [{ code: status }] },
            code: { coding: [{ system: 'http://hl7.org/fhir/sid/icd-10', code: c.icd }], text: c.display }, onsetDateTime: onset } };
}
function labRow(pid, prov, l, i, extra = {}) {
  const [unit, lo, hi] = prov.country === 'GB' ? l.gb : l.us;
  const v = extra.value ?? Math.round((lo + rand() * (hi - lo)) * 10) / 10;
  const observed = extra.observed_at ?? randTs(2023, 2026);
  const id = uuid(`ob:${pid}:${prov.id}:${l.loinc}:${i}`);
  return { id, patient_id: pid, provider_id: prov.id, source_id: `Observation/${id.slice(0, 8)}`,
    loinc_code: l.loinc, name: l.name, value: v, unit, reference_low: lo, reference_high: hi,
    observed_at: observed, recorded_at: observed,
    fhir: { resourceType: 'Observation', status: 'final', category: [{ coding: [{ code: 'laboratory' }] }],
            code: { coding: [{ system: 'http://loinc.org', code: l.loinc }], text: l.name },
            valueQuantity: { value: v, unit }, effectiveDateTime: observed } };
}
function immRow(pid, prov, im, i) {
  const occurred = randDate(2015, 2025);
  const id = uuid(`im:${pid}:${prov.id}:${im.cvx}:${i}`);
  return { id, patient_id: pid, provider_id: prov.id, source_id: `Immunization/${id.slice(0, 8)}`,
    cvx_code: im.cvx, name: im.name, occurred_on: occurred, recorded_at: `${occurred}T10:00:00Z`,
    fhir: { resourceType: 'Immunization', status: 'completed', vaccineCode: { coding: [{ system: 'http://hl7.org/fhir/sid/cvx', code: im.cvx }], text: im.name }, occurrenceDateTime: occurred } };
}

// ---------------------------------------------------------------------------
// Demo patient: Noah Dixon, London, connected to all three providers.
// ---------------------------------------------------------------------------
const NOAH = uuid('patient:noah-dixon');
rows.patients.push({ id: NOAH, auth_user_id: null, given_name: 'Noah', family_name: 'Dixon', birth_date: '1991-03-14', sex: 'male',
  nhs_number: '943 476 5919', mrn: 'HP-4471930', home_country: 'GB', is_demo: true });
for (const prov of providers) rows.patient_providers.push({ patient_id: NOAH, provider_id: prov.id, external_id: `${prov.short_name.slice(0,2).toUpperCase()}-${int(100000, 999999)}`, last_synced: '2026-11-04T15:40:00Z' });

const lisinopril = MEDS[0], metformin = MEDS[1], atorva = MEDS[2], salbutamol = MEDS[6], omep = MEDS[5], ibu = MEDS[8];
// Fault #1 · dose conflict: Thameside says 10 mg, Harbor Point says 20 mg (titrated in Boston, never fed back).
rows.medications.push(medRow(NOAH, P.thameside, lisinopril, 10, { started_on: '2022-02-14', recorded_at: '2025-09-02T09:15:00Z', frequency: 'once daily' }));
rows.medications.push(medRow(NOAH, P.harbor,    lisinopril, 20, { started_on: '2025-10-21', recorded_at: '2025-10-21T14:30:00Z', frequency: 'once daily' }));
// Agreeing records (so the scan is not all red)
rows.medications.push(medRow(NOAH, P.thameside, metformin, 500, { started_on: '2023-01-10', recorded_at: '2025-09-02T09:15:00Z', frequency: 'twice daily' }));
rows.medications.push(medRow(NOAH, P.harbor,    metformin, 500, { started_on: '2023-01-10', recorded_at: '2025-10-21T14:30:00Z', frequency: 'twice daily' }));
rows.medications.push(medRow(NOAH, P.thameside, atorva, 20, { started_on: '2023-06-01', recorded_at: '2025-09-02T09:15:00Z', frequency: 'at night' }));
rows.medications.push(medRow(NOAH, P.thameside, salbutamol, 100, { started_on: '2001-05-30', recorded_at: '2025-09-02T09:15:00Z', frequency: 'as needed' }));
// Fault #3 · stale: omeprazole still "active" at Lakeside, last touched April 2019, no end date.
rows.medications.push(medRow(NOAH, P.lakeside, omep, 20, { started_on: '2019-04-02', recorded_at: '2019-04-02T11:05:00Z', frequency: 'once daily' }));
// Fault #6 · duplicate: ibuprofen entered twice at Lakeside.
rows.medications.push(medRow(NOAH, P.lakeside, ibu, 400, { started_on: '2025-11-01', recorded_at: '2025-11-01T16:00:00Z', frequency: 'as needed', suffix: 'a' }));
rows.medications.push(medRow(NOAH, P.lakeside, ibu, 400, { started_on: '2025-11-01', recorded_at: '2025-11-01T16:02:00Z', frequency: 'as needed', suffix: 'b' }));

// Fault #2 · missing allergy: penicillin (anaphylaxis) is on file at Thameside and Harbor Point, absent at Lakeside.
rows.allergies.push(allergyRow(NOAH, P.thameside, ALLERGIES[0], { recorded_at: '2009-06-21T10:00:00Z' }));
rows.allergies.push(allergyRow(NOAH, P.harbor,    ALLERGIES[0], { recorded_at: '2025-10-21T14:30:00Z' }));
rows.allergies.push(allergyRow(NOAH, P.thameside, ALLERGIES[1], { recorded_at: '1994-02-03T10:00:00Z' }));
rows.allergies.push(allergyRow(NOAH, P.harbor,    ALLERGIES[1], { recorded_at: '2025-10-21T14:30:00Z' }));
rows.allergies.push(allergyRow(NOAH, P.lakeside,  ALLERGIES[1], { recorded_at: '2024-11-03T16:00:00Z' }));

// Conditions · Fault #5: asthma active at Thameside, "resolved" at Lakeside.
rows.conditions.push(conditionRow(NOAH, P.thameside, CONDITIONS[0], { onset_on: '2023-01-10', recorded_at: '2025-09-02T09:15:00Z' }));
rows.conditions.push(conditionRow(NOAH, P.harbor,    CONDITIONS[0], { onset_on: '2023-01-10', recorded_at: '2025-10-21T14:30:00Z' }));
rows.conditions.push(conditionRow(NOAH, P.thameside, CONDITIONS[1], { onset_on: '2022-02-14', recorded_at: '2025-09-02T09:15:00Z' }));
rows.conditions.push(conditionRow(NOAH, P.harbor,    CONDITIONS[1], { onset_on: '2022-02-14', recorded_at: '2025-10-21T14:30:00Z' }));
rows.conditions.push(conditionRow(NOAH, P.thameside, CONDITIONS[2], { onset_on: '2001-05-30', recorded_at: '2025-09-02T09:15:00Z' }));
rows.conditions.push(conditionRow(NOAH, P.lakeside,  CONDITIONS[2], { onset_on: '2001-05-30', clinical_status: 'resolved', abated_on: '2019-04-02', recorded_at: '2019-04-02T11:05:00Z' }));

// Labs: UK units at Thameside, US units at Harbor Point (shows the conversion story).
let li = 0;
rows.observations.push(labRow(NOAH, P.thameside, LABS[0], li++, { value: 48, observed_at: '2025-08-28T08:10:00Z' }));   // HbA1c 48 mmol/mol
rows.observations.push(labRow(NOAH, P.harbor,    LABS[0], li++, { value: 6.6, observed_at: '2025-10-20T09:00:00Z' }));  // HbA1c 6.6 %
rows.observations.push(labRow(NOAH, P.thameside, LABS[1], li++, { value: 6.1, observed_at: '2025-08-28T08:10:00Z' }));
rows.observations.push(labRow(NOAH, P.harbor,    LABS[1], li++, { value: 112, observed_at: '2025-10-20T09:00:00Z' }));
rows.observations.push(labRow(NOAH, P.thameside, LABS[2], li++, { value: 4.9, observed_at: '2025-08-28T08:10:00Z' }));
rows.observations.push(labRow(NOAH, P.harbor,    LABS[2], li++, { value: 188, observed_at: '2025-10-20T09:00:00Z' }));
rows.observations.push(labRow(NOAH, P.thameside, LABS[3], li++, { value: 84, observed_at: '2025-08-28T08:10:00Z' }));
rows.observations.push(labRow(NOAH, P.thameside, LABS[4], li++, { value: 148, observed_at: '2025-08-28T08:10:00Z' }));
rows.observations.push(labRow(NOAH, P.harbor,    LABS[4], li++, { value: 14.9, observed_at: '2025-10-20T09:00:00Z' }));
rows.immunizations.push(immRow(NOAH, P.thameside, IMMS[0], 0));
rows.immunizations.push(immRow(NOAH, P.thameside, IMMS[1], 1));
rows.immunizations.push(immRow(NOAH, P.harbor,    IMMS[2], 2));

// ---------------------------------------------------------------------------
// Background population: ~300 synthetic patients so every table is large
// enough for Sodabase to watch and for the scan to run at realistic scale.
// A small share of them carry the same kinds of faults as Noah, so the
// "built to scale" story holds: the rules find problems across the cohort.
// ---------------------------------------------------------------------------
const N = 300;
for (let i = 0; i < N; i++) {
  const pid = uuid(`patient:${i}`);
  const home = chance(0.35) ? 'GB' : 'US';
  rows.patients.push({ id: pid, auth_user_id: null, given_name: pick(GIVEN), family_name: pick(FAMILY),
    birth_date: randDate(1940, 2005), sex: pick(['male', 'female']),
    nhs_number: home === 'GB' ? `${int(100,999)} ${int(100,999)} ${int(1000,9999)}` : null,
    mrn: home === 'US' ? `HP-${int(1000000, 9999999)}` : null, home_country: home, is_demo: false });

  // 1–3 providers
  const provs = [...providers].sort(() => rand() - 0.5).slice(0, int(1, 3));
  for (const prov of provs) rows.patient_providers.push({ patient_id: pid, provider_id: prov.id, external_id: `${prov.short_name.slice(0,2).toUpperCase()}-${int(100000, 999999)}`, last_synced: randTs(2026, 2026) });

  const meds = [...MEDS].sort(() => rand() - 0.5).slice(0, int(1, 4));
  const seen = new Set();
  for (const m of meds) {
    const dose = pick(m.doses);
    for (const prov of provs) {
      if (chance(0.3)) continue;
      // ~8% of shared meds disagree on dose across providers
      const d = seen.has(m.name) && chance(0.08) ? pick(m.doses.filter(x => x !== dose)) ?? dose : dose;
      seen.add(m.name);
      const stale = chance(0.06);
      rows.medications.push(medRow(pid, prov, m, d, stale ? { recorded_at: randTs(2018, 2023) } : {}));
    }
  }
  const alls = [...ALLERGIES].sort(() => rand() - 0.5).slice(0, int(0, 2));
  for (const a of alls) for (const prov of provs) if (!chance(0.25)) rows.allergies.push(allergyRow(pid, prov, a));
  const conds = [...CONDITIONS].sort(() => rand() - 0.5).slice(0, int(0, 3));
  for (const c of conds) for (const prov of provs) if (!chance(0.3)) rows.conditions.push(conditionRow(pid, prov, c, chance(0.05) ? { clinical_status: 'resolved' } : {}));
  let k = 0;
  for (const prov of provs) for (const l of [...LABS].sort(() => rand() - 0.5).slice(0, int(1, 4))) rows.observations.push(labRow(pid, prov, l, k++));
  for (const prov of provs) for (const im of [...IMMS].sort(() => rand() - 0.5).slice(0, int(0, 2))) rows.immunizations.push(immRow(pid, prov, im, k++));
}

// ---------------------------------------------------------------------------
// Emit inserts in chunks
// ---------------------------------------------------------------------------
// Sodabase's freshness check reads created_at and reconstructs ~2 weeks of history
// from the column's own values, so rows are spread over the last 14 days (denser
// recently) instead of all landing on one timestamp like a bulk dump.
const BASE = Date.parse('2026-11-04T20:00:00Z');
const spread = () => new Date(BASE - Math.pow(rand(), 1.6) * 14 * 864e5).toISOString();
const TS_COL = { patients: 'created_at', patient_providers: 'connected_at', medications: 'created_at', allergies: 'created_at',
                 conditions: 'created_at', observations: 'created_at', immunizations: 'created_at' };
function emitTable(table, list, conflict) {
  if (!list.length) return;
  if (TS_COL[table]) for (const r of list) { r[TS_COL[table]] = spread(); if (['medications','allergies','conditions'].includes(table)) r.updated_at = r.created_at; }
  const cols = Object.keys(list[0]);
  for (let i = 0; i < list.length; i += 200) {
    const chunk = list.slice(i, i + 200);
    emit(`insert into ${table} (${cols.join(', ')}) values`);
    emit(chunk.map(r => `  (${cols.map(c => q(r[c])).join(', ')})`).join(',\n') + `\n  on conflict ${conflict} do nothing;`);
  }
}
emitTable('patients', rows.patients, '(id)');
emitTable('patient_providers', rows.patient_providers, '(patient_id, provider_id)');
emitTable('medications', rows.medications, '(provider_id, source_id)');
emitTable('allergies', rows.allergies, '(provider_id, source_id)');
emitTable('conditions', rows.conditions, '(provider_id, source_id)');
emitTable('observations', rows.observations, '(provider_id, source_id)');
emitTable('immunizations', rows.immunizations, '(provider_id, source_id)');
emit('commit;');
emit(`-- rows: ${Object.entries(rows).map(([k, v]) => `${k}=${v.length}`).join(', ')}`);
process.stdout.write(out.join('\n') + '\n');
