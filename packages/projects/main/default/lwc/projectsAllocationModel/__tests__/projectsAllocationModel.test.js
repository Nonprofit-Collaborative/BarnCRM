import {
  allocation,
  hoursInRange,
  mondayOf,
  rankCandidates,
  skillList,
  weekRange,
  weekStarts
} from 'c/projectsAllocationModel';

const person = (id, name, extra = {}) => ({
  Id: `r${id}`,
  User__c: `u${id}`,
  User__r: { Name: name },
  Active__c: true,
  ...extra
});
const plan = (userId, hours, start, end) => ({
  Resource__c: userId,
  Planned_Hours__c: hours,
  Start_Date__c: start,
  End_Date__c: end
});

describe('c-projects-allocation-model weeks', () => {
  it('finds the Monday of any day, Sunday included', () => {
    expect(mondayOf('2026-11-12')).toBe('2026-11-09');
    expect(mondayOf('2026-11-15')).toBe('2026-11-09');
    expect(mondayOf('2026-11-09')).toBe('2026-11-09');
    expect(mondayOf('')).toBe('');
  });

  it('builds whole weeks from a start and a count, and lists their Mondays', () => {
    expect(weekRange('2026-11-12', 2)).toEqual({ from: '2026-11-09', to: '2026-11-22' });
    expect(weekRange('', 2)).toBeNull();
    expect(weekStarts('2026-11-12', '2026-11-22')).toEqual(['2026-11-09', '2026-11-16']);
  });

  it('splits a multi-select value into skills', () => {
    expect(skillList('Apex; Data Migration;')).toEqual(['Apex', 'Data Migration']);
    expect(skillList(null)).toEqual([]);
  });
});

describe('c-projects-allocation-model hours', () => {
  const span = { from: '2026-11-09', to: '2026-11-22' };

  it('spreads hours over working days only, so a weekend adds none', () => {
    const item = { hours: 40, start: '2026-11-09', end: '2026-11-20' };
    expect(hoursInRange(item, '2026-11-09', '2026-11-15', span)).toBe(20);
    expect(hoursInRange(item, '2026-11-14', '2026-11-15', span)).toBe(0);
    expect(hoursInRange(item, '2026-11-09', '2026-11-11', span)).toBe(12);
  });

  it('uses the range itself when an item has no dates, and is 0 for no hours', () => {
    expect(hoursInRange({ hours: 20 }, '2026-11-09', '2026-11-15', span)).toBe(10);
    const none = { hours: 0, start: '2026-11-09', end: '2026-11-13' };
    expect(hoursInRange(none, span.from, span.to, span)).toBe(0);
  });
});

describe('c-projects-allocation-model allocation', () => {
  const data = {
    defaultCapacity: 40,
    resources: [
      person(2, 'Zed'),
      person(1, 'Ann', { Weekly_Capacity_Hours__c: 20 }),
      person(3, 'Gone', { Active__c: false })
    ],
    assignments: [
      plan('u1', 40, '2026-11-09', '2026-11-20'),
      plan('u1', 10, '2026-11-09', '2026-11-13'),
      plan('u3', 40, '2026-11-09', '2026-11-13')
    ],
    logged: [
      { userId: 'u1', date: '2026-11-10', hours: 3 },
      { userId: 'u1', date: '2026-11-12', hours: 2.5 },
      { userId: 'u1', date: '2026-11-17', hours: 4 }
    ],
    requests: [{ Hours__c: 20, Start_Date__c: '2026-11-16', End_Date__c: '2026-11-20' }]
  };

  it('works out each person by week against their own capacity, over included', () => {
    const view = allocation(data, '2026-11-09', '2026-11-22');
    expect(view.weeks).toEqual(['2026-11-09', '2026-11-16']);
    expect(view.people.map((row) => row.name)).toEqual(['Ann', 'Zed']);
    const [ann, zed] = view.people;
    expect(ann.cells[0]).toEqual({
      week: '2026-11-09',
      allocated: 30,
      capacity: 20,
      logged: 5.5,
      percent: 150,
      over: true
    });
    expect(ann.cells[1]).toMatchObject({ allocated: 20, logged: 4, percent: 100, over: false });
    expect(zed.cells[0]).toMatchObject({ allocated: 0, capacity: 40, percent: 0, over: false });
  });

  it('shows unfilled requests as demand in the weeks they fall in', () => {
    const view = allocation(data, '2026-11-09', '2026-11-22');
    expect(view.demand).toEqual([
      { week: '2026-11-09', hours: 0 },
      { week: '2026-11-16', hours: 20 }
    ]);
  });

  it('is empty for no data', () => {
    expect(allocation({}, '2026-11-09', '2026-11-15').people).toEqual([]);
  });
});

describe('c-projects-allocation-model candidates', () => {
  const request = {
    Role__c: 'Data Migration',
    Skills__c: 'Apex;Data',
    Start_Date__c: '2026-11-09',
    End_Date__c: '2026-11-13'
  };
  const data = {
    defaultCapacity: 40,
    resources: [
      person(1, 'Busy', { Skills__c: 'Apex;Data', Weekly_Capacity_Hours__c: 40 }),
      person(2, 'Free', { Skills__c: 'Apex;Data;Flow' }),
      person(3, 'RoleOnly', { Skills__c: 'Apex', Default_Role__c: 'data migration' }),
      person(4, 'Partial', { Skills__c: 'Apex', Weekly_Capacity_Hours__c: 10 }),
      person(5, 'Off', { Skills__c: 'Apex;Data', Active__c: false })
    ],
    assignments: [plan('u1', 30, '2026-11-09', '2026-11-13')]
  };

  it('lists people with every skill first, then role, then free capacity', () => {
    const list = rankCandidates(request, data);
    expect(list.map((row) => row.name)).toEqual(['Free', 'Busy', 'RoleOnly', 'Partial']);
    expect(list[0]).toMatchObject({ matched: 2, needed: 2, allSkills: true, free: 40 });
    expect(list[1]).toMatchObject({ allocated: 30, free: 10 });
    expect(list[2]).toMatchObject({ allSkills: false, roleMatch: true, matched: 1 });
  });

  it('counts only the request days: a part-time person has less capacity', () => {
    const partial = rankCandidates(request, data).find((row) => row.name === 'Partial');
    expect(partial.capacity).toBe(10);
  });

  it('treats a request with no skills as matched by everyone', () => {
    const list = rankCandidates({ ...request, Skills__c: null }, data);
    expect(list.every((row) => row.allSkills)).toBe(true);
    expect(list[0].name).toBe('RoleOnly');
    expect(list[1].name).toBe('Free');
  });
});
