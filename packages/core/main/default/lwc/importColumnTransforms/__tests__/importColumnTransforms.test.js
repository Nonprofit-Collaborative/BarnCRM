import { createElement } from 'lwc';
import ImportColumnTransforms from 'c/importColumnTransforms';
import previewChanges from '@salesforce/apex/ImportController.previewChanges';

jest.mock('@salesforce/apex/ImportController.previewChanges', () => ({ default: jest.fn() }), {
  virtual: true
});

const ROWS = [
  { First: 'ana', Middle: 'M', Last: 'Ramirez' },
  { First: 'ben', Middle: '', Last: 'Okafor' }
];

function flush() {
  let chain = Promise.resolve();
  for (let i = 0; i < 6; i++) {
    chain = chain.then(() => Promise.resolve());
  }
  return chain;
}

function render(transforms = []) {
  const element = createElement('c-import-column-transforms', { is: ImportColumnTransforms });
  Object.assign(element, {
    source: 'First',
    columnNames: ['First', 'Middle', 'Last'],
    sampleRows: ROWS,
    transforms
  });
  document.body.appendChild(element);
  return element;
}

function steps(element) {
  return element.shadowRoot.querySelectorAll('[data-id="step"]');
}

function input(element, name, index = 0) {
  return steps(element)[index].querySelector(`[data-name="${name}"]`);
}

function change(target, value) {
  if (target.type === 'checkbox') {
    target.checked = value;
    target.dispatchEvent(new CustomEvent('change'));
  } else {
    target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  }
}

describe('the changes to one column', () => {
  let changes;

  beforeEach(() => {
    previewChanges.mockResolvedValue({
      problems: [],
      samples: [{ rowNumber: 2, column: 'First', before: 'ana', after: 'Ana' }]
    });
    changes = [];
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function listen(element) {
    element.addEventListener('change', (event) => changes.push(event.detail));
  }

  it('shows the saved changes and the first values before and after', async () => {
    const element = render([{ op: 'proper' }]);
    await flush();
    expect(steps(element)).toHaveLength(1);
    expect(input(element, 'op').value).toBe('proper');
    expect(previewChanges).toHaveBeenCalledWith({
      source: 'First',
      transformsJson: JSON.stringify([{ op: 'proper' }]),
      sampleRowsJson: JSON.stringify(ROWS)
    });
    const samples = element.shadowRoot.querySelectorAll('[data-id="sample"]');
    expect(samples).toHaveLength(1);
    expect(samples[0].textContent).toContain('Ana');
    expect(element.shadowRoot.querySelector('table').getAttribute('aria-label')).toBe(
      'c.Core_Import_ChangesPreviewHeading'
    );
  });

  it('offers every kind of change, and the other columns to add', async () => {
    const element = render([{ op: 'append', columns: ['Last'] }]);
    await flush();
    expect(input(element, 'op').options.map((option) => option.value)).toEqual([
      'trim',
      'upper',
      'lower',
      'proper',
      'replace',
      'ifBlank',
      'append',
      'date'
    ]);
    const columns = input(element, 'columns');
    expect(columns.options.map((option) => option.value)).toEqual(['Middle', 'Last']);
    expect(columns.value).toEqual(['Last']);
  });

  it('adds a change and sends only what each kind reads', async () => {
    const element = render();
    listen(element);
    await flush();
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    change(input(element, 'op'), 'replace');
    await flush();
    change(input(element, 'text'), 'St.');
    change(input(element, 'replaceWith'), 'Street');
    change(input(element, 'wholeValue'), true);
    await flush();
    expect(changes[changes.length - 1]).toEqual({
      source: 'First',
      transforms: [
        { op: 'replace', text: 'St.', replaceWith: 'Street', matchCase: false, wholeValue: true }
      ]
    });
    change(input(element, 'op'), 'date');
    await flush();
    expect(changes[changes.length - 1].transforms).toEqual([{ op: 'date', dateOrder: 'MDY' }]);
    expect(previewChanges).toHaveBeenLastCalledWith(
      expect.objectContaining({
        transformsJson: JSON.stringify([{ op: 'date', dateOrder: 'MDY' }])
      })
    );
  });

  it('removes a change, and allows no more than ten', async () => {
    const ten = Array.from({ length: 10 }, () => ({ op: 'trim' }));
    const element = render(ten);
    listen(element);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add"]').disabled).toBe(true);
    steps(element)[0].querySelector('[data-id="remove"]').click();
    await flush();
    expect(steps(element)).toHaveLength(9);
    expect(changes[0].transforms).toHaveLength(9);
    expect(element.shadowRoot.querySelector('[data-id="add"]').disabled).toBe(false);
  });

  it('says what stops the changes saving', async () => {
    previewChanges.mockResolvedValue({
      problems: ['Value when empty needs a value.'],
      samples: []
    });
    const element = render([{ op: 'ifBlank', value: '' }]);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="problems"]').textContent).toContain(
      'Value when empty needs a value.'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="sample"]')).toHaveLength(0);
  });

  it('says so when the preview fails, rather than showing nothing', async () => {
    previewChanges.mockRejectedValue({ body: { message: 'No access.' } });
    const element = render([{ op: 'trim' }]);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="problems"]').textContent).toContain(
      'No access.'
    );
  });

  it('keeps its steps when handed back what it sent, and previews another column afresh', async () => {
    const element = render([{ op: 'upper' }]);
    await flush();
    const before = steps(element)[0];
    element.transforms = [{ op: 'upper' }];
    await flush();
    expect(steps(element)[0]).toBe(before);
    previewChanges.mockClear();
    element.source = 'Last';
    element.transforms = [];
    await flush();
    expect(steps(element)).toHaveLength(0);
    expect(previewChanges).toHaveBeenCalledWith(expect.objectContaining({ source: 'Last' }));
  });

  it('tells the wizard when it is done', async () => {
    const element = render();
    const done = jest.fn();
    element.addEventListener('done', done);
    await flush();
    element.shadowRoot.querySelector('[data-id="done"]').click();
    expect(done).toHaveBeenCalledTimes(1);
  });

  it('inside bulk update: steps only, a record fields to add, and no preview of its own', async () => {
    const element = createElement('c-import-column-transforms', { is: ImportColumnTransforms });
    Object.assign(element, {
      embedded: true,
      source: 'Title',
      columnOptions: [
        { label: 'Title', value: 'Title' },
        { label: 'Last Name', value: 'LastName' }
      ],
      transforms: [{ op: 'append', columns: ['LastName'] }]
    });
    document.body.appendChild(element);
    listen(element);
    await flush();

    expect(previewChanges).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('h3')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="done"]')).toBeNull();
    expect(input(element, 'columns').options).toEqual([{ label: 'Last Name', value: 'LastName' }]);
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    expect(changes[0].transforms).toEqual([
      { op: 'append', columns: ['LastName'] },
      { op: 'trim' }
    ]);
    expect(previewChanges).not.toHaveBeenCalled();
  });
});
