import { createElement } from 'lwc';
import FindExportFiles from 'c/findExportFiles';
import startServerExport from '@salesforce/apex/FindController.startServerExport';
import serverExportStatus from '@salesforce/apex/FindController.serverExportStatus';

jest.mock('@salesforce/apex/FindController.startServerExport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.serverExportStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_Find_ExportFilesProgress',
  () => ({ default: 'Exporting: {0} of {1} chunks done.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Find_ExportFilesDone',
  () => ({ default: 'Ready: {0} files.' }),
  {
    virtual: true
  }
);

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
    expect(one(element, 'status-line').textContent).toBe('Exporting: 1 of 4 chunks done.');

    poll();
    await flush();
    expect(serverExportStatus).toHaveBeenCalledWith({ jobId: '707000000000001', tag: 'abc123' });
    expect(one(element, 'status-line').textContent).toBe('Ready: 2 files.');
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
    expect(one(element, 'error-message').textContent).toBe('This object is not available.');
    expect(one(element, 'export-files-status')).toBeNull();
  });
});
