/**
 * Skips rows of a file as it is staged (canonical model R-IT18; ADR-NEXT
 * `NEXT-import-row-rules.md`): a row a Skip rows rule matches, and a row whose One row per key
 * an earlier row of the same file already has. A skipped row is staged with Status Skipped and
 * the reason, so it is listed with the file's rows and no pass reads it again.
 *
 * Both rules read the cells as uploaded, before any column change, trimmed and ignoring
 * capitals. Nothing is evaluated: a rule is a column name, a test from a closed set and literal
 * text. A key is kept as a 64-bit digest on the row (`Row_Key__c`), so a later page of the file
 * finds an earlier row's key with one indexed query, however long the file.
 */
public with sharing class ImportRowFilter {
    /** The most Skip rows rules and key columns one mapping may have. */
    public static final Integer MAX_RULES = 5;
    /** The tests a Skip rows rule may use. */
    public static final Set<String> TESTS = new Set<String>{ 'equals', 'contains', 'blank' };

    private static final String KEY_DIGEST = 'row:';
    private static final String KEY_SEPARATOR = '\u001f';

    /** What is wrong with the mapping's row rules, one sentence each; empty when nothing. */
    public static List<String> problems(ImportMapping mapping) {
        List<String> result = new List<String>();
        List<ImportMapping.SkipRule> rules = mapping.skipRows == null
            ? new List<ImportMapping.SkipRule>()
            : mapping.skipRows;
        List<String> keys = mapping.uniqueBy == null ? new List<String>() : mapping.uniqueBy;
        if (rules.size() > MAX_RULES || keys.size() > MAX_RULES) {
            result.add(
                String.format(
                    Label.Core_Import_ErrorRowRulesTooMany,
                    new List<String>{ String.valueOf(MAX_RULES) }
                )
            );
        }
        for (ImportMapping.SkipRule rule : rules) {
            Boolean usable =
                rule != null &&
                String.isNotBlank(rule.column) &&
                rule.test != null &&
                TESTS.contains(rule.test) &&
                (rule.test == 'blank' || String.isNotBlank(rule.text)) &&
                (rule.text == null ||
                rule.text.length() <= DataTransform.MAX_TEXT);
            if (!usable) {
                result.add(Label.Core_Import_ErrorSkipRule);
                break;
            }
        }
        for (String key : keys) {
            if (String.isBlank(key)) {
                result.add(Label.Core_Import_ErrorUniqueBy);
                break;
            }
        }
        return result;
    }

    /**
     * Marks the rows of one staged page that the mapping skips, before they are inserted, and
     * works out the key digest of every other row that has one. Earlier pages are read by
     * digest, in system mode: the staged rows are the package's own bookkeeping (ADR-0021).
     *
     * @param batchId the import the rows belong to
     * @param rows the page's rows, not yet inserted, in file order
     * @param raw each row's uploaded values, in the same order
     * @return each row's key digest to keep in Row Key, in the same order; null for a row that
     *         is skipped or has no key. Not set on the rows, since the caller inserts them in
     *         user mode and the key is in no permission set.
     */
    public static List<String> apply(
        Id batchId,
        ImportMapping mapping,
        List<Import_Row__c> rows,
        List<Map<String, Object>> raw
    ) {
        List<ImportMapping.SkipRule> rules = mapping.skipRows == null
            ? new List<ImportMapping.SkipRule>()
            : mapping.skipRows;
        List<String> keys = mapping.uniqueBy == null ? new List<String>() : mapping.uniqueBy;
        List<String> digests = new List<String>();
        if ((rules.isEmpty() && keys.isEmpty()) || !problems(mapping).isEmpty()) {
            for (Import_Row__c row : rows) {
                digests.add(null);
            }
            return digests;
        }
        for (Integer i = 0; i < rows.size(); i++) {
            Map<String, String> cells = cells(raw[i]);
            String reason = skipReason(rules, cells);
            if (reason != null) {
                skip(rows[i], reason);
            }
            digests.add(reason == null ? digestOf(keys, cells) : null);
        }
        Map<String, Integer> seen = earlierRows(batchId, new Set<String>(digests));
        for (Integer i = 0; i < rows.size(); i++) {
            String digest = digests[i];
            if (digest == null) {
                continue;
            }
            Integer earlier = seen.get(digest);
            if (earlier != null) {
                skip(
                    rows[i],
                    String.format(
                        Label.Core_Import_SkippedRepeat,
                        new List<String>{ String.valueOf(earlier), String.join(keys, ', ') }
                    )
                );
                digests[i] = null;
                continue;
            }
            seen.put(digest, rows[i].Row_Number__c.intValue());
        }
        return digests;
    }

    /** The reason the first matching rule gives, or null when no rule matches. */
    @TestVisible
    private static String skipReason(
        List<ImportMapping.SkipRule> rules,
        Map<String, String> cells
    ) {
        for (ImportMapping.SkipRule rule : rules) {
            String value = cells.get(ImportMapping.key(rule.column));
            Boolean matches;
            if (rule.test == 'blank') {
                matches = String.isBlank(value);
            } else if (String.isBlank(value)) {
                matches = false;
            } else if (rule.test == 'equals') {
                matches = value.trim().equalsIgnoreCase(rule.text.trim());
            } else {
                matches = value.toLowerCase().contains(rule.text.trim().toLowerCase());
            }
            if (matches) {
                return String.format(
                    Label.Core_Import_SkippedByRule,
                    new List<String>{ rule.column }
                );
            }
        }
        return null;
    }

    /** The digest of the row's key cells, or null when there is no key or every cell is empty. */
    private static String digestOf(List<String> keys, Map<String, String> cells) {
        if (keys.isEmpty()) {
            return null;
        }
        List<String> parts = new List<String>();
        Boolean anyValue = false;
        for (String key : keys) {
            String value = cells.get(ImportMapping.key(key));
            value = value == null ? '' : value.trim().toLowerCase();
            anyValue = anyValue || value.length() > 0;
            parts.add(value);
        }
        if (!anyValue) {
            return null;
        }
        return EncodingUtil.convertToHex(
                Crypto.generateDigest(
                    'MD5',
                    Blob.valueOf(KEY_DIGEST + String.join(parts, KEY_SEPARATOR))
                )
            )
            .left(16);
    }

    /** Each digest an earlier page of this file kept, with that row's number. */
    private static Map<String, Integer> earlierRows(Id batchId, Set<String> digests) {
        digests.remove(null);
        Map<String, Integer> result = new Map<String, Integer>();
        if (digests.isEmpty()) {
            return result;
        }
        for (Import_Row__c row : [
            SELECT Row_Key__c, Row_Number__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId AND Row_Key__c IN :digests
            WITH SYSTEM_MODE
            ORDER BY Row_Number__c ASC
        ]) {
            if (!result.containsKey(row.Row_Key__c)) {
                result.put(row.Row_Key__c, row.Row_Number__c.intValue());
            }
        }
        return result;
    }

    private static Map<String, String> cells(Map<String, Object> raw) {
        Map<String, String> result = new Map<String, String>();
        if (raw == null) {
            return result;
        }
        for (String column : raw.keySet()) {
            Object value = raw.get(column);
            result.put(ImportMapping.key(column), value == null ? null : String.valueOf(value));
        }
        return result;
    }

    private static void skip(Import_Row__c row, String reason) {
        row.Status__c = ImportRowProcessor.STATUS_SKIPPED;
        row.Error_Message__c = reason.abbreviate(4000);
    }
}
