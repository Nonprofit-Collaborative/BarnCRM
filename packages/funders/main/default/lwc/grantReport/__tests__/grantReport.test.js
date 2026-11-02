import { createElement } from 'lwc';
import GrantReport from 'c/grantReport';
import getReportData from '@salesforce/apex/GrantReportController.getReportData';
import { saveBlob } from 'c/findCsv';

jest.mock('@salesforce/apex/GrantReportController.getReportData', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('c/findCsv', () => ({
  saveBlob: jest.fn(),
  fileName: jest.fn(() => 'Funder_Report.html')
}));
jest.mock(
  '@salesforce/label/c.Funders_Report_Downloaded',
  () => ({ default: 'Report downloaded.' }),
  {
    virtual: true
  }
);

const DATA = {
  templates: [
    { id: 't1', name: 'Grant report', body: '<h1>{GrantName}</h1>{RequirementTable}' },
    { id: 't2', name: 'Short', body: '<p>{FunderName}</p>' }
  ],
  grant: { GrantName: 'Reading <Grant>', FunderName: 'Lakeside' },
  requirements: [
    { name: 'Final report', type: 'Narrative Report', dueDate: '2027-01-31', status: 'Not Started' }
  ],
  requirementLabels: { name: 'Requirement Name' },
  outcomes: [],
  currencyCode: 'USD'
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getReportData.mockResolvedValue(data);
  const element = createElement('c-grant-report', { is: GrantReport });
  element.recordId = 'g1';
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);

function blobText(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsText(blob);
  });
}

describe('c-grant-report', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the templates and downloads the merged report', async () => {
    const element = await render();
    expect(one(element, '[data-id="template"]').options.map((o) => o.label)).toEqual([
      'Grant report',
      'Short'
    ]);
    one(element, '[data-id="download"]').click();
    await flush();
    expect(saveBlob).toHaveBeenCalledTimes(1);
    const html = await blobText(saveBlob.mock.calls[0][0]);
    expect(html).toContain('<h1>Reading &lt;Grant&gt;</h1>');
    expect(html).toContain('<th>Requirement Name</th>');
    expect(html).toContain('<title>Grant report: Reading &lt;Grant&gt;</title>');
    expect(one(element, '[data-id="result"]').textContent).toBe('Report downloaded.');
  });

  it('uses the template chosen', async () => {
    const element = await render();
    one(element, '[data-id="template"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 't2' } })
    );
    one(element, '[data-id="download"]').click();
    await flush();
    const html = await blobText(saveBlob.mock.calls[0][0]);
    expect(html).toContain('<p>Lakeside</p>');
  });

  it('says when there is no template, and shows a load error', async () => {
    let element = await render({ ...DATA, templates: [] });
    expect(one(element, '[data-id="no-templates"]')).not.toBeNull();
    expect(one(element, '[data-id="download"]')).toBeNull();
    document.body.removeChild(element);

    getReportData.mockRejectedValue({ body: { message: 'Broken' } });
    element = createElement('c-grant-report', { is: GrantReport });
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent).toBe('Broken');
  });
});
