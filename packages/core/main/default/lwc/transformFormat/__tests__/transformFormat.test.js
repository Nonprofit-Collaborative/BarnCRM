import fs from 'fs';
import path from 'path';
import {
  formatDigits,
  countPlaces,
  isValidDigitsStep,
  PHONE_PRESET_STEPS
} from 'c/transformFormat';

// The fixture the Apex tests read too (DataTransformDigitsTest).
// eslint-disable-next-line no-undef
const HERE = __dirname;
const FIXTURE = JSON.parse(
  fs.readFileSync(path.join(HERE, '../../../staticresources/TransformFormatFixture.json'), 'utf8')
);

describe('c-transform-format against the shared fixture', () => {
  it('has cases', () => {
    expect(FIXTURE.cases.length).toBeGreaterThan(20);
  });

  FIXTURE.cases.forEach((fixtureCase) => {
    it(`${fixtureCase.name}`, () => {
      expect(formatDigits(fixtureCase.input, fixtureCase.pattern, fixtureCase.country)).toBe(
        fixtureCase.expected
      );
    });
  });
});

describe('c-transform-format helpers', () => {
  it('counts digit places', () => {
    expect(countPlaces('(###) ###-####')).toBe(10);
    expect(countPlaces('')).toBe(0);
    expect(countPlaces(undefined)).toBe(0);
  });

  it('checks a step', () => {
    expect(isValidDigitsStep('(###) ###-####', '1')).toBe(true);
    expect(isValidDigitsStep('(###) ###-####', '')).toBe(true);
    expect(isValidDigitsStep('', '1')).toBe(false);
    expect(isValidDigitsStep('no places', '')).toBe(false);
    expect(isValidDigitsStep('################', '')).toBe(false);
    expect(isValidDigitsStep('###', 'abc')).toBe(false);
    expect(isValidDigitsStep('###', '1234')).toBe(false);
    expect(isValidDigitsStep('#'.repeat(5) + 'x'.repeat(30), '')).toBe(false);
  });

  it('keeps the phone preset valid', () => {
    expect(PHONE_PRESET_STEPS).toHaveLength(1);
    const [step] = PHONE_PRESET_STEPS;
    expect(isValidDigitsStep(step.pattern, step.country)).toBe(true);
    expect(formatDigits('555.123.4567', step.pattern, step.country)).toBe('(555) 123-4567');
  });
});
