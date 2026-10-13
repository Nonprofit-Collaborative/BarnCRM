import {
  OPERATORS,
  VALUE_KINDS,
  isFilterableField,
  logicProblem,
  operatorsFor,
  parseDocument,
  serializeDocument,
  toDocumentValue,
  toInputValue,
  valueKindFor,
  valueProblem
} from 'c/filterDocument';

const field = (dataType, extra = {}) => ({ apiName: 'X__c', dataType, filterable: true, ...extra });

describe('c/filterDocument', () => {
  it('offers only the operators that suit a field type', () => {
    expect(operatorsFor(field('boolean'))).toEqual([OPERATORS.EQUALS]);
    expect(operatorsFor(field('picklist'))).not.toContain(OPERATORS.CONTAINS);
    expect(operatorsFor(field('string'))).toContain(OPERATORS.STARTS_WITH);
    expect(operatorsFor(field('currency'))).toContain(OPERATORS.GREATER_OR_EQUAL);
    expect(operatorsFor(field('currency'))).not.toContain(OPERATORS.THIS_YEAR);
    expect(operatorsFor(field('date'))).toContain(OPERATORS.LAST_N_DAYS);
    expect(operatorsFor(field('date'), false)).not.toContain(OPERATORS.LAST_N_DAYS);
    expect(operatorsFor(field('reference'))).toContain(OPERATORS.IN);
    expect(operatorsFor(field('base64'))).toEqual([]);
  });

  it('offers a field only when it can be filtered and its type is known', () => {
    expect(isFilterableField(field('string'))).toBe(true);
    expect(isFilterableField(field('string', { filterable: false }))).toBe(false);
    expect(isFilterableField(field('time'))).toBe(false);
  });

  it('chooses the value input from the field and operator', () => {
    expect(valueKindFor(field('picklist'), OPERATORS.IN)).toBe(VALUE_KINDS.PICK_LIST);
    expect(valueKindFor(field('string'), OPERATORS.IN)).toBe(VALUE_KINDS.LINES);
    expect(valueKindFor(field('picklist'), OPERATORS.EQUALS)).toBe(VALUE_KINDS.PICK);
    expect(valueKindFor(field('date'), OPERATORS.THIS_YEAR)).toBe(VALUE_KINDS.NONE);
    expect(valueKindFor(field('date'), OPERATORS.LAST_N_DAYS)).toBe(VALUE_KINDS.DAYS);
    expect(valueKindFor(field('datetime'), OPERATORS.EQUALS)).toBe(VALUE_KINDS.DATETIME);
    expect(valueKindFor(field('double'), OPERATORS.EQUALS)).toBe(VALUE_KINDS.NUMBER);
    expect(valueKindFor(field('boolean'), OPERATORS.EQUALS)).toBe(VALUE_KINDS.BOOLEAN);
    expect(valueKindFor(field('string'), OPERATORS.IS_NULL)).toBe(VALUE_KINDS.NONE);
  });

  it('writes values typed as R-R2 says and reads them back', () => {
    expect(toDocumentValue(VALUE_KINDS.NUMBER, '12.5')).toBe(12.5);
    expect(toDocumentValue(VALUE_KINDS.DAYS, '30')).toBe(30);
    expect(toDocumentValue(VALUE_KINDS.BOOLEAN, 'false')).toBe(false);
    expect(toDocumentValue(VALUE_KINDS.LINES, ' Grant \n\nStock ')).toEqual(['Grant', 'Stock']);
    expect(toDocumentValue(VALUE_KINDS.NONE, 'ignored')).toBeUndefined();
    expect(toInputValue(VALUE_KINDS.LINES, ['Grant', 'Stock'])).toBe('Grant\nStock');
    expect(toInputValue(VALUE_KINDS.PICK_LIST, 'Grant')).toEqual(['Grant']);
    expect(toInputValue(VALUE_KINDS.BOOLEAN, true)).toBe('true');
  });

  it('says what is wrong with a value', () => {
    expect(valueProblem(VALUE_KINDS.TEXT, ' ')).toBe('valueRequired');
    expect(valueProblem(VALUE_KINDS.NUMBER, 'abc')).toBe('number');
    expect(valueProblem(VALUE_KINDS.DAYS, '0')).toBe('days');
    expect(valueProblem(VALUE_KINDS.DAYS, '2.5')).toBe('days');
    expect(valueProblem(VALUE_KINDS.DAYS, '3651')).toBe('days');
    expect(valueProblem(VALUE_KINDS.DAYS, '30')).toBeNull();
    expect(valueProblem(VALUE_KINDS.PICK_LIST, [])).toBe('valueRequired');
    expect(valueProblem(VALUE_KINDS.NONE, '')).toBeNull();
  });

  it('accepts well formed logic and explains what is not', () => {
    expect(logicProblem('1 AND (2 OR 3)', 3)).toBeNull();
    expect(logicProblem('NOT 1 or 2', 2)).toBeNull();
    expect(logicProblem('1 AND 4', 3)).toEqual({ problem: 'unknown', condition: '4' });
    expect(logicProblem('1 AND 2', 3)).toEqual({ problem: 'missing', condition: '3' });
    expect(logicProblem('1 AND (2 OR 3', 3)).toEqual({ problem: 'syntax' });
    expect(logicProblem('1 2', 2)).toEqual({ problem: 'syntax' });
    expect(logicProblem('1 AND Name = 2', 2)).toEqual({ problem: 'syntax' });
    expect(logicProblem('1 AND', 1)).toEqual({ problem: 'syntax' });
    expect(logicProblem('', 1)).toEqual({ problem: 'syntax' });
  });

  it('reads a document and renumbers its logic to the order of its conditions', () => {
    const parsed = parseDocument(
      JSON.stringify({
        version: 1,
        logic: '7 OR 9',
        conditions: [
          { id: 7, field: 'Status__c', operator: 'Equals', value: 'Received' },
          { id: 9, field: 'Amount__c', operator: 'greater than', value: 0 }
        ]
      })
    );
    expect(parsed.logic).toBe('1 OR 2');
    expect(parsed.conditions[0]).toEqual({
      field: 'Status__c',
      operator: 'equals',
      value: 'Received'
    });
    expect(parseDocument('')).toEqual({ logic: '', conditions: [] });
    expect(() => parseDocument('{"version": 2, "conditions": []}')).toThrow();
    expect(() => parseDocument('not json')).toThrow();
  });

  it('writes a document with sequential ids and leaves out a missing value', () => {
    const text = serializeDocument(
      [
        { field: 'Status__c', operator: 'equals', value: 'Received' },
        { field: 'Closed__c', operator: 'is null', value: undefined }
      ],
      ' 1 OR 2 '
    );
    expect(JSON.parse(text)).toEqual({
      version: 1,
      logic: '1 OR 2',
      conditions: [
        { id: 1, field: 'Status__c', operator: 'equals', value: 'Received' },
        { id: 2, field: 'Closed__c', operator: 'is null' }
      ]
    });
    expect(serializeDocument([], '')).toBe('');
  });
});
