import { createElement } from 'lwc';
import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import FilesImport from 'c/filesImport';
import check from '@salesforce/apex/FilesImportController.check';
import start from '@salesforce/apex/FilesImportController.start';
import addFiles from '@salesforce/apex/FilesImportController.addFiles';
import finish from '@salesforce/apex/FilesImportController.finish';
import undo from '@salesforce/apex/FilesImportController.undo';
import getJobs from '@salesforce/apex/FilesImportController.getJobs';
import { openZip } from 'c/zipReader';

global.TextDecoder = global.TextDecoder || NodeTextDecoder;
const encoder = new NodeTextEncoder();

jest.mock('@salesforce/apex/FilesImportController.check', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FilesImportController.start', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FilesImportController.addFiles', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FilesImportController.finish', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FilesImportController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FilesImportController.getJobs', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('c/zipReader', () => {
  const actual = jest.requireActual('c/zipReader');
  return { ...actual, openZip: jest.fn() };
});

const CONTACT = '0035g00000AbCdEAAV';
const GONE = '0035g00000ZzZzZAAV';
const FILES = {
  'manifest.csv': `File,Record Id,Title\na.pdf,${CONTACT},Pledge\nb.pdf,${GONE},\nmissing.pdf,${CONTACT},`,
  'a.pdf': 'first',
  'b.pdf': 'second'
};
const JOB = {
  id: 'a0B000000000010',
  name: 'IB-000010',
  fileName: 'letters.zip',
  status: 'Complete',
  saved: 1,
  refused: 0,
  canUndo: true
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-files-import', { is: FilesImport });
  document.body.appendChild(element);
  await flush();
  return element;
}

async function chooseZip(element) {
  const input = find(element, 'zip');
  Object.defineProperty(input, 'files', {
    value: [{ name: 'letters.zip', arrayBuffer: async () => new ArrayBuffer(1) }],
    configurable: true
  });
  input.dispatchEvent(new CustomEvent('change'));
  await flush();
  await flush();
}

describe('c-files-import', () => {
  beforeEach(() => {
    getJobs.mockResolvedValue([]);
    openZip.mockReturnValue({
      names: Object.keys(FILES),
      sizeOf: (name) => (FILES[name] || '').length,
      read: async (name) => (name in FILES ? encoder.encode(FILES[name]) : null)
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reads the manifest, checks every row, and loads only the ready ones', async () => {
    check.mockResolvedValue([GONE]);
    start.mockResolvedValue(JOB.id);
    addFiles.mockResolvedValue({ saved: 1, refusals: [] });
    finish.mockResolvedValue(JOB);
    const element = await render();
    await chooseZip(element);
    expect(find(element, 'manifest').textContent).toBe('c.Core_FilesImport_Read');
    expect(find(element, 'load').disabled).toBe(true);

    find(element, 'dry-run').click();
    await flush();
    expect(check).toHaveBeenCalledWith({ recordIds: [CONTACT, GONE] });
    expect(find(element, 'refused').querySelectorAll('tbody tr')).toHaveLength(2);

    getJobs.mockResolvedValue([JOB]);
    find(element, 'load').click();
    await flush();
    await flush();
    expect(start).toHaveBeenCalledWith({ fileName: 'letters.zip', rowCount: 1 });
    const sent = addFiles.mock.calls[0][0];
    expect(sent.jobId).toBe(JOB.id);
    expect(sent.files).toEqual([
      expect.objectContaining({ row: 2, recordId: CONTACT, fileName: 'a.pdf', title: 'Pledge' })
    ]);
    expect(sent.files[0].data).toBe('Zmlyc3Q=');
    expect(finish).toHaveBeenCalledWith({ jobId: JOB.id });
    expect(find(element, 'notice').message).toBe('c.Core_FilesImport_Done');
    expect(find(element, 'jobs')).not.toBeNull();
  });

  it('says what is wrong with a zip that has no manifest', async () => {
    openZip.mockReturnValue({ names: ['a.pdf'], sizeOf: () => 1, read: async () => null });
    const element = await render();
    await chooseZip(element);
    expect(find(element, 'error').message).toBe('c.Core_FilesImport_ErrorNoManifest');
    expect(find(element, 'dry-run')).toBeNull();
  });

  it('undoes a recent load once its file count is typed', async () => {
    getJobs.mockResolvedValue([JOB]);
    undo.mockResolvedValue({ ...JOB, status: 'Undone', canUndo: false });
    const element = await render();
    find(element, 'jobs').querySelector('lightning-button').click();
    await flush();
    expect(find(element, 'undo-button').disabled).toBe(true);
    const typed = find(element, 'undo-text');
    typed.dispatchEvent(new CustomEvent('change', { detail: { value: '1' } }));
    await flush();
    find(element, 'undo-button').click();
    await flush();
    expect(undo).toHaveBeenCalledWith({ jobId: JOB.id, confirmedFiles: 1 });
    expect(find(element, 'notice').message).toBe('c.Core_FilesImport_Undone');
  });
});
