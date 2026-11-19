import { LightningElement, api } from 'lwc';
import { helpText } from 'c/barnHelpText';
import { COUNTED_RANGES, normalizeRange } from 'c/reportingModel';

const NONE = '';

/**
 * A date range for Advanced Reporting: a named range (This Month, Last 12 Months, Between N and
 * M Days Ago) or From and To dates. Used by the report builder and by a dashboard's date filter.
 * Fires `change` with `{ value }`: `{ range, n, m, from, to }`, or null for Any Time.
 */
export default class ReportingRange extends LightningElement {
  @api label = '';
  @api disabled = false;

  /** Whether the person can pick Any Time (no range). */
  @api allowAny = false;

  current = { range: NONE };

  @api
  get value() {
    return this.current.range ? this.current : null;
  }
  set value(next) {
    this.current = normalizeRange(next) || { range: NONE };
  }

  get rangeOptions() {
    const options = [
      { value: 'TODAY', label: helpText('Reporting', 'Reporting_Range_Today') },
      { value: 'YESTERDAY', label: helpText('Reporting', 'Reporting_Range_Yesterday') },
      { value: 'THIS_WEEK', label: helpText('Reporting', 'Reporting_Range_ThisWeek') },
      { value: 'LAST_WEEK', label: helpText('Reporting', 'Reporting_Range_LastWeek') },
      { value: 'THIS_MONTH', label: helpText('Reporting', 'Reporting_Range_ThisMonth') },
      { value: 'LAST_MONTH', label: helpText('Reporting', 'Reporting_Range_LastMonth') },
      { value: 'THIS_QUARTER', label: helpText('Reporting', 'Reporting_Range_ThisQuarter') },
      { value: 'LAST_QUARTER', label: helpText('Reporting', 'Reporting_Range_LastQuarter') },
      { value: 'THIS_YEAR', label: helpText('Reporting', 'Reporting_Range_ThisYear') },
      { value: 'LAST_YEAR', label: helpText('Reporting', 'Reporting_Range_LastYear') },
      { value: 'LAST_N_DAYS', label: helpText('Reporting', 'Reporting_Range_LastNDays') },
      { value: 'NEXT_N_DAYS', label: helpText('Reporting', 'Reporting_Range_NextNDays') },
      { value: 'LAST_N_MONTHS', label: helpText('Reporting', 'Reporting_Range_LastNMonths') },
      { value: 'BETWEEN_DAYS_AGO', label: helpText('Reporting', 'Reporting_Range_BetweenDaysAgo') },
      { value: 'CUSTOM', label: helpText('Reporting', 'Reporting_Range_Custom') }
    ];
    return this.allowAny
      ? [{ value: NONE, label: helpText('Reporting', 'Reporting_Range_Any') }, ...options]
      : options;
  }

  get showCount() {
    return COUNTED_RANGES.includes(this.current.range);
  }

  get countLabel() {
    if (this.current.range === 'LAST_N_MONTHS') {
      return helpText('Reporting', 'Reporting_Range_Months');
    }
    return this.current.range === 'BETWEEN_DAYS_AGO'
      ? helpText('Reporting', 'Reporting_Range_From')
      : helpText('Reporting', 'Reporting_Range_Days');
  }

  get showSecond() {
    return this.current.range === 'BETWEEN_DAYS_AGO';
  }

  get showDates() {
    return this.current.range === 'CUSTOM';
  }

  get labels() {
    return {
      to: helpText('Reporting', 'Reporting_Range_To'),
      fromDate: helpText('Reporting', 'Reporting_Range_FromDate'),
      toDate: helpText('Reporting', 'Reporting_Range_ToDate')
    };
  }

  handleRange(event) {
    this.update({ range: event.detail.value });
  }

  handlePart(event) {
    const part = event.target.dataset.part;
    const raw = event.detail.value;
    this.update({
      ...this.current,
      [part]: part === 'from' || part === 'to' ? raw || '' : Number(raw)
    });
  }

  update(next) {
    this.current = normalizeRange(next) || { range: NONE };
    this.dispatchEvent(new CustomEvent('change', { detail: { value: this.value } }));
  }
}
