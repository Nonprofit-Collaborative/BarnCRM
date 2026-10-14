/**
 * Every query against staged import rows.
 *
 * Rows are read in pages, never all at once: an import of hundreds of thousands of rows must
 * not be able to make a screen ask for all of them. A screen that needs every row of a status
 * (the exceptions file) walks an Apex pagination cursor page by page, so there is no OFFSET
 * ceiling and no row is skipped or read twice.
 */
@NamespaceAccessible
public with sharing class ImportRowSelector {
    /** How many rows a screen may ask for in one call. */
    @NamespaceAccessible
    public static final Integer PAGE_SIZE = 200;

    /**
     * The most rows one pagination cursor may hold (a platform limit). The cursor's query is
     * capped here, so a larger batch gives its first rows instead of failing.
     */
    @NamespaceAccessible
    public static final Integer MAX_CURSOR_ROWS = 100000;

    private static final String FIELDS =
        'Id, Name, Import_Batch__c, Row_Number__c, ' +
        'Raw_Values_JSON__c, Status__c, Error_Message__c, Household__c, Contact_1__c, ' +
        'Person_1_Account__c, Contact_2__c, Person_2_Account__c, Organization__c, Gift_Id__c, ' +
        'Soft_Credit_Id__c';

    /** The first page of a batch's rows in file order. */
    @NamespaceAccessible
    public static List<Import_Row__c> selectFirstPage(Id batchId) {
        if (batchId == null) {
            return new List<Import_Row__c>();
        }
        return Database.queryWithBinds(
            'SELECT ' +
                FIELDS +
                ' FROM Import_Row__c WHERE Import_Batch__c = :batchId' +
                ' ORDER BY Row_Number__c ASC LIMIT :pageSize',
            new Map<String, Object>{ 'batchId' => batchId, 'pageSize' => PAGE_SIZE },
            AccessLevel.USER_MODE
        );
    }

    /**
     * A pagination cursor over a batch's rows in file order, only those in the given status
     * when one is given. This is what the exceptions file is read through, with status
     * Rejected. Read as the person (user mode), at most MAX_CURSOR_ROWS rows.
     */
    @NamespaceAccessible
    public static Database.PaginationCursor openCursor(Id batchId, String status) {
        Integer maxRows = MAX_CURSOR_ROWS;
        String query = 'SELECT ' + FIELDS + ' FROM Import_Row__c WHERE Import_Batch__c = :batchId';
        if (String.isNotBlank(status)) {
            query += ' AND Status__c = :status';
        }
        query += ' ORDER BY Row_Number__c ASC LIMIT :maxRows';
        return Database.getPaginationCursor(query, AccessLevel.USER_MODE);
    }

    /** How many digests one query takes; a chunk with more is asked in slices. */
    private static final Integer DIGESTS_PER_QUERY = 1000;

    /**
     * The batch's current pass (R-IB13), or null for a batch read without it, as a test that
     * never started a pass reads it.
     */
    @NamespaceAccessible
    public static Decimal passOf(Import_Batch__c batch) {
        return batch != null && batch.isSet(Import_Batch__c.Pass_Number__c)
            ? batch.Pass_Number__c
            : null;
    }

    /**
     * Which of these digests an earlier chunk of the current pass wrote as a person or an
     * organization it would create (R-IB12). Only rows stamped with this pass are read (R-IB13),
     * and only for the chunk's own digests, so what this costs never depends on how many rows
     * came before. In system mode (ADR-0021): the staged rows are the package's own bookkeeping.
     */
    @NamespaceAccessible
    public static Set<String> createdDigestsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> digests
    ) {
        return createdDigestCounts(batch, digests).keySet();
    }

    /**
     * The same, with how many times each was written: a shared key two people created would
     * hold is written twice, so a later chunk knows it can no longer find one of them by it
     * alone (R-IB12).
     */
    @NamespaceAccessible
    public static Map<String, Integer> createdDigestCounts(
        Import_Batch__c batch,
        Set<String> digests
    ) {
        return digestsWrittenEarlier(
            batch,
            digests,
            new List<String>{
                'Person_1_Key__c',
                'Person_2_Key__c',
                'Person_1_Name_Key__c',
                'Person_2_Name_Key__c',
                'Organization_Key__c'
            }
        );
    }

    /**
     * Which of these digests an earlier chunk of the current pass wrote as the entity
     * processor's key (R-IR6): for Giving, the external IDs of the gifts a dry run would load.
     */
    @NamespaceAccessible
    public static Set<String> processorDigestsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> digests
    ) {
        return digestsWrittenEarlier(batch, digests, new List<String>{ 'Processor_Key__c' })
            .keySet();
    }

    /**
     * Which of these records an earlier chunk of the current pass gave a row as its resulting
     * record (R-IT16): true for one such a row created, false for one it only updated or
     * matched. A one-object template matching through the duplicate rules uses it so the commit
     * takes a record the import created as the dry run does (not there), and a record an
     * earlier row loads is never loaded again. Rejected rows name none.
     */
    @NamespaceAccessible
    public static Map<String, Boolean> resultingRecordsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> recordIds
    ) {
        Map<String, Boolean> found = new Map<String, Boolean>();
        if (batch == null || batch.Id == null || recordIds == null || recordIds.isEmpty()) {
            return found;
        }
        for (Import_Row__c row : [
            SELECT Gift_Id__c, Status__c
            FROM Import_Row__c
            WHERE
                Import_Batch__c = :batch.Id
                AND Pass_Number__c = :passOf(batch)
                AND Gift_Id__c IN :recordIds
            WITH SYSTEM_MODE
        ]) {
            Boolean created = row.Status__c == ImportRowProcessor.STATUS_CREATED;
            found.put(
                row.Gift_Id__c,
                created || (found.containsKey(row.Gift_Id__c) && found.get(row.Gift_Id__c))
            );
        }
        return found;
    }

    private static Map<String, Integer> digestsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> digests,
        List<String> fields
    ) {
        Map<String, Integer> found = new Map<String, Integer>();
        if (batch == null || batch.Id == null || digests == null || digests.isEmpty()) {
            return found;
        }
        List<String> all = new List<String>(digests);
        for (Integer start = 0; start < all.size(); start += DIGESTS_PER_QUERY) {
            List<String> slice = new List<String>();
            for (Integer i = start; i < Math.min(start + DIGESTS_PER_QUERY, all.size()); i++) {
                slice.add(all[i]);
            }
            found.putAll(digestSlice(batch, slice, fields));
        }
        return found;
    }

    /** One slice, kept out of the caller's loop so no query sits lexically inside one. */
    private static Map<String, Integer> digestSlice(
        Import_Batch__c batch,
        List<String> slice,
        List<String> fields
    ) {
        Set<String> wanted = new Set<String>(slice);
        List<String> matches = new List<String>();
        for (String field : fields) {
            matches.add(field + ' IN :slice');
        }
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT ' +
                String.join(fields, ', ') +
                ' FROM Import_Row__c WHERE Import_Batch__c = :batchId' +
                ' AND Pass_Number__c = :pass AND (' +
                String.join(matches, ' OR ') +
                ')',
            new Map<String, Object>{
                'batchId' => batch.Id,
                'slice' => slice,
                'pass' => passOf(batch)
            },
            AccessLevel.SYSTEM_MODE
        );
        Map<String, Integer> found = new Map<String, Integer>();
        for (Import_Row__c row : rows) {
            for (String field : fields) {
                String value = (String) row.get(field);
                if (value != null && wanted.contains(value)) {
                    found.put(value, found.containsKey(value) ? found.get(value) + 1 : 1);
                }
            }
        }
        return found;
    }

    /**
     * The first person and organization pairs that rows of earlier chunks of the current pass
     * would link (R-AF5, R-IB12), among the given people and organizations. Each side is a
     * record Id, or the digest a row wrote for one it would create. A row that is rejected
     * links nothing. Pairs are written `person>organization`, every way the row names each side.
     */
    @NamespaceAccessible
    public static Set<String> affiliationPairsWrittenEarlier(
        Import_Batch__c batch,
        Set<String> people,
        Set<String> organizations
    ) {
        Set<String> pairs = new Set<String>();
        if (batch == null || batch.Id == null || people.isEmpty() || organizations.isEmpty()) {
            return pairs;
        }
        Map<String, Object> binds = new Map<String, Object>{
            'batchId' => batch.Id,
            'pass' => passOf(batch),
            'rejected' => ImportRowProcessor.STATUS_REJECTED
        };
        String personMatch = sideMatch(
            people,
            binds,
            'personIds',
            new List<String>{ 'Contact_1__c', 'Person_1_Account__c' },
            'personDigests',
            new List<String>{ 'Person_1_Key__c', 'Person_1_Name_Key__c' }
        );
        String organizationMatch = sideMatch(
            organizations,
            binds,
            'organizationIds',
            new List<String>{ 'Organization__c' },
            'organizationDigests',
            new List<String>{ 'Organization_Key__c' }
        );
        // System mode (ADR-0021): the staged rows are the package's own bookkeeping.
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT Contact_1__c, Person_1_Account__c, Person_1_Key__c, Person_1_Name_Key__c,' +
                ' Organization__c, Organization_Key__c FROM Import_Row__c' +
                ' WHERE Import_Batch__c = :batchId AND Pass_Number__c = :pass' +
                ' AND Status__c != :rejected AND (' +
                personMatch +
                ') AND (' +
                organizationMatch +
                ')',
            binds,
            AccessLevel.SYSTEM_MODE
        );
        for (Import_Row__c row : rows) {
            List<Object> rowPeople = new List<Object>{
                row.Contact_1__c,
                row.Person_1_Account__c,
                row.Person_1_Key__c,
                row.Person_1_Name_Key__c
            };
            List<Object> rowOrganizations = new List<Object>{
                row.Organization__c,
                row.Organization_Key__c
            };
            for (Object person : rowPeople) {
                for (Object organization : rowOrganizations) {
                    if (person != null && organization != null) {
                        pairs.add(String.valueOf(person) + '>' + String.valueOf(organization));
                    }
                }
            }
        }
        return pairs;
    }

    /**
     * The condition for one side of a pair: its Ids against the lookup fields and its digests
     * against the key fields. The field names are the caller's constants, never a user's text.
     */
    private static String sideMatch(
        Set<String> values,
        Map<String, Object> binds,
        String idBind,
        List<String> idFields,
        String digestBind,
        List<String> digestFields
    ) {
        Set<Id> ids = new Set<Id>();
        Set<String> digests = new Set<String>();
        for (String value : values) {
            Id asId = ImportValues.idOrNull(value);
            if (asId != null) {
                ids.add(asId);
            } else {
                digests.add(value);
            }
        }
        binds.put(idBind, ids);
        binds.put(digestBind, digests);
        List<String> parts = new List<String>();
        for (String field : idFields) {
            parts.add(field + ' IN :' + idBind);
        }
        for (String field : digestFields) {
            parts.add(field + ' IN :' + digestBind);
        }
        return String.join(parts, ' OR ');
    }
}
