import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import {
  MAX_FILE_BYTES,
  REASONS,
  checkRows,
  countRows,
  groupRows,
  idsToCheck,
  isRecordId,
  markUnseen,
  readManifest,
  toBase64
} from 'c/filesImportModel';

global.TextDecoder = global.TextDecoder || NodeTextDecoder;
const encoder = new NodeTextEncoder();

const CONTACT = '0035g00000AbCdEAAV';
const ACCOUNT = '001Hp00002XyZaBIAV';

/** A stand-in for an opened zip (c/zipReader): file names, their sizes, and their bytes. */
function zipOf(files) {
  const names = Object.keys(files);
  return {
    names,
    sizeOf: (name) => (typeof files[name] === 'number' ? files[name] : (files[name] || '').length),
    read: async (name) => (name in files ? encoder.encode(String(files[name])) : null)
  };
}

describe('c/filesImportModel', () => {
  it('reads the manifest headings in any case and spacing, and numbers rows as lines', async () => {
    const rows = await readManifest(
      zipOf({
        'MANIFEST.csv': `record id;FILE;Title\n${CONTACT};letters\\a.pdf;Pledge\n;;\n${ACCOUNT};./b.jpg;`
      })
    );
    expect(rows).toEqual([
      {
        row: 2,
        file: 'letters/a.pdf',
        recordId: CONTACT,
        title: 'Pledge',
        description: '',
        reason: null
      },
      { row: 4, file: 'b.jpg', recordId: ACCOUNT, title: '', description: '', reason: null }
    ]);
  });

  it('refuses a zip with no manifest, no headings or no rows', async () => {
    await expect(readManifest(zipOf({ 'a.pdf': 'x' }))).rejects.toMatchObject({
      reason: REASONS.noManifest
    });
    await expect(readManifest(zipOf({ 'manifest.csv': 'Name,Id\nx,y' }))).rejects.toMatchObject({
      reason: REASONS.noHeadings
    });
    await expect(readManifest(zipOf({ 'manifest.csv': 'File,Record Id\n' }))).rejects.toMatchObject(
      { reason: REASONS.noRows }
    );
  });

  it('checks each row in the browser and then marks the records the server did not find', () => {
    const zip = zipOf({
      'a.pdf': 'pdf',
      'empty.txt': '',
      'big.pdf': MAX_FILE_BYTES + 1,
      'b.pdf': 'pdf'
    });
    const rows = [
      { row: 2, file: 'a.pdf', recordId: CONTACT },
      { row: 3, file: 'missing.pdf', recordId: CONTACT },
      { row: 4, file: 'empty.txt', recordId: CONTACT },
      { row: 5, file: 'big.pdf', recordId: CONTACT },
      { row: 6, file: 'b.pdf', recordId: 'not-an-id' },
      { row: 7, file: 'a.pdf', recordId: CONTACT },
      { row: 8, file: 'b.pdf', recordId: ACCOUNT }
    ];
    const checked = checkRows(rows, zip);
    expect(checked.map((row) => row.reason)).toEqual([
      null,
      REASONS.notInZip,
      REASONS.empty,
      REASONS.tooLarge,
      REASONS.recordId,
      REASONS.repeated,
      null
    ]);
    expect(idsToCheck(checked)).toEqual([CONTACT, ACCOUNT]);
    const marked = markUnseen(checked, [ACCOUNT]);
    expect(marked[6].reason).toBe(REASONS.unseen);
    expect(countRows(marked)).toEqual({ ready: 1, refused: 6 });
  });

  it('groups the ready rows by count and by size', () => {
    const rows = [];
    for (let index = 0; index < 25; index++) {
      rows.push({ row: index + 2, file: `f${index}`, recordId: CONTACT, reason: null });
    }
    rows.push({ row: 99, file: 'refused', recordId: CONTACT, reason: REASONS.empty });
    expect(groupRows(rows, () => 10).map((group) => group.length)).toEqual([20, 5]);
    expect(groupRows(rows.slice(0, 3), () => MAX_FILE_BYTES).map((group) => group.length)).toEqual([
      1, 1, 1
    ]);
  });

  it('knows an Id when it sees one and writes base64', () => {
    expect(isRecordId(CONTACT)).toBe(true);
    expect(isRecordId('0035g00000AbCdE')).toBe(true);
    expect(isRecordId('0035g00000AbCd')).toBe(false);
    expect(toBase64(encoder.encode('Hello'))).toBe('SGVsbG8=');
  });
});
