import { createElement } from 'lwc';
import VolunteerSuggestions from 'c/volunteerSuggestions';
import getSuggestions from '@salesforce/apex/VolunteerSuggestionController.getSuggestions';
import addSignup from '@salesforce/apex/VolunteerShiftSignupsController.addSignup';

jest.mock(
  '@salesforce/apex/VolunteerSuggestionController.getSuggestions',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerShiftSignupsController.addSignup',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_Booked',
  () => ({ default: '{0} is signed up.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_SignUpFor',
  () => ({ default: 'Sign up {0}' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_ReasonAvailable',
  () => ({ default: 'Available on {0}s' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_ReasonSkills',
  () => ({ default: 'Has {0} of {1} skills' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_MoreConsidered',
  () => ({ default: 'Ranked from {0}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_BookFailed',
  () => ({ default: 'Not saved.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Suggestions_LoadFailed',
  () => ({ default: 'Not loaded.' }),
  {
    virtual: true
  }
);

const SHIFT_ID = 'a06000000000001AAA';

function candidate(id, name, extra) {
  return {
    personId: id,
    name,
    availableDays: [],
    skillIds: [],
    interestIds: [],
    hoursOnJob: 0,
    hoursTotal: 0,
    onboarding: 'none',
    ...extra
  };
}

function suggestions(candidates, extra) {
  return {
    canBook: true,
    weekday: 'Saturday',
    requiredSkillIds: ['s1', 's2'],
    candidates,
    moreThanConsidered: false,
    ...extra
  };
}

function build() {
  const element = createElement('c-volunteer-suggestions', { is: VolunteerSuggestions });
  element.recordId = SHIFT_ID;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-volunteer-suggestions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the best match first with its reasons', async () => {
    getSuggestions.mockResolvedValue(
      suggestions([
        candidate('p2', 'Ben Weak'),
        candidate('p1', 'Ana Strong', { availableDays: ['Saturday'], skillIds: ['s1', 's2'] })
      ])
    );
    const element = build();
    await flush();

    expect(getSuggestions).toHaveBeenCalledWith({ shiftId: SHIFT_ID });
    const rows = element.shadowRoot.querySelectorAll('[data-id="suggestion"]');
    expect(rows.length).toBe(2);
    expect(rows[0].querySelector('th').textContent).toBe('Ana Strong');
    const reasons = Array.from(rows[0].querySelectorAll('[data-id="reason"]')).map(
      (li) => li.textContent
    );
    expect(reasons).toEqual(['Has 2 of 2 skills', 'Available on Saturdays']);
    expect(rows[0].querySelector('.sign-up').ariaLabel).toBe('Sign up Ana Strong');
  });

  it('shows nothing when the user cannot book', async () => {
    getSuggestions.mockResolvedValue({ canBook: false, candidates: [], requiredSkillIds: [] });
    const element = build();
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('says so when nobody is left to suggest', async () => {
    getSuggestions.mockResolvedValue(suggestions([]));
    const element = build();
    await flush();

    expect(byId(element, 'empty-state')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="suggestion"]').length).toBe(0);
  });

  it('signs the person up through the Sign-ups panel save, tells the panel and reloads', async () => {
    getSuggestions
      .mockResolvedValueOnce(suggestions([candidate('p1', 'Ana Strong')]))
      .mockResolvedValueOnce(suggestions([]));
    addSignup.mockResolvedValue({});
    const heard = jest.fn();
    window.addEventListener('barnshiftsignupschanged', heard);
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.sign-up').click();
    await flush();

    expect(addSignup).toHaveBeenCalledWith({ shiftId: SHIFT_ID, personId: 'p1', status: null });
    expect(heard).toHaveBeenCalledTimes(1);
    expect(heard.mock.calls[0][0].detail).toEqual({ shiftId: SHIFT_ID });
    expect(byId(element, 'result-text').textContent).toBe('Ana Strong is signed up.');
    expect(element.shadowRoot.querySelectorAll('[data-id="suggestion"]').length).toBe(0);
    window.removeEventListener('barnshiftsignupschanged', heard);
  });

  it('reports a sign-up the server refused in its own words', async () => {
    getSuggestions.mockResolvedValue(suggestions([candidate('p1', 'Ana Strong')]));
    addSignup.mockRejectedValue({ body: { message: 'Already signed up.' } });
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.sign-up').click();
    await flush();

    expect(byId(element, 'error-message').textContent).toBe('Already signed up.');
  });

  it('falls back to a plain message when the failure has no text', async () => {
    getSuggestions.mockResolvedValue(suggestions([candidate('p1', 'Ana Strong')]));
    addSignup.mockRejectedValue(new Error('boom'));
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.sign-up').click();
    await flush();

    expect(byId(element, 'error-message').textContent).toBe('Not saved.');
  });

  it('shows a load failure', async () => {
    getSuggestions.mockRejectedValue(new Error('boom'));
    const element = build();
    await flush();

    expect(byId(element, 'error-message').textContent).toBe('Not loaded.');
  });

  it('shows only the best ten and notes when more volunteers were not ranked', async () => {
    const many = Array.from({ length: 12 }, (_, i) =>
      candidate(`p${i}`, `Person ${String(i).padStart(2, '0')}`)
    );
    getSuggestions.mockResolvedValue(suggestions(many, { moreThanConsidered: true }));
    const element = build();
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="suggestion"]').length).toBe(10);
    expect(byId(element, 'more-note').textContent).toBe('Ranked from 12');
  });
});
