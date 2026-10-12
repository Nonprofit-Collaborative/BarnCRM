/**
 * The Nonprofit Hub home page's Apex surface: how far setup has got, whether automation is
 * paused, and how many errors nobody has looked at.
 *
 * The steps themselves belong to the Setup Assistant, which loads them itself, so the home
 * page asks only for the two counters it uses to decide whether the assistant is still the
 * main panel.
 *
 * Everything except the checklist is optional: automation control and the Error Log belong
 * to other features, so each call is wrapped and a failure costs the page a number, not the
 * page.
 */
public with sharing class HubController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String ERROR_CONTEXT = 'Open Impact home';

    public class HomeModel {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public Boolean automationPaused;
        @AuraEnabled
        public Integer newErrorCount;
        @AuraEnabled
        public Integer stepsCompleted;
        @AuraEnabled
        public Integer stepsTotal;
        @AuraEnabled
        public Datetime rollupsLastCalculated;
        @AuraEnabled
        public Boolean rollupsStale;
        @AuraEnabled
        public Datetime seasonalAddressLastRun;
        @AuraEnabled
        public String seasonalAddressLastRunSummary;
        @AuraEnabled
        public Boolean seasonalAddressScheduled;
        @AuraEnabled
        public Boolean seasonalAddressStale;
        @AuraEnabled
        public List<RecurringSource> recurringSources;
    }

    /** One file that arrives regularly, and when it was last imported (R-IT6). */
    public class RecurringSource {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String sourceName;
        @AuraEnabled
        public String templateName;
        @AuraEnabled
        public Date lastImportDate;
    }

    @AuraEnabled(cacheable=true)
    public static HomeModel getHomeModel() {
        try {
            return buildModel();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_HubHome_LoadErrorMessage);
        }
    }

    private static HomeModel buildModel() {
        HomeModel model = new HomeModel();
        model.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        model.stepsTotal = steps.size();
        model.stepsCompleted = SetupAssistantService.countCompleted(steps);
        model.automationPaused = readAutomationPaused();
        model.newErrorCount = readNewErrorCount();
        readRollupFreshness(model);
        readSeasonalAddressRun(model);
        model.recurringSources = readRecurringSources();
        return model;
    }

    private static Boolean readAutomationPaused() {
        try {
            return AutomationControl.isPaused();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            return false;
        }
    }

    /**
     * "Rollups last completed", and whether the nightly run is overdue (plan Section 4.10).
     * Optional like the rest: an org where the rollup engine cannot answer loses a tile, not the
     * page.
     */
    private static void readRollupFreshness(HomeModel model) {
        try {
            model.rollupsLastCalculated = RollupService.lastCalculated();
            model.rollupsStale = RollupService.isStale();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            model.rollupsStale = false;
        }
    }

    /**
     * "Seasonal addresses last swapped", and whether the nightly job has missed its window
     * (C-18, R-AD8). A nightly job whose last run nobody can see is a job nobody trusts, so this
     * belongs on the page an administrator opens every morning rather than only on the settings
     * page they open twice a year.
     *
     * Optional like the rest: an org that cannot answer loses a tile, not the page.
     */
    private static void readSeasonalAddressRun(HomeModel model) {
        try {
            model.seasonalAddressLastRun = SeasonalAddressService.lastRun();
            model.seasonalAddressLastRunSummary = SeasonalAddressService.lastRunSummary();
            model.seasonalAddressScheduled = SeasonalAddressScheduler.isScheduled();
            model.seasonalAddressStale = SeasonalAddressService.isStale();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            model.seasonalAddressScheduled = false;
            model.seasonalAddressStale = false;
        }
    }

    /**
     * The files that arrive regularly and when each was last imported, oldest first, so the
     * one nobody has loaded this month is at the top (R-IT6). Optional like the rest: a user
     * who cannot read import templates loses the list, not the page.
     */
    private static List<RecurringSource> readRecurringSources() {
        List<RecurringSource> result = new List<RecurringSource>();
        if (!Schema.SObjectType.Import_Template__c.isAccessible()) {
            return result;
        }
        try {
            for (Import_Template__c template : ImportTemplateService.recurringSources()) {
                RecurringSource source = new RecurringSource();
                source.id = template.Id;
                source.sourceName = template.Source_Name__c;
                source.templateName = template.Name;
                source.lastImportDate = template.Last_Import_Date__c;
                result.add(source);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
        }
        return result;
    }

    private static Integer readNewErrorCount() {
        try {
            return HubErrorCountSelector.countNewErrors();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            return 0;
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
