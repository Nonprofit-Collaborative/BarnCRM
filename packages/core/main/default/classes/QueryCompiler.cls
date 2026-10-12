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
    }

    /** A compiled query: SOQL with bind names, its binds, and the rendering to show. */
    public class Compiled {
        public String soql;
        public String display;
        public Map<String, Object> binds;
        public String objectName;
        public List<String> fields;
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
        return document;
    }

    /** The query the results grid runs: the document's own order and row count. */
    public static Compiled compile(String queryJson) {
        QueryDocument document = parse(queryJson);
        Compiled compiled = selectAndWhere(document, null);
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
        Compiled compiled = selectAndWhere(document, afterId);
        compiled.binds.put('pageSize', EXPORT_PAGE_SIZE);
        compiled.soql += ' ORDER BY Id LIMIT :pageSize';
        compiled.display += ' ORDER BY Id LIMIT ' + EXPORT_PAGE_SIZE;
        return compiled;
    }

    /** Runs a compiled query with the running user's access. */
    public static List<SObject> run(Compiled compiled) {
        return Database.queryWithBinds(compiled.soql, compiled.binds, AccessLevel.USER_MODE);
    }

    private static Compiled selectAndWhere(QueryDocument document, Id afterId) {
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
        if (afterId != null) {
            binds.put('afterId', afterId);
            whereParts.add('Id > :afterId');
            shownParts.add('Id > \'' + String.valueOf(afterId) + '\'');
        }

        String selectFrom = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectName;
        Compiled compiled = new Compiled();
        compiled.objectName = objectName;
        compiled.fields = fields;
        compiled.binds = binds;
        compiled.soql =
            selectFrom + (whereParts.isEmpty() ? '' : ' WHERE ' + String.join(whereParts, ' AND '));
        compiled.display =
            selectFrom + (shownParts.isEmpty() ? '' : ' WHERE ' + String.join(shownParts, ' AND '));
        return compiled;
    }

    /** A field path checked against the running user's describe, or a refusal naming it. */
    private static Schema.DescribeFieldResult resolve(String objectName, String path) {
        if (String.isBlank(path) || !FIELD_PATH.matcher(path).matches()) {
            throw new QueryCompilerException(
                String.format(System.Label.Core_Filter_ErrorUnknownField, new List<Object>{ path })
            );
        }
        try {
            return QueryFieldCatalog.resolvePath(objectName, path);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new QueryCompilerException(refused.getMessage());
        }
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
