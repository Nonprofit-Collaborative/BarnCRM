/**
 * A module's public page and list as a page shows them (ADR-NEXT public event pages, decision 6),
 * framework free (plan 9.9) so an off-platform site can draw the same JSON. Every text comes
 * finished from the module; this module only formats dates in the page's time zone, amounts in
 * their currency, and the link from a list to each page.
 */

function dateFrom(value) {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatter(locale, timeZone, options) {
  try {
    return new Intl.DateTimeFormat(locale || undefined, { ...options, timeZone });
  } catch {
    // An unknown time zone or locale: the browser's own.
    return new Intl.DateTimeFormat(undefined, options);
  }
}

const DAY_AND_TIME = {
  weekday: 'short',
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit'
};
const TIME = { hour: 'numeric', minute: '2-digit' };
const DAY = { year: 'numeric', month: 'numeric', day: 'numeric' };

/**
 * When something runs, as `{ start, end }` texts: the end as a time only when it is the same
 * day. Empty texts when there is no start.
 */
export function whenText(start, end, timeZone, locale) {
  const from = dateFrom(start);
  if (!from) {
    return { start: '', end: '' };
  }
  const to = dateFrom(end);
  const full = formatter(locale, timeZone, DAY_AND_TIME);
  if (!to) {
    return { start: full.format(from), end: '' };
  }
  const day = formatter(locale, timeZone, DAY);
  const sameDay = day.format(from) === day.format(to);
  return {
    start: full.format(from),
    end: sameDay ? formatter(locale, timeZone, TIME).format(to) : full.format(to)
  };
}

/** An amount in its currency, or empty when there is none. */
export function amountText(amount, currency, locale) {
  if (amount === null || amount === undefined || amount === '' || !currency) {
    return '';
  }
  const value = Number(amount);
  if (Number.isNaN(value)) {
    return '';
  }
  try {
    return new Intl.NumberFormat(locale || undefined, { style: 'currency', currency }).format(
      value
    );
  } catch {
    return `${currency} ${value.toFixed(2)}`;
  }
}

function joinWhen(when, joiner) {
  if (!when.start) {
    return '';
  }
  return when.end ? joiner(when.start, when.end) : when.start;
}

/**
 * The page as the component draws it.
 *
 * @param page the module's page JSON
 * @param locale the viewer's locale
 * @param joiner `(start, end) => text`, the words between a start and an end
 */
export function pageView(page, locale, joiner) {
  if (!page || !page.title) {
    return null;
  }
  const zone = page.timeZone;
  const sections = (page.sections || []).map((section, sectionIndex) => ({
    key: section.key || String(sectionIndex),
    title: section.title || '',
    items: (section.items || []).map((item, itemIndex) => ({
      key: `${section.key || sectionIndex}-${itemIndex}`,
      title: item.title || '',
      subtitle: item.subtitle || '',
      text: item.text || '',
      when: joinWhen(whenText(item.start, item.end, zone, locale), joiner),
      price: amountText(item.amount, item.currency, locale),
      note: item.amount ? item.note || '' : '',
      badges: (item.badges || []).filter(Boolean).map((badge, badgeIndex) => ({
        key: String(badgeIndex),
        text: badge
      }))
    }))
  }));
  return {
    title: page.title,
    description: page.description || '',
    when: joinWhen(whenText(page.start, page.end, zone, locale), joiner),
    facts: (page.facts || []).map((fact, index) => ({
      key: String(index),
      label: fact.label || '',
      value: fact.value || ''
    })),
    sections,
    formId: page.registration === 'Open' && page.formId ? page.formId : null,
    message: page.message || ''
  };
}

/**
 * The list as the component draws it, each item linking to its page.
 *
 * @param list the module's list JSON
 * @param pageUrl `(recordId) => href`, the address of one record's page
 */
export function listView(list, locale, joiner, pageUrl) {
  if (!list) {
    return null;
  }
  const items = (list.items || []).map((item) => ({
    key: item.recordId,
    title: item.title || '',
    subtitle: item.subtitle || '',
    when: joinWhen(whenText(item.start, item.end, list.timeZone, locale), joiner),
    href: pageUrl(item.recordId)
  }));
  return { title: list.title || '', empty: list.empty || '', items };
}

/** The Site address of one record's page, beside the current page: `FormsPublic?record=<id>`. */
export function sitePageUrl(recordId) {
  return `FormsPublic?record=${encodeURIComponent(recordId)}`;
}
