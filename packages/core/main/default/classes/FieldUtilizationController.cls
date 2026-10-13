/**
 * The Field Utilization page of the BarnCRM Settings console (canonical model Section 29F).
 *
 * It answers whether the weekly count is switched on, when it last ran and what it found, and
 * carries the only ways the list of objects is changed and the count is started. Every change
 * requires `Manage_BarnCRM_Settings`; the counting itself is in user mode (R-FU3).
 */
public with sharing class FieldUtilizationController {
    private static final String EDIT_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final String OBJECTS_KEY = 'Field_Utilization_Objects__c';
    private static final Integer KEY_LENGTH = 255;

    /** Raised with a message the page shows as it is. */
    public class FieldUtilizationException extends Exception {
    }

    /** One choice in the object picker. */
    public class Option {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
    }

    /** The page, in one round trip. */
    public class PageView {
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean scheduled;
        @AuraEnabled
        public Datetime nextRunAt;
        @AuraEnabled
        public Datetime lastRun;
        @AuraEnabled
        public String lastRunSummary;
        @AuraEnabled
        public List<String> tracked;
        @AuraEnabled
        public List<Option> choosable;
    }

    /** One field and record type from the latest run, with its change since the run before. */
    public class FieldRow {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String fieldLabel;
        @AuraEnabled
        public String fieldName;
        @AuraEnabled
        public String recordType;
        @AuraEnabled
        public Integer filled;
        @AuraEnabled
        public Integer total;
        @AuraEnabled
        public Decimal percent;
        @AuraEnabled
        public Decimal change;
        @AuraEnabled
        public Boolean sampled;
    }

    /** One object's latest results. */
    public class Results {
        @AuraEnabled
        public Datetime takenAt;
        @AuraEnabled
        public Datetime previousTakenAt;
        @AuraEnabled
        public List<FieldRow> rows = new List<FieldRow>();
    }

    @AuraEnabled(cacheable=true)
    public static PageView getView() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization page');
        }
    }

    /** The latest counts for one object, with the change since the run before (R-FU1 to R-FU8). */
    @AuraEnabled(cacheable=true)
    public static Results getResults(String objectName) {
        try {
            return resultsFor(objectName);
        } catch (Exception caught) {
            throw asUserError(caught, 'Field utilization results');
        }
    }

    /** Saves the objects to count. An empty list counts nothing. */
    @AuraEnabled
    public static PageView saveObjects(List<String> objectNames) {
        try {
            requirePermission();
            List<String> names = new List<String>();
            for (String name : objectNames == null ? new List<String>() : objectNames) {
                Schema.DescribeSObjectResult described = FieldUtilizationService.countable(name);
                if (described == null) {
                    throw new FieldUtilizationException(
                        String.format(
                            System.Label.Core_FieldUtilization_UnknownObject,
                            new List<Object>{ name }
                        )
                    );
                }
                if (!names.contains(described.getName())) {
                    names.add(described.getName());
                }
            }
            String joined = String.join(names, ',');
            if (joined.length() > KEY_LENGTH) {
                throw new FieldUtilizationException(System.Label.Core_FieldUtilization_TooMany);
            }
            SettingsService.saveSystemValue(OBJECTS_KEY, String.isBlank(joined) ? null : joined);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Save the field utilization objects');
        }
    }

    /** Starts or stops the weekly count. */
    @AuraEnabled
    public static PageView setSchedule(Boolean scheduled) {
        try {
            requirePermission();
            if (scheduled == true) {
                FieldUtilizationScheduler.start();
            } else {
                FieldUtilizationScheduler.stop();
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Schedule the field utilization count');
        }
    }

    /** Counts now. The page refreshes into the new last run once the batch ends. */
    @AuraEnabled
    public static PageView runNow() {
        try {
            requirePermission();
            if (FieldUtilizationService.trackedObjects().isEmpty()) {
                throw new FieldUtilizationException(
                    System.Label.Core_FieldUtilization_NothingChosen
                );
            }
            FieldUtilizationScheduler.runNow();
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Run the field utilization count now');
        }
    }

    private static PageView currentView() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        PageView view = new PageView();
        view.canManage = canManage();
        view.scheduled = FieldUtilizationScheduler.isScheduled();
        view.nextRunAt = FieldUtilizationScheduler.nextRunAt();
        view.lastRun = settings.Field_Utilization_Last_Run__c;
        view.lastRunSummary = settings.Field_Utilization_Last_Run_Summary__c;
        view.tracked = FieldUtilizationService.trackedObjects();
        view.choosable = choosable(view.tracked);
        return view;
    }

    /**
     * Account, Contact and every custom object the viewer can count, by label, plus anything
     * already tracked. Standard objects beyond these two are not offered: Core names no others.
     */
    private static List<Option> choosable(List<String> tracked) {
        List<String> names = new List<String>{
            Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
        };
        names.addAll(tracked);
        for (String name : Schema.getGlobalDescribe().keySet()) {
            if (name.endsWith('__c')) {
                names.add(name);
            }
        }
        Map<String, Option> byLabel = new Map<String, Option>();
        for (String name : names) {
            Schema.DescribeSObjectResult described = FieldUtilizationService.countable(name);
            if (described == null || !described.isCreateable()) {
                continue;
            }
            Option option = new Option();
            option.value = described.getName();
            option.label = described.getLabel();
            byLabel.put(option.label + '|' + option.value, option);
        }
        List<String> sortKeys = new List<String>(byLabel.keySet());
        sortKeys.sort();
        List<Option> options = new List<Option>();
        for (String sortKey : sortKeys) {
            options.add(byLabel.get(sortKey));
        }
        return options;
    }

    private static Results resultsFor(String objectName) {
        Results results = new Results();
        Schema.DescribeSObjectResult described = FieldUtilizationService.countable(objectName);
        if (described == null) {
            return results;
        }
        String name = described.getName();
        results.takenAt = FieldUtilizationSelector.latestRun(name);
        if (results.takenAt == null) {
            return results;
        }
        results.previousTakenAt = FieldUtilizationSelector.runBefore(name, results.takenAt);
        Set<Datetime> runs = new Set<Datetime>{ results.takenAt };
        if (results.previousTakenAt != null) {
            runs.add(results.previousTakenAt);
        }
        Map<String, Decimal> previous = new Map<String, Decimal>();
        List<Field_Utilization_Snapshot__c> latest = new List<Field_Utilization_Snapshot__c>();
        for (Field_Utilization_Snapshot__c row : FieldUtilizationSelector.rowsAt(name, runs)) {
            if (row.Taken_At__c == results.takenAt) {
                latest.add(row);
            } else {
                previous.put(keyOf(row), percentOf(row));
            }
        }
        Boolean grouped = FieldUtilizationService.groupsByRecordType(described);
        Map<String, Schema.RecordTypeInfo> recordTypes = described.getRecordTypeInfosByDeveloperName();
        for (Field_Utilization_Snapshot__c row : latest) {
            FieldRow shown = new FieldRow();
            shown.key = keyOf(row);
            shown.fieldLabel = row.Field_Label__c;
            shown.fieldName = row.Field_Name__c;
            shown.recordType = recordTypeLabel(grouped, recordTypes, row.Record_Type__c);
            shown.filled = row.Filled_Count__c == null ? 0 : row.Filled_Count__c.intValue();
            shown.total = row.Record_Count__c == null ? 0 : row.Record_Count__c.intValue();
            shown.percent = percentOf(row);
            shown.sampled = row.Sampled__c == true;
            Decimal before = previous.get(shown.key);
            shown.change = before == null ||
                shown.percent == null
                ? null
                : (shown.percent - before).setScale(1);
            results.rows.add(shown);
        }
        return results;
    }

    private static String recordTypeLabel(
        Boolean grouped,
        Map<String, Schema.RecordTypeInfo> recordTypes,
        String developerName
    ) {
        if (!grouped) {
            return '';
        }
        if (String.isBlank(developerName)) {
            return System.Label.Core_FieldUtilization_NoRecordType;
        }
        Schema.RecordTypeInfo info = recordTypes.get(developerName);
        return info == null ? developerName : info.getName();
    }

    private static String keyOf(Field_Utilization_Snapshot__c row) {
        return row.Field_Name__c + '|' + (row.Record_Type__c == null ? '' : row.Record_Type__c);
    }

    private static Decimal percentOf(Field_Utilization_Snapshot__c row) {
        if (
            row.Record_Count__c == null ||
            row.Record_Count__c == 0 ||
            row.Filled_Count__c == null
        ) {
            return null;
        }
        return (row.Filled_Count__c * 100).divide(row.Record_Count__c, 1);
    }

    private static Boolean canManage() {
        return FeatureManagement.checkPermission(EDIT_PERMISSION);
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new FieldUtilizationException(
                System.Label.Core_FieldUtilization_PermissionRequired
            );
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof FieldUtilizationException)) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_FieldUtilization_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
