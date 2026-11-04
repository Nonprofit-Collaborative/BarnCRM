/**
 * Computed indicator starters (canonical model R-IN8; v1.0 modules-22): a Logic Models Admin picks
 * "People served by a service", "Services delivered", "Approved volunteer hours" or "Grants
 * awarded" and the record it is about, and BarnCRM writes the Find saved query for them, then
 * saves the computed source from it exactly as a hand-built query is saved (R-IN4).
 *
 * Logic Models depends on Core only (ADR-0154): every starter names another module's object and
 * fields by API name, as configuration, and is offered only when that object is in the org
 * (`NamespaceUtil.packagedObjectType`). Nothing here references their schema at compile time.
 * The saved query is the admin's own, private, and compiled as them before it is saved.
 */
public with sharing class IndicatorStarterService {
    private static final Integer CHOICE_LIMIT = 500;
    private static final Integer NAME_LIMIT = 80;
    private static final List<Object> NOT_ABSENT = new List<Object>{
        new Map<String, Object>{
            'field' => 'Attendance__c',
            'operator' => 'not equals',
            'value' => 'Excused Absence'
        },
        new Map<String, Object>{
            'field' => 'Attendance__c',
            'operator' => 'not equals',
            'value' => 'Unexcused Absence'
        }
    };

    /** One starter, by API names only. */
    public class Starter {
        public String key;
        public String objectName;
        /** Fixed conditions: field, operator, value. */
        public List<Object> conditions = new List<Object>();
        public String dateField;
        public String function;
        public String field;
        /** The object the person picks a record of, and the field that must hold its Id. */
        public String choiceObject;
        public String choiceField;
        public Boolean choiceRequired = false;

        public Starter(String key, String objectName, String dateField, String function) {
            this.key = key;
            this.objectName = objectName;
            this.dateField = dateField;
            this.function = function;
        }

        public Starter measuring(String field) {
            this.field = field;
            return this;
        }

        public Starter filtered(List<Object> conditions) {
            this.conditions = conditions;
            return this;
        }

        public Starter asking(String choiceObject, String choiceField, Boolean required) {
            this.choiceObject = choiceObject;
            this.choiceField = choiceField;
            this.choiceRequired = required;
            return this;
        }
    }

    /** The starters, in the order offered; a test swaps in its own. */
    @TestVisible
    private static List<Starter> starters = new List<Starter>{
        new Starter('peopleServed', 'Service_Delivery__c', 'Delivery_Date__c', 'unique')
            .measuring('Contact__c')
            .filtered(NOT_ABSENT)
            .asking('Service__c', 'Service__c', true),
        new Starter('servicesDelivered', 'Service_Delivery__c', 'Delivery_Date__c', 'count')
            .filtered(NOT_ABSENT)
            .asking('Service__c', 'Service__c', true),
        new Starter('volunteerHours', 'Volunteer_Hours__c', 'Date_Worked__c', 'sum')
            .measuring('Hours__c')
            .filtered(
                new List<Object>{
                    new Map<String, Object>{
                        'field' => 'Status__c',
                        'operator' => 'equals',
                        'value' => 'Approved'
                    }
                }
            )
            .asking('Volunteer_Job__c', 'Volunteer_Job__c', false),
        new Starter('grantsAwarded', 'Grant__c', 'Decision_Date__c', 'count')
            .filtered(
                new List<Object>{
                    new Map<String, Object>{
                        'field' => 'Stage__c',
                        'operator' => 'equals',
                        'value' => 'Awarded'
                    }
                }
            )
            .asking('Program__c', 'Program_Id__c', false)
    };

    // ------------------------------------------------------------------------------ choices

    /**
     * The starters this org can use: their object is installed and readable. A starter whose
     * record choice is required is left out when that object is missing; an optional choice is
     * simply not offered.
     *
     * @return value (the key), choiceLabel (the chosen object's label, or null) and choiceRequired
     */
    public static List<Map<String, Object>> available() {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        for (Starter starter : starters) {
            if (readable(starter.objectName) == null) {
                continue;
            }
            Schema.SObjectType choice = readable(starter.choiceObject);
            if (choice == null && starter.choiceRequired) {
                continue;
            }
            options.add(
                new Map<String, Object>{
                    'value' => starter.key,
                    'choiceLabel' => choice == null
                        ? null
                        : choice.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel(),
                    'choiceRequired' => starter.choiceRequired
                }
            );
        }
        return options;
    }

    /**
     * The records a starter can be about (services, volunteer jobs, programs), by name, as the
     * person can see them.
     *
     * @param starterKey the starter
     * @return value and label pairs, at most 500
     */
    public static List<Map<String, String>> choices(String starterKey) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.SObjectType type = readable(starterFor(starterKey).choiceObject);
        if (type == null) {
            return options;
        }
        // The object name comes from describe, never from the person.
        String soql =
            'SELECT Id, Name FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' ORDER BY Name LIMIT :maxRows';
        for (
            SObject record : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'maxRows' => CHOICE_LIMIT },
                AccessLevel.USER_MODE
            )
        ) {
            options.add(
                new Map<String, String>{
                    'value' => (String) record.Id,
                    'label' => (String) record.get('Name')
                }
            );
        }
        return options;
    }

    // ------------------------------------------------------------------------------- saving

    /**
     * Writes the starter's saved query as the person and returns the source to save from it.
     *
     * @param starterKey the starter
     * @param choiceId the record chosen, or blank where the choice is optional
     * @param queryName the saved query's name, as the person reads the starter
     * @return id-less source fields: source, queryId, dateField, function, field
     */
    public static Map<String, Object> createQuery(
        String starterKey,
        String choiceId,
        String queryName
    ) {
        Starter starter = starterFor(starterKey);
        Schema.SObjectType target = readable(starter.objectName);
        if (target == null) {
            throw new LogicModelService.BuilderException(
                BarnHelp.text('LogicModels', 'LogicModels_Starter_Unavailable')
            );
        }
        List<Object> conditions = new List<Object>();
        for (Object fixed : starter.conditions) {
            Map<String, Object> condition = ((Map<String, Object>) fixed).clone();
            condition.put('field', qualified((String) condition.get('field')));
            conditions.add(condition);
        }
        if (String.isNotBlank(choiceId)) {
            conditions.add(
                new Map<String, Object>{
                    'field' => qualified(starter.choiceField),
                    'operator' => 'equals',
                    'value' => checkedChoice(starter, choiceId)
                }
            );
        } else if (starter.choiceRequired) {
            throw new LogicModelService.BuilderException(
                BarnHelp.text('LogicModels', 'LogicModels_Starter_ChooseRecord')
            );
        }
        for (Integer i = 0; i < conditions.size(); i++) {
            ((Map<String, Object>) conditions[i]).put('id', i + 1);
        }
        String objectName = target.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        String document = JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => objectName,
                'fields' => new List<String>{ 'Name' },
                'filter' => new Map<String, Object>{ 'version' => 1, 'conditions' => conditions }
            }
        );
        // Compiled as the person first: an object or field they cannot read is refused (R-IN4).
        IndicatorSourceService.compile(document);
        if (
            !Saved_Query__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()
        ) {
            throw new LogicModelService.BuilderException(
                BarnHelp.text('LogicModels', 'LogicModels_Starter_NoFind')
            );
        }
        String name = String.isBlank(queryName) ? starter.key : queryName.trim();
        Saved_Query__c query = new Saved_Query__c(
            Name = name.left(NAME_LIMIT),
            Object_Name__c = objectName,
            Query_JSON__c = document,
            Shared__c = false
        );
        insert as user query;
        return new Map<String, Object>{
            'source' => IndicatorSourceService.COMPUTED,
            'queryId' => query.Id,
            'dateField' => qualified(starter.dateField),
            'function' => starter.function,
            'field' => starter.field == null ? null : qualified(starter.field)
        };
    }

    /** The chosen record's Id, checked to be one of the starter's records the person can see. */
    private static String checkedChoice(Starter starter, String choiceId) {
        Schema.SObjectType type = readable(starter.choiceObject);
        Id recordId;
        try {
            recordId = Id.valueOf(choiceId);
        } catch (Exception notAnId) {
            recordId = null;
        }
        if (type == null || recordId == null || recordId.getSObjectType() != type) {
            throw new LogicModelService.BuilderException(
                BarnHelp.text('LogicModels', 'LogicModels_Starter_ChooseRecord')
            );
        }
        String soql =
            'SELECT Id FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE Id = :recordId';
        if (
            Database.queryWithBinds(
                    soql,
                    new Map<String, Object>{ 'recordId' => recordId },
                    AccessLevel.USER_MODE
                )
                .isEmpty()
        ) {
            throw new LogicModelService.BuilderException(
                BarnHelp.text('LogicModels', 'LogicModels_Starter_ChooseRecord')
            );
        }
        return String.valueOf(recordId);
    }

    private static Starter starterFor(String starterKey) {
        for (Starter starter : starters) {
            if (starter.key == starterKey) {
                return starter;
            }
        }
        throw new LogicModelService.BuilderException(
            BarnHelp.text('LogicModels', 'LogicModels_Starter_Unavailable')
        );
    }

    /** A packaged object the person can read, or null. */
    private static Schema.SObjectType readable(String objectName) {
        Schema.SObjectType type = String.isBlank(objectName)
            ? null
            : NamespaceUtil.packagedObjectType(objectName);
        return type != null && type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()
            ? type
            : null;
    }

    /** A custom field's API name with whatever prefix the org needs; standard names as they are. */
    private static String qualified(String fieldName) {
        return fieldName != null && fieldName.endsWith('__c')
            ? NamespaceUtil.qualify(fieldName)
            : fieldName;
    }
}
