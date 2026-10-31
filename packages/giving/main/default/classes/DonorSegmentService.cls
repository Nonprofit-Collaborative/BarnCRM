/**
 * Donor segments (feature G-28, canonical model Section 25O): saved Find queries of people or
 * organizations, counted, listed and exported for an email tool.
 *
 * A segment is a Saved Query (R-DS1), so nothing here stores anything of its own: the saved
 * query's document is compiled and run by Find's `QueryCompiler`, in user mode, so a segment
 * shows only the records and fields the person can see (R-SQ2). The email tool layouts add three
 * conditions to the segment's filter, never remove one, so an export is never wider than the
 * segment (R-DS5). Nothing is sent anywhere.
 */
public with sharing class DonorSegmentService {
    /** Raised for anything the person can act on; the message is shown as it is. */
    public class SegmentException extends Exception {
    }

    public static final Integer COUNT_CAP = 10000;
    public static final String LAYOUT_MAILCHIMP = 'mailchimp';
    public static final String LAYOUT_CONSTANT_CONTACT = 'constantContact';
    public static final String LAYOUT_ALL = 'all';
    @TestVisible
    private static Integer maxSegments = 500;

    /** The columns the email tool layouts read; the page arranges them per tool. */
    public static final List<String> EMAIL_FIELDS = new List<String>{
        'Email',
        'FirstName',
        'LastName',
        'MailingStreet',
        'MailingCity',
        'MailingState',
        'MailingPostalCode',
        'MailingCountry'
    };

    /** One segment as the page lists it. */
    public class Segment {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public Boolean people;
        @AuraEnabled
        public Boolean shared;
        @AuraEnabled
        public Boolean mine;
        @AuraEnabled
        public String ownerName;
    }

    /** A column: the field path a row is keyed by and the label to show. */
    public class Column {
        @AuraEnabled
        public String path;
        @AuraEnabled
        public String label;
    }

    /** Rows of a segment, each a map of field path to value, and where the next page starts. */
    public class Rows {
        @AuraEnabled
        public List<Column> columns = new List<Column>();
        @AuraEnabled
        public List<Map<String, Object>> rows = new List<Map<String, Object>>();
        @AuraEnabled
        public String lastId;
        @AuraEnabled
        public Boolean done = true;
    }

    /** How many records a segment holds, up to COUNT_CAP; `more` when there are more. */
    public class SegmentCount {
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public Boolean more;
    }

    /** Every saved query of people or organizations the person can read, their own first. */
    public static List<Segment> segments() {
        List<String> objects = new List<String>{
            DonorSegmentTemplates.PEOPLE,
            DonorSegmentTemplates.ORGANIZATIONS
        };
        Id me = UserInfo.getUserId();
        List<Segment> found = new List<Segment>();
        for (Saved_Query__c query : [
            SELECT Id, Name, Object_Name__c, Shared__c, OwnerId, Owner.Name
            FROM Saved_Query__c
            WHERE OwnerId = :me AND Object_Name__c IN :objects
            WITH USER_MODE
            ORDER BY Name
            LIMIT :maxSegments
        ]) {
            found.add(segment(query, true));
        }
        Integer room = maxSegments - found.size();
        if (room > 0) {
            for (Saved_Query__c query : [
                SELECT Id, Name, Object_Name__c, Shared__c, OwnerId, Owner.Name
                FROM Saved_Query__c
                WHERE OwnerId != :me AND Object_Name__c IN :objects
                WITH USER_MODE
                ORDER BY Name
                LIMIT :room
            ]) {
                found.add(segment(query, false));
            }
        }
        return found;
    }

    /**
     * Saves a template as the person's own segment under `name`, replacing the query of their own
     * saved query of that name (whose sharing is kept), and returns its Id. The document is
     * compiled first, so a segment the person could not run is never saved.
     */
    public static Id saveFromTemplate(String templateKey, String objectName, String name) {
        if (String.isBlank(name) || name.trim().length() > 80) {
            throw new SegmentException(System.Label.Giving_Segments_ErrorName);
        }
        String document = DonorSegmentTemplates.document(templateKey, objectName);
        QueryCompiler.compile(document);
        Id me = UserInfo.getUserId();
        String trimmed = name.trim();
        // Only a segment is replaced: a Find query of the same name on another object (a gift
        // or program search) is left alone and the segment is saved beside it.
        List<String> segmentObjects = new List<String>{
            DonorSegmentTemplates.PEOPLE,
            DonorSegmentTemplates.ORGANIZATIONS
        };
        List<Saved_Query__c> existing = [
            SELECT Id
            FROM Saved_Query__c
            WHERE OwnerId = :me AND Name = :trimmed AND Object_Name__c IN :segmentObjects
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        Saved_Query__c query = new Saved_Query__c(
            Name = trimmed,
            Object_Name__c = objectName,
            Query_JSON__c = document
        );
        if (existing.isEmpty()) {
            query.Shared__c = false;
            Database.insert(query, AccessLevel.USER_MODE);
        } else {
            query.Id = existing[0].Id;
            Database.update(query, AccessLevel.USER_MODE);
        }
        return query.Id;
    }

    /** How many records the segment holds, as the person (R-DS3). */
    public static SegmentCount countRecords(Id segmentId) {
        Integer counted = QueryCompiler.count(
            requireSegment(segmentId).Query_JSON__c,
            COUNT_CAP + 1
        );
        SegmentCount result = new SegmentCount();
        result.more = counted > COUNT_CAP;
        result.count = Math.min(counted, COUNT_CAP);
        return result;
    }

    /** The segment's own columns, order and row count, as Find's results grid shows them (R-DS4). */
    public static Rows listRows(Id segmentId) {
        Saved_Query__c query = requireSegment(segmentId);
        List<String> fields = fieldsOf(query.Query_JSON__c);
        Rows result = new Rows();
        result.columns = columns(query.Object_Name__c, fields);
        result.rows = flatten(
            QueryCompiler.run(QueryCompiler.compile(query.Query_JSON__c)),
            fields
        );
        return result;
    }

    /**
     * One export page in Id order after `afterId` (R-DS5): the email layouts read the email
     * columns of people who can be emailed, All Columns the segment's own columns.
     */
    public static Rows exportPage(Id segmentId, String layout, String afterId) {
        Saved_Query__c query = requireSegment(segmentId);
        Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
            query.Query_JSON__c
        );
        document.remove('children');
        document.remove('aggregate');
        if (layout == LAYOUT_MAILCHIMP || layout == LAYOUT_CONSTANT_CONTACT) {
            if (query.Object_Name__c != DonorSegmentTemplates.PEOPLE) {
                throw new SegmentException(System.Label.Giving_Segments_ErrorPeopleOnly);
            }
            document.put('fields', EMAIL_FIELDS);
            Map<String, Object> filter = filterOf(document);
            andCondition(filter, condition('Email', 'is not null', null));
            andCondition(filter, condition('HasOptedOutOfEmail', 'equals', false));
            andCondition(
                filter,
                condition(DonorSegmentTemplates.qualifyPath('Deceased__c'), 'equals', false)
            );
            document.put('filter', filter);
        } else if (layout != LAYOUT_ALL) {
            throw new SegmentException(System.Label.Giving_Segments_ErrorLayout);
        }
        String exportJson = JSON.serialize(document);
        List<String> fields = fieldsOf(exportJson);
        Rows result = new Rows();
        result.columns = columns(query.Object_Name__c, fields);
        List<SObject> records = QueryCompiler.run(
            QueryCompiler.compileExportPage(
                exportJson,
                String.isBlank(afterId) ? null : Id.valueOf(afterId)
            )
        );
        result.rows = flatten(records, fields);
        result.done = records.size() < QueryCompiler.EXPORT_PAGE_SIZE;
        result.lastId = records.isEmpty()
            ? afterId
            : String.valueOf(records[records.size() - 1].Id);
        return result;
    }

    /** One R-R2 filter condition. */
    public static Map<String, Object> condition(String field, String operator, Object value) {
        Map<String, Object> built = new Map<String, Object>{
            'field' => field,
            'operator' => operator
        };
        if (value != null) {
            built.put('value', value);
        }
        return built;
    }

    /**
     * Joins a condition to a filter document with AND: it takes the next free number, and when
     * the filter has its own logic, that logic is wrapped so its meaning is kept.
     */
    public static void andCondition(Map<String, Object> filter, Map<String, Object> condition) {
        List<Object> conditions = filter.get('conditions') instanceof List<Object>
            ? (List<Object>) filter.get('conditions')
            : new List<Object>();
        Integer nextNumber = 1;
        for (Object entry : conditions) {
            Object given = ((Map<String, Object>) entry).get('id');
            if (given != null) {
                nextNumber = Math.max(nextNumber, Integer.valueOf(String.valueOf(given)) + 1);
            }
        }
        condition.put('id', nextNumber);
        conditions.add(condition);
        filter.put('conditions', conditions);
        String logic = (String) filter.get('logic');
        if (String.isNotBlank(logic)) {
            filter.put('logic', '(' + logic + ') AND ' + nextNumber);
        }
    }

    /** The saved query, read as the person, refused unless it is of people or organizations. */
    private static Saved_Query__c requireSegment(Id segmentId) {
        List<Saved_Query__c> found = segmentId == null
            ? new List<Saved_Query__c>()
            : [
                  SELECT Id, Name, Object_Name__c, Query_JSON__c
                  FROM Saved_Query__c
                  WHERE Id = :segmentId
                  WITH USER_MODE
                  LIMIT 1
              ];
        if (found.isEmpty()) {
            throw new SegmentException(System.Label.Giving_Segments_ErrorNotFound);
        }
        String objectName = found[0].Object_Name__c;
        if (
            objectName != DonorSegmentTemplates.PEOPLE &&
            objectName != DonorSegmentTemplates.ORGANIZATIONS
        ) {
            throw new SegmentException(System.Label.Giving_Segments_ErrorNotSegment);
        }
        return found[0];
    }

    /** The filter of a document as a map, whether it was saved as an object or as text. */
    private static Map<String, Object> filterOf(Map<String, Object> document) {
        Object filter = document.get('filter');
        if (filter instanceof String && String.isNotBlank((String) filter)) {
            filter = JSON.deserializeUntyped((String) filter);
        }
        return filter instanceof Map<String, Object>
            ? (Map<String, Object>) filter
            : new Map<String, Object>{ 'version' => 1, 'conditions' => new List<Object>() };
    }

    private static List<String> fieldsOf(String document) {
        List<String> fields = new List<String>();
        Object raw = ((Map<String, Object>) JSON.deserializeUntyped(document)).get('fields');
        for (Object field : raw instanceof List<Object> ? (List<Object>) raw : new List<Object>()) {
            fields.add(String.valueOf(field));
        }
        return fields;
    }

    /**
     * A label per field path, from the person's describe. A field across a lookup is named by
     * the lookup ("Donor Level" for `Donor_Level__r.Name`), or the lookup and the field.
     */
    private static List<Column> columns(String objectName, List<String> fields) {
        List<Column> columns = new List<Column>();
        for (String path : fields) {
            Column column = new Column();
            column.path = path;
            String label = QueryCompiler.resolve(objectName, path).getLabel();
            if (path.contains('.')) {
                String lookup = path.substringBeforeLast('.');
                String lookupField = lookup.endsWithIgnoreCase('__r')
                    ? lookup.left(lookup.length() - 1) + 'c'
                    : lookup + 'Id';
                String lookupLabel = QueryCompiler.resolve(objectName, lookupField).getLabel();
                label = path.substringAfterLast('.') == 'Name'
                    ? lookupLabel
                    : lookupLabel + ': ' + label;
            }
            column.label = label;
            columns.add(column);
        }
        return columns;
    }

    /** Each record as a map of field path to value, following lookups. */
    private static List<Map<String, Object>> flatten(List<SObject> records, List<String> fields) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (SObject record : records) {
            Map<String, Object> row = new Map<String, Object>{ 'Id' => record.Id };
            for (String path : fields) {
                row.put(path, valueAt(record, path));
            }
            rows.add(row);
        }
        return rows;
    }

    private static Object valueAt(SObject record, String path) {
        List<String> parts = path.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < parts.size() - 1 && current != null; i++) {
            current = current.getSObject(parts[i]);
        }
        return current == null ? null : current.get(parts[parts.size() - 1]);
    }

    private static Segment segment(Saved_Query__c query, Boolean mine) {
        Segment view = new Segment();
        view.recordId = query.Id;
        view.name = query.Name;
        view.objectName = query.Object_Name__c;
        view.people = query.Object_Name__c == DonorSegmentTemplates.PEOPLE;
        view.shared = query.Shared__c;
        view.mine = mine;
        view.ownerName = query.Owner?.Name;
        return view;
    }
}
