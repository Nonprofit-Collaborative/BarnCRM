/**
 * Find's export to Files (C-36, canonical model R-SQ12, ADR-0115 `0115-find-export-to-files.md`),
 * run as the person who started it.
 *
 * - **At most the export limit.** The query locator is the document's filter in Id order, in
 *   user mode, with the limit as its LIMIT, so the server never reads past it (FINDA-6).
 * - **CSV parts in Files.** Rows are written as R-SQ3's CSV into a text buffer kept between
 *   chunks; a new `ContentVersion`, owned by the person, is written every `ROWS_PER_PART` rows or
 *   about `CHARS_PER_PART` characters, each with the header row. A `ContentVersion` cannot be
 *   appended to, and one transaction's heap cannot hold a large export.
 * - **Told when it is over.** The finish writes the last part and sends the Q-04 notification,
 *   opening the first file.
 */
public with sharing class FindExportBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Records per chunk: wide rows, so fewer than a query page. */
    public static final Integer SCOPE = 500;
    @TestVisible
    private static Integer rowsPerPart = 50000;
    @TestVisible
    private static Integer charsPerPart = 4000000;

    private static final String CRLF = '\r\n';
    private static final String BYTE_ORDER_MARK = String.fromCharArray(new List<Integer>{ 65279 });

    private final String queryJson;
    private final Map<String, String> labelsByPath;
    private final String tag;
    private final Integer rowLimit;
    private final Id recipientId;

    private List<String> paths = new List<String>();
    private String objectName;
    private String header;
    private List<String> buffer = new List<String>();
    private Integer bufferChars = 0;
    private Integer rowsInPart = 0;
    private Integer rowsWritten = 0;
    private Integer parts = 0;
    private Id firstDocumentId;
    private Boolean failed = false;

    /**
     * @param queryJson the Find query document
     * @param labelsByPath each column's label as the page shows it, by field path
     * @param tag six hex digits naming this export's files
     * @param rowLimit the export row limit
     */
    public FindExportBatch(
        String queryJson,
        Map<String, String> labelsByPath,
        String tag,
        Integer rowLimit
    ) {
        this.queryJson = queryJson;
        this.labelsByPath = new Map<String, String>();
        if (labelsByPath != null) {
            for (String path : labelsByPath.keySet()) {
                this.labelsByPath.put(path.toLowerCase(), labelsByPath.get(path));
            }
        }
        this.tag = tag;
        this.rowLimit = rowLimit;
        this.recipientId = JobNotifier.starter();
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        try {
            QueryCompiler.Compiled compiled = QueryCompiler.compileServerExport(
                queryJson,
                rowLimit
            );
            objectName = compiled.objectName;
            paths = compiled.fields;
            List<String> labels = new List<String>();
            for (String path : paths) {
                String label = labelsByPath.get(path.toLowerCase());
                labels.add(cell(String.isBlank(label) ? path : label, false));
            }
            header = String.join(labels, ',');
            return Database.getQueryLocatorWithBinds(
                compiled.soql,
                compiled.binds,
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            failed = true;
            if (!(e instanceof QueryCompiler.QueryCompilerException)) {
                ErrorLogger.log(e, 'FindExportBatch.start');
            }
            return Database.getQueryLocatorWithBinds(
                'SELECT Id FROM User WHERE Id = NULL',
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        try {
            for (SObject record : records) {
                List<String> cells = new List<String>();
                for (String path : paths) {
                    cells.add(valueCell(record, path));
                }
                String line = String.join(cells, ',');
                buffer.add(line);
                bufferChars += line.length() + 2;
                rowsInPart++;
                rowsWritten++;
                if (rowsInPart >= rowsPerPart || bufferChars >= charsPerPart) {
                    writePart();
                }
            }
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'FindExportBatch.execute');
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            if (!buffer.isEmpty() || parts == 0) {
                writePart();
            }
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'FindExportBatch.finish');
        }
        JobNotifier.aboutRecord(
            recipientId,
            System.Label.Core_JobNotice_FindExport,
            failed,
            String.format(
                System.Label.Core_JobNotice_FindExportBody,
                new List<Object>{ rowsWritten.format(), parts.format() }
            ),
            firstDocumentId
        );
    }

    /** Writes the buffer as the next part, with the header row, as a file the person owns. */
    private void writePart() {
        parts++;
        String title = titleOf(objectName, tag, parts);
        String body =
            BYTE_ORDER_MARK +
            (header == null ? '' : header) +
            CRLF +
            (buffer.isEmpty() ? '' : String.join(buffer, CRLF) + CRLF);
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.csv',
            VersionData = Blob.valueOf(body)
        );
        Database.insert(version, AccessLevel.USER_MODE);
        if (firstDocumentId == null) {
            firstDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
                WITH USER_MODE
                LIMIT 1
            ]
            .ContentDocumentId;
        }
        buffer = new List<String>();
        bufferChars = 0;
        rowsInPart = 0;
    }

    /** A part's title: `Contact-2026-10-13-a1b2c3-part-2`. */
    public static String titleOf(String objectName, String tag, Integer part) {
        return String.valueOf(objectName == null ? 'export' : objectName) +
            '-' +
            String.valueOf(Date.today()) +
            '-' +
            tag +
            '-part-' +
            part;
    }

    /** The cell for a field path such as `Account.Name`, as the page shows the value. */
    private static String valueCell(SObject record, String path) {
        List<String> names = path.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < names.size() - 1 && current != null; i++) {
            current = current.getSObject(names[i]);
        }
        Object value = current == null ? null : current.get(names[names.size() - 1]);
        if (value == null) {
            return '';
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        if (value instanceof Date) {
            return String.valueOf(value);
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).toPlainString();
        }
        Boolean numeric =
            value instanceof Integer ||
            value instanceof Long ||
            value instanceof Double;
        return cell(String.valueOf(value), numeric);
    }

    /**
     * One CSV cell as `c/findCsv` writes it (R-SQ3): text starting = + - @, a tab or a carriage
     * return gets a leading single quote, and a cell holding a comma, quote or line break is
     * quoted.
     */
    @TestVisible
    private static String cell(String text, Boolean numeric) {
        String result = text == null ? '' : text;
        if (!numeric && result.length() > 0 && '=+-@\t\r'.contains(result.left(1))) {
            result = '\'' + result;
        }
        if (
            result.contains(',') ||
            result.contains('"') ||
            result.contains('\r') ||
            result.contains('\n')
        ) {
            result = '"' + result.replace('"', '""') + '"';
        }
        return result;
    }
}
