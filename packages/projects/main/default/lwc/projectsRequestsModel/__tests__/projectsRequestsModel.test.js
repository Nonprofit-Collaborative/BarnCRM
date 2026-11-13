import { VIEWS, changesBetween, decorate, options, viewOrDefault } from 'c/projectsRequestsModel';

describe('c/projectsRequestsModel', () => {
  it('saves only the editable fields that changed, blanks as null', () => {
    const loaded = {
      status: 'New',
      priority: 'Medium',
      ownerId: 'u1',
      dueDate: '2026-11-20',
      resolution: null
    };
    expect(
      changesBetween(loaded, {
        status: 'New',
        priority: 'High',
        resolution: '',
        dueDate: '',
        subject: 'x'
      })
    ).toEqual({ Priority__c: 'High', Due_Date__c: null });
    expect(changesBetween(loaded, {})).toEqual({});
    expect(changesBetween(null, { projectId: 'p1' })).toEqual({ Project__c: 'p1' });
  });

  it('falls back to the first view and builds options', () => {
    expect(viewOrDefault('closed')).toBe('closed');
    expect(viewOrDefault('nonsense')).toBe(VIEWS[0]);
    expect(options(['A'])).toEqual([{ label: 'A', value: 'A' }]);
  });

  it('flags overdue rows', () => {
    const rows = decorate([
      { id: 'r1', overdue: true },
      { id: 'r2', overdue: false }
    ]);
    expect(rows[0].rowClass).toBe('slds-text-color_error');
    expect(rows[1].rowClass).toBe('');
    expect(decorate(undefined)).toEqual([]);
  });
});
