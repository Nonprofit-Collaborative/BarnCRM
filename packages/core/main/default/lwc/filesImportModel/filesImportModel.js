/**
 * Import Files' browser logic (C-70, canonical model R-FI1 to R-FI3; ADR-0214
 * `0214-files-import.md`): reading `manifest.csv` from the zip, the checks that need no server,
 * and the groups the files are sent in. Plain JavaScript on plain values, so it is tested
 * without the platform and ports as is (plan 9.9).
 */
import { decodeUtf8 } from 'c/zipReader';
import { detectDelimiter, parseCsv } from 'c/csvParser';

export const MAX_FILES = 2000;
/** Matches FilesImportService: 2 MB a file, and 2 MB or 20 files a group. */
export const MAX_FILE_BYTES = 2 * 1024 * 1024;
export const MAX_GROUP_BYTES = 2 * 1024 * 1024;
export const MAX_GROUP_FILES = 20;
/** The most a manifest may hold; 2,000 rows of paths and Ids are far less. */
const MAX_MANIFEST_BYTES = 5 * 1024 * 1024;
const MANIFEST = 'manifest.csv';

/** Why a zip or a row is refused, as keys the panel turns into sentences. */
export const REASONS = {
  noManifest: 'noManifest',
  noHeadings: 'noHeadings',
  noRows: 'noRows',
  tooMany: 'tooMany',
  notInZip: 'notInZip',
  empty: 'empty',
  tooLarge: 'tooLarge',
  recordId: 'recordId',
  repeated: 'repeated',
  unseen: 'unseen'
};

export class ManifestError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

const HEADINGS = {
  file: 'file',
  recordid: 'recordId',
  title: 'title',
  description: 'description'
};

/** True for text shaped like a 15 or 18 character Salesforce record Id. */
export function isRecordId(text) {
  return /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(String(text || ''));
}

/**
 * The manifest's rows, each `{ row, file, recordId, title, description, reason }` with `row`
 * its line in the spreadsheet (the heading is line 1) and `reason` null until checked.
 *
 * @param {{names: string[], read: function}} zip an opened zip (c/zipReader)
 * @returns {Promise<object[]>} the rows
 */
export async function readManifest(zip) {
  const name = zip.names.find((entry) => entry.toLowerCase() === MANIFEST);
  if (!name) {
    throw new ManifestError(REASONS.noManifest);
  }
  const text = decodeUtf8(await zip.read(name, MAX_MANIFEST_BYTES));
  const lines = parseCsv(text, detectDelimiter(text));
  const columns = {};
  (lines[0] || []).forEach((heading, index) => {
    const key = HEADINGS[String(heading).replace(/\s+/g, '').toLowerCase()];
    if (key && columns[key] === undefined) {
      columns[key] = index;
    }
  });
  if (columns.file === undefined || columns.recordId === undefined) {
    throw new ManifestError(REASONS.noHeadings);
  }
  const cellOf = (line, key) => {
    return columns[key] === undefined ? '' : String(line[columns[key]] || '').trim();
  };
  const rows = lines
    .slice(1)
    .map((line, index) => ({
      row: index + 2,
      file: cellOf(line, 'file')
        .replace(/\\/g, '/')
        .replace(/^\.?\//, ''),
      recordId: cellOf(line, 'recordId'),
      title: cellOf(line, 'title'),
      description: cellOf(line, 'description'),
      reason: null
    }))
    .filter((row) => row.file || row.recordId);
  if (!rows.length) {
    throw new ManifestError(REASONS.noRows);
  }
  if (rows.length > MAX_FILES) {
    throw new ManifestError(REASONS.tooMany);
  }
  return rows;
}

/**
 * The checks the browser can make (R-FI2): the file is in the zip, not empty and not too
 * large, the Record Id has an Id's shape, and the same file and record are not on an earlier
 * row. Returns new rows with `reason` set, or null for a row that passed.
 */
export function checkRows(rows, zip) {
  const seen = new Set();
  return rows.map((row) => {
    let reason = null;
    const size = zip.sizeOf(row.file);
    const key = `${row.file}\n${row.recordId.toLowerCase()}`;
    if (!row.file || !zip.names.includes(row.file)) {
      reason = REASONS.notInZip;
    } else if (size === 0) {
      reason = REASONS.empty;
    } else if (size > MAX_FILE_BYTES) {
      reason = REASONS.tooLarge;
    } else if (!isRecordId(row.recordId)) {
      reason = REASONS.recordId;
    } else if (seen.has(key)) {
      reason = REASONS.repeated;
    }
    seen.add(key);
    return { ...row, reason };
  });
}

/** The Record Ids of the rows that passed, once each, for the server's check. */
export function idsToCheck(rows) {
  return [...new Set(rows.filter((row) => !row.reason).map((row) => row.recordId))];
}

/** The rows with those whose record the server did not find marked `unseen`. */
export function markUnseen(rows, unseenIds) {
  const unseen = new Set(unseenIds || []);
  return rows.map((row) => {
    return !row.reason && unseen.has(row.recordId) ? { ...row, reason: REASONS.unseen } : row;
  });
}

/** How many rows are ready and how many are refused. */
export function countRows(rows) {
  const ready = rows.filter((row) => !row.reason).length;
  return { ready, refused: rows.length - ready };
}

/**
 * The ready rows in the groups they are sent in: at most MAX_GROUP_FILES files and
 * MAX_GROUP_BYTES bytes each, in manifest order.
 */
export function groupRows(rows, sizeOf) {
  const groups = [];
  let current = [];
  let bytes = 0;
  for (const row of rows.filter((candidate) => !candidate.reason)) {
    const size = sizeOf(row.file);
    if (current.length && (current.length >= MAX_GROUP_FILES || bytes + size > MAX_GROUP_BYTES)) {
      groups.push(current);
      current = [];
      bytes = 0;
    }
    current.push(row);
    bytes += size;
  }
  if (current.length) {
    groups.push(current);
  }
  return groups;
}

/** Bytes as base64, in slices so a large file does not overflow the argument list. */
export function toBase64(bytes) {
  let binary = '';
  const slice = 0x8000;
  for (let start = 0; start < bytes.length; start += slice) {
    binary += String.fromCharCode.apply(null, bytes.subarray(start, start + slice));
  }
  return btoa(binary);
}
