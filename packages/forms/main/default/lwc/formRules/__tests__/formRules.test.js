import {
  checkAll,
  checkAnswer,
  checkStep,
  countedAnswers,
  evaluate,
  isBlank,
  nextStep,
  previousStep,
  visibility,
  visibleSteps
} from 'c/formRules';
import vectors from './data/formVectors.json';

const codes = (problems) =>
  Object.fromEntries(Object.entries(problems).map(([key, found]) => [key, found.code]));

describe('c/formRules shared vectors', () => {
  it('are the same cases FormRulesTest holds the Apex rules to', () => {
    const fs = require('fs');
    const apex = fs.readFileSync('packages/forms/main/default/classes/FormRulesTest.cls', 'utf8');
    const block = apex.split('// vectors:start')[1].split('// vectors:end')[0];
    const text = [...block.matchAll(/'([^']*)'/g)].map((piece) => piece[1]).join('');
    const { about, ...shared } = vectors;
    expect(about).toBeTruthy();
    expect(JSON.parse(text)).toEqual(shared);
  });

  it.each(vectors.cases)('$name', (testCase) => {
    const { definition } = vectors;
    expect(visibleSteps(definition, testCase.answers)).toEqual(testCase.visibleSteps);
    expect(countedAnswers(definition, testCase.answers)).toEqual(testCase.counted);
    expect(codes(checkAll(definition, testCase.answers))).toEqual(testCase.problems);
  });
});

describe('c/formRules conditions', () => {
  it('holds with no condition and reads nested groups', () => {
    expect(evaluate(null, {})).toBe(true);
    const condition = {
      any: [
        { field: 'a', op: 'isBlank' },
        {
          all: [
            { field: 'b', op: 'contains', value: 'OO' },
            { field: 'c', op: 'notEquals', value: 'x' }
          ]
        }
      ]
    };
    expect(evaluate(condition, { a: 'set', b: 'food', c: 'y' })).toBe(true);
    expect(evaluate(condition, { a: 'set', b: 'food', c: 'X' })).toBe(false);
    expect(evaluate(condition, {})).toBe(true);
  });

  it('compares numbers and dates, and nothing else, by order', () => {
    expect(evaluate({ field: 'n', op: 'greaterThan', value: '9' }, { n: 10 })).toBe(true);
    expect(evaluate({ field: 'd', op: 'lessThan', value: '2026-01-02' }, { d: '2026-01-01' })).toBe(
      true
    );
    expect(evaluate({ field: 't', op: 'greaterThan', value: 'a' }, { t: 'b' })).toBe(false);
    expect(evaluate({ field: 't', op: 'unknown' }, { t: 'b' })).toBe(false);
  });

  it('reads a checkbox as true or false, never blank', () => {
    expect(evaluate({ field: 'c', op: 'equals', value: true }, { c: true })).toBe(true);
    expect(evaluate({ field: 'c', op: 'equals', value: 'TRUE' }, { c: true })).toBe(true);
    expect(isBlank(false)).toBe(false);
    expect(isBlank('  ')).toBe(true);
  });

  it('hides a question whose condition names a hidden one', () => {
    const shown = visibility(vectors.definition, { role: 'Donor', shirt: 'M' });
    expect(shown.shirt).toBe(false);
    expect(shown.why).toBe(false);
  });
});

describe('c/formRules steps and answers', () => {
  const { definition } = vectors;

  it('moves past a hidden step both ways', () => {
    expect(nextStep(definition, 0, { age: 40 })).toBe(2);
    expect(nextStep(definition, 0, { age: 12 })).toBe(1);
    expect(nextStep(definition, 2, {})).toBe(-1);
    expect(previousStep(definition, 2, { age: 40 })).toBe(0);
    expect(previousStep(definition, 0, {})).toBe(-1);
  });

  it('checks only the step asked about', () => {
    expect(codes(checkStep(definition, 2, { phone: '+1 (555) 123-4567' }))).toEqual({});
    expect(codes(checkStep(definition, 0, {}))).toEqual({
      firstName: 'required',
      lastName: 'required',
      email: 'required'
    });
    expect(checkStep(definition, 9, {})).toEqual({});
  });

  it('gives the limit with the problem', () => {
    expect(checkAnswer({ type: 'number', min: 5 }, '4')).toEqual({ code: 'belowMin', args: [5] });
    expect(checkAnswer({ type: 'text' }, 'x'.repeat(256))).toEqual({
      code: 'tooLong',
      args: [255]
    });
    expect(checkAnswer({ type: 'checkbox', required: true }, 'true')).toBeNull();
    expect(checkAnswer({ type: 'date' }, '2026-11-06')).toBeNull();
  });
});
