import { checkDefinition, emptyDefinition } from 'c/formDefinition';
import {
  addField,
  addRecord,
  addStep,
  conditionFrom,
  conditionParts,
  earlierFields,
  moveField,
  moveStep,
  optionsFromText,
  optionsToText,
  recordObject,
  removeField,
  removeRecord,
  removeStep,
  setCondition,
  setLink,
  uniqueKey,
  updateField,
  updateRecord,
  updateStep
} from 'c/formBuilderModel';

function twoSteps() {
  let definition = emptyDefinition();
  definition = updateStep(definition, 0, { title: 'You' });
  definition = addField(definition, 0);
  definition = updateField(definition, 0, 0, {
    key: 'last',
    label: 'Last Name',
    required: true,
    target: { record: 'person', field: 'LastName' }
  });
  definition = addField(definition, 0, 'email');
  definition = updateField(definition, 0, 1, {
    key: 'email',
    label: 'Email',
    target: { record: 'person', field: 'Email' }
  });
  definition = addStep(definition);
  definition = updateStep(definition, 1, { title: 'More' });
  definition = addField(definition, 1, 'textarea');
  definition = updateField(definition, 1, 0, { key: 'why', label: 'Why' });
  return definition;
}

describe('c/formBuilderModel', () => {
  it('builds a definition the checks accept, never changing the one given', () => {
    const start = emptyDefinition();
    const built = twoSteps();

    expect(start.steps[0].fields).toHaveLength(0);
    expect(built.steps.map((step) => step.key)).toEqual(['step1', 'step2']);
    expect(checkDefinition(built)).toEqual([]);
  });

  it('picks the first free key', () => {
    expect(uniqueKey(['question1', 'question3'], 'question')).toBe('question2');
  });

  it('moves steps and questions within bounds', () => {
    const built = twoSteps();

    expect(moveStep(built, 0, 1).steps[0].title).toBe('More');
    expect(moveStep(built, 0, -1).steps[0].title).toBe('You');
    expect(moveField(built, 0, 1, -1).steps[0].fields[0].key).toBe('email');
  });

  it('follows a renamed question into conditions and drops a removed one from them', () => {
    let built = twoSteps();
    built = setCondition(built, 1, null, {
      all: [{ field: 'email', op: 'isNotBlank' }]
    });

    const renamed = updateField(built, 0, 1, { key: 'mail' });
    expect(renamed.steps[1].showWhen).toEqual({ all: [{ field: 'mail', op: 'isNotBlank' }] });

    const removed = removeField(built, 0, 1);
    expect(removed.steps[1].showWhen).toBeUndefined();
    expect(removeStep(built, 0).steps[0].showWhen).toBeUndefined();
  });

  it('keeps choices only on a picklist', () => {
    let built = twoSteps();
    built = updateField(built, 1, 0, { type: 'picklist', options: optionsFromText('A\n\n B ') });
    expect(built.steps[1].fields[0].options).toEqual([
      { label: 'A', value: 'A' },
      { label: 'B', value: 'B' }
    ]);
    expect(optionsToText(built.steps[1].fields[0].options)).toBe('A\nB');

    built = updateField(built, 1, 0, { type: 'text' });
    expect(built.steps[1].fields[0].options).toBeUndefined();
  });

  it('adds and removes records, with their targets and links', () => {
    let built = twoSteps();
    built = addRecord(built, 'organization');
    built = addRecord(built, 'related');
    built = updateRecord(built, 2, { object: 'Affiliation__c' });
    built = setLink(built, 2, 'Contact__c', 'person');
    built = setLink(built, 2, 'Organization__c', 'organization1');
    built = updateField(built, 1, 0, { target: { record: 'organization1', field: 'Name' } });

    expect(built.records[1].matching).toEqual({ rule: 'name', onMatch: 'fillBlanks' });
    expect(recordObject(built.records[1])).toBe('Account');
    expect(recordObject(built.records[2])).toBe('Affiliation__c');

    const without = removeRecord(built, 1);
    expect(without.records[1].links).toEqual({ Contact__c: 'person' });
    expect(without.steps[1].fields[0].target).toBeUndefined();
    expect(setLink(built, 2, 'Contact__c', '').records[2].links).toEqual({
      Organization__c: 'organization1'
    });
  });

  it('edits a condition as a mode and flat clauses, keeping a nested group', () => {
    const nested = { any: [{ all: [{ field: 'a', op: 'isBlank' }] }] };
    const condition = {
      any: [{ field: 'email', op: 'equals', value: 'x' }, nested.any[0]]
    };

    const parts = conditionParts(condition);
    expect(parts.mode).toBe('any');
    expect(parts.clauses).toHaveLength(1);
    expect(parts.nested).toHaveLength(1);
    expect(conditionFrom(parts)).toEqual(condition);
    expect(conditionFrom({ ...parts, mode: 'always' })).toBeNull();
    expect(conditionParts(null).mode).toBe('always');
  });

  it('offers only earlier questions to a condition', () => {
    const built = twoSteps();

    expect(earlierFields(built, 1, null).map((field) => field.key)).toEqual(['last', 'email']);
    expect(earlierFields(built, 0, 1).map((field) => field.key)).toEqual(['last']);
    expect(earlierFields(built, 0, null)).toEqual([]);
  });
});
