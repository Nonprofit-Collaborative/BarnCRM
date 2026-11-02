/**
 * Where an indicator's results come from (L-03; ADR-0158 `0158-indicator-sources.md`; canonical
 * model R-IN3 and R-IN4): typed in, imported with the Indicator Results template, or computed
 * from a Find saved query by `IndicatorResultsBatch`.
 *
 * Everything here runs as the person: the saved queries offered are the ones they can open, a
 * computed source is checked by compiling its query as them (`QueryCompiler`, so an object or
 * field they cannot read is refused), and the source fields are written in user mode, which only
 * Logic Models Admin may edit. The counting itself runs in system mode in the batch (R-IN5).
 *
 * A computed source's choices are kept as JSON (plan 9.9):
 * `{"version": 1, "dateField": "Delivery_Date__c", "function": "count", "field": null}`.
 */
public with sharing class IndicatorSourceService {
    public static final String MANUAL = 'Manual';
    public static final String IMPORTED = 'Import';
    public static final String COMPUTED = 'Computed';
    public static final String COUNT = 'count';
    public static final String SUM = 'sum';
    public static final String UNIQUE = 'unique';
    private static final Set<String> SOURCES = new Set<String>{ MANUAL, IMPORTED, COMPUTED };
    private static final Set<String> FUNCTIONS = new Set<String>{ COUNT, SUM, UNIQUE };
    private static final Integer DEFINITION_VERSION = 1;
    private static final Integer QUERY_LIMIT = 500;
    private static final Set<Schema.DisplayType> DATES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };
    private static final Set<Schema.DisplayType> NUMBERS = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG
    };

    /** A computed source's choices, as stored in Source Definition. */
    public class Definition {
        public String dateField;
        public String function;
        public String field;
        /** The fields' labels when the source was saved, for the builder's line only. */
        public String dateLabel;
        public String fieldLabel;

        /** The JSON stored in Source Definition. */
        public String toJson() {
            return JSON.serialize(
                new Map<String, Object>{
                    'version' => DEFINITION_VERSION,
                    'dateField' => dateField,
                    'function' => function,
                    'field' => field,
                    'dateLabel' => dateLabel,
                    'fieldLabel' => fieldLabel
                }
            );
        }
    }

    /**
     * A stored definition, or null when it is blank or not one this version reads.
     *
     * @param stored the Source Definition text
     * @return the definition, or null
     */
    public static Definition parse(String stored) {
        if (String.isBlank(stored)) {
            return null;
        }
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(stored);
            Definition definition = new Definition();
            definition.dateField = textOf(raw.get('dateField'));
            definition.function = textOf(raw.get('function'));
            definition.field = textOf(raw.get('field'));
            definition.dateLabel = textOf(raw.get('dateLabel'));
            definition.fieldLabel = textOf(raw.get('fieldLabel'));
            return String.isBlank(definition.dateField) || !FUNCTIONS.contains(definition.function)
                ? null
                : definition;
        } catch (Exception unreadable) {
            return null;
        }
    }

    // ------------------------------------------------------------------------------ choices

    /**
     * The Find saved queries the person can open, by name, for the Computed source's picker.
     *
     * @return value (the saved query's Id), label (its name) and objectName
     */
    public static List<Map<String, String>> queries() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        if (
            !Saved_Query__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()
        ) {
            return options;
        }
        for (Saved_Query__c query : [
            SELECT Id, Name, Object_Name__c
            FROM Saved_Query__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT :QUERY_LIMIT
        ]) {
            options.add(
                new Map<String, String>{
                    'value' => query.Id,
                    'label' => query.Name,
                    'objectName' => query.Object_Name__c
                }
            );
        }
        return options;
    }

    /**
     * The fields of a saved query's object a computed source may use, read through the person's
     * describe: date and date-time fields to place a record in a period, number fields to sum,
     * and fields whose values can be counted once.
     *
     * @param queryId the saved query
     * @return objectName, objectLabel, dateFields, numberFields, uniqueFields (value and label)
     */
    public static Map<String, Object> fields(Id queryId) {
        QueryCompiler.Compiled compiled = compile(savedQuery(queryId).Query_JSON__c);
        Schema.DescribeSObjectResult described = Schema.describeSObjects(
            new List<String>{ compiled.objectName },
            SObjectDescribeOptions.DEFERRED
        )[0];
        Map<String, Map<String, String>> dateOptions = new Map<String, Map<String, String>>();
        Map<String, Map<String, String>> numberOptions = new Map<String, Map<String, String>>();
        Map<String, Map<String, String>> uniqueOptions = new Map<String, Map<String, String>>();
        for (Schema.SObjectField token : described.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (!field.isAccessible()) {
                continue;
            }
            String key = field.getLabel() + '|' + field.getName();
            Map<String, String> option = new Map<String, String>{
                'value' => field.getName(),
                'label' => field.getLabel()
            };
            Schema.DisplayType type = field.getType();
            if (DATES.contains(type) && field.isFilterable()) {
                dateOptions.put(key, option);
            }
            if (NUMBERS.contains(type)) {
                numberOptions.put(key, option);
            }
            if (field.isGroupable()) {
                uniqueOptions.put(key, option);
            }
        }
        return new Map<String, Object>{
            'objectName' => compiled.objectName,
            'objectLabel' => described.getLabel(),
            'dateFields' => sorted(dateOptions),
            'numberFields' => sorted(numberOptions),
            'uniqueFields' => sorted(uniqueOptions)
        };
    }

    // ------------------------------------------------------------------------------- saving

    /**
     * Saves where an indicator's results come from, checking a computed source as the person
     * (R-IN4). Choosing Typed In or Imported clears the query and definition.
     *
     * @param fields id, source, and for Computed: queryId, dateField, function, field
     * @return true when the source is Computed, so the caller starts a refresh
     */
    public static Boolean save(Map<String, Object> fields) {
        Id indicatorId = Id.valueOf(textOf(fields.get('id')));
        String source = textOf(fields.get('source'));
        if (!SOURCES.contains(source)) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_Invalid);
        }
        Indicator__c change = new Indicator__c(
            Id = indicatorId,
            Source__c = source,
            Source_Query__c = null,
            Source_Definition__c = null
        );
        if (source == COMPUTED) {
            Id queryId = String.isBlank(textOf(fields.get('queryId')))
                ? null
                : Id.valueOf(textOf(fields.get('queryId')));
            Definition definition = new Definition();
            definition.dateField = textOf(fields.get('dateField'));
            definition.function = textOf(fields.get('function'));
            definition.field = definition.function == COUNT ? null : textOf(fields.get('field'));
            QueryCompiler.Compiled compiled = compile(savedQuery(queryId).Query_JSON__c);
            check(compiled.objectName, definition);
            change.Source_Query__c = queryId;
            change.Source_Definition__c = definition.toJson();
        }
        update as user change;
        return source == COMPUTED;
    }

    /**
     * Starts working out one computed indicator's results now (Refresh Results). Refused for
     * someone who cannot change periods, or for an indicator that is not computed.
     *
     * @param indicatorId the indicator
     */
    public static void refresh(Id indicatorId) {
        if (
            !Indicator_Period__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .isUpdateable()
        ) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_CannotRefresh);
        }
        List<Indicator__c> found = [
            SELECT Id, Source__c
            FROM Indicator__c
            WHERE Id = :indicatorId
            WITH USER_MODE
        ];
        if (found.isEmpty() || found[0].Source__c != COMPUTED) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_NotComputed);
        }
        IndicatorResultsBatch.run(new List<Id>{ indicatorId });
    }

    // ------------------------------------------------------------------------------ checking

    /**
     * Compiles a saved query's document as the running user, or refuses with Find's own reason.
     *
     * @param queryJson the saved query's document
     * @return the compiled query (its object, FROM and WHERE, and binds)
     */
    public static QueryCompiler.Compiled compile(String queryJson) {
        try {
            return QueryCompiler.compile(queryJson);
        } catch (QueryCompiler.QueryCompilerException refused) {
            throw new LogicModelService.BuilderException(
                String.format(
                    Label.LogicModels_Source_QueryRefused,
                    new List<String>{ refused.getMessage() }
                )
            );
        }
    }

    /**
     * Checks a definition against the query's object through the running user's describe
     * (R-IN4): a date or date-time to place records, a number to sum, a groupable field to count
     * once.
     *
     * @param objectName the query's object
     * @param definition the choices
     */
    public static void check(String objectName, Definition definition) {
        if (definition == null || !FUNCTIONS.contains(definition.function)) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_Invalid);
        }
        Schema.DescribeFieldResult dateField = resolve(objectName, definition.dateField);
        if (!DATES.contains(dateField.getType()) || !dateField.isFilterable()) {
            throw new LogicModelService.BuilderException(
                String.format(
                    Label.LogicModels_Source_DateField,
                    new List<String>{ dateField.getLabel() }
                )
            );
        }
        definition.dateLabel = dateField.getLabel();
        if (definition.function == COUNT) {
            return;
        }
        Schema.DescribeFieldResult measured = resolve(objectName, definition.field);
        definition.fieldLabel = measured.getLabel();
        Boolean fits = definition.function == SUM
            ? NUMBERS.contains(measured.getType())
            : measured.isGroupable();
        if (!fits) {
            throw new LogicModelService.BuilderException(
                String.format(
                    definition.function == SUM
                        ? Label.LogicModels_Source_SumField
                        : Label.LogicModels_Source_UniqueField,
                    new List<String>{ measured.getLabel() }
                )
            );
        }
    }

    private static Schema.DescribeFieldResult resolve(String objectName, String path) {
        if (String.isBlank(path)) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_Invalid);
        }
        try {
            return QueryCompiler.resolve(objectName, path);
        } catch (QueryCompiler.QueryCompilerException refused) {
            throw new LogicModelService.BuilderException(refused.getMessage());
        }
    }

    /** The saved query, as the person can open it, or a refusal. */
    private static Saved_Query__c savedQuery(Id queryId) {
        List<Saved_Query__c> found = queryId == null
            ? new List<Saved_Query__c>()
            : [
                  SELECT Id, Name, Query_JSON__c
                  FROM Saved_Query__c
                  WHERE Id = :queryId
                  WITH USER_MODE
              ];
        if (found.isEmpty()) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_QueryMissing);
        }
        return found[0];
    }

    private static List<Map<String, String>> sorted(Map<String, Map<String, String>> byKey) {
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (String key : keys) {
            result.add(byKey.get(key));
        }
        return result;
    }

    private static String textOf(Object value) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value).trim();
        return String.isEmpty(text) ? null : text;
    }
}
