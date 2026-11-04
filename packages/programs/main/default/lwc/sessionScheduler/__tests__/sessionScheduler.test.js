import { createElement } from 'lwc';
import SessionScheduler from 'c/sessionScheduler';
import getSchedule from '@salesforce/apex/SessionScheduleController.getSchedule';
import scheduleSessions from '@salesforce/apex/SessionScheduleController.scheduleSessions';
import getTakenDays from '@salesforce/apex/SessionScheduleController.getTakenDays';
import {
  MAX_SESSIONS,
  countMessage,
  format,
  newAndSkipped,
  parseIsoDate,
  previewMessage,
  sessionDates,
  toIsoDate,
  weekdayOptions
} from '../schedule';

jest.mock(
  '@salesforce/apex/SessionScheduleController.getSchedule',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/SessionScheduleController.scheduleSessions',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/SessionScheduleController.getTakenDays',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Programs_Schedule_Skipped', () => ({ default: 'skipped {0}' }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock(
  '@salesforce/label/c.Programs_Schedule_PreviewMany',
  () => ({ default: '{0} sessions' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Programs_Schedule_CreatedMany', () => ({ default: '{0} made' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Schedule_IntroCohort', () => ({ default: 'For {0}' }), {
  virtual: true
});

const COHORT_ID = 'a0C000000000001AAA';
const SERVICE_ID = 'a0A000000000001AAA';

function scheduleOf(extra) {
  return {
    programId: 'a08000000000001AAA',
    cohortId: COHORT_ID,
    cohortName: 'Spring',
    services: [{ label: 'Tutoring', value: SERVICE_ID }],
    startDate: '2027-03-01',
    endDate: '2027-03-14',
    canSchedule: true,
    maxSessions: 200,
    created: 0,
    ...extra
  };
}

async function flush() {
  for (let i = 0; i < 10; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function render() {
  const element = createElement('c-session-scheduler', { is: SessionScheduler });
  element.recordId = COHORT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('schedule (framework free)', () => {
  it('reads and writes ISO dates in UTC', () => {
    expect(toIsoDate(parseIsoDate('2027-03-01'))).toBe('2027-03-01');
    expect(parseIsoDate('3/1/2027')).toBeNull();
    expect(parseIsoDate(undefined)).toBeNull();
    expect(format('{0} of {1}', 1)).toBe('1 of {1}');
  });

  it('names the weekdays Monday first', () => {
    const options = weekdayOptions('en-US');
    expect(options.map((one) => one.value)).toEqual(['1', '2', '3', '4', '5', '6', '0']);
    expect(options[0].label).toBe('Monday');
    expect(options[6].label).toBe('Sunday');
    expect(weekdayOptions('not a locale !')).toHaveLength(7);
  });

  it('lists the chosen weekdays between two dates, both included', () => {
    // 1 March 2027 is a Monday.
    expect(sessionDates('2027-03-01', '2027-03-14', ['1', '3']).dates).toEqual([
      '2027-03-01',
      '2027-03-03',
      '2027-03-08',
      '2027-03-10'
    ]);
    expect(sessionDates('2027-03-02', '2027-03-02', ['2']).dates).toEqual(['2027-03-02']);
  });

  it('says what is missing, and stops past the most', () => {
    expect(sessionDates('2027-03-14', '2027-03-01', ['1']).problem).toBe('dates');
    expect(sessionDates(undefined, '2027-03-01', ['1']).problem).toBe('dates');
    expect(sessionDates('2027-03-01', '2027-03-14', []).problem).toBe('weekdays');
    const long = sessionDates('2027-01-01', '2030-12-31', ['0', '1', '2', '3', '4', '5', '6']);
    expect(long.tooMany).toBe(true);
    expect(long.dates).toHaveLength(MAX_SESSIONS);
    const labels = {
      chooseDates: 'dates',
      chooseWeekdays: 'days',
      tooMany: 'at most {0}',
      none: 'none',
      one: 'one',
      many: '{0} sessions'
    };
    expect(previewMessage({ problem: 'dates', dates: [] }, labels)).toBe('dates');
    expect(previewMessage({ problem: 'weekdays', dates: [] }, labels)).toBe('days');
    expect(previewMessage(long, labels)).toBe('at most 200');
    expect(previewMessage({ problem: null, dates: [] }, labels)).toBe('none');
    expect(previewMessage({ problem: null, dates: ['x'] }, labels)).toBe('one');
    expect(previewMessage({ problem: null, dates: ['x', 'y'] }, labels)).toBe('2 sessions');
  });

  it('counts the days that already have a session as skipped', () => {
    const labels = { one: 'one', many: '{0} sessions', skipped: 'skipped {0}' };
    expect(newAndSkipped(['a', 'b', 'c'], ['b', 'z'])).toEqual({ toCreate: 2, skipped: 1 });
    expect(newAndSkipped(['a'], undefined)).toEqual({ toCreate: 1, skipped: 0 });
    expect(countMessage(2, 1, labels)).toBe('2 sessions skipped 1');
    expect(countMessage(1, 0, labels)).toBe('one');
    expect(
      previewMessage({ problem: null, dates: ['a', 'b'] }, { ...labels, none: 'none' }, ['a', 'b'])
    ).toBe('0 sessions skipped 2');
  });
});

describe('c-session-scheduler', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the cohort dates and schedules the chosen weekdays', async () => {
    getSchedule.mockResolvedValue(scheduleOf());
    scheduleSessions.mockResolvedValue(scheduleOf({ created: 4 }));
    const element = await render();
    expect(getSchedule).toHaveBeenCalledWith({ recordId: COHORT_ID });
    expect(q(element, 'intro').textContent).toBe('For Spring');
    expect(q(element, 'schedule').disabled).toBe(true);

    q(element, 'weekdays').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['1', '3'] } })
    );
    const time = q(element, 'start-time');
    time.value = '18:30:00.000';
    time.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(q(element, 'preview').textContent).toBe('4 sessions');
    expect(q(element, 'schedule').disabled).toBe(false);

    const refreshed = jest.fn();
    element.addEventListener('lightning__refresh', refreshed);
    q(element, 'schedule').click();
    await flush();
    expect(scheduleSessions).toHaveBeenCalledWith({
      recordId: COHORT_ID,
      serviceId: SERVICE_ID,
      dates: ['2027-03-01', '2027-03-03', '2027-03-08', '2027-03-10'],
      startTime: '18:30:00.000'
    });
    expect(q(element, 'result').textContent).toBe('4 made');
    expect(refreshed).toHaveBeenCalled();
  });

  it('changes the service and dates, and shows a refusal', async () => {
    getSchedule.mockResolvedValue(
      scheduleOf({
        cohortId: null,
        startDate: null,
        endDate: null,
        services: [
          { label: 'Tutoring', value: SERVICE_ID },
          { label: 'Snack', value: 'a0A000000000002AAA' }
        ]
      })
    );
    scheduleSessions.mockRejectedValue({ body: { message: 'Choose an active service.' } });
    const element = await render();
    expect(q(element, 'intro').textContent).toContain('Programs_Schedule_IntroProgram');
    q(element, 'service').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a0A000000000002AAA' } })
    );
    const from = q(element, 'from');
    from.value = '2027-03-01';
    from.dispatchEvent(new CustomEvent('change'));
    const to = q(element, 'to');
    to.value = '2027-03-01';
    to.dispatchEvent(new CustomEvent('change'));
    q(element, 'weekdays').dispatchEvent(new CustomEvent('change', { detail: { value: ['1'] } }));
    await flush();
    q(element, 'schedule').click();
    await flush();
    expect(scheduleSessions.mock.calls[0][0]).toMatchObject({
      serviceId: 'a0A000000000002AAA',
      dates: ['2027-03-01'],
      startTime: null
    });
    expect(q(element, 'error-message').message).toContain('Choose an active service.');
  });

  it('skips days that already have a session, in the preview and the result', async () => {
    getSchedule.mockResolvedValue(scheduleOf());
    getTakenDays.mockResolvedValue(['2027-03-01', '2027-03-08']);
    scheduleSessions.mockResolvedValue(scheduleOf({ created: 1, skipped: 2 }));
    const element = await render();
    expect(getTakenDays).toHaveBeenCalledWith({
      recordId: COHORT_ID,
      serviceId: SERVICE_ID,
      fromDate: '2027-03-01',
      toDate: '2027-03-14'
    });

    q(element, 'weekdays').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['1', '3'] } })
    );
    await flush();
    expect(q(element, 'preview').textContent).toBe('2 sessions skipped 2');
    expect(q(element, 'schedule').disabled).toBe(false);

    q(element, 'schedule').click();
    await flush();
    expect(q(element, 'result').textContent).toContain('skipped 2');

    // Every chosen day already has a session: nothing to schedule.
    getTakenDays.mockResolvedValue(['2027-03-01', '2027-03-08', '2027-03-15']);
    const to = q(element, 'to');
    to.value = '2027-03-15';
    to.dispatchEvent(new CustomEvent('change'));
    q(element, 'weekdays').dispatchEvent(new CustomEvent('change', { detail: { value: ['1'] } }));
    await flush();
    expect(q(element, 'preview').textContent).toBe('0 sessions skipped 3');
    expect(q(element, 'schedule').disabled).toBe(true);
  });

  it('says when the program has no active service, and when the load fails', async () => {
    getSchedule.mockResolvedValue(scheduleOf({ services: [] }));
    const element = await render();
    expect(q(element, 'no-services')).not.toBeNull();
    expect(q(element, 'schedule')).toBeNull();

    getSchedule.mockRejectedValue({});
    const second = await render();
    expect(q(second, 'error-message').message).toContain('Programs_Fail_Schedule');
  });
});
