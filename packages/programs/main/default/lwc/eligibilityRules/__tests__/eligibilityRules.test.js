import { createElement } from 'lwc';
import EligibilityRules from 'c/eligibilityRules';
import getState from '@salesforce/apex/EligibilityController.getState';
import saveRules from '@salesforce/apex/EligibilityController.saveRules';
import screen from '@salesforce/apex/EligibilityController.screen';
import {
  evaluateRules,
  format,
  moveRule,
  newRule,
  parseRules,
  serializeRules
} from '../eligibilityEngine';

jest.mock('@salesforce/apex/EligibilityController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EligibilityController.saveRules', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EligibilityController.screen', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Programs_Elig_PreviewResult',
  () => ({ default: 'Would give {0}: {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Programs_Elig_Screened',
  () => ({ default: '{0} E, {1} N, {2} R, {3} left.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Programs_Elig_Rule', () => ({ default: 'Rule {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Elig_Saved', () => ({ default: 'Saved.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Elig_Value', () => ({ default: 'Value' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Elig_ValueList', () => ({ default: 'commas' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Elig_NoRuleMatched', () => ({ default: 'None.' }), {
  virtual: true
});

const PROGRAM_ID = 'a08000000000001AAA';
const RULES = JSON.stringify({
  version: 1,
  defaultResult: 'Review',
  defaultReason: 'Needs a look',
  rules: [
    {
      id: 'r1',
      all: [{ field: 'Referral_Source__c', operator: 'equals', value: 'Self' }],
      result: 'Not Eligible',
      reason: 'Self referral is not accepted',
      basis: 'Referral'
    },
    {
      id: 'r2',
      all: [{ field: 'Referral_Source__c', operator: 'in', value: ['School', 'Another Agency'] }],
      result: 'Eligible',
      reason: 'Referred by a partner'
    }
  ]
});

function stateOf(extra) {
  return {
    rules: RULES,
    canEdit: true,
    canScreen: true,
    fields: [
      { apiName: 'Referral_Source__c', label: 'Referral Source', kind: 'string' },
      { apiName: 'Intake_Date__c', label: 'Intake Date', kind: 'date' }
    ],
    bases: ['Income', 'Referral'],
    people: [
      {
        enrollmentId: 'a09000000000001AAA',
        name: 'Ana Rivera',
        status: 'Not Screened',
        values: { Referral_Source__c: 'Self' }
      },
      {
        enrollmentId: 'a09000000000002AAA',
        name: 'Ben Okafor',
        status: 'Not Screened',
        values: { Referral_Source__c: 'School' }
      }
    ],
    moreThanShown: false,
    ...extra
  };
}

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount() {
  const element = createElement('c-eligibility-rules', { is: EligibilityRules });
  element.recordId = PROGRAM_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('eligibilityEngine (framework free)', () => {
  const rule = (conditions, result = 'Eligible') =>
    parseRules(
      JSON.stringify({
        rules: [{ id: 'r1', all: conditions, result, reason: 'Because', basis: 'Income' }]
      })
    );
  const decide = (conditions, values) => evaluateRules(rule(conditions), values, 'None.');

  it('gives nothing when there are no rules', () => {
    expect(evaluateRules(parseRules(''), {})).toBeNull();
    expect(evaluateRules(parseRules('not json'), {})).toBeNull();
    expect(evaluateRules(null, {})).toBeNull();
  });

  it('compares text without regard to case and numbers as numbers', () => {
    const self = [{ field: 'Referral_Source__c', operator: 'equals', value: 'self' }];
    expect(decide(self, { referral_source__c: ' Self ' }).status).toBe('Eligible');
    const four = [{ field: 'Household_Size__c', operator: 'equals', value: '4' }];
    expect(decide(four, { Household_Size__c: 4.0 }).status).toBe('Eligible');
    const notSelf = [{ field: 'Referral_Source__c', operator: 'notEquals', value: 'Self' }];
    expect(decide(notSelf, { Referral_Source__c: 'Self' }).status).toBe('Review');
  });

  it('handles lists, ordering, dates and blanks', () => {
    const inList = [{ field: 'S', operator: 'in', value: ['Self', 'School'] }];
    expect(decide(inList, { S: 'School' }).status).toBe('Eligible');
    const notIn = [{ field: 'S', operator: 'notIn', value: ['Self', 'School'] }];
    expect(decide(notIn, { S: 'Other' }).status).toBe('Eligible');
    const range = [
      { field: 'N', operator: 'greaterOrEqual', value: 3 },
      { field: 'N', operator: 'lessThan', value: 10 }
    ];
    expect(decide(range, { N: 9 }).status).toBe('Eligible');
    expect(decide([{ field: 'N', operator: 'lessOrEqual', value: 3 }], { N: 'many' }).status).toBe(
      'Review'
    );
    const after = [{ field: 'D', operator: 'greaterThan', value: '2026-01-01' }];
    expect(decide(after, { D: '2026-03-15' }).status).toBe('Eligible');
    expect(decide([{ field: 'D', operator: 'isBlank' }], { D: null }).status).toBe('Eligible');
    expect(decide([{ field: 'D', operator: 'isNotBlank' }], { D: '2026-03-15' }).status).toBe(
      'Eligible'
    );
  });

  it('lets the first matching rule decide, else the default', () => {
    const config = parseRules(RULES);
    const first = evaluateRules(config, { Referral_Source__c: 'Self' });
    expect(first).toEqual({
      status: 'Not Eligible',
      reason: 'Self referral is not accepted',
      basis: 'Referral',
      ruleId: 'r1'
    });
    expect(evaluateRules(config, { Referral_Source__c: 'School' }).status).toBe('Eligible');
    const none = evaluateRules(config, { Referral_Source__c: null });
    expect(none).toMatchObject({ status: 'Review', ruleId: '' });
    expect(none.reason).toBe('Needs a look');
    const plain = parseRules(RULES);
    plain.defaultReason = '';
    expect(evaluateRules(plain, {}, 'None.').reason).toBe('None.');
  });

  it('round trips the rules, editing lists as comma text', () => {
    const config = parseRules(RULES);
    expect(config.rules[1].all[0].value).toBe('School, Another Agency');
    const again = JSON.parse(serializeRules(config));
    expect(again.rules[1].all[0].value).toEqual(['School', 'Another Agency']);
    expect(again.rules[0].basis).toBe('Referral');
    expect(again.rules[1].basis).toBeUndefined();
    expect(again.defaultReason).toBe('Needs a look');
    expect(serializeRules(parseRules(''))).toBe('');
    const blank = parseRules(
      JSON.stringify({
        rules: [{ id: 'r1', all: [{ field: 'A', operator: 'isBlank' }], result: 'Review' }]
      })
    );
    expect(JSON.parse(serializeRules(blank)).rules[0].all[0]).toEqual({
      field: 'A',
      operator: 'isBlank'
    });
  });

  it('builds new rules, moves them and fills labels', () => {
    const config = parseRules(RULES);
    expect(newRule(config, 'Intake_Date__c')).toMatchObject({
      id: 'r3',
      result: 'Not Eligible',
      all: [{ field: 'Intake_Date__c', operator: 'equals', value: '' }]
    });
    expect(moveRule(config.rules, 0, 1).map((r) => r.id)).toEqual(['r2', 'r1']);
    expect(moveRule(config.rules, 0, -1)).toBe(config.rules);
    expect(format('{0} and {1}', 'a', 2)).toBe('a and 2');
  });
});

describe('c-eligibility-rules', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the rules and previews what they decide for the chosen enrollment', async () => {
    getState.mockResolvedValue(stateOf());
    const element = await mount();

    expect(findAll(element, 'rule')).toHaveLength(2);
    expect(find(element, 'preview').textContent).toBe(
      'Would give Not Eligible: Self referral is not accepted'
    );
    find(element, 'person').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a09000000000002AAA' } })
    );
    await flush();
    expect(find(element, 'preview').textContent).toBe('Would give Eligible: Referred by a partner');
    expect(find(element, 'save').disabled).toBe(true);
  });

  it('previews a rule edited and not yet saved, then saves it', async () => {
    getState.mockResolvedValue(stateOf());
    saveRules.mockResolvedValue([]);
    const element = await mount();

    const result = findAll(element, 'rule-result')[0];
    result.dispatchEvent(new CustomEvent('change', { detail: { value: 'Review' } }));
    await flush();
    expect(find(element, 'preview').textContent).toContain('Would give Review');
    expect(find(element, 'unsaved')).not.toBeNull();

    find(element, 'save').click();
    await flush();
    const sent = JSON.parse(saveRules.mock.calls[0][0].rules);
    expect(sent.rules[0].result).toBe('Review');
    expect(find(element, 'result').textContent).toBe('Saved.');
    expect(find(element, 'unsaved')).toBeNull();
  });

  it('shows the problems the server finds and keeps the changes', async () => {
    getState.mockResolvedValue(stateOf());
    saveRules.mockResolvedValue(['Rule 1: give a reason.']);
    const element = await mount();
    findAll(element, 'reason')[0].value = '';
    findAll(element, 'reason')[0].dispatchEvent(new CustomEvent('change'));
    await flush();
    find(element, 'save').click();
    await flush();
    expect(findAll(element, 'problem')).toHaveLength(1);
    expect(find(element, 'unsaved')).not.toBeNull();
  });

  it('adds and removes rules and conditions, and moves a rule', async () => {
    getState.mockResolvedValue(stateOf());
    const element = await mount();

    find(element, 'add-rule').click();
    await flush();
    expect(findAll(element, 'rule')).toHaveLength(3);

    findAll(element, 'add-condition')[2].click();
    await flush();
    expect(findAll(element, 'condition')).toHaveLength(4);
    findAll(element, 'remove-condition')[0].click();
    await flush();
    expect(findAll(element, 'condition')).toHaveLength(3);

    findAll(element, 'move-down')[0].click();
    await flush();
    expect(find(element, 'preview').textContent).toContain('Would give Not Eligible');

    findAll(element, 'remove-rule')[2].click();
    await flush();
    expect(findAll(element, 'rule')).toHaveLength(2);
  });

  it('screens one enrollment or all, only after the rules are saved', async () => {
    getState.mockResolvedValue(stateOf());
    screen.mockResolvedValue({
      eligible: 1,
      notEligible: 1,
      review: 0,
      skipped: 0,
      noRules: false
    });
    const element = await mount();

    find(element, 'screen-all').click();
    await flush();
    expect(screen).toHaveBeenCalledWith({
      programId: PROGRAM_ID,
      enrollmentId: null,
      includeDecided: false
    });
    expect(find(element, 'result').textContent).toBe('1 E, 1 N, 0 R, 0 left.');

    find(element, 'include-decided').checked = true;
    find(element, 'include-decided').dispatchEvent(new CustomEvent('change'));
    find(element, 'apply-one').click();
    await flush();
    expect(screen.mock.calls[1][0]).toEqual({
      programId: PROGRAM_ID,
      enrollmentId: 'a09000000000001AAA',
      includeDecided: true
    });

    findAll(element, 'rule-result')[0].dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Eligible' } })
    );
    await flush();
    find(element, 'screen-all').click();
    await flush();
    expect(screen).toHaveBeenCalledTimes(2);
    expect(find(element, 'error-message').textContent).toContain('Programs_Elig_SaveFirst');
  });

  it('is read only without permission, and says so when there are no rules', async () => {
    getState.mockResolvedValue(stateOf({ canEdit: false, canScreen: false }));
    const element = await mount();
    expect(find(element, 'read-only')).not.toBeNull();
    expect(find(element, 'add-rule')).toBeNull();
    expect(find(element, 'save')).toBeNull();
    expect(find(element, 'screen-all')).toBeNull();

    getState.mockResolvedValue(stateOf({ rules: null, people: [] }));
    const empty = await mount();
    expect(find(empty, 'no-rules')).not.toBeNull();
    expect(find(empty, 'no-people')).not.toBeNull();
  });

  it('shows a failure to load in its own words', async () => {
    getState.mockRejectedValue({ body: { message: 'No access.' } });
    const element = await mount();
    expect(find(element, 'error-message').textContent).toContain('No access.');
  });
});
