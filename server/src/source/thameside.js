// Fictional source: "Thameside General Hospital", London. FHIR R4-shaped. All data invented.
// See decision.md D3.

export const SOURCE = {
  id: 'thameside',
  name: 'Thameside General Hospital',
  city: 'London',
  country: 'United Kingdom',
  flag: '🇬🇧',
};

export const patient = {
  resourceType: 'Patient',
  id: 'tgh-pt-20417',
  identifier: [{ system: 'https://fhir.nhs.uk/Id/nhs-number', value: '999 123 4567' }],
  name: [{ use: 'official', family: 'Dixon', given: ['Noah'] }],
  gender: 'male',
  birthDate: '1988-04-12',
  address: [{ city: 'London', country: 'GB' }],
};

const subject = { reference: 'Patient/tgh-pt-20417' };
const med = (id, text, dose, start) => ({
  resourceType: 'MedicationStatement', id, status: 'active', subject,
  medicationCodeableConcept: { text }, dosage: [{ text: dose }], effectivePeriod: { start },
});
const lab = (id, loinc, text, value, unit, range, date) => ({
  resourceType: 'Observation', id, status: 'final', subject,
  category: [{ coding: [{ code: 'laboratory' }] }],
  code: { coding: [{ system: 'http://loinc.org', code: loinc }], text },
  valueQuantity: { value, unit }, referenceRange: [{ text: range }], effectiveDateTime: date,
});
const imm = (id, text, note, date) => ({
  resourceType: 'Immunization', id, status: 'completed', patient: subject,
  vaccineCode: { text }, note: [{ text: note }], occurrenceDateTime: date,
});

export const resources = {
  medications: [
    med('ms-1', 'Ramipril 5 mg capsules', 'One capsule once daily', '2022-03-02'),
    med('ms-2', 'Metformin 500 mg tablets', 'One tablet twice daily with meals', '2023-01-18'),
    med('ms-3', 'Atorvastatin 20 mg tablets', 'One tablet at night', '2023-01-18'),
    med('ms-4', 'Salbutamol 100 micrograms/dose inhaler', 'Two puffs when required for breathlessness', '2015-09-10'),
  ],
  allergies: [
    {
      resourceType: 'AllergyIntolerance', id: 'al-1', patient: subject, criticality: 'high',
      code: { text: 'Penicillin' }, recordedDate: '2009-06-21',
      reaction: [{ manifestation: [{ text: 'Anaphylaxis' }], severity: 'severe' }],
    },
    {
      resourceType: 'AllergyIntolerance', id: 'al-2', patient: subject, criticality: 'low',
      code: { text: 'Peanut' }, recordedDate: '1994-02-03',
      reaction: [{ manifestation: [{ text: 'Hives, lip swelling' }], severity: 'moderate' }],
    },
  ],
  conditions: [
    { resourceType: 'Condition', id: 'cd-1', subject, clinicalStatus: { text: 'Active' }, code: { text: 'Type 2 diabetes mellitus' }, onsetDateTime: '2023-01-10' },
    { resourceType: 'Condition', id: 'cd-2', subject, clinicalStatus: { text: 'Active' }, code: { text: 'Essential hypertension' }, onsetDateTime: '2022-02-14' },
    { resourceType: 'Condition', id: 'cd-3', subject, clinicalStatus: { text: 'Active' }, code: { text: 'Asthma, mild intermittent' }, onsetDateTime: '2001-05-30' },
  ],
  labs: [
    lab('ob-1', '59261-8', 'HbA1c', 48, 'mmol/mol', '20–41 mmol/mol', '2026-09-22'),
    lab('ob-2', '15074-8', 'Fasting glucose', 7.2, 'mmol/L', '3.9–5.5 mmol/L', '2026-09-22'),
    lab('ob-3', '14647-2', 'Total cholesterol', 5.1, 'mmol/L', '< 5.0 mmol/L', '2026-09-22'),
    lab('ob-4', '14682-9', 'Creatinine', 88, 'µmol/L', '59–104 µmol/L', '2026-09-22'),
    lab('ob-5', '62238-1', 'eGFR', 82, 'mL/min/1.73m²', '> 60 mL/min/1.73m²', '2026-09-22'),
  ],
  immunizations: [
    imm('im-1', 'COVID-19 mRNA (Comirnaty)', 'Autumn booster', '2025-10-14'),
    imm('im-2', 'Influenza (inactivated)', 'Seasonal', '2025-10-14'),
    imm('im-3', 'Tetanus, diphtheria, polio (Revaxis)', 'Booster', '2019-07-02'),
    imm('im-4', 'Hepatitis B', 'Course complete (3 doses)', '2008-11-20'),
  ],
};
