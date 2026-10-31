/**
 * What the Automation page of the BarnCRM Settings console reads and writes.
 *
 * Every method returns the whole page, so the component never has to work out what changed, and
 * every write is refused for a user without the Manage BarnCRM Settings permission with a
 * message that names the permission.
 */
public with sharing class AutomationControlController {
    /**
     * One row in the list: what it does, and whether it is running.
     */
    public class AutomationView {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String automationName { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public String objectName { get; set; }
        @AuraEnabled
        public Boolean enabled { get; set; }
        /** True when this automation enforces a rule, so its switch is shown off and disabled. */
        @AuraEnabled
        public Boolean alwaysRuns { get; set; }
    }

    /**
     * The whole page: the pause, the permission, and the list.
     */
    public class AutomationPageView {
        @AuraEnabled
        public Boolean paused { get; set; }
        @AuraEnabled
        public Datetime pausedUntil { get; set; }
        /** Who started the pause in effect, from the audit trail; null when not known. */
        @AuraEnabled
        public String pausedBy { get; set; }
        @AuraEnabled
        public Boolean canManage { get; set; }
        @AuraEnabled
        public List<Integer> pauseHourOptions { get; set; }
        @AuraEnabled
        public List<AutomationView> automations { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static AutomationPageView getPage() {
        try {
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Automation page');
        }
    }

    @AuraEnabled
    public static AutomationPageView pauseAll(Integer hours) {
        try {
            requirePermission();
            AutomationControl.pauseAll(hours);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Pause all automation');
        }
    }

    @AuraEnabled
    public static AutomationPageView resumeAll() {
        try {
            requirePermission();
            AutomationControl.resumeAll();
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Resume automation');
        }
    }

    @AuraEnabled
    public static AutomationPageView setEnabled(String automationName, Boolean enabled) {
        try {
            requirePermission();
            if (String.isBlank(automationName)) {
                throw new AutomationControl.AutomationControlException(
                    Label.Core_Automation_NameRequired
                );
            }
            AutomationControl.setEnabled(automationName, enabled == true);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Switch an automation');
        }
    }

    private static AutomationPageView currentPage() {
        AutomationPageView page = new AutomationPageView();
        page.pausedUntil = AutomationControl.pausedUntil();
        page.paused = page.pausedUntil != null;
        page.pausedBy = page.paused ? AutomationControl.pausedBy() : null;
        page.canManage = canManage();
        page.pauseHourOptions = new List<Integer>(AutomationControl.allowedPauseHours());
        page.pauseHourOptions.sort();
        page.automations = new List<AutomationView>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForConsole()) {
            AutomationView view = new AutomationView();
            view.recordId = setting.Id;
            view.automationName = setting.Automation_Name__c;
            view.label = setting.Name;
            view.description = setting.Description__c;
            view.objectName = objectLabel(setting.Object_Name__c);
            view.alwaysRuns = setting.Always_Runs__c == true;
            // A rule enforcing automation is never running "on" a switch: it is shown off, and
            // disabled, so nobody reads the page as saying it can be turned on (ADR-0024).
            view.enabled = view.alwaysRuns ? false : setting.Enabled__c;
            page.automations.add(view);
        }
        return page;
    }

    /**
     * The object's label in this org ("Household Member", not "Household_Member__c"). A name
     * that is not an object here, or that cannot be described, is shown as stored.
     */
    @TestVisible
    private static String objectLabel(String apiName) {
        if (String.isBlank(apiName)) {
            return apiName;
        }
        try {
            Schema.DescribeSObjectResult described = Schema.describeSObjects(
                new List<String>{ apiName.trim() },
                SObjectDescribeOptions.DEFERRED
            )[0];
            return described.getLabel();
        } catch (Exception notAnObject) {
            return apiName;
        }
    }

    private static Boolean canManage() {
        // Bare, and correctly so: a custom permission defined in the same package resolves without
        // a namespace prefix, so this is not the B5 problem that TriggerHandler.getName had.
        return BarnCRMPermissions.canManageSettings();
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new AutomationControl.AutomationControlException(
                Label.Core_Automation_NoPermission
            );
        }
    }

    /**
     * Turns anything that went wrong into a message the page can show, and records the ones the
     * page cannot explain.
     */
    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof AutomationControl.AutomationControlException,
            context,
            Label.Core_Automation_UnexpectedError
        );
    }
}
