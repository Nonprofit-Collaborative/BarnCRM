import { rankSuggestions, DEFAULT_WEIGHTS, REASON } from '../rankSuggestions';

const SHIFT = { weekday: 'Saturday', requiredSkillIds: ['s1', 's2'] };

function person(overrides) {
  return {
    personId: 'p',
    name: 'Person',
    availableDays: [],
    skillIds: [],
    interestIds: [],
    hoursOnJob: 0,
    hoursTotal: 0,
    onboarding: 'none',
    ...overrides
  };
}

function codes(ranked) {
  return ranked.map((row) => row.reasons.map((reason) => reason.code));
}

describe('rankSuggestions', () => {
  it('puts the person who matches skills, day, hours and onboarding first', () => {
    const best = person({
      personId: 'best',
      name: 'Best',
      availableDays: ['Saturday'],
      skillIds: ['s1', 's2'],
      hoursOnJob: 40,
      hoursTotal: 200,
      onboarding: 'cleared'
    });
    const middling = person({ personId: 'mid', name: 'Mid', availableDays: ['Saturday'] });
    const worst = person({
      personId: 'worst',
      name: 'Worst',
      availableDays: ['Monday'],
      onboarding: 'open'
    });

    const ranked = rankSuggestions(SHIFT, [worst, middling, best]);

    expect(ranked.map((row) => row.personId)).toEqual(['best', 'mid', 'worst']);
    // 30 + 25 + 20 + 5 + 10 with every cap reached.
    expect(ranked[0].score).toBe(90);
    expect(ranked[1].score).toBe(DEFAULT_WEIGHTS.availableDay);
    expect(ranked[2].score).toBe(DEFAULT_WEIGHTS.unavailableDay + DEFAULT_WEIGHTS.onboardingOpen);
  });

  it('scores skills by the share of required skills held and interests only for the rest', () => {
    const half = person({ personId: 'half', skillIds: ['s1'], interestIds: ['s1', 's2'] });

    const [row] = rankSuggestions(SHIFT, [half]);

    // Half the skills (15) plus the one skill held only as an interest (5).
    expect(row.score).toBe(20);
    expect(codes([row])[0]).toEqual([REASON.SKILLS, REASON.INTERESTS, REASON.NO_AVAILABILITY]);
    expect(row.reasons[0]).toEqual({ code: REASON.SKILLS, matched: 1, total: 2 });
    expect(row.reasons[1]).toEqual({ code: REASON.INTERESTS, matched: 1, total: 2 });
  });

  it('says so when no availability is recorded and does not penalise it', () => {
    const [row] = rankSuggestions(SHIFT, [person({})]);

    expect(row.score).toBe(0);
    expect(row.reasons).toEqual([{ code: REASON.NO_AVAILABILITY }]);
  });

  it('ignores skills when the job asks for none', () => {
    const [row] = rankSuggestions({ weekday: 'Saturday', requiredSkillIds: [] }, [
      person({ skillIds: ['s1'] })
    ]);

    expect(row.reasons.map((reason) => reason.code)).toEqual([REASON.NO_AVAILABILITY]);
  });

  it('caps hours so a long-serving volunteer cannot outweigh a perfect match', () => {
    const veteran = person({ name: 'Veteran', hoursOnJob: 5000, hoursTotal: 90000 });

    const [row] = rankSuggestions(SHIFT, [veteran]);

    expect(row.score).toBe(DEFAULT_WEIGHTS.hoursOnJob + DEFAULT_WEIGHTS.hoursTotal);
  });

  it('breaks ties on name so the order is stable', () => {
    const ranked = rankSuggestions(SHIFT, [
      person({ personId: 'b', name: 'Bea' }),
      person({ personId: 'a', name: 'Abe' })
    ]);

    expect(ranked.map((row) => row.name)).toEqual(['Abe', 'Bea']);
  });

  it('lets a caller override single weights and keeps the rest', () => {
    const ranked = rankSuggestions(
      SHIFT,
      [
        person({ personId: 'day', name: 'Day', availableDays: ['Saturday'] }),
        person({ personId: 'skill', name: 'Skill', skillIds: ['s1', 's2'] })
      ],
      { availableDay: 50 }
    );

    expect(ranked[0].personId).toBe('day');
    expect(ranked[0].score).toBe(50);
    expect(ranked[1].score).toBe(DEFAULT_WEIGHTS.skillMatch);
  });

  it('copes with missing input', () => {
    expect(rankSuggestions(undefined, undefined)).toEqual([]);
    expect(rankSuggestions(undefined, [{ personId: 'x', name: 'X' }])[0].reasons).toEqual([
      { code: REASON.NO_AVAILABILITY }
    ]);
  });
});
