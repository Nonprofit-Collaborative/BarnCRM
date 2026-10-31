import { parseCsv, detectDelimiter } from './csv';
import { isXlsx, readXlsx, readSheetNames } from './xlsx';

/**
 * Where an import's rows come from: a source turns what the user gave into sheets of rows,
 * `[{ name, rows }]`, each row an array of text. An uploaded file is the only source today; a
 * later one (a shared spreadsheet, a scheduled file, C-38) returns the same shape, and nothing
 * after this point knows which source it was (C-49a).
 *
 * A text file is one sheet with no name. A workbook is every sheet, in tab order (ADR-NEXT,
 * amending ADR-0049). Errors are the readers' own, for the wizard to put into words.
 *
 * @param {File} file the uploaded file
 * @param {object} [options] `delimiter`, the text file's separator, detected when left out
 * @returns {Promise<{sheets: object[], delimiter: string}>} the sheets, and the separator used
 */
export async function readFileSheets(file, options = {}) {
  if (isXlsx(file.name)) {
    const buffer = await readAs(file, 'readAsArrayBuffer');
    const names = await readSheetNames(buffer);
    const sheets = [];
    for (const name of names) {
      // One sheet at a time keeps one sheet's XML in memory at once.
      // eslint-disable-next-line no-await-in-loop
      sheets.push({ name, rows: await readXlsx(buffer, { sheet: name }) });
    }
    return { sheets, delimiter: undefined };
  }
  const text = await readAs(file, 'readAsText');
  const delimiter = options.delimiter || detectDelimiter(text);
  return { sheets: [{ name: '', rows: parseCsv(text, delimiter) }], delimiter };
}

function readAs(file, method) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader[method](file);
  });
}
