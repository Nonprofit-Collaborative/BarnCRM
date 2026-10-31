/**
 * The digit-format transform step (C-50f2), without a framework (plan 9.9): keep the digits of a
 * value and write them into a pattern. The Apex twin is DataTransform.formatDigits, which runs
 * the step on the server; both are tested against the one JSON fixture
 * `staticresources/TransformFormatFixture.json`, so the preview a browser could draw and the
 * run the server does cannot drift apart.
 *
 * Imports nothing from lightning/* or @salesforce/*.
 */

/** Longest pattern, most digit places, longest country code, longest value (as DataTransform). */
export const MAX_PATTERN = 30;
export const MAX_SLOTS = 15;
export const MAX_COUNTRY = 3;
export const MAX_VALUE = 100;

/** The preset a one-click phone format adds: United States and Canada numbers. */
export const PHONE_PRESET_STEPS = [{ op: 'digits', pattern: '(###) ###-####', country: '1' }];

/** The same pattern and flags as DataTransform.EXTENSION: number, marker, extension digits. */
const EXTENSION = /^(.*?)\s*(?:ext(?:ension)?\.?|x)\s*([0-9]+)\s*$/i;

/** How many digit places (#) a pattern has. */
export function countPlaces(pattern) {
  return pattern ? pattern.split('#').length - 1 : 0;
}

/**
 * Whether a digits step's parameters are usable: a pattern of 1 to 15 places, at most 30
 * characters, and a country code that is blank or up to three digits.
 */
export function isValidDigitsStep(pattern, country) {
  const places = countPlaces(pattern);
  if (!pattern || !pattern.trim() || pattern.length > MAX_PATTERN) {
    return false;
  }
  if (places < 1 || places > MAX_SLOTS) {
    return false;
  }
  return !country || (country.length <= MAX_COUNTRY && /^[0-9]+$/.test(country));
}

/**
 * Keeps the digits of a value and writes them into the pattern. A leading country code is
 * dropped when that makes the digits fit; an extension (x, ext, ext., extension) is kept and
 * written " x" and its digits after the number. A value whose digits do not fit, a blank or an
 * overlong one comes back unchanged.
 *
 * @param {string|null} value the text to format
 * @param {string} pattern one # per digit; any other character is written as it is
 * @param {string} [country] a country code to drop from the front when it makes the digits fit
 * @returns {string|null} the formatted text, or the value unchanged
 */
export function formatDigits(value, pattern, country) {
  if (value === null || value === undefined) {
    return value;
  }
  const text = String(value);
  if (!text.trim() || !pattern || !pattern.trim()) {
    return value;
  }
  if (text.length > MAX_VALUE || pattern.length > MAX_PATTERN) {
    return value;
  }
  let main = text.trim();
  let extension = '';
  const found = EXTENSION.exec(main);
  if (found) {
    main = found[1];
    extension = found[2];
  }
  let digits = main.replace(/[^0-9]/g, '');
  const places = countPlaces(pattern);
  const code = country ? String(country).trim() : '';
  if (code.length > 0 && digits.length === places + code.length && digits.startsWith(code)) {
    digits = digits.substring(code.length);
  }
  if (places < 1 || digits.length !== places) {
    return value;
  }
  let next = 0;
  let out = '';
  for (const character of pattern) {
    if (character === '#') {
      out += digits.charAt(next);
      next += 1;
    } else {
      out += character;
    }
  }
  return extension ? `${out} x${extension}` : out;
}
