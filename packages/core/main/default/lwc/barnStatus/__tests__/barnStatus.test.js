import { statusFor, TONES, ALIASES } from 'c/barnStatus';
import { iconFor, ICONS } from 'c/barnIcons';

describe('c/barnStatus', () => {
  it('maps every alias to a real tone', () => {
    Object.values(ALIASES).forEach((tone) => expect(TONES[tone]).toBeDefined());
  });

  it('gives every tone but neutral an icon, so color is never the only signal', () => {
    Object.values(TONES)
      .filter((look) => look.tone !== 'neutral')
      .forEach((look) => expect(look.iconName).toMatch(/^utility:/));
  });

  it('normalizes case, spaces and underscores, and falls back to neutral', () => {
    expect(statusFor('Needs Attention').tone).toBe('warning');
    expect(statusFor('NOT_MET').tone).toBe('error');
    expect(statusFor('').tone).toBe('neutral');
    expect(statusFor(null).tone).toBe('neutral');
    expect(statusFor('constructor').tone).toBe('neutral');
  });
});

describe('c/barnIcons', () => {
  it('returns the tab icon, or the fallback for an unknown name', () => {
    expect(iconFor('Gift__c')).toBe('custom:custom41');
    expect(iconFor('Ask_Pipeline')).toBe('custom:custom54');
    expect(iconFor('Contact')).toBe('standard:contact');
    expect(iconFor('Nothing__c', 'standard:default')).toBe('standard:default');
    expect(iconFor('toString')).toBeUndefined();
  });

  // All 100 motifs are in use, so module tabs in different packages may share one (D-193,
  // docs/contributor-guide/tab-icons.md); test_core_navigation.py checks the per-package rule.
  it('names only the documented custom motifs', () => {
    const custom = Object.values(ICONS).filter((icon) => icon.startsWith('custom:'));
    custom.forEach((icon) => {
      const number = Number(icon.replace('custom:custom', ''));
      expect(number >= 1 && number <= 100).toBe(true);
    });
  });
});
