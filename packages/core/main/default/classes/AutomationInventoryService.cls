/**
 * The automation inventory in the Data Dictionary section of Org Optimizer (plan 6.1.5 item
 * C-60, canonical model Section 29F-2 rules R-AI1 to R-AI4): for one object, the Apex triggers and
 * the record-triggered flows (and processes) that run on it.
 *
 * Read only, and only what a user-mode SOQL query can read: `ApexTrigger`, `FlowDefinitionView`
 * and `EntityDefinition` (to turn a custom object's name into the Id a flow names it by).
 * Validation rules, workflow rules and process builder criteria need the Tooling API and are not
 * covered; the page and the guide say so. Flows that are not triggered by a record (screen flows,
 * scheduled flows) belong to no object and are not listed.
 */
public with sharing class AutomationInventoryService {
    /** The most triggers, and the most flows, listed for one object. */
    @TestVisible
    private static final Integer MAX_PER_TYPE = 200;

    public static final String TYPE_TRIGGER = 'ApexTrigger';
    public static final String TYPE_FLOW = 'Flow';

    /** The events a trigger runs on, by the field that says so, in the order Apex lists them. */
    private static final List<String> TRIGGER_FIELDS = new List<String>{
        'UsageBeforeInsert',
        'UsageBeforeUpdate',
        'UsageBeforeDelete',
        'UsageAfterInsert',
        'UsageAfterUpdate',
        'UsageAfterDelete',
        'UsageAfterUndelete'
    };

    /** A flow's trigger type (the point in the save it runs at), in words. */
    private static final Map<String, String> FLOW_TRIGGERS = new Map<String, String>{
        'RecordBeforeSave' => 'Before save',
        'RecordAfterSave' => 'After save',
        'RecordBeforeDelete' => 'Before delete',
        'PlatformEvent' => 'Platform event'
    };

    /** A flow's process type, in words, for the kinds that are not a plain flow. */
    private static final Map<String, String> PROCESS_TYPES = new Map<String, String>{
        'Workflow' => 'Process Builder',
        'CustomEvent' => 'Platform event flow',
        'InvocableProcess' => 'Process Builder'
    };

    /** One trigger or flow that runs on the object. */
    public class Item {
        public String automationType;
        public String name;
        public String apiName;
        public String status;
        public String detail;
        public Integer apiVersion;
    }

    public class Result {
        public List<Item> items = new List<Item>();
        /** True when the triggers (or the flows) could not be read. */
        public Boolean triggersFailed = false;
        public Boolean flowsFailed = false;
        /** True when a type stopped at MAX_PER_TYPE. */
        public Boolean truncated = false;
    }

    /** Test hook: a query kind (trigger or flow) made to fail. */
    @TestVisible
    private static String failType;

    public static Result forObject(Schema.DescribeSObjectResult described) {
        Result result = new Result();
        Map<String, Object> binds = new Map<String, Object>{
            'keys' => objectKeys(described),
            'readUpTo' => MAX_PER_TYPE + 1
        };
        try {
            fail(TYPE_TRIGGER);
            List<SObject> triggers = Database.queryWithBinds(
                'SELECT Name, Status, ApiVersion, UsageBeforeInsert, UsageAfterInsert,' +
                    ' UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete, UsageAfterDelete,' +
                    ' UsageAfterUndelete FROM ApexTrigger WHERE TableEnumOrId IN :keys' +
                    ' ORDER BY Name LIMIT :readUpTo',
                binds,
                AccessLevel.USER_MODE
            );
            result.truncated = result.truncated || triggers.size() > MAX_PER_TYPE;
            for (Integer i = 0; i < Math.min(triggers.size(), MAX_PER_TYPE); i++) {
                result.items.add(triggerItem(triggers[i]));
            }
        } catch (Exception unreadable) {
            result.triggersFailed = true;
        }
        try {
            fail(TYPE_FLOW);
            List<SObject> flows = Database.queryWithBinds(
                'SELECT ApiName, Label, IsActive, ProcessType, TriggerType, ApiVersion' +
                    ' FROM FlowDefinitionView WHERE TriggerObjectOrEventId IN :keys' +
                    ' ORDER BY Label LIMIT :readUpTo',
                binds,
                AccessLevel.USER_MODE
            );
            result.truncated = result.truncated || flows.size() > MAX_PER_TYPE;
            for (Integer i = 0; i < Math.min(flows.size(), MAX_PER_TYPE); i++) {
                result.items.add(flowItem(flows[i]));
            }
        } catch (Exception unreadable) {
            result.flowsFailed = true;
        }
        return result;
    }

    /**
     * What a trigger or flow calls the object: its API name, and for a custom object the Id
     * (the 15 character form) as well, because a flow names a custom object by Id. When
     * EntityDefinition cannot be read the name alone is used.
     */
    private static List<String> objectKeys(Schema.DescribeSObjectResult described) {
        List<String> keys = new List<String>{ described.getName() };
        if (described.isCustom()) {
            try {
                for (
                    SObject row : Database.queryWithBinds(
                        'SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = :name',
                        new Map<String, Object>{ 'name' => described.getName() },
                        AccessLevel.USER_MODE
                    )
                ) {
                    String durable = (String) row.get('DurableId');
                    keys.add(durable);
                    if (durable != null && durable.length() > 15) {
                        keys.add(durable.left(15));
                    }
                }
            } catch (Exception unreadable) {
                // Triggers still match by name; a flow on this custom object may be missed, and
                // the page does not claim more than it read.
                keys = new List<String>{ described.getName() };
            }
        }
        return keys;
    }

    private static Item triggerItem(SObject row) {
        Item item = new Item();
        item.automationType = TYPE_TRIGGER;
        item.name = (String) row.get('Name');
        item.apiName = item.name;
        item.status = (String) row.get('Status');
        item.apiVersion = row.get('ApiVersion') == null
            ? null
            : ((Decimal) row.get('ApiVersion')).intValue();
        List<String> events = new List<String>();
        for (String field : TRIGGER_FIELDS) {
            if (row.get(field) == true) {
                // UsageBeforeInsert reads "before insert".
                events.add(
                    field.substringAfter('Usage')
                        .replaceAll('([a-z])([A-Z])', '$1 $2')
                        .toLowerCase()
                );
            }
        }
        item.detail = String.join(events, ', ');
        return item;
    }

    private static Item flowItem(SObject row) {
        Item item = new Item();
        item.automationType = TYPE_FLOW;
        item.name = (String) row.get('Label');
        item.apiName = (String) row.get('ApiName');
        item.status = row.get('IsActive') == true ? 'Active' : 'Inactive';
        item.apiVersion = row.get('ApiVersion') == null
            ? null
            : ((Decimal) row.get('ApiVersion')).intValue();
        String triggerType = (String) row.get('TriggerType');
        String processType = (String) row.get('ProcessType');
        List<String> parts = new List<String>();
        if (PROCESS_TYPES.containsKey(processType)) {
            parts.add(PROCESS_TYPES.get(processType));
        }
        if (triggerType != null) {
            parts.add(
                FLOW_TRIGGERS.containsKey(triggerType)
                    ? FLOW_TRIGGERS.get(triggerType)
                    : triggerType
            );
        }
        item.detail = String.join(parts, ', ');
        return item;
    }

    private static void fail(String type) {
        if (type == failType) {
            throw new QueryException('Made to fail by a test.');
        }
    }
}
