import { createElement } from 'lwc';
import ReportingRange from 'c/reportingRange';
import { expectAccessible } from 'barn/a11y';

function mount(props) {
  const element = createElement('c-reporting-range', { is: ReportingRange });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-reporting-range', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('picks a named range and asks for a count where it needs one', async () => {
    const element = mount({ label: 'Gift Date', allowAny: true });
    const handler = jest.fn();
    element.addEventListener('change', handler);
    await Promise.resolve();
    const kind = find(element, 'kind');
    expect(kind.options[0].value).toBe('');
    expect(kind.options).toHaveLength(16);
    await expectAccessible(element);

    kind.dispatchEvent(new CustomEvent('change', { detail: { value: 'LAST_N_DAYS' } }));
    await Promise.resolve();
    expect(handler.mock.calls[0][0].detail.value).toEqual({ range: 'LAST_N_DAYS', n: 30 });
    const n = find(element, 'n');
    expect(n.label).toBe('c.Reporting_Range_Days');
    n.dispatchEvent(new CustomEvent('change', { detail: { value: '7' } }));
    expect(handler.mock.calls[1][0].detail.value).toEqual({ range: 'LAST_N_DAYS', n: 7 });

    kind.dispatchEvent(new CustomEvent('change', { detail: { value: '' } }));
    expect(handler.mock.calls[2][0].detail.value).toBeNull();
  });

  it('takes two numbers for days ago and two dates for a custom range', async () => {
    const element = mount({ value: { range: 'BETWEEN_DAYS_AGO', n: 365, m: 182 } });
    await Promise.resolve();
    expect(find(element, 'n').label).toBe('c.Reporting_Range_From');
    expect(find(element, 'm').value).toBe(182);
    expect(find(element, 'kind').options).toHaveLength(15);

    element.value = { range: 'LAST_N_MONTHS', n: 12 };
    await Promise.resolve();
    expect(find(element, 'n').label).toBe('c.Reporting_Range_Months');
    expect(find(element, 'm')).toBeNull();

    element.value = { range: 'CUSTOM', from: '2026-01-01' };
    await Promise.resolve();
    const handler = jest.fn();
    element.addEventListener('change', handler);
    find(element, 'to').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2026-03-31' } })
    );
    expect(handler.mock.calls[0][0].detail.value).toEqual({
      range: 'CUSTOM',
      from: '2026-01-01',
      to: '2026-03-31'
    });
    expect(element.value.range).toBe('CUSTOM');
  });
});
