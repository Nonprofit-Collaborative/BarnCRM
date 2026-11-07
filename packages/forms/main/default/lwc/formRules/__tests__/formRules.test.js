import {
  FILE_ACCEPT,
  MAX_FILE_BYTES,
  checkAll,
  checkAnswer,
  checkFileSizes,
  readFiles,
  checkStep,
  countedAnswers,
  evaluate,
  isBlank,
  nextStep,
  previousStep,
  questionViews,
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

  it('takes documents and pictures for a file question, within the size together', () => {
    expect(checkAnswer({ type: 'file' }, 'Resume.PDF')).toBeNull();
    expect(checkAnswer({ type: 'file' }, 'page.html')).toEqual({ code: 'badFileType', args: [] });
    expect(checkAnswer({ type: 'file' }, 'pdf')).toEqual({ code: 'badFileType', args: [] });
    expect(checkAnswer({ type: 'file', required: true }, '')).toEqual({
      code: 'required',
      args: []
    });
    expect(checkFileSizes({ a: { size: MAX_FILE_BYTES } })).toEqual({});
    expect(checkFileSizes({ a: { size: MAX_FILE_BYTES }, b: { size: 1 } })).toEqual({
      b: { code: 'fileTooLarge', args: [1024] }
    });
    expect(FILE_ACCEPT).toContain('.pdf');
  });

  it('reads a file as base64 for the server', async () => {
    const read = await readFiles({ cv: new File(['hello'], 'cv.txt') });
    expect(read).toEqual({ cv: { name: 'cv.txt', data: btoa('hello') } });
  });

  it('draws the shown questions of a step with their answers and problems', () => {
    const oneStep = {
      steps: [
        {
          key: 'you',
          fields: [
            { key: 'age', label: 'Age', type: 'number' },
            {
              key: 'guardian',
              label: 'Guardian',
              type: 'text',
              showWhen: { all: [{ field: 'age', op: 'lessThan', value: 18 }] }
            },
            { key: 'kind', label: 'Kind', type: 'picklist', options: [{ value: 1 }] },
            { key: 'ok', label: 'OK', type: 'checkbox' }
          ]
        }
      ]
    };
    const problem = { code: 'required', args: [] };
    const views = questionViews(oneStep, 0, { age: 40, ok: true }, { kind: problem });
    expect(views.map((view) => view.key)).toEqual(['age', 'kind', 'ok']);
    expect(views[0]).toMatchObject({
      isInput: true,
      inputType: 'number',
      value: 40,
      problem: null
    });
    expect(views[1]).toMatchObject({ isPicklist: true, problem, value: '' });
    expect(views[1].options).toEqual([{ value: '1', label: '1' }]);
    expect(views[2]).toMatchObject({ isCheckbox: true, checked: true });
    const young = questionViews(oneStep, 0, { age: 10 }, null);
    expect(young.map((view) => view.key)).toContain('guardian');
  });
});
