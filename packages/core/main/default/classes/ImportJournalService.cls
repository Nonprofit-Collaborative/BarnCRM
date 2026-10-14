/**
 * The import journal (canonical model Section 17A): the changes an import made to records it
 * did not create, kept so an undo can put them back, and what an undo left in place and why.
 *
 * A page holds the entries of one chunk, so a large import leaves hundreds of journal records
 * rather than one per change (R-IJ1). A page that would overflow its attribute is split in
 * two, never shortened: a shortened entry is a change that can no longer be put back.
 *
 * Nothing here is allowed to fail an import (R-IJ4). The records a chunk saved are already
 * saved when its page is written, so a write that fails is logged and reported to the caller,
 * which says so in the run log, rather than thrown.
 */
@NamespaceAccessible
public with sharing class ImportJournalService {
    @NamespaceAccessible
    public static final String PHASE_COMMIT = 'Commit';
    @NamespaceAccessible
    public static final String PHASE_UNDO = 'Undo';
    /** The records a one-object import created, which carry no batch tag (R-IJ3, R-IT12). */
    @NamespaceAccessible
    public static final String PHASE_CREATED = 'Created';

    @NamespaceAccessible
    public static final String ACTION_UPDATED = 'Updated';
    @NamespaceAccessible
    public static final String ACTION_CREATED = 'Created';
    @NamespaceAccessible
    public static final String ACTION_KEPT = 'Kept';
    @NamespaceAccessible
    public static final String ACTION_NOT_RESTORED = 'NotRestored';
    /** A record a bulk update could not save (C-35). */
    @NamespaceAccessible
    public static final String ACTION_FAILED = 'Failed';
    /** A record a bulk delete deleted, which its undo brings back from the Recycle Bin (C-37). */
    @NamespaceAccessible
    public static final String ACTION_DELETED = 'Deleted';

    /** The document version written into every page, so a reader can tell the shape. */
    private static final Integer DOCUMENT_VERSION = 1;

    /** The size of the Entries attribute. A page is always written within it. */
    @TestVisible
    private static Integer maxDocumentLength = 131072;

    /**
     * The most entries one page holds, so an undo putting back one page stays inside one
     * transaction's limits (R-IJ1).
     */
    @TestVisible
    private static Integer maxEntriesPerPage = 200;

    /**
     * The most entries one Created page holds: an undo deletes a page's records in one
     * transaction, after reading each one's children (R-IJ3).
     */
    @TestVisible
    private static Integer maxCreatedPerPage = 100;

    /** The most pages a walk through one phase reads: the journal's own read limit. */
    @NamespaceAccessible
    public static final Integer MAX_PAGES_READ = 200;

    /**
     * Pages read per query on such a walk, each window released before the next: at most
     * about 2.6 MB of text at once, well inside the heap.
     */
    @TestVisible
    private static Integer pagesPerRead = 10;

    /** A created record: which object, which record, which file row (R-IJ3). */
    @NamespaceAccessible
    public static Map<String, Object> created(String objectName, Id recordId, Integer row) {
        return new Map<String, Object>{
            'action' => ACTION_CREATED,
            'object' => objectName,
            'id' => String.valueOf(recordId),
            'row' => row
        };
    }

    /** How long a label or a reason may be; neither is needed to put anything back. */
    private static final Integer MAX_TEXT_LENGTH = 255;

    /**
     * An update entry: which record, which file row, and for each attribute the value before
     * the import and the value it wrote, both as typed values (R-IJ2, R-IJ3).
     */
    @NamespaceAccessible
    public static Map<String, Object> updated(
        String objectName,
        Id recordId,
        Integer row,
        Map<String, Object> beforeByField,
        Map<String, Object> afterByField
    ) {
        Map<String, Object> fields = new Map<String, Object>();
        for (String field : afterByField.keySet()) {
            fields.put(
                field,
                new Map<String, Object>{
                    'before' => beforeByField.get(field),
                    'after' => afterByField.get(field)
                }
            );
        }
        return new Map<String, Object>{
            'action' => ACTION_UPDATED,
            'object' => objectName,
            'id' => String.valueOf(recordId),
            'row' => row,
            'fields' => fields
        };
    }

    /** A record an undo kept, and why. */
    @NamespaceAccessible
    public static Map<String, Object> kept(
        String objectName,
        Id recordId,
        String label,
        String reason
    ) {
        return new Map<String, Object>{
            'action' => ACTION_KEPT,
            'object' => objectName,
            'id' => String.valueOf(recordId),
            'label' => shorten(label),
            'reason' => shorten(reason)
        };
    }

    /** A record a bulk update could not save, and the platform's reason (R-IJ2, R-BU3). */
    @NamespaceAccessible
    public static Map<String, Object> failed(String objectName, Id recordId, String reason) {
        return new Map<String, Object>{
            'action' => ACTION_FAILED,
            'object' => objectName,
            'id' => String.valueOf(recordId),
            'reason' => shorten(reason)
        };
    }

    /** A record a bulk delete deleted, with its name for the undo to report (R-IJ2, R-BD3). */
    @NamespaceAccessible
    public static Map<String, Object> deleted(String objectName, Id recordId, String label) {
        return new Map<String, Object>{
            'action' => ACTION_DELETED,
            'object' => objectName,
            'id' => String.valueOf(recordId),
            'label' => shorten(label)
        };
    }

    /** A value an undo did not put back, and why. */
    @NamespaceAccessible
    public static Map<String, Object> notRestored(
        String objectName,
        Id recordId,
        String field,
        String reason
    ) {
        return new Map<String, Object>{
            'action' => ACTION_NOT_RESTORED,
            'object' => objectName,
            'id' => String.valueOf(recordId),
            'field' => field,
            'reason' => shorten(reason)
        };
    }

    /**
     * Writes the entries as one or more pages. Written in system mode for the reason ADR-0021
     * gives: the journal is the package's own bookkeeping and has to be written even where the
     * running user cannot edit it.
     *
     * @return true when everything was written (or there was nothing to write), false when a
     *         write failed or an entry was too large to keep; either is already in the Error Log
     */
    @NamespaceAccessible
    public static Boolean write(Id batchId, String phase, List<Map<String, Object>> entries) {
        if (batchId == null || entries == null || entries.isEmpty()) {
            return true;
        }
        try {
            List<Import_Journal__c> pages = new List<Import_Journal__c>();
            Integer paged = 0;
            String written = PHASE_UNDO.equals(phase) || PHASE_CREATED.equals(phase)
                ? phase
                : PHASE_COMMIT;
            Integer cap = written == PHASE_CREATED ? maxCreatedPerPage : maxEntriesPerPage;
            for (List<Map<String, Object>> page : paginate(entries, batchId, cap)) {
                paged += page.size();
                pages.add(
                    new Import_Journal__c(
                        Import_Batch__c = batchId,
                        Phase__c = written,
                        Entry_Count__c = page.size(),
                        Entries_JSON__c = document(page)
                    )
                );
            }
            if (!pages.isEmpty()) {
                Database.insert(pages, AccessLevel.SYSTEM_MODE);
            }
            return paged == entries.size();
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportJournalService.write', batchId);
            return false;
        }
    }

    /** The entries of one page, oldest first, or an empty list when the page cannot be read. */
    @NamespaceAccessible
    public static List<Map<String, Object>> entries(Import_Journal__c page) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (page == null || String.isBlank(page.Entries_JSON__c)) {
            return result;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                page.Entries_JSON__c
            );
            for (Object entry : (List<Object>) parsed.get('entries')) {
                result.add((Map<String, Object>) entry);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportJournalService.entries', page.Id);
        }
        return result;
    }

    /** How many entries one phase of a batch holds, summed from the pages (R-IJ1). */
    @NamespaceAccessible
    public static Integer entryCount(Id batchId, String phase) {
        if (batchId == null) {
            return 0;
        }
        List<AggregateResult> totals = Database.queryWithBinds(
            'SELECT SUM(Entry_Count__c) total FROM Import_Journal__c ' +
            'WHERE Import_Batch__c = :batchId AND Phase__c = :phase',
            new Map<String, Object>{ 'batchId' => batchId, 'phase' => phase },
            AccessLevel.SYSTEM_MODE
        );
        Object total = totals.isEmpty() ? null : totals[0].get('total');
        return total == null ? 0 : ((Decimal) total).intValue();
    }

    /**
     * How many entries of one action one phase of a batch holds, read from the pages (at most
     * 200 of them): what a job whose finish never counted its rows did, for example the records
     * an aborted bulk update saved, leaving out the ones it journaled as Failed.
     */
    @NamespaceAccessible
    public static Integer actionCount(Id batchId, String phase, String action) {
        return walk(batchId, phase, action, null, 0);
    }

    /**
     * The first `howMany` entries of one action in one phase, in the order they were written,
     * from at most MAX_PAGES_READ pages: for example the first refusals of a job, wherever in
     * the job they fell.
     */
    @NamespaceAccessible
    public static List<Map<String, Object>> firstWithAction(
        Id batchId,
        String phase,
        String action,
        Integer howMany
    ) {
        List<Map<String, Object>> kept = new List<Map<String, Object>>();
        if (howMany != null && howMany > 0) {
            walk(batchId, phase, action, kept, howMany);
        }
        return kept;
    }

    /**
     * Counts the entries of one action, and keeps the first `keep` of them in `kept` when it is
     * given, stopping once it has them. Reads a few pages at a time, so a long journal never
     * holds the heap, and parses only a page whose text names the action.
     */
    private static Integer walk(
        Id batchId,
        String phase,
        String action,
        List<Map<String, Object>> kept,
        Integer keep
    ) {
        Integer total = 0;
        if (batchId == null || action == null) {
            return total;
        }
        String marker = JSON.serialize(action);
        String after;
        Integer read = 0;
        while (read < MAX_PAGES_READ) {
            Integer asked = Math.min(pagesPerRead, MAX_PAGES_READ - read);
            List<Import_Journal__c> window = pagesAfter(batchId, phase, asked, after);
            for (Import_Journal__c page : window) {
                after = page.Name;
                if (page.Entries_JSON__c == null || !page.Entries_JSON__c.contains(marker)) {
                    continue;
                }
                for (Map<String, Object> entry : entries(page)) {
                    if (!action.equals(entry.get('action'))) {
                        continue;
                    }
                    total++;
                    if (kept != null) {
                        kept.add(entry);
                        if (kept.size() >= keep) {
                            return total;
                        }
                    }
                }
            }
            read += window.size();
            if (window.size() < asked) {
                break;
            }
        }
        return total;
    }

    /** The pages of one phase of a batch, in the order they were written. */
    @NamespaceAccessible
    public static List<Import_Journal__c> pages(Id batchId, String phase, Integer howMany) {
        return pagesAfter(batchId, phase, howMany, null);
    }

    /** As `pages`, starting after the page named `afterName`, or at the start when null. */
    private static List<Import_Journal__c> pagesAfter(
        Id batchId,
        String phase,
        Integer howMany,
        String afterName
    ) {
        Integer limitSize = howMany == null || howMany <= 0 ? 20 : Math.min(howMany, 200);
        return Database.queryWithBinds(
            'SELECT Id, Name, Phase__c, Entry_Count__c, Entries_JSON__c FROM Import_Journal__c ' +
                'WHERE Import_Batch__c = :batchId AND Phase__c = :phase ' +
                (afterName == null ? '' : 'AND Name > :afterName ') +
                'ORDER BY Name ASC LIMIT :limitSize',
            new Map<String, Object>{
                'batchId' => batchId,
                'phase' => phase,
                'limitSize' => limitSize,
                'afterName' => afterName
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Whether one entry fits a journal page on its own. An entry that does not is never
     * written (see `paginate`), so a caller that must be able to undo what it saves checks
     * this before saving.
     */
    @NamespaceAccessible
    public static Boolean fitsOnAPage(Map<String, Object> entry) {
        return document(new List<Map<String, Object>>{ entry }).length() <= maxDocumentLength;
    }

    /**
     * Splits the entries into pages that each fit the attribute and the entry cap, halving
     * until they do. A single entry too large for a page on its own is never cut short: it is
     * left out and written to the Error Log, and the others are still written (R-IJ1).
     */
    private static List<List<Map<String, Object>>> paginate(
        List<Map<String, Object>> entries,
        Id batchId,
        Integer cap
    ) {
        List<List<Map<String, Object>>> result = new List<List<Map<String, Object>>>();
        if (entries.size() <= cap && document(entries).length() <= maxDocumentLength) {
            result.add(entries);
            return result;
        }
        if (entries.size() == 1) {
            ErrorLogger.logMessage(
                Label.Core_Import_JournalEntryTooLarge,
                'ImportJournalService.write',
                ErrorLogger.SEVERITY_ERROR,
                batchId
            );
            return result;
        }
        Integer half = entries.size() / 2;
        List<Map<String, Object>> first = new List<Map<String, Object>>();
        List<Map<String, Object>> second = new List<Map<String, Object>>();
        for (Integer i = 0; i < entries.size(); i++) {
            (i < half ? first : second).add(entries[i]);
        }
        result.addAll(paginate(first, batchId, cap));
        result.addAll(paginate(second, batchId, cap));
        return result;
    }

    private static String document(List<Map<String, Object>> entries) {
        return JSON.serialize(
            new Map<String, Object>{ 'version' => DOCUMENT_VERSION, 'entries' => entries }
        );
    }

    private static String shorten(String value) {
        return String.isBlank(value) ? null : value.abbreviate(MAX_TEXT_LENGTH);
    }
}
