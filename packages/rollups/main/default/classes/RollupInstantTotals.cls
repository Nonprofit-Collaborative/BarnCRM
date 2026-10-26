/**
 * Instant totals on an object BarnCRM ships no trigger for: a standard object, another
 * package's object or the organization's own (canonical model R-R12, ADR-0138).
 *
 * The Rollup Builder generates a one-line trigger and its test for the object, and the
 * administrator deploys them: in a sandbox and then with a change set, or with the Salesforce
 * CLI from the deploy package built here. BarnCRM deploys nothing itself (ADR-0138 says why).
 * The names come from the object's API name, so the same object gives the same code in every
 * org and a sandbox's change set lands exactly what the production Builder expects to find.
 *
 * Each object's state is read from the org, never remembered: Built in (a BarnCRM registry row
 * already runs `RollupTriggerHandler` on it), On, Turned off (its switch), Inactive in Setup,
 * Not set up, or Not available (the platform allows no Apex trigger on it). The switch is an
 * Automation Setting named after the trigger, so turning instant totals off takes effect at
 * once, in production too, and shows on the Automation page with every other switch.
 *
 * Every object name reaches the generated code only after describe has resolved it, and is
 * written back from describe, so nothing typed reaches the code or the package files.
 */
public with sharing class RollupInstantTotals {
    public static final String STATUS_BUILT_IN = 'builtIn';
    public static final String STATUS_ON = 'on';
    public static final String STATUS_OFF = 'off';
    public static final String STATUS_INACTIVE = 'inactive';
    public static final String STATUS_NOT_SET_UP = 'notSetUp';
    public static final String STATUS_NOT_AVAILABLE = 'notAvailable';

    /** The API version of the generated files: the version this package itself is built on. */
    @TestVisible
    private static final String API_VERSION = '67.0';
    private static final String METADATA_NAMESPACE = 'http://soap.sforce.com/2006/04/metadata';
    private static final String TRIGGER_ACTIVE = 'Active';

    /** Test seam: the org's generated triggers, in place of the `ApexTrigger` query. */
    @TestVisible
    private static List<GeneratedTrigger> triggersOverride;

    /** Test seam: the objects that can carry a trigger, in place of `EntityDefinition`. */
    @TestVisible
    private static Set<String> triggerableOverride;

    /** One object an instant rollup counts, or that has a generated trigger, as the Builder shows it. */
    public class ObjectState {
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String triggerName;
        @AuraEnabled
        public String testClassName;
        /** Active Instantly or Both rollups that count this object. */
        @AuraEnabled
        public Integer instantRollups;
    }

    /** What "Turn on instant totals" and "Remove the trigger" show and download. */
    public class GeneratedCode {
        @AuraEnabled
        public String triggerName;
        @AuraEnabled
        public String testClassName;
        @AuraEnabled
        public String triggerSource;
        @AuraEnabled
        public String testSource;
        /** Base64 Metadata API zip: package.xml, the trigger and the test. */
        @AuraEnabled
        public String deployPackage;
        /** Base64 Metadata API zip: an empty package.xml and destructiveChanges.xml. */
        @AuraEnabled
        public String removalPackage;
    }

    /** A trigger in this org with a generated name. */
    @TestVisible
    private class GeneratedTrigger {
        String name;
        String status;
        String objectApiName;

        @TestVisible
        GeneratedTrigger(String name, String status, String objectApiName) {
            this.name = name;
            this.status = status;
            this.objectApiName = objectApiName;
        }
    }

    // ------------------------------------------------------------------------------- the Builder

    /**
     * Every object an active Instantly or Both rollup counts, and every object that has a
     * generated trigger whether a rollup still counts it or not, sorted by label.
     */
    @AuraEnabled
    public static List<ObjectState> getStates() {
        try {
            Map<String, Integer> rollupsByObject = instantRollupsByObject();
            Map<String, GeneratedTrigger> triggers = triggersByName();
            Map<String, Schema.SObjectType> types = new Map<String, Schema.SObjectType>();
            for (String objectName : rollupsByObject.keySet()) {
                addType(types, objectName);
            }
            for (GeneratedTrigger found : triggers.values()) {
                addType(types, found.objectApiName);
            }
            Set<String> triggerable = triggerableAmong(types.keySet());
            List<ObjectState> states = new List<ObjectState>();
            for (String objectName : types.keySet()) {
                Integer count = rollupsByObject.get(objectName);
                states.add(
                    stateOf(types.get(objectName), count == null ? 0 : count, triggers, triggerable)
                );
            }
            return sortedByLabel(states);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** One object's state, for the Builder's step 5. */
    @AuraEnabled
    public static ObjectState getState(String objectApiName) {
        try {
            return stateOf(requireType(objectApiName));
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** The trigger, its test, and the deploy and removal packages for one object. */
    @AuraEnabled
    public static GeneratedCode getCode(String objectApiName) {
        try {
            Schema.SObjectType type = requireType(objectApiName);
            String name = apiNameOf(type);
            if (isBuiltIn(type)) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupBuilder_InstantBuiltInError
                );
            }
            if (!triggerableAmong(new Set<String>{ name }).contains(name)) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupBuilder_InstantNotAvailableError
                );
            }
            GeneratedCode code = new GeneratedCode();
            code.triggerName = triggerNameFor(name);
            code.testClassName = testClassNameFor(name);
            code.triggerSource = triggerSource(name);
            code.testSource = testSource(name);
            code.deployPackage = EncodingUtil.base64Encode(deployPackage(name));
            code.removalPackage = EncodingUtil.base64Encode(removalPackage(name));
            return code;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Turns instant totals on this object off or back on, through its switch, with no deploy.
     * The switch row is made the first time (`AutomationControl.ensureSwitch`), which, like the
     * switch itself, needs the Manage BarnCRM Settings permission.
     */
    @AuraEnabled
    public static ObjectState setTurnedOn(String objectApiName, Boolean turnedOn) {
        try {
            Schema.SObjectType type = requireType(objectApiName);
            String name = apiNameOf(type);
            // The switch is named after the trigger (RollupInstantTrigger reads it by that name).
            String automationName = triggerNameFor(name);
            String objectLabel = type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
            AutomationControl.ensureSwitch(
                automationName,
                String.format(
                    Label.Core_RollupBuilder_InstantSwitchName,
                    new List<Object>{ objectLabel }
                ),
                name,
                String.format(
                    Label.Core_RollupBuilder_InstantSwitchDescription,
                    new List<Object>{ automationName }
                )
            );
            AutomationControl.setEnabled(automationName, turnedOn == true);
            return stateOf(type);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    // --------------------------------------------------------------------------- generated code

    private static String triggerNameFor(String objectApiName) {
        return RollupInstantTrigger.triggerNameFor(objectApiName);
    }

    private static String testClassNameFor(String objectApiName) {
        return RollupInstantTrigger.testClassNameFor(objectApiName);
    }

    /**
     * The entry point as subscriber code must name it: `ns.RollupInstantTrigger` once there is
     * a namespace, the bare name until then (never hard-coded, ADR-0001).
     */
    private static String entryPoint() {
        return RollupInstantTrigger.class.getName();
    }

    @TestVisible
    private static String triggerSource(String objectApiName) {
        return '/*\n' +
            ' * Generated by the BarnCRM Rollup Builder. Keeps the instant rollups that count\n' +
            ' * ' +
            objectApiName +
            ' up to date; how each total is worked out stays in the rollup.\n' +
            ' * Do not edit: every org gets the same code. Turn it off in the Rollup Builder.\n' +
            ' */\n' +
            'trigger ' +
            triggerNameFor(objectApiName) +
            ' on ' +
            objectApiName +
            ' (before insert, after insert, after update, before delete, after delete, after undelete) {\n' +
            '    ' +
            entryPoint() +
            '.run();\n' +
            '}\n';
    }

    @TestVisible
    private static String testSource(String objectApiName) {
        return '/*\n' +
            ' * Generated by the BarnCRM Rollup Builder: the test for the trigger ' +
            triggerNameFor(objectApiName) +
            '.\n' +
            ' */\n' +
            '@IsTest\n' +
            'private class ' +
            testClassNameFor(objectApiName) +
            ' {\n' +
            '    @IsTest\n' +
            '    static void savingARecordRunsTheRollupTrigger() {\n' +
            '        // The trigger runs before this org\'s required fields and validation rules\n' +
            '        // are checked, so the empty record may be refused: the trigger has still run.\n' +
            '        Database.insert(new List<SObject>{ new ' +
            objectApiName +
            '() }, false, AccessLevel.SYSTEM_MODE);\n' +
            '        System.assert(' +
            entryPoint() +
            '.hasRun(), \'The BarnCRM rollup trigger did not run.\');\n' +
            '    }\n' +
            '}\n';
    }

    private static String metaXml(String type) {
        return '<?xml version="1.0" encoding="UTF-8"?>\n<' +
            type +
            ' xmlns="' +
            METADATA_NAMESPACE +
            '">\n    <apiVersion>' +
            API_VERSION +
            '</apiVersion>\n    <status>Active</status>\n</' +
            type +
            '>\n';
    }

    /** A package.xml, or a destructiveChanges.xml, naming the trigger and its test, or nothing. */
    private static String packageXml(String objectApiName, Boolean naming) {
        String types = naming
            ? '    <types>\n        <members>' +
              triggerNameFor(objectApiName) +
              '</members>\n        <name>ApexTrigger</name>\n    </types>\n' +
              '    <types>\n        <members>' +
              testClassNameFor(objectApiName) +
              '</members>\n        <name>ApexClass</name>\n    </types>\n'
            : '';
        return '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="' +
            METADATA_NAMESPACE +
            '">\n' +
            types +
            '    <version>' +
            API_VERSION +
            '</version>\n</Package>\n';
    }

    @TestVisible
    private static Blob deployPackage(String objectApiName) {
        String triggerName = triggerNameFor(objectApiName);
        String testName = testClassNameFor(objectApiName);
        Compression.ZipWriter zip = new Compression.ZipWriter();
        zip.addEntry('package.xml', Blob.valueOf(packageXml(objectApiName, true)));
        zip.addEntry(
            'triggers/' + triggerName + '.trigger',
            Blob.valueOf(triggerSource(objectApiName))
        );
        zip.addEntry(
            'triggers/' + triggerName + '.trigger-meta.xml',
            Blob.valueOf(metaXml('ApexTrigger'))
        );
        zip.addEntry('classes/' + testName + '.cls', Blob.valueOf(testSource(objectApiName)));
        zip.addEntry('classes/' + testName + '.cls-meta.xml', Blob.valueOf(metaXml('ApexClass')));
        return zip.getArchive();
    }

    @TestVisible
    private static Blob removalPackage(String objectApiName) {
        Compression.ZipWriter zip = new Compression.ZipWriter();
        zip.addEntry('package.xml', Blob.valueOf(packageXml(objectApiName, false)));
        zip.addEntry('destructiveChanges.xml', Blob.valueOf(packageXml(objectApiName, true)));
        return zip.getArchive();
    }

    // ------------------------------------------------------------------------------------ state

    private static ObjectState stateOf(Schema.SObjectType type) {
        String name = apiNameOf(type);
        Integer count = instantRollupsByObject().get(name);
        return stateOf(
            type,
            count == null ? 0 : count,
            triggersByName(),
            triggerableAmong(new Set<String>{ name })
        );
    }

    private static ObjectState stateOf(
        Schema.SObjectType type,
        Integer instantRollups,
        Map<String, GeneratedTrigger> triggers,
        Set<String> triggerable
    ) {
        String name = apiNameOf(type);
        ObjectState state = new ObjectState();
        state.objectApiName = name;
        state.objectLabel = type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
        state.triggerName = triggerNameFor(name);
        state.testClassName = testClassNameFor(name);
        state.instantRollups = instantRollups;
        GeneratedTrigger found = triggers.get(state.triggerName.toLowerCase());
        if (isBuiltIn(type)) {
            state.status = STATUS_BUILT_IN;
        } else if (found != null && TRIGGER_ACTIVE.equalsIgnoreCase(found.status)) {
            state.status = AutomationControl.isEnabled(state.triggerName) ? STATUS_ON : STATUS_OFF;
        } else if (found != null) {
            state.status = STATUS_INACTIVE;
        } else if (triggerable.contains(name)) {
            state.status = STATUS_NOT_SET_UP;
        } else {
            state.status = STATUS_NOT_AVAILABLE;
        }
        return state;
    }

    /** Active Instantly and Both rollups, counted by the API name of the object they count. */
    private static Map<String, Integer> instantRollupsByObject() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (
            Rollup_Definition__c definition : RollupSelector.selectActiveForModes(
                new Set<String>{ RollupService.MODE_REAL_TIME, RollupService.MODE_BOTH }
            )
        ) {
            Schema.SObjectType type = SettingsService.typeByName(definition.Source_Object__c);
            if (type == null) {
                continue;
            }
            String name = apiNameOf(type);
            counts.put(name, counts.containsKey(name) ? counts.get(name) + 1 : 1);
        }
        return counts;
    }

    /** True when a BarnCRM registry row already runs the rollup handler on this object. */
    private static Boolean isBuiltIn(Schema.SObjectType type) {
        String handler = RollupTriggerHandler.class.getName();
        for (Automation_Registry__mdt entry : Automation_Registry__mdt.getAll().values()) {
            if (
                String.isNotBlank(entry.Handler_Class__c) &&
                handler.endsWithIgnoreCase(entry.Handler_Class__c.trim()) &&
                SettingsService.typeByName(entry.Object_Name__c) == type
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * The generated triggers in this org, by lower-case name. Read in system mode: they are
     * the org's metadata, which a Builder user may not have View Setup to read, and only their
     * name, status and object leave this method.
     */
    private static Map<String, GeneratedTrigger> triggersByName() {
        List<GeneratedTrigger> found = triggersOverride;
        if (found == null) {
            found = new List<GeneratedTrigger>();
            String pattern = RollupInstantTrigger.namePrefix().replace('_', '\\_') + '%';
            List<ApexTrigger> rows = [
                SELECT Name, Status, TableEnumOrId
                FROM ApexTrigger
                WHERE Name LIKE :pattern AND NamespacePrefix = NULL
                WITH SYSTEM_MODE
                ORDER BY Name
                LIMIT 1000
            ];
            Map<String, String> customObjectNames = customObjectNames(rows);
            for (ApexTrigger row : rows) {
                String objectName = customObjectNames.containsKey(row.TableEnumOrId)
                    ? customObjectNames.get(row.TableEnumOrId)
                    : row.TableEnumOrId;
                found.add(new GeneratedTrigger(row.Name, row.Status, objectName));
            }
        }
        Map<String, GeneratedTrigger> byName = new Map<String, GeneratedTrigger>();
        for (GeneratedTrigger generated : found) {
            byName.put(generated.name.toLowerCase(), generated);
        }
        return byName;
    }

    /**
     * A trigger on a custom object names the object by its id, not its API name: the names of
     * those objects, keyed by the id as the trigger gives it.
     */
    private static Map<String, String> customObjectNames(List<ApexTrigger> rows) {
        Map<String, String> byShortId = new Map<String, String>();
        Map<String, String> fullIdByShort = new Map<String, String>();
        for (ApexTrigger row : rows) {
            String tableId = row.TableEnumOrId;
            if (String.isNotBlank(tableId) && tableId.length() >= 15 && tableId.startsWith('01I')) {
                fullIdByShort.put(tableId.left(15), tableId);
            }
        }
        if (fullIdByShort.isEmpty()) {
            return byShortId;
        }
        Set<String> durableIds = new Set<String>(fullIdByShort.keySet());
        durableIds.addAll(fullIdByShort.values());
        for (EntityDefinition entity : [
            SELECT QualifiedApiName, DurableId
            FROM EntityDefinition
            WHERE DurableId IN :durableIds
            WITH SYSTEM_MODE
        ]) {
            String shortId = entity.DurableId.left(15);
            if (fullIdByShort.containsKey(shortId)) {
                byShortId.put(fullIdByShort.get(shortId), entity.QualifiedApiName);
            }
        }
        return byShortId;
    }

    /** The names among these that the platform lets carry an Apex trigger. */
    private static Set<String> triggerableAmong(Set<String> objectNames) {
        if (triggerableOverride != null) {
            Set<String> allowed = new Set<String>();
            for (String name : objectNames) {
                if (triggerableOverride.contains(name)) {
                    allowed.add(name);
                }
            }
            return allowed;
        }
        Set<String> triggerable = new Set<String>();
        if (objectNames.isEmpty()) {
            return triggerable;
        }
        for (EntityDefinition entity : [
            SELECT QualifiedApiName, IsApexTriggerable
            FROM EntityDefinition
            WHERE QualifiedApiName IN :objectNames
            WITH SYSTEM_MODE
        ]) {
            if (entity.IsApexTriggerable) {
                triggerable.add(entity.QualifiedApiName);
            }
        }
        return triggerable;
    }

    // ---------------------------------------------------------------------------------- helpers

    private static void addType(Map<String, Schema.SObjectType> types, String objectName) {
        Schema.SObjectType type = SettingsService.typeByName(objectName);
        if (type != null) {
            types.put(apiNameOf(type), type);
        }
    }

    private static String apiNameOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
    }

    private static Schema.SObjectType requireType(String objectApiName) {
        Schema.SObjectType type = SettingsService.typeByName(objectApiName);
        if (type == null) {
            throw new RollupService.RollupServiceException(Label.Core_Rollups_ErrorUnknownObject);
        }
        return type;
    }

    private static List<ObjectState> sortedByLabel(List<ObjectState> states) {
        Map<String, ObjectState> byKey = new Map<String, ObjectState>();
        for (ObjectState state : states) {
            byKey.put(state.objectLabel.toLowerCase() + '|' + state.objectApiName, state);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<ObjectState> sorted = new List<ObjectState>();
        for (String key : keys) {
            sorted.add(byKey.get(key));
        }
        return sorted;
    }

    private static AuraHandledException asUserError(Exception caught) {
        String message;
        if (
            caught instanceof RollupService.RollupServiceException ||
            caught instanceof AutomationControl.AutomationControlException
        ) {
            message = caught.getMessage();
        } else if (caught instanceof DmlException) {
            message = ((DmlException) caught).getDmlMessage(0);
        } else {
            ErrorLogger.log(caught, 'RollupInstantTotals');
            message = Label.Core_Rollups_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
