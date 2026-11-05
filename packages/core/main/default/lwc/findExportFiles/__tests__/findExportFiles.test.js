import { createElement } from 'lwc';
import FindExportFiles from 'c/findExportFiles';
import startServerExport from '@salesforce/apex/FindController.startServerExport';
import serverExportStatus from '@salesforce/apex/FindController.serverExportStatus';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Core_Find_ExportFilesDone: 'Ready: {0} files.'
});

jest.mock('@salesforce/apex/FindController.startServerExport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.serverExportStatus', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const RUNNING = {
  jobId: '707000000000001',
  tag: 'abc123',
  status: 'Processing',
  done: false,
  failed: false,
  chunksDone: 1,
  chunksTotal: 4,
  files: []
};

const FINISHED = {
  ...RUNNING,
  status: 'Completed',
  done: true,
  chunksDone: 4,
  files: [
    { documentId: '069000000000001', title: 'Contact-2026-10-13-abc123-part-1', size: 10 },
    { documentId: '069000000000002', title: 'Contact-2026-10-13-abc123-part-2', size: 10 }
  ]
};

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-find-export-files', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('shows nothing until Find starts an export, then follows it to its files', async () => {
    startServerExport.mockResolvedValue(RUNNING);
    serverExportStatus.mockResolvedValue(FINISHED);
    let poll;
    jest.spyOn(window, 'setInterval').mockImplementation((callback) => {
      poll = callback;
      return 1;
    });
    jest.spyOn(window, 'clearInterval').mockImplementation(() => {});
    const element = createElement('c-find-export-files', { is: FindExportFiles });
    document.body.appendChild(element);
    await flush();
    expect(one(element, 'export-files-status')).toBeNull();

    await element.start('{"version":1}', { LastName: 'Last Name' });
    await flush();
    expect(startServerExport).toHaveBeenCalledWith({
      queryJson: '{"version":1}',
      labelsJson: '{"LastName":"Last Name"}'
    });
    // While it runs, a bar shows the share written, in percent (not parts).
    const meter = one(element, 'export-meter');
    expect(meter.value).toBe(25);
    expect(meter.valueText).toBe('c.Core_Find_ExportFilesProgress');
    expect(one(element, 'status-notice')).toBeNull();

    poll();
    await flush();
    expect(serverExportStatus).toHaveBeenCalledWith({ jobId: '707000000000001', tag: 'abc123' });
    expect(one(element, 'export-meter')).toBeNull();
    expect(one(element, 'status-notice').message).toBe('Ready: 2 files.');
    expect(one(element, 'status-notice').variant).toBe('success');
    const links = [...element.shadowRoot.querySelectorAll('[data-id="file"] a')];
    expect(links.map((link) => link.getAttribute('href'))).toEqual([
      '/sfc/servlet.shepherd/document/download/069000000000001',
      '/sfc/servlet.shepherd/document/download/069000000000002'
    ]);
  });

  it('shows a refusal', async () => {
    startServerExport.mockRejectedValue({ body: { message: 'This object is not available.' } });
    const element = createElement('c-find-export-files', { is: FindExportFiles });
    document.body.appendChild(element);
    await element.start('{}', {});
    await flush();
    expect(one(element, 'error-message').message).toBe('This object is not available.');
    expect(one(element, 'error-message').variant).toBe('error');
    expect(one(element, 'export-files-status')).toBeNull();
  });
});
