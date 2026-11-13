import { ICONS, iconFor } from 'c/barnIcons';

describe('c/barnIcons', () => {
  it('gives a listed tab or object its icon', () => {
    expect(iconFor('Address__c')).toBe('custom:custom78');
    expect(iconFor('Contact', 'standard:default')).toBe('standard:contact');
  });

  it('gives the fallback for a name it does not list, even an inherited property name', () => {
    expect(iconFor('Not_A_Tab__c', 'standard:default')).toBe('standard:default');
    expect(iconFor('toString', 'standard:default')).toBe('standard:default');
    expect(iconFor('Not_A_Tab__c')).toBeUndefined();
  });

  it('is frozen and names only icons the Lightning icon set has', () => {
    expect(Object.isFrozen(ICONS)).toBe(true);
    for (const icon of Object.values(ICONS)) {
      expect(icon).toMatch(/^(custom|standard|utility):[a-z0-9_]+$/);
    }
  });
});
