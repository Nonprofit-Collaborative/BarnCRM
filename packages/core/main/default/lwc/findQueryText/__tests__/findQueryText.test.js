import { parseQueryText, PROBLEMS, QueryTextError } from 'c/findQueryText';

function problemOf(text) {
  try {
    parseQueryText(text);
  } catch (error) {
    expect(error).toBeInstanceOf(QueryTextError);
    return error.problem;
  }
  throw new Error(`Expected a refusal for: ${text}`);
}

describe('c/findQueryText', () => {
  it('reads a simple query into the document', () => {
    expect(
      parseQueryText(
        "select Name, BillingCity FROM Account WHERE BillingCity = 'Springfield' ORDER BY Name desc LIMIT 500"
      )
    ).toEqual({
      version: 1,
      object: 'Account',
      fields: ['Name', 'BillingCity'],
      filter: {
        version: 1,
        conditions: [{ id: 1, field: 'BillingCity', operator: 'equals', value: 'Springfield' }]
      },
      orderBy: [{ field: 'Name', direction: 'DESC' }],
      limit: 500
    });
  });

  it('maps every comparison onto an R-R2 operator, with typed values', () => {
    const document = parseQueryText(
      'SELECT Name FROM Gift__c WHERE Amount__c >= 100 AND Amount__c < 250.5 AND Status__c != null ' +
        "AND Status__c <> 'Cancelled' AND Gift_Date__c = LAST_N_DAYS:90 AND Paid__c = TRUE " +
        'AND Received__c > 2026-01-31 AND CreatedDate <= 2026-02-01T08:00:00Z AND Notes__c = null ' +
        "AND Type__c IN ('Cash', 'Check') AND Fund__c NOT IN ('a0B000000000001AAA') AND Close__c = THIS_YEAR"
    );
    expect(document.filter.logic).toBeUndefined();
    expect(document.filter.conditions.map(({ operator, value }) => [operator, value])).toEqual([
      ['greater or equal', 100],
      ['less than', 250.5],
      ['is not null', undefined],
      ['not equals', 'Cancelled'],
      ['last n days', 90],
      ['equals', true],
      ['greater than', '2026-01-31'],
      ['less or equal', '2026-02-01T08:00:00Z'],
      ['is null', undefined],
      ['in', ['Cash', 'Check']],
      ['not in', ['a0B000000000001AAA']],
      ['this year', undefined]
    ]);
  });

  it('reads LIKE as starts with, contains or equals, with escaped wildcards', () => {
    const document = parseQueryText(
      "SELECT Name FROM Account WHERE Name LIKE 'Smi%' AND Name LIKE '%50\\% off%' AND Name LIKE 'Exact'"
    );
    expect(document.filter.conditions.map(({ operator, value }) => [operator, value])).toEqual([
      ['starts with', 'Smi'],
      ['contains', '50% off'],
      ['equals', 'Exact']
    ]);
    expect(problemOf("SELECT Name FROM Account WHERE Name LIKE '%son'")).toBe(PROBLEMS.LIKE);
    expect(problemOf("SELECT Name FROM Account WHERE Name LIKE 'S_ith'")).toBe(PROBLEMS.LIKE);
  });

  it('reads back the backslashes the shown query writes, in a value and in a LIKE', () => {
    // As FilterValueBinder.display writes C:\temp (equals) and a\b (contains).
    const document = parseQueryText(
      "SELECT Name FROM Error_Log__c WHERE Context__c = 'C:\\\\temp' AND Message__c LIKE '%a\\\\\\\\b%' AND Name LIKE '%50\\% off%'"
    );
    expect(document.filter.conditions.map(({ operator, value }) => [operator, value])).toEqual([
      ['equals', 'C:\\temp'],
      ['contains', 'a\\b'],
      ['contains', '50% off']
    ]);
  });

  it('writes AND, OR, NOT and brackets as condition logic', () => {
    const document = parseQueryText(
      "SELECT Name FROM Account WHERE City__c = 'A' AND (Type = 'Household' OR Type = null) AND NOT Name LIKE '%Test%'"
    );
    expect(document.filter.logic).toBe('1 AND (2 OR 3) AND NOT 4');
    expect(document.filter.conditions).toHaveLength(4);
    expect(parseQueryText('SELECT Name FROM Account WHERE A__c = 1 OR B__c = 2').filter.logic).toBe(
      '1 OR 2'
    );
  });

  it('refuses AND and OR mixed without brackets, as SOQL does', () => {
    expect(problemOf('SELECT Name FROM Account WHERE A__c = 1 AND B__c = 2 OR C__c = 3')).toBe(
      PROBLEMS.MIXED_LOGIC
    );
    expect(problemOf('SELECT Name FROM Account WHERE A__c = 1 OR B__c = 2 AND C__c = 3')).toBe(
      PROBLEMS.MIXED_LOGIC
    );
  });

  it('reads related records conditions and related record columns', () => {
    const document = parseQueryText(
      'SELECT Name, (SELECT Name, Email FROM Contacts LIMIT 3) FROM Account ' +
        "WHERE Id IN (SELECT Household__c FROM Gift__c WHERE Gift_Date__c = THIS_YEAR) AND Type = 'Household' " +
        'AND Id NOT IN (SELECT Organization__c FROM Affiliation__c)'
    );
    expect(document.children).toEqual([
      { relationship: 'Contacts', fields: ['Name', 'Email'], limit: 3 }
    ]);
    expect(document.related).toEqual([
      {
        object: 'Gift__c',
        field: 'Household__c',
        has: true,
        filter: {
          version: 1,
          conditions: [{ id: 1, field: 'Gift_Date__c', operator: 'this year' }]
        }
      },
      { object: 'Affiliation__c', field: 'Organization__c', has: false }
    ]);
    expect(document.filter.conditions).toEqual([
      { id: 1, field: 'Type', operator: 'equals', value: 'Household' }
    ]);
  });

  it('refuses related records anywhere but the top-level AND', () => {
    expect(
      problemOf(
        "SELECT Name FROM Account WHERE Type = 'A' OR Id IN (SELECT AccountId FROM Contact)"
      )
    ).toBe(PROBLEMS.RELATED_PLACE);
    expect(problemOf('SELECT Name FROM Account WHERE Name IN (SELECT Name FROM Contact)')).toBe(
      PROBLEMS.RELATED_PLACE
    );
  });

  it('reads back the SOQL Find displays for a document', () => {
    const shown =
      'SELECT Id, Name, Household__r.Name, (SELECT Id, Email FROM Contacts ORDER BY CreatedDate DESC LIMIT 10) ' +
      "FROM Account WHERE ((Name LIKE '%Ruiz%') AND ((Type = 'Household') OR (Type = null))) " +
      'AND Id IN (SELECT Household__c FROM Gift__c WHERE (Amount__c > 100)) ' +
      'ORDER BY Name ASC NULLS FIRST LIMIT 200';
    expect(parseQueryText(shown)).toEqual({
      version: 1,
      object: 'Account',
      fields: ['Name', 'Household__r.Name'],
      children: [{ relationship: 'Contacts', fields: ['Email'], limit: 10 }],
      filter: {
        version: 1,
        logic: '1 AND (2 OR 3)',
        conditions: [
          { id: 1, field: 'Name', operator: 'contains', value: 'Ruiz' },
          { id: 2, field: 'Type', operator: 'equals', value: 'Household' },
          { id: 3, field: 'Type', operator: 'is null' }
        ]
      },
      related: [
        {
          object: 'Gift__c',
          field: 'Household__c',
          has: true,
          filter: {
            version: 1,
            conditions: [{ id: 1, field: 'Amount__c', operator: 'greater than', value: 100 }]
          }
        }
      ],
      orderBy: [{ field: 'Name', direction: 'ASC' }],
      limit: 200
    });
    expect(
      parseQueryText("SELECT Id, Name FROM Account WHERE (NOT Name LIKE '%x%')").filter.logic
    ).toBe('NOT 1');
  });

  it('refuses what the document cannot hold, saying where', () => {
    expect(problemOf('')).toBe(PROBLEMS.EMPTY);
    expect(problemOf('SELECT COUNT(Id) FROM Account')).toBe(PROBLEMS.UNSUPPORTED);
    expect(problemOf('SELECT Name FROM Account GROUP BY Name')).toBe(PROBLEMS.UNSUPPORTED);
    expect(problemOf('SELECT Name FROM Account ORDER BY Name, Type')).toBe(PROBLEMS.ONE_SORT);
    expect(problemOf('SELECT Name FROM Account WHERE CreatedDate > LAST_YEAR')).toBe(
      PROBLEMS.UNSUPPORTED
    );
    expect(problemOf('SELECT Name FROM Account WHERE Name = :name')).toBe(PROBLEMS.SYNTAX);
    expect(problemOf('SELECT Name FROM Account; DELETE')).toBe(PROBLEMS.SYNTAX);
    expect(problemOf('SELECT Name FROM Account LIMIT 1.5')).toBe(PROBLEMS.SYNTAX);
    let refusal;
    try {
      parseQueryText("SELECT Name FROM Account WHERE Name == 'x'");
    } catch (error) {
      refusal = error;
    }
    expect(refusal.near).toContain("= 'x'");
  });
});
