import { createHelpStore, formatHelp, languageCandidates } from 'c/barnHelpCatalog';

const CATALOGS = {
  '/r/BarnHelp_Core': {
    languages: ['en', 'fr', 'fr_CA'],
    texts: { Hello: 'Hello.', Count: '{0} of {1}.', Only: 'English only.' }
  },
  '/r/BarnHelp_Core_fr': { texts: { Hello: 'Bonjour.', Count: '{0} sur {1}.' } },
  '/r/BarnHelp_Core_fr_CA': { texts: { Hello: 'Allo.' } },
  '/r/BarnHelp_Giving': { languages: ['en'], texts: { Gift: 'A gift.' } }
};

function makeStore(onMissing) {
  const fetchJson = jest.fn((url) => Promise.resolve(CATALOGS[url] || null));
  const store = createHelpStore(fetchJson, (name) => '/r/' + name, onMissing);
  return { store, fetchJson };
}

describe('barnHelpCatalog', () => {
  it('lists the languages to try, most specific first, never English', () => {
    expect(languageCandidates('fr-CA')).toEqual(['fr_CA', 'fr']);
    expect(languageCandidates('fr')).toEqual(['fr']);
    expect(languageCandidates('en-US')).toEqual([]);
    expect(languageCandidates('en')).toEqual([]);
    expect(languageCandidates(undefined)).toEqual([]);
  });

  it('formats placeholders and leaves unknown ones', () => {
    expect(formatHelp('{0} of {1}.', [3, 'ten'])).toBe('3 of ten.');
    expect(formatHelp('{0} and {2}', ['a'])).toBe('a and {2}');
    expect(formatHelp(undefined, [])).toBe('');
  });

  it('is empty until loaded, then answers synchronously', async () => {
    const { store } = makeStore();
    expect(store.isLoaded('Core')).toBe(false);
    expect(store.text('Core', 'Hello')).toBe('');
    await store.load('Core', 'en-US');
    expect(store.isLoaded('Core')).toBe(true);
    expect(store.text('Core', 'Hello')).toBe('Hello.');
    expect(store.text('Core', 'Count', [1, 2])).toBe('1 of 2.');
  });

  it('fetches each package once however many callers ask', async () => {
    const { store, fetchJson } = makeStore();
    await Promise.all([
      store.load('Core', 'en'),
      store.load(['Core', 'Giving'], 'en'),
      store.load('Giving', 'en')
    ]);
    expect(fetchJson).toHaveBeenCalledTimes(2);
    expect(store.isLoaded(['Core', 'Giving'])).toBe(true);
    expect(store.text('Giving', 'Gift')).toBe('A gift.');
  });

  it('prefers the regional translation, then the language, then English', async () => {
    const { store } = makeStore();
    await store.load('Core', 'fr-CA');
    expect(store.text('Core', 'Hello')).toBe('Allo.');
    expect(store.text('Core', 'Count', [1, 2])).toBe('1 sur 2.');
    expect(store.text('Core', 'Only')).toBe('English only.');
  });

  it('never fetches a translation the English file does not list', async () => {
    const { store, fetchJson } = makeStore();
    await store.load('Giving', 'fr');
    expect(fetchJson).toHaveBeenCalledTimes(1);
    expect(store.text('Giving', 'Gift')).toBe('A gift.');
  });

  it('reads a missing key or a missing catalog as empty text and reports a key once', async () => {
    const onMissing = jest.fn();
    const { store } = makeStore(onMissing);
    await store.load(['Core', 'Programs'], 'en');
    expect(store.text('Core', 'Nope')).toBe('');
    expect(store.text('Core', 'Nope')).toBe('');
    expect(onMissing).toHaveBeenCalledTimes(1);
    expect(store.isLoaded('Programs')).toBe(true);
    expect(store.text('Programs', 'Anything')).toBe('');
  });

  it('treats a failed fetch as an empty catalog', async () => {
    const store = createHelpStore(
      () => Promise.reject(new Error('offline')),
      (name) => name
    );
    await store.load('Core', 'en');
    expect(store.text('Core', 'Hello')).toBe('');
  });
});
