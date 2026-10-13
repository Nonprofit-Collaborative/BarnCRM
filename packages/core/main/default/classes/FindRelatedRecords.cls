/**
 * Related records in a Find query (C-36, canonical model R-SQ8): a condition that keeps the
 * records that have, or do not have, related records matching a filter of their own, and a
 * column that lists each record's most recent related records.
 *
 * Every name comes from the running user's describe: the child object must be one the user
 * can query, its lookup must be readable and point at the query's object, and each column
 * field is resolved through QueryFieldCatalog. The related filter is an R-R2 document bound
 * by RollupFilterParser under its own bind names, so no value is ever written into the query.
 */
public with sharing class FindRelatedRecords {
    public static final Integer MAX_RELATED = 2;
    public static final Integer MAX_CHILD_COLUMNS = 2;
    public static final Integer MAX_CHILD_FIELDS = 5;
    public static final Integer MAX_CHILD_ROWS = 10;
    private static final Pattern NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');
    private static final Pattern FIELD_PATH = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$'
    );

    /** One kind of related record, as Find offers it. */
    public class ChildOption {
        @AuraEnabled
        public String label;
        /** The name a related record column uses (`Contacts`). */
        @AuraEnabled
        public String relationshipName;
        /** The child object and its lookup, which a related-records condition uses. */
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String field;
        /** False when the lookup cannot be filtered on, so only a column can use it. */
        @AuraEnabled
        public Boolean filterable;
    }

    /** A rendered part of the query: the clause with bind names, its binds and its display. */
    public class Rendered {
        public String clause;
        public String display;
        public Map<String, Object> binds = new Map<String, Object>();
    }

    /** Every kind of related record of an object the running user can query, by label. */
    public static List<ChildOption> childOptions(String objectName) {
        Schema.DescribeSObjectResult parent = QueryFieldCatalog.describeObject(objectName);
        Map<String, ChildOption> byLabel = new Map<String, ChildOption>();
        for (Schema.ChildRelationship relationship : parent.getChildRelationships()) {
            Schema.DescribeSObjectResult child = offeredChild(relationship);
            if (child == null) {
                continue;
            }
            Schema.DescribeFieldResult lookup = relationship.getField().getDescribe();
            ChildOption option = new ChildOption();
            option.label = child.getLabelPlural() + ' (' + lookup.getLabel() + ')';
            option.relationshipName = relationship.getRelationshipName();
            option.objectName = child.getName();
            option.field = lookup.getName();
            option.filterable = lookup.isFilterable() && child.getName() != parent.getName();
            byLabel.put(option.label.toLowerCase() + '\u0000' + option.relationshipName, option);
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        List<ChildOption> options = new List<ChildOption>();
        for (String key : keys) {
            options.add(byLabel.get(key));
        }
        return options;
    }

    /**
     * `Id IN (SELECT lookup FROM child WHERE ...)`, or `NOT IN` when `has` is false. `index`
     * keeps each entry's bind names apart.
     */
    public static Rendered condition(String parentObject, Object rawEntry, Integer index) {
        Map<String, Object> entry = asMap(rawEntry);
        String childName = String.valueOf(entry.get('object'));
        String fieldName = String.valueOf(entry.get('field'));
        Schema.DescribeSObjectResult parent = QueryFieldCatalog.describeObject(parentObject);
        Schema.DescribeSObjectResult child;
        try {
            child = QueryFieldCatalog.describeObject(childName);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw refusedRelated(childName);
        }
        Schema.SObjectField token = NAME.matcher(fieldName).matches()
            ? child.fields.getMap().get(fieldName)
            : null;
        Schema.DescribeFieldResult lookup = token == null ? null : token.getDescribe();
        if (
            lookup == null ||
            !lookup.isAccessible() ||
            !lookup.isFilterable() ||
            !lookup.getReferenceTo().contains(parent.getSObjectType()) ||
            child.getName() == parent.getName()
        ) {
            throw refusedRelated(childName + '.' + fieldName);
        }
        Object filter = entry.get('filter');
        FilterValueBinder bound;
        try {
            bound = RollupFilterParser.toBoundClause(
                filter == null
                    ? null
                    : (filter instanceof String ? (String) filter : JSON.serialize(filter)),
                child.getName(),
                'rj' + index + '_'
            );
        } catch (RollupFilterParser.RollupFilterException refused) {
            throw new QueryCompiler.QueryCompilerException(refused.getMessage());
        }
        String operator = entry.get('has') == false ? ' NOT IN ' : ' IN ';
        String head = 'Id' + operator + '(SELECT ' + lookup.getName() + ' FROM ' + child.getName();
        Rendered rendered = new Rendered();
        rendered.binds.putAll(bound.binds);
        rendered.clause =
            head +
            (String.isBlank(bound.clause) ? '' : ' WHERE (' + bound.clause + ')') +
            ')';
        rendered.display =
            head +
            (String.isBlank(bound.clause) ? '' : ' WHERE (' + bound.display() + ')') +
            ')';
        return rendered;
    }

    /** A subquery over the named child relationship, newest first, at most `limit` rows. */
    public static Rendered childColumn(String parentObject, Object rawEntry) {
        Map<String, Object> entry = asMap(rawEntry);
        String name = String.valueOf(entry.get('relationship'));
        Schema.ChildRelationship found = null;
        for (
            Schema.ChildRelationship relationship : QueryFieldCatalog.describeObject(parentObject)
                .getChildRelationships()
        ) {
            if (name.equalsIgnoreCase(relationship.getRelationshipName())) {
                found = relationship;
            }
        }
        Schema.DescribeSObjectResult child = found == null ? null : offeredChild(found);
        if (child == null) {
            throw refusedRelated(name);
        }
        List<Object> rawFields = entry.get('fields') instanceof List<Object>
            ? (List<Object>) entry.get('fields')
            : new List<Object>();
        Integer rows = entry.get('limit') == null
            ? MAX_CHILD_ROWS
            : wholeNumber(entry.get('limit'));
        if (
            rawFields.isEmpty() ||
            rawFields.size() > MAX_CHILD_FIELDS ||
            rows == null ||
            rows < 1 ||
            rows > MAX_CHILD_ROWS
        ) {
            throw new QueryCompiler.QueryCompilerException(System.Label.Core_Find_ErrorChildColumn);
        }
        List<String> fields = new List<String>{ 'Id' };
        for (Object rawField : rawFields) {
            String path = String.valueOf(rawField);
            if (!FIELD_PATH.matcher(path).matches()) {
                throw unknownField(path);
            }
            try {
                QueryFieldCatalog.resolvePath(child.getName(), path);
            } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
                throw new QueryCompiler.QueryCompilerException(refused.getMessage());
            }
            if (!fields.contains(path)) {
                fields.add(path);
            }
        }
        Schema.SObjectField created = child.fields.getMap().get('CreatedDate');
        String order = created != null && created.getDescribe().isSortable()
            ? 'CreatedDate DESC'
            : 'Id';
        Rendered rendered = new Rendered();
        rendered.clause =
            '(SELECT ' +
            String.join(fields, ', ') +
            ' FROM ' +
            found.getRelationshipName() +
            ' ORDER BY ' +
            order +
            ' LIMIT ' +
            rows +
            ')';
        rendered.display = rendered.clause;
        return rendered;
    }

    /** The child object of a relationship Find offers, or null. */
    private static Schema.DescribeSObjectResult offeredChild(
        Schema.ChildRelationship relationship
    ) {
        if (
            relationship.getRelationshipName() == null ||
            relationship.isDeprecatedAndHidden() ||
            !relationship.getField().getDescribe().isAccessible()
        ) {
            return null;
        }
        Schema.DescribeSObjectResult child = relationship.getChildSObject()
            .getDescribe(SObjectDescribeOptions.DEFERRED);
        if (
            !child.isAccessible() ||
            !child.isQueryable() ||
            QueryFieldCatalog.isSystemObject(child)
        ) {
            return null;
        }
        return child;
    }

    private static Map<String, Object> asMap(Object raw) {
        if (!(raw instanceof Map<String, Object>)) {
            throw new QueryCompiler.QueryCompilerException(
                System.Label.Core_Find_ErrorInvalidQuery
            );
        }
        return (Map<String, Object>) raw;
    }

    private static Integer wholeNumber(Object raw) {
        try {
            Decimal value = Decimal.valueOf(String.valueOf(raw).trim());
            return value.stripTrailingZeros().scale() > 0 ? null : value.intValue();
        } catch (Exception notANumber) {
            return null;
        }
    }

    private static QueryCompiler.QueryCompilerException refusedRelated(String name) {
        return new QueryCompiler.QueryCompilerException(
            String.format(
                System.Label.Core_Find_ErrorRelated,
                new List<Object>{ String.valueOf(name).abbreviate(80) }
            )
        );
    }

    private static QueryCompiler.QueryCompilerException unknownField(String path) {
        return new QueryCompiler.QueryCompilerException(
            String.format(
                System.Label.Core_Filter_ErrorUnknownField,
                new List<Object>{ String.valueOf(path).abbreviate(80) }
            )
        );
    }
}
