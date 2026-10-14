/**
 * Turns a Find query document (canonical model R-SQ1) into SOQL, and runs it as the user.
 *
 * Every name in the query comes from the running user's describe (QueryFieldCatalog): an object
 * or field the user cannot see is refused with a message naming it. Every filter value is a bind
 * variable (RollupFilterParser.toBoundClause), the row count is a bind variable, and the query
 * runs through Database.queryWithBinds with AccessLevel.USER_MODE, so CRUD, field-level security
 * and sharing apply to every read (R-SQ2, ADR-0047). The display rendering is for showing only;
 * this class never accepts SOQL text.
 */
public with sharing class QueryCompiler {
    /** Raised when a query document cannot be compiled; the message is for the person. */
    public class QueryCompilerException extends Exception {
    }

    public static final Integer MAX_FIELDS = 20;
    public static final Integer MAX_ROWS = 2000;
    public static final Integer DEFAULT_ROWS = 200;
    public static final Integer EXPORT_PAGE_SIZE = 2000;
    private static final Integer SUPPORTED_VERSION = 1;
    private static final Pattern FIELD_PATH = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$'
    );

    /** The query document, read and checked. */
    public class QueryDocument {
        public String objectName;
        public List<String> fields = new List<String>();
        public String filter;
        public String orderField;
        public String orderDirection;
        public Integer rowLimit = DEFAULT_ROWS;
        /** Related-records conditions and related record columns (C-36, R-SQ8), as sent. */
        public List<Object> related = new List<Object>();
        public List<Object> children = new List<Object>();
        /** The summary (C-36, R-SQ9), as sent; null when there is none. */
        public Map<String, Object> aggregate;
    }

    /** A compiled query: SOQL with bind names, its binds, and the rendering to show. */
    public class Compiled {
        public String soql;
        public String display;
        public Map<String, Object> binds;
        public String objectName;
        public List<String> fields;
        /** The FROM and WHERE part, for a count of the same records. */
        public String fromWhere;
    }

    /** Reads a query document; refuses one that is not a version 1 document within limits. */
    public static QueryDocument parse(String queryJson) {
        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(queryJson);
        } catch (Exception unreadable) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
        }
        if (raw == null) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
        }
        try {
            return read(raw);
        } catch (TypeException wrongShape) {
            // A part of the right name but the wrong shape, such as "orderBy": ["Name"].
            throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
        }
    }

    private static QueryDocument read(Map<String, Object> raw) {
        Object version = raw.get('version');
        if (version != null && String.valueOf(version) != String.valueOf(SUPPORTED_VERSION)) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
        }
        QueryDocument document = new QueryDocument();
        document.objectName = (String) raw.get('object');
        for (
            Object field : raw.get('fields') instanceof List<Object>
                ? (List<Object>) raw.get('fields')
                : new List<Object>()
        ) {
            document.fields.add(String.valueOf(field));
        }
        if (document.fields.isEmpty() || document.fields.size() > MAX_FIELDS) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorFieldCount);
        }
        Object filter = raw.get('filter');
        document.filter = filter == null
            ? null
            : (filter instanceof String ? (String) filter : JSON.serialize(filter));
        if (raw.get('orderBy') instanceof List<Object>) {
            List<Object> orderBy = (List<Object>) raw.get('orderBy');
            if (orderBy.size() > 1) {
                throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
            }
            if (!orderBy.isEmpty()) {
                Map<String, Object> order = (Map<String, Object>) orderBy[0];
                document.orderField = (String) order.get('field');
                String direction = order.get('direction') == null
                    ? 'ASC'
                    : String.valueOf(order.get('direction')).toUpperCase();
                if (direction != 'ASC' && direction != 'DESC') {
                    throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
                }
                document.orderDirection = direction;
            }
        }
        if (raw.get('limit') != null) {
            document.rowLimit = rowLimit(raw.get('limit'));
        }
        document.related = optionalList(raw.get('related'));
        document.children = optionalList(raw.get('children'));
        if (
            document.related.size() > FindRelatedRecords.MAX_RELATED ||
            document.children.size() > FindRelatedRecords.MAX_CHILD_COLUMNS
        ) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorRelatedCount);
        }
        if (raw.get('aggregate') != null) {
            if (!(raw.get('aggregate') instanceof Map<String, Object>)) {
                throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
            }
            document.aggregate = (Map<String, Object>) raw.get('aggregate');
        }
        return document;
    }

    /** The query the results grid runs: the document's own order and row count. */
    public static Compiled compile(String queryJson) {
        QueryDocument document = parse(queryJson);
        Compiled compiled = selectAndWhere(document, null, null);
        String order = '';
        if (String.isNotBlank(document.orderField)) {
            Schema.DescribeFieldResult sortField = resolve(
                document.objectName,
                document.orderField
            );
            if (!sortField.isSortable()) {
                throw new QueryCompilerException(
                    String.format(
                        System.Label.Core_Find_ErrorSortField,
                        new List<Object>{ document.orderField }
                    )
                );
            }
            order =
                ' ORDER BY ' +
                document.orderField +
                ' ' +
                document.orderDirection +
                (document.orderDirection == 'DESC' ? ' NULLS LAST' : ' NULLS FIRST');
        }
        compiled.binds.put('rowLimit', document.rowLimit);
        compiled.soql += order + ' LIMIT :rowLimit';
        compiled.display += order + ' LIMIT ' + document.rowLimit;
        return compiled;
    }

    /** One export page: the document's filter, in Id order, after the last Id already read. */
    public static Compiled compileExportPage(String queryJson, Id afterId) {
        QueryDocument document = parse(queryJson);
        Compiled compiled = selectAndWhere(document, afterId, null);
        compiled.binds.put('pageSize', EXPORT_PAGE_SIZE);
        compiled.soql += ' ORDER BY Id LIMIT :pageSize';
        compiled.display += ' ORDER BY Id LIMIT ' + EXPORT_PAGE_SIZE;
        return compiled;
    }

    /**
     * One page of the Ids the document's filter matches, in Id order, after the last Id already
     * read: the document's own columns, order and row count are ignored (R-BD8).
     */
    public static Compiled compileIdPage(String queryJson, Id afterId, Integer pageSize) {
        QueryDocument document = parse(queryJson);
        document.fields = new List<String>{ 'Id' };
        document.children.clear();
        Compiled compiled = selectAndWhere(document, afterId, null);
        compiled.binds.put('pageSize', pageSize);
        compiled.soql += ' ORDER BY Id LIMIT :pageSize';
        compiled.display += ' ORDER BY Id LIMIT ' + pageSize;
        return compiled;
    }

    /**
     * The document's filter over other fields of its object, for bulk update (C-35, R-BU1): the
     * document's own columns, order and row count are ignored. With `onlyIds`, only those
     * records; the caller adds any order and row count.
     */
    public static Compiled compileSelection(
        String queryJson,
        Set<String> fieldNames,
        Set<Id> onlyIds
    ) {
        QueryDocument document = parse(queryJson);
        document.fields = new List<String>(fieldNames);
        document.children.clear();
        return selectAndWhere(document, null, onlyIds);
    }

    /**
     * How many records the document's filter matches, as the user, counting at most `atMost`
     * (a count reads one query row per record, R-BU2).
     */
    public static Integer count(String queryJson, Integer atMost) {
        return count(selectAndWhere(parse(queryJson), null, null), atMost);
    }

    /** As `count`, from a query already compiled, so it is not read and checked again. */
    public static Integer count(Compiled compiled, Integer atMost) {
        Map<String, Object> binds = new Map<String, Object>(compiled.binds);
        binds.put('countLimit', atMost);
        return Database.countQueryWithBinds(
            'SELECT COUNT()' + compiled.fromWhere + ' LIMIT :countLimit',
            binds,
            AccessLevel.USER_MODE
        );
    }

    /** Runs a compiled query with the running user's access. */
    public static List<SObject> run(Compiled compiled) {
        return Database.queryWithBinds(compiled.soql, compiled.binds, AccessLevel.USER_MODE);
    }

    private static Compiled selectAndWhere(QueryDocument document, Id afterId, Set<Id> onlyIds) {
        String objectName;
        try {
            objectName = QueryFieldCatalog.describeObject(document.objectName).getName();
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new QueryCompilerException(refused.getMessage());
        }
        List<String> fields = new List<String>{ 'Id' };
        Set<String> seen = new Set<String>{ 'id' };
        for (String path : document.fields) {
            resolve(objectName, path);
            if (seen.add(path.toLowerCase())) {
                fields.add(path);
            }
        }

        FilterValueBinder bound;
        try {
            bound = RollupFilterParser.toBoundClause(document.filter, objectName);
        } catch (RollupFilterParser.RollupFilterException refused) {
            throw new QueryCompilerException(refused.getMessage());
        }
        List<String> whereParts = new List<String>();
        List<String> shownParts = new List<String>();
        if (String.isNotBlank(bound.clause)) {
            whereParts.add('(' + bound.clause + ')');
            shownParts.add('(' + bound.display() + ')');
        }
        Map<String, Object> binds = new Map<String, Object>(bound.binds);
        for (Integer index = 0; index < document.related.size(); index++) {
            FindRelatedRecords.Rendered joined = FindRelatedRecords.condition(
                objectName,
                document.related[index],
                index
            );
            whereParts.add(joined.clause);
            shownParts.add(joined.display);
            binds.putAll(joined.binds);
        }
        for (Object child : document.children) {
            fields.add(FindRelatedRecords.childColumn(objectName, child).clause);
        }
        if (afterId != null) {
            binds.put('afterId', afterId);
            whereParts.add('Id > :afterId');
            shownParts.add('Id > \'' + String.valueOf(afterId) + '\'');
        }
        if (onlyIds != null) {
            binds.put('onlyIds', onlyIds);
            whereParts.add('Id IN :onlyIds');
            shownParts.add('Id IN :onlyIds');
        }

        String selectFrom = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectName;
        Compiled compiled = new Compiled();
        compiled.objectName = objectName;
        compiled.fields = fields;
        compiled.binds = binds;
        compiled.fromWhere =
            ' FROM ' +
            objectName +
            (whereParts.isEmpty() ? '' : ' WHERE ' + String.join(whereParts, ' AND '));
        compiled.soql =
            selectFrom + (whereParts.isEmpty() ? '' : ' WHERE ' + String.join(whereParts, ' AND '));
        compiled.display =
            selectFrom + (shownParts.isEmpty() ? '' : ' WHERE ' + String.join(shownParts, ' AND '));
        return compiled;
    }

    /**
     * A field path checked against the running user's describe, or a refusal naming it (cut to
     * 80 characters). One check for the filter, the sort, the summary and the related columns.
     */
    public static Schema.DescribeFieldResult resolve(String objectName, String path) {
        if (String.isBlank(path) || !FIELD_PATH.matcher(path).matches()) {
            throw new QueryCompilerException(
                String.format(
                    System.Label.Core_Filter_ErrorUnknownField,
                    new List<Object>{ String.valueOf(path).abbreviate(80) }
                )
            );
        }
        try {
            return QueryFieldCatalog.resolvePath(objectName, path);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new QueryCompilerException(refused.getMessage());
        }
    }

    /** An optional list key of the document: absent reads as empty, anything else is refused. */
    private static List<Object> optionalList(Object raw) {
        if (raw == null) {
            return new List<Object>();
        }
        if (!(raw instanceof List<Object>)) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorInvalidQuery);
        }
        return (List<Object>) raw;
    }

    private static Integer rowLimit(Object raw) {
        Decimal rows;
        try {
            rows = Decimal.valueOf(String.valueOf(raw).trim());
        } catch (Exception notANumber) {
            rows = null;
        }
        if (rows == null || rows.stripTrailingZeros().scale() > 0 || rows < 1 || rows > MAX_ROWS) {
            throw new QueryCompilerException(System.Label.Core_Find_ErrorRowLimit);
        }
        return rows.intValue();
    }
}
