// The real module (relative path: jest.config.js maps c/barnHelpText to a stand-in for every
// other test).
import { helpText, isHelpLoaded, loadHelp } from '../barnHelpText';

const CATALOGS = {
  BarnHelp_Core: {
    languages: ['en'],
    texts: { Core_Example_Intro: 'Start here.', Core_Example_Count: '{0} rows.' }
  },
  BarnHelp_Giving: { languages: ['en'], texts: { Giving_Example_Help: 'A gift is money given.' } }
};

describe('c/barnHelpText', () => {
  beforeEach(() => {
    global.fetch = jest.fn((url) => {
      const name = url.substring(url.lastIndexOf('/') + 1);
      return Promise.resolve({
        ok: Boolean(CATALOGS[name]),
        json: () => Promise.resolve(CATALOGS[name])
      });
    });
  });

  it('fetches each package catalog from its static resource once and answers by key', async () => {
    expect(isHelpLoaded('Core')).toBe(false);
    expect(helpText('Core', 'Core_Example_Intro')).toBe('');
    await loadHelp(['Core', 'Giving']);
    await loadHelp('Core');
    expect(global.fetch).toHaveBeenCalledTimes(2);
    const urls = global.fetch.mock.calls.map((call) => call[0]);
    expect(urls.every((url) => url.startsWith('/resource/'))).toBe(true);
    expect(isHelpLoaded(['Core', 'Giving'])).toBe(true);
    expect(helpText('Core', 'Core_Example_Intro')).toBe('Start here.');
    expect(helpText('Core', 'Core_Example_Count', 12)).toBe('12 rows.');
    expect(helpText('Giving', 'Giving_Example_Help')).toBe('A gift is money given.');
  });

  it('reads a key it does not know as empty text and warns once', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    await loadHelp('Core');
    expect(helpText('Core', 'Core_Not_There')).toBe('');
    expect(helpText('Core', 'Core_Not_There')).toBe('');
    expect(warn).toHaveBeenCalledTimes(1);
    warn.mockRestore();
  });
});
