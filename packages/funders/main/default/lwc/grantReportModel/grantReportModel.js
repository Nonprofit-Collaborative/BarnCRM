/**
 * Funder reporting logic, with no framework in it (L-06 and F-06, canonical model 29ZI R-GQ6,
 * ADR-NEXT `NEXT-funders-reporting-links.md`, plan Section 9.9). Plain JavaScript in and out, so a
 * WordPress block or Node can use the same module. Dates arrive as ISO date strings.
 */

/** A number as the person's locale writes it, or the `notSet` word when there is none. */
export function showNumber(value, notSet = '') {
  if (value === null || value === undefined || value === '') {
    return notSet;
  }
  const number = Number(value);
  return Number.isNaN(number) ? String(value) : number.toLocaleString();
}

/**
 * The indicators of a linked outcome as lines to show: the indicator name with its unit, then one
 * line per period in the award period.
 *
 * @param {object} outcome `{indicators: [{id, name, unit, periods: [{name, target, result}]}]}`
 * @param {{periodLine: string, notSet: string}} words `periodLine` holds {0} period, {1} target
 *   and {2} result
 * @returns {{key: string, title: string, lines: {key: string, text: string}[]}[]} indicators with
 *   at least one period
 */
export function indicatorLines(outcome, words) {
  const indicators = (outcome && outcome.indicators) || [];
  return indicators
    .filter((indicator) => (indicator.periods || []).length > 0)
    .map((indicator) => ({
      key: indicator.id,
      title: indicator.unit ? `${indicator.name} (${indicator.unit})` : indicator.name,
      lines: indicator.periods.map((period, index) => ({
        key: `${indicator.id}-${index}`,
        text: [
          period.name,
          showNumber(period.target, words.notSet),
          showNumber(period.result, words.notSet)
        ].reduce((text, value, position) => text.replace(`{${position}}`, value), words.periodLine)
      }))
    }));
}
