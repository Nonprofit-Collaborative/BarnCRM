import { apexController, apexFiles, apexNames, apexTest } from 'c/lwcBuilderExportKit';

const count = (text, char) => text.split(char).length - 1;

describe('the exported Apex', () => {
  it('names the controller and its test within 40 characters', () => {
    const names = apexNames('A'.repeat(60));
    expect(names.controller.length).toBeLessThanOrEqual(40);
    expect(names.test.length).toBeLessThanOrEqual(40);
  });

  it('keeps the report grouping walk in a test-visible method over plain inputs', () => {
    const source = apexController('SnapshotController', 'snapshot');
    expect(source).toMatch(/@TestVisible\s+private static List<Map<String, Object>> walk\(/);
    expect(source).toMatch(/@TestVisible\s+private static Object typed\(/);
    // chart() hands the walk plain maps, never report classes.
    expect(source).toContain('walk(plain(groups), plain(across), cellsByKey, series)');
  });

  it('has balanced braces and parentheses in both files', () => {
    const source = apexController('SnapshotController', 'snapshot');
    const test = apexTest('SnapshotControllerTest', 'SnapshotController');
    for (const text of [source, test]) {
      expect(count(text, '{')).toBe(count(text, '}'));
      expect(count(text, '(')).toBe(count(text, ')'));
    }
  });

  it('tests the controller well past the 75 percent a production deploy needs', () => {
    const test = apexTest('SnapshotControllerTest', 'SnapshotController');
    expect(test).toContain("'parentField' => 'ParentId'");
    expect(test).toContain("'filterOperator' => 'notEquals'");
    for (const type of ['Boolean', 'Currency', 'Integer', 'Date', 'Text']) {
      expect(test).toMatch(new RegExp(`\\s'${type}'`));
    }
    expect(test).toContain('SnapshotController.typed(');
    expect(test).toContain('SnapshotController.walk(');
    // summary, two groupings, matrix and the row cap each have a test.
    const tests = test.match(/@IsTest/g) || [];
    expect(tests.length).toBeGreaterThanOrEqual(6);
  });

  it('writes four files for a bundle', () => {
    const files = apexFiles('Snapshot', 'snapshot').map((file) => file.name);
    expect(files).toEqual([
      'SnapshotController.cls',
      'SnapshotController.cls-meta.xml',
      'SnapshotControllerTest.cls',
      'SnapshotControllerTest.cls-meta.xml'
    ]);
  });
});
