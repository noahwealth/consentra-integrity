import { toUS } from '../units.js';

export const CATEGORIES = ['medications', 'allergies', 'conditions', 'labs', 'immunizations'];

export const CATEGORY_TITLES = {
  medications: 'Medications',
  allergies: 'Allergies',
  conditions: 'Conditions',
  labs: 'Lab results',
  immunizations: 'Immunizations',
};

const item = (r, fields) => ({
  id: r.id, title: '', detail: '', date: null,
  value: null, unit: null, usValue: null, usUnit: null, ...fields,
});

/** Flattens one FHIR resource into the display shape both the app and the clinician page use. */
export function toDisplayItem(category, r) {
  switch (category) {
    case 'medications':
      return item(r, { title: r.medicationCodeableConcept.text, detail: r.dosage?.[0]?.text ?? '', date: r.effectivePeriod?.start ?? null });
    case 'allergies': {
      const rx = r.reaction?.[0];
      return item(r, { title: r.code.text, detail: [rx?.manifestation?.[0]?.text, rx?.severity && `${rx.severity}`].filter(Boolean).join(' · '), date: r.recordedDate ?? null });
    }
    case 'conditions':
      return item(r, { title: r.code.text, detail: r.clinicalStatus?.text ?? '', date: r.onsetDateTime ?? null });
    case 'labs': {
      const q = r.valueQuantity;
      const loinc = r.code.coding?.[0]?.code;
      const us = toUS(loinc, q.value, q.unit);
      return item(r, {
        title: r.code.text, detail: r.referenceRange?.[0]?.text ? `Ref: ${r.referenceRange[0].text}` : '',
        date: r.effectiveDateTime ?? null, value: q.value, unit: q.unit,
        usValue: us?.value ?? null, usUnit: us?.unit ?? null,
      });
    }
    case 'immunizations':
      return item(r, { title: r.vaccineCode.text, detail: r.note?.[0]?.text ?? '', date: r.occurrenceDateTime ?? null });
    default:
      throw new Error(`unknown category ${category}`);
  }
}
