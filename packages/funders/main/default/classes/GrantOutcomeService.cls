/**
 * The Logic Models outcome a grant requirement reports on (L-06, canonical model 29ZI R-GQ6,
 * ADR-0163 `0163-funders-reporting-links.md`): the rule on the stored identifier, the outcomes to
 * choose from, and each linked outcome's indicators with their targets and results.
 *
 * Logic Models is found by describe only (`NamespaceUtil.packagedObjectType`), so Funders installs
 * without it and Logic Models never knows about Funders. Object and field names in the dynamic
 * queries come from describe and constants, never from the user; every read runs in user mode.
 */
public with sharing class GrantOutcomeService {
    private static final String ELEMENT_OBJECT = 'Logic_Model_Element__c';
    private static final String INDICATOR_OBJECT = 'Indicator__c';
    private static final String PERIOD_OBJECT = 'Indicator_Period__c';
    /** The element types a requirement can report on: those that carry indicators. */
    @TestVisible
    private static final List<String> REPORTABLE_TYPES = new List<String>{ 'Outcome', 'Output' };
    private static final Integer OPTION_LIMIT = 500;
    private static final Integer PERIOD_LIMIT = 2000;

    /** Thrown with a message a person can act on. */
    public class GrantOutcomeException extends Exception {
    }

    /** A packaged field or relationship name with whatever prefix this org needs. */
    private static String q(String apiName) {
        return NamespaceUtil.qualify(apiName);
    }

    /** Logic Models' element object, or null where Logic Models is not installed. */
    private static Schema.SObjectType elementObject() {
        return NamespaceUtil.packagedObjectType(ELEMENT_OBJECT);
    }

    /** An object of Logic Models the person can read, or null. */
    private static Schema.SObjectType readable(String apiName) {
        Schema.SObjectType type = NamespaceUtil.packagedObjectType(apiName);
        if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            return null;
        }
        return type;
    }

    private static String nameOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
    }

    /** Whether outcomes can be shown here: Logic Models is installed and the person reads it. */
    public static Boolean available() {
        return readable(ELEMENT_OBJECT) != null &&
            readable(INDICATOR_OBJECT) != null &&
            readable(PERIOD_OBJECT) != null;
    }

    /**
     * R-GQ6: stores each requirement's outcome in its 18-character form and refuses text that is
     * not a record identifier, or, where Logic Models is installed, an identifier of another
     * object.
     *
     * @param requirements the requirements being saved
     */
    public static void checkOutcomes(List<Grant_Requirement__c> requirements) {
        Schema.SObjectType elementType = null;
        Boolean looked = false;
        for (Grant_Requirement__c requirement : requirements) {
            if (String.isBlank(requirement.Outcome_Id__c)) {
                requirement.Outcome_Id__c = null;
                continue;
            }
            Id outcomeId = GrantService.asId(requirement.Outcome_Id__c);
            if (outcomeId != null && !looked) {
                elementType = elementObject();
                looked = true;
            }
            if (
                outcomeId == null ||
                (elementType != null &&
                outcomeId.getSObjectType() != elementType)
            ) {
                requirement.Outcome_Id__c.addError(
                    BarnHelp.text('Funders', 'Funders_Outcomes_NotAnOutcome')
                );
                continue;
            }
            requirement.Outcome_Id__c = String.valueOf(outcomeId);
        }
    }

    /**
     * The outcomes and outputs a requirement can name, by logic model, as value and label pairs.
     * Empty without Logic Models.
     */
    public static List<Map<String, String>> outcomeOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.SObjectType type = available() ? readable(ELEMENT_OBJECT) : null;
        if (type == null) {
            return options;
        }
        String model = q('Logic_Model__r');
        String soql =
            'SELECT Id, Name, ' +
            q('Type__c') +
            ', ' +
            model +
            '.Name FROM ' +
            nameOf(type) +
            ' WHERE ' +
            q('Type__c') +
            ' IN :types' +
            ' ORDER BY ' +
            model +
            '.Name, ' +
            q('Stage_Rank__c') +
            ', ' +
            q('Sort_Order__c') +
            ', Name' +
            ' LIMIT :maxRows';
        for (
            SObject element : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'types' => REPORTABLE_TYPES, 'maxRows' => OPTION_LIMIT },
                AccessLevel.USER_MODE
            )
        ) {
            options.add(
                new Map<String, String>{
                    'value' => (String) element.Id,
                    'label' => modelName(element) +
                    ': ' +
                    (String) element.get('Name')
                }
            );
        }
        return options;
    }

    private static String modelName(SObject element) {
        SObject model = element.getSObject(q('Logic_Model__r'));
        return model == null ? '' : (String) model.get('Name');
    }

    /**
     * The linked outcomes with their indicators and the periods that overlap the award period
     * (every period when either end is blank), as plain maps by outcome identifier. An outcome
     * the person cannot see, or that is gone, is simply absent. Empty without Logic Models.
     *
     * @param outcomeIds the outcomes named
     * @param fromDate the award period's start, or null
     * @param toDate the award period's end, or null
     */
    public static Map<String, Map<String, Object>> outcomes(
        Set<String> outcomeIds,
        Date fromDate,
        Date toDate
    ) {
        Map<String, Map<String, Object>> byId = new Map<String, Map<String, Object>>();
        if (outcomeIds == null || outcomeIds.isEmpty() || !available()) {
            return byId;
        }
        String soql =
            'SELECT Id, Name, ' +
            q('Type__c') +
            ', ' +
            q('Logic_Model__r') +
            '.Name FROM ' +
            nameOf(readable(ELEMENT_OBJECT)) +
            ' WHERE Id IN :ids';
        for (
            SObject element : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'ids' => outcomeIds },
                AccessLevel.USER_MODE
            )
        ) {
            byId.put(
                (String) element.Id,
                new Map<String, Object>{
                    'id' => (String) element.Id,
                    'name' => element.get('Name'),
                    'type' => element.get(q('Type__c')),
                    'model' => modelName(element),
                    'indicators' => new List<Map<String, Object>>()
                }
            );
        }
        if (byId.isEmpty()) {
            return byId;
        }
        Map<Id, Map<String, Object>> indicators = new Map<Id, Map<String, Object>>();
        String element = q('Element__c');
        soql =
            'SELECT Id, Name, ' +
            element +
            ', ' +
            q('Unit__c') +
            ', ' +
            q('Better_When__c') +
            ', ' +
            q('Baseline_Value__c') +
            ' FROM ' +
            nameOf(readable(INDICATOR_OBJECT)) +
            ' WHERE ' +
            element +
            ' IN :ids ORDER BY Name';
        for (
            SObject indicator : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'ids' => byId.keySet() },
                AccessLevel.USER_MODE
            )
        ) {
            Map<String, Object> shape = new Map<String, Object>{
                'id' => (String) indicator.Id,
                'name' => indicator.get('Name'),
                'unit' => indicator.get(q('Unit__c')),
                'betterWhen' => indicator.get(q('Better_When__c')),
                'baseline' => indicator.get(q('Baseline_Value__c')),
                'periods' => new List<Map<String, Object>>()
            };
            indicators.put(indicator.Id, shape);
            ((List<Map<String, Object>>) byId.get(String.valueOf(indicator.get(element)))
                    .get('indicators'))
                .add(shape);
        }
        if (!indicators.isEmpty()) {
            addPeriods(indicators, fromDate, toDate);
        }
        return byId;
    }

    private static void addPeriods(
        Map<Id, Map<String, Object>> indicators,
        Date fromDate,
        Date toDate
    ) {
        String indicator = q('Indicator__c');
        String startField = q('Start_Date__c');
        String endField = q('End_Date__c');
        Boolean bounded = fromDate != null && toDate != null;
        String soql =
            'SELECT Id, Name, ' +
            indicator +
            ', ' +
            startField +
            ', ' +
            endField +
            ', ' +
            q('Target_Value__c') +
            ', ' +
            q('Result_Value__c') +
            ' FROM ' +
            nameOf(readable(PERIOD_OBJECT)) +
            ' WHERE ' +
            indicator +
            ' IN :ids' +
            (bounded
                ? ' AND ' + startField + ' <= :toDate AND ' + endField + ' >= :fromDate'
                : '') +
            ' ORDER BY ' +
            startField +
            ' LIMIT :maxRows';
        for (
            SObject period : Database.queryWithBinds(
                soql,
                new Map<String, Object>{
                    'ids' => indicators.keySet(),
                    'fromDate' => fromDate,
                    'toDate' => toDate,
                    'maxRows' => PERIOD_LIMIT
                },
                AccessLevel.USER_MODE
            )
        ) {
            ((List<Map<String, Object>>) indicators.get((Id) period.get(indicator)).get('periods'))
                .add(
                    new Map<String, Object>{
                        'name' => period.get('Name'),
                        'startDate' => period.get(startField),
                        'endDate' => period.get(endField),
                        'target' => period.get(q('Target_Value__c')),
                        'result' => period.get(q('Result_Value__c'))
                    }
                );
        }
    }

    /**
     * Names the outcome a requirement reports on, or clears it when `outcomeId` is blank. The
     * outcome must be an Outcome or Output the person can see; saved in user mode.
     *
     * @param requirementId the requirement
     * @param outcomeId a logic model element's record identifier, or blank for none
     */
    public static void setOutcome(Id requirementId, String outcomeId) {
        String value = null;
        if (String.isNotBlank(outcomeId)) {
            Id parsed = GrantService.asId(outcomeId);
            Map<String, Map<String, Object>> found = parsed == null
                ? new Map<String, Map<String, Object>>()
                : outcomes(new Set<String>{ String.valueOf(parsed) }, null, null);
            Map<String, Object> outcome = found.get(String.valueOf(parsed));
            if (outcome == null || !REPORTABLE_TYPES.contains((String) outcome.get('type'))) {
                throw new GrantOutcomeException(
                    BarnHelp.text('Funders', 'Funders_Outcomes_NotAnOutcome')
                );
            }
            value = String.valueOf(parsed);
        }
        update as user new Grant_Requirement__c(Id = requirementId, Outcome_Id__c = value);
    }
}
