import { createElement } from 'lwc';
import LogicModelReport from 'c/logicModelReport';
import { downloadCsv, saveBlob } from 'c/findCsv';

import reportPdf from '@salesforce/apex/LogicModelBuilderController.reportPdf';

jest.mock('c/findCsv', () => ({
  ...jest.requireActual('c/findCsv'),
  downloadCsv: jest.fn(),
  saveBlob: jest.fn()
}));

jest.mock(
  '@salesforce/apex/LogicModelBuilderController.reportPdf',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const period = (id, name, startDate, endDate, targetValue, resultValue) => ({
  id,
  name,
  startDate,
  endDate,
  targetValue,
  resultValue
});

const model = (extra = {}) => ({
  id: 'm1',
  name: 'Reading',
  elements: [{ id: 'o1', name: 'Sessions held', type: 'Output', sortOrder: 10 }],
  links: [],
  indicators: [
    {
      id: 'i1',
      elementId: 'o1',
      name: 'Sessions',
      unit: 'sessions',
      baselineValue: 0,
      periods: [
        period('p1', 'Q1', '2026-01-01', '2026-03-31', 10, 10),
        period('p2', 'Q2', '2026-04-01', '2026-06-30', 10, 5),
        period('p3', 'Q3', '2026-07-01', '2026-09-30', 10, null),
        period('p4', 'Q4', '2026-10-01', '2026-12-31', 10, null),
        period('p5', 'Q5', '2027-01-01', '2027-03-31', 10, null)
      ]
    }
  ],
  ...extra
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(value = model()) {
  const element = createElement('c-logic-model-report', { is: LogicModelReport });
  element.model = value;
  element.scopeName = 'The whole organization';
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('c-logic-model-report', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens on the latest four periods, one row per indicator', async () => {
    const element = await render();
    const picker = q(element, 'report-periods');
    expect(picker.options).toHaveLength(5);
    expect(picker.value).toHaveLength(4);
    expect(qa(element, 'report-period')).toHaveLength(4);
    expect(qa(element, 'report-row')).toHaveLength(1);
    const progress = qa(element, 'report-progress');
    expect(progress[0].textContent).toBe('50%');
  });

  it('shows only the periods chosen', async () => {
    const element = await render();
    const picker = q(element, 'report-periods');
    picker.dispatchEvent(
      new CustomEvent('change', { detail: { value: [picker.options[0].value] } })
    );
    await flush();
    expect(qa(element, 'report-period')).toHaveLength(1);
    expect(qa(element, 'report-progress')[0].textContent).toBe('c.LogicModels_Period_Met');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: [] } }));
    await flush();
    expect(q(element, 'report-choose')).not.toBeNull();
    expect(q(element, 'report-csv').disabled).toBe(true);
  });

  it('downloads the CSV and the printable page', async () => {
    const element = await render();
    q(element, 'report-csv').click();
    expect(downloadCsv).toHaveBeenCalledTimes(1);
    const [fileBase, columns, rows] = downloadCsv.mock.calls[0];
    expect(fileBase).toBe('Logic_Model_Report');
    expect(columns).toHaveLength(7 + 4 * 3);
    expect(rows).toHaveLength(1);
    q(element, 'report-print').click();
    expect(saveBlob).toHaveBeenCalledTimes(1);
    const [blob, name] = saveBlob.mock.calls[0];
    expect(blob.type).toBe('text/html;charset=utf-8');
    expect(name).toMatch(/^Logic_Model_Report-.*\.html$/);
    await flush();
    expect(q(element, 'report-result').textContent.trim()).toBe('c.Core_Shared_ReportDownloaded');
  });

  it('downloads a PDF of the printable page made by the server (L-04b)', async () => {
    reportPdf.mockResolvedValue(btoa('%PDF-1.4'));
    const element = await render();
    q(element, 'report-pdf').click();
    await flush();
    expect(reportPdf).toHaveBeenCalledTimes(1);
    expect(reportPdf.mock.calls[0][0].html.startsWith('<!doctype html>')).toBe(true);
    expect(reportPdf.mock.calls[0][0].html).toContain('@page { size: landscape;');
    const [blob, name] = saveBlob.mock.calls[0];
    expect(blob.type).toBe('application/pdf');
    expect(blob.size).toBe(8);
    expect(name).toMatch(/^Logic_Model_Report-.*\.pdf$/);
    expect(q(element, 'report-pdf-error')).toBeNull();
  });

  it('shows why a PDF was not made', async () => {
    reportPdf.mockRejectedValue({ body: { message: 'Not made.' } });
    const element = await render();
    q(element, 'report-pdf').click();
    await flush();
    expect(saveBlob).not.toHaveBeenCalled();
    expect(q(element, 'report-pdf-error').textContent.trim()).toBe('Not made.');
    expect(q(element, 'report-pdf').disabled).toBe(false);
  });

  it('keeps the choice when the model is saved and drops periods that are gone', async () => {
    const element = await render();
    const picker = q(element, 'report-periods');
    const [first, second] = picker.options.map((option) => option.value);
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: [first, second] } }));
    await flush();
    element.model = model();
    await flush();
    expect(q(element, 'report-periods').value).toEqual([first, second]);
    const changed = model();
    changed.indicators[0].periods = changed.indicators[0].periods.slice(1);
    element.model = changed;
    await flush();
    expect(q(element, 'report-periods').value).toEqual([second]);
  });

  it('says when there are no periods or no indicators', async () => {
    const noPeriods = await render(
      model({ indicators: [{ id: 'i1', elementId: 'o1', name: 'Sessions', periods: [] }] })
    );
    expect(q(noPeriods, 'report-no-periods')).not.toBeNull();
    expect(q(noPeriods, 'report-csv')).toBeNull();
    document.body.removeChild(noPeriods);
    const none = await render(model({ indicators: [] }));
    expect(q(none, 'report-no-indicators')).not.toBeNull();
    expect(q(none, 'report-table')).toBeNull();
  });
});
