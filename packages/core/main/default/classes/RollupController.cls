/**
 * What the Rollups page of the BarnCRM Settings console reads and writes.
 *
 * Every method returns the whole page, so the component never has to work out what changed, and
 * every write is refused for a user without the Manage BarnCRM Settings permission with a
 * message that names the permission. The page is reached the way ADR-0020 requires: it is a Core
 * component, so `settingsConsole` imports it by name from its own registry, and the Setting
 * Definition row that puts it in the Rollups section names it in `Component__c`.
 */
public with sharing class RollupController {
    /** One rollup, as the administrator reads it. */
    public class RollupView {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public String definitionKey { get; set; }
        @AuraEnabled
        public String sourceObject { get; set; }
        @AuraEnabled
        public String targetObject { get; set; }
        @AuraEnabled
        public String targetField { get; set; }
        @AuraEnabled
        public String relationshipPath { get; set; }
        @AuraEnabled
        public String aggregate { get; set; }
        @AuraEnabled
        public String sourceField { get; set; }
        @AuraEnabled
        public String mode { get; set; }
        @AuraEnabled
        public Boolean fiscalYearAware { get; set; }
        @AuraEnabled
        public Decimal fiscalYearOffset { get; set; }
        @AuraEnabled
        public Boolean active { get; set; }
        @AuraEnabled
        public Boolean packageDefault { get; set; }
        @AuraEnabled
        public Datetime lastCalculated { get; set; }
        @AuraEnabled
        public String filterJson { get; set; }
        @AuraEnabled
        public String targetFilterJson { get; set; }
    }

    /** The whole page: the schedule, the freshness, the permission, and the list. */
    public class RollupPageView {
        @AuraEnabled
        public Boolean canManage { get; set; }
        @AuraEnabled
        public Boolean scheduled { get; set; }
        @AuraEnabled
        public Datetime nextRunAt { get; set; }
        @AuraEnabled
        public Datetime lastCalculated { get; set; }
        @AuraEnabled
        public Boolean stale { get; set; }
        @AuraEnabled
        public String defaultMode { get; set; }
        @AuraEnabled
        public List<String> modes { get; set; }
        @AuraEnabled
        public List<RollupView> rollups { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static RollupPageView getPage() {
        try {
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Rollups page');
        }
    }

    /** Creates the shipped rollups this org does not have yet, and never touches the ones it has. */
    @AuraEnabled
    public static RollupPageView restoreDefaults() {
        try {
            requirePermission();
            RollupService.ensureDefaults();
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Restore shipped rollups');
        }
    }

    /** Turns one rollup on or off. Turning it off never removes the values already calculated. */
    @AuraEnabled
    public static RollupPageView setActive(Id definitionId, Boolean active) {
        try {
            requirePermission();
            Rollup_Definition__c definition = require(definitionId);
            RollupWriter.saveAsUser(
                new Rollup_Definition__c(Id = definition.Id, Active__c = active == true)
            );
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Switch a rollup');
        }
    }

    /** Changes when one rollup is recalculated. */
    @AuraEnabled
    public static RollupPageView setMode(Id definitionId, String mode) {
        try {
            requirePermission();
            Rollup_Definition__c definition = require(definitionId);
            if (!isKnownMode(mode)) {
                throw new RollupService.RollupServiceException(Label.Core_Rollups_ErrorInvalidMode);
            }
            RollupWriter.saveAsUser(new Rollup_Definition__c(Id = definition.Id, Mode__c = mode));
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Change a rollup mode');
        }
    }

    /** Recalculates one rollup now. This is the admin's recalculate action (plan Section 4.10). */
    @AuraEnabled
    public static RollupPageView recalculate(Id definitionId) {
        try {
            requirePermission();
            require(definitionId);
            RollupService.recalculate(definitionId);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Recalculate a rollup');
        }
    }

    /** Runs the nightly work now, over every scheduled rollup. */
    @AuraEnabled
    public static RollupPageView recalculateAll() {
        try {
            requirePermission();
            RollupScheduler.runNow();
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Recalculate all rollups');
        }
    }

    /** Starts or stops the nightly recalculation. */
    @AuraEnabled
    public static RollupPageView setSchedule(Boolean scheduled) {
        try {
            requirePermission();
            if (scheduled == true) {
                RollupScheduler.start();
            } else {
                RollupScheduler.stop();
            }
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Schedule the nightly rollups');
        }
    }

    private static RollupPageView currentPage() {
        RollupPageView page = new RollupPageView();
        page.canManage = canManage();
        page.scheduled = RollupScheduler.isScheduled();
        page.nextRunAt = RollupScheduler.nextRunAt();
        page.lastCalculated = RollupService.lastCalculated();
        page.stale = RollupService.isStale();
        page.defaultMode = RollupService.defaultMode();
        page.modes = new List<String>{
            RollupService.MODE_REAL_TIME,
            RollupService.MODE_SCHEDULED,
            RollupService.MODE_BOTH
        };
        page.rollups = new List<RollupView>();
        for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
            page.rollups.add(toView(definition));
        }
        return page;
    }

    private static RollupView toView(Rollup_Definition__c definition) {
        RollupView view = new RollupView();
        view.recordId = definition.Id;
        view.name = definition.Name;
        view.description = definition.Description__c;
        view.definitionKey = definition.Definition_Key__c;
        view.sourceObject = definition.Source_Object__c;
        view.targetObject = definition.Target_Object__c;
        view.targetField = definition.Target_Field__c;
        view.relationshipPath = definition.Relationship_Path__c;
        view.aggregate = definition.Aggregate__c;
        view.sourceField = definition.Source_Field__c;
        view.mode = definition.Mode__c;
        view.fiscalYearAware = definition.Fiscal_Year_Aware__c;
        view.fiscalYearOffset = definition.Fiscal_Year_Offset__c;
        view.active = definition.Active__c;
        view.packageDefault = definition.Is_Package_Default__c;
        view.lastCalculated = definition.Last_Calculated__c;
        view.filterJson = definition.Filter_JSON__c;
        view.targetFilterJson = definition.Target_Filter_JSON__c;
        return view;
    }

    private static Boolean isKnownMode(String mode) {
        return RollupService.MODE_REAL_TIME.equals(mode) ||
            RollupService.MODE_SCHEDULED.equals(mode) ||
            RollupService.MODE_BOTH.equals(mode);
    }

    private static Rollup_Definition__c require(Id definitionId) {
        Rollup_Definition__c definition = RollupSelector.selectById(definitionId);
        if (definition == null) {
            throw new RollupService.RollupServiceException(
                Label.Core_Rollups_ErrorUnknownDefinition
            );
        }
        return definition;
    }

    private static Boolean canManage() {
        return FeatureManagement.checkPermission('Manage_BarnCRM_Settings');
    }

    private static void requirePermission() {
        if (!canManage()) {
            throw new RollupService.RollupServiceException(Label.Core_Rollups_ErrorNoPermission);
        }
    }

    /**
     * Turns anything that went wrong into a message the page can show, and records the ones the
     * page cannot explain.
     */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof RollupService.RollupServiceException)) {
            ErrorLogger.log(caught, context);
            message = Label.Core_Rollups_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
