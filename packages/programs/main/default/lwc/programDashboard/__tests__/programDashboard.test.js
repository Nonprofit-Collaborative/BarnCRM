import { createElement } from 'lwc';
import ProgramDashboard from 'c/programDashboard';
import getDashboard from '@salesforce/apex/ProgramDashboardController.getDashboard';
import { attendanceRate, isoDate, periodRange, programRows, tiles } from '../dashboardRows';

jest.mock(
  '@salesforce/apex/ProgramDashboardController.getDashboard',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const DASHBOARD = {
  canSee: true,
  activePrograms: 2,
  moreThanShown: false,
  totals: {
    openEnrollments: 12,
    newEnrollments: 3,
    completedEnrollments: 1,
    peopleServed: 9,
    delivered: 30,
    deliveries: 40
  },
  programs: [
    {
      programId: 'a08000000000001AAA',
      name: 'Pantry',
      status: 'Active',
      openEnrollments: 10,
      newEnrollments: 3,
      completedEnrollments: 1,
      peopleServed: 9,
      delivered: 30,
      deliveries: 40
    },
    { programId: 'a08000000000002AAA', name: 'Tutoring', status: 'Active' }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-program-dashboard', { is: ProgramDashboard });
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const all = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('dashboardRows (framework free)', () => {
  const today = new Date(2026, 9, 31);

  it('works out each period, both ends included', () => {
    expect(periodRange('thisMonth', today)).toEqual({
      fromDate: '2026-10-01',
      toDate: '2026-10-31'
    });
    expect(periodRange('lastMonth', today)).toEqual({
      fromDate: '2026-09-01',
      toDate: '2026-09-30'
    });
    expect(periodRange('thisYear', today)).toEqual({
      fromDate: '2026-01-01',
      toDate: '2026-12-31'
    });
    expect(periodRange('lastYear', today)).toEqual({
      fromDate: '2025-01-01',
      toDate: '2025-12-31'
    });
    expect(periodRange('last12Months', today)).toEqual({
      fromDate: '2025-11-01',
      toDate: '2026-10-31'
    });
    expect(periodRange('lastMonth', new Date(2026, 0, 15)).fromDate).toBe('2025-12-01');
    expect(periodRange('unknown', today)).toEqual(periodRange('thisMonth', today));
    expect(isoDate(new Date(2026, 1, 3))).toBe('2026-02-03');
  });

  it('gives the attendance rate, or the none label', () => {
    expect(attendanceRate({ delivered: 30, deliveries: 40 }, 'None')).toBe('75%');
    expect(attendanceRate({ delivered: 0, deliveries: 0 }, 'None')).toBe('None');
    expect(attendanceRate(undefined, 'None')).toBe('None');
  });

  it('builds the tiles and the program rows', () => {
    const labels = { noRate: 'None', activePrograms: 'Active' };
    const shown = tiles(DASHBOARD, labels);
    expect(shown.map((tile) => tile.key)).toEqual([
      'active',
      'open',
      'new',
      'people',
      'delivered',
      'rate'
    ]);
    expect(shown[0].value).toBe('2');
    expect(shown[5].value).toBe('75%');
    expect(tiles({ canSee: false }, labels)).toEqual([]);

    const rows = programRows(DASHBOARD, 'None');
    expect(rows[0].href).toBe('/lightning/r/Program__c/a08000000000001AAA/view');
    expect(rows[1]).toMatchObject({ openEnrollments: 0, delivered: 0, rate: 'None' });
    expect(programRows(undefined, 'None')).toEqual([]);
  });
});

describe('c-program-dashboard', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('loads this month and shows the tiles and a row per program', async () => {
    getDashboard.mockResolvedValue(DASHBOARD);
    const element = mount();
    await flush();

    const args = getDashboard.mock.calls[0][0];
    expect(args.fromDate).toMatch(/^\d{4}-\d{2}-01$/);
    expect(all(element, 'tile').length).toBe(6);
    expect(one(element, 'rate').textContent).toBe('75%');
    expect(all(element, 'program-row').length).toBe(2);
    expect(one(element, 'no-programs')).toBeNull();
  });

  it('loads again for another period', async () => {
    getDashboard.mockResolvedValue(DASHBOARD);
    const element = mount();
    await flush();

    const picker = one(element, 'period');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'lastYear' } }));
    await flush();

    expect(getDashboard).toHaveBeenCalledTimes(2);
    const args = getDashboard.mock.calls[1][0];
    expect(args.fromDate.endsWith('-01-01')).toBe(true);
    expect(args.toDate.endsWith('-12-31')).toBe(true);
  });

  it('says so with no programs, no access, or a failed load', async () => {
    getDashboard.mockResolvedValue({ ...DASHBOARD, programs: [], moreThanShown: true });
    const element = mount();
    await flush();
    expect(one(element, 'no-programs')).not.toBeNull();
    expect(one(element, 'more')).not.toBeNull();

    getDashboard.mockResolvedValue({ canSee: false });
    const second = mount();
    await flush();
    expect(one(second, 'no-access')).not.toBeNull();
    expect(all(second, 'tile').length).toBe(0);

    getDashboard.mockRejectedValue({});
    const third = mount();
    await flush();
    expect(one(third, 'error').textContent).toContain('Programs_Dashboard_LoadFailed');
  });
});
