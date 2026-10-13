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
        /** The calculation by the name the Aggregate picklist gives it: Sum, Count distinct, Any. */
        @AuraEnabled
        public String aggregateLabel { get; set; }
        /** What separates a text list's values, by its picklist name; blank for anything else. */
        @AuraEnabled
        public String delimiterLabel { get; set; }
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
        /** The same modes with the names an administrator reads (R-R4): Instantly, and so on. */
        @AuraEnabled
        public List<ModeOption> modeOptions { get; set; }
        @AuraEnabled
        public List<RollupView> rollups { get; set; }
        /** The Rollup Builder tab, with the package namespace when there is one. */
        @AuraEnabled
        public String builderTabApiName { get; set; }
    }

    /** One mode: the stored value and the name the picklist gives it. */
    public class ModeOption {
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public String label { get; set; }
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
            if (
                RollupService.MODE_REAL_TIME.equals(mode) &&
                RollupDateWindow.movesWithTheDate(definition)
            ) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupBuilder_ErrorInstantMovesWithDate
                );
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
            refuseWhileAFullRunIsGoing();
            RollupService.recalculate(definitionId);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Recalculate a rollup');
        }
    }

    /** Recalculates every active rollup now, whatever its mode, Instantly ones included. */
    @AuraEnabled
    public static RollupPageView recalculateAll() {
        try {
            requirePermission();
            refuseWhileAFullRunIsGoing();
            RollupService.startFullRunOfEveryDefinition();
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

    /** A rough rate for a full run, from the first measured runs; an org run refines it. */
    @TestVisible
    private static final Integer RECORDS_PER_MINUTE = 1650;

    /** The moment the estimate treats as now, so a test can pick a weekday or a night. */
    @TestVisible
    private static Datetime estimatedAt = null;

    /** What Recalculate all will go through, said before it starts (ADR decision 12, S12). */
    public class FullRunEstimate {
        @AuraEnabled
        public String summary { get; set; }
        @AuraEnabled
        public Boolean workingHours { get; set; }
    }

    /**
     * Counts the records Recalculate all goes through: every record of each entity an active
     * rollup writes, whatever its mode. The time is a rough figure, and during working hours
     * (8 AM to 6 PM, Monday to Friday, in the user's time zone) the Builder suggests tonight.
     */
    @AuraEnabled
    public static FullRunEstimate estimateFullRun() {
        try {
            requirePermission();
            Set<Schema.SObjectType> targets = new Set<Schema.SObjectType>();
            for (
                Rollup_Definition__c definition : RollupSelector.selectActiveForModes(
                    RollupService.everyMode()
                )
            ) {
                Schema.SObjectType target = SettingsService.typeByName(definition.Target_Object__c);
                if (target != null) {
                    targets.add(target);
                }
            }
            Integer records = 0;
            for (Schema.SObjectType target : targets) {
                records += Database.countQueryWithBinds(
                    'SELECT COUNT() FROM ' + String.valueOf(target),
                    new Map<String, Object>(),
                    AccessLevel.USER_MODE
                );
            }
            Integer minutes = Math.max(
                1,
                (Integer) Math.ceil(records / (Decimal) RECORDS_PER_MINUTE)
            );
            Datetime moment = estimatedAt == null ? Datetime.now() : estimatedAt;
            Integer weekday = Integer.valueOf(moment.format('u'));
            Integer hour = Integer.valueOf(moment.format('H'));
            FullRunEstimate estimate = new FullRunEstimate();
            estimate.summary = String.format(
                Label.Core_RollupBuilder_Estimate,
                new List<String>{ records.format(), minutes.format() }
            );
            estimate.workingHours = weekday <= 5 && hour >= 8 && hour < 18;
            return estimate;
        } catch (Exception caught) {
            throw asUserError(caught, 'Estimate the full recalculation');
        }
    }

    /**
     * Recalculate all, tonight: nothing extra when the nightly run is scheduled, since it
     * recalculates every Every night and Both total at 2:00 AM and each save keeps the Instantly
     * ones (a second run at the same moment would only be refused as one already running);
     * otherwise one run of every definition at 2:00 AM tonight.
     *
     * @return what to tell the administrator
     */
    @AuraEnabled
    public static String runTonight() {
        try {
            requirePermission();
            if (RollupScheduler.isScheduled()) {
                return Label.Core_RollupBuilder_TonightAlreadyScheduled;
            }
            RollupScheduler.scheduleTonight();
            return Label.Core_RollupBuilder_TonightScheduled;
        } catch (Exception caught) {
            throw asUserError(caught, 'Recalculate all rollups tonight');
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
        page.modeOptions = modeOptions(page.modes);
        page.builderTabApiName = NamespaceUtil.qualify('Rollup_Builder');
        page.rollups = new List<RollupView>();
        Map<String, String> aggregateLabels = labelsOf(Rollup_Definition__c.Aggregate__c);
        Map<String, String> delimiterLabels = labelsOf(Rollup_Definition__c.Delimiter__c);
        for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
            RollupView view = toView(definition);
            String aggregate = definition.Aggregate__c == null ? '' : definition.Aggregate__c;
            view.aggregateLabel = aggregateLabels.containsKey(aggregate)
                ? aggregateLabels.get(aggregate)
                : aggregate;
            if (aggregate.startsWith('TEXT_LIST')) {
                String delimiter = String.isBlank(definition.Delimiter__c)
                    ? 'Comma'
                    : definition.Delimiter__c;
                view.delimiterLabel = delimiterLabels.get(delimiter);
            }
            page.rollups.add(view);
        }
        return page;
    }

    /** A picklist's labels by stored value, in the running user's language. */
    private static Map<String, String> labelsOf(Schema.SObjectField picklist) {
        Map<String, String> labelByValue = new Map<String, String>();
        for (Schema.PicklistEntry entry : picklist.getDescribe().getPicklistValues()) {
            labelByValue.put(entry.getValue(), entry.getLabel());
        }
        return labelByValue;
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

    /** The modes in the order given, each named by the Mode picklist's own label. */
    private static List<ModeOption> modeOptions(List<String> modes) {
        Map<String, String> labelByValue = labelsOf(Rollup_Definition__c.Mode__c);
        List<ModeOption> options = new List<ModeOption>();
        for (String mode : modes) {
            ModeOption option = new ModeOption();
            option.value = mode;
            option.label = labelByValue.containsKey(mode) ? labelByValue.get(mode) : mode;
            options.add(option);
        }
        return options;
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

    /** R-R14: one full run at a time, and the admin is told so rather than left guessing. */
    private static void refuseWhileAFullRunIsGoing() {
        if (RollupFullRecalcBatch.runningJobId() != null) {
            throw new RollupService.RollupServiceException(
                Label.Core_Rollups_FullRunAlreadyRunning
            );
        }
    }

    private static Boolean canManage() {
        return BarnCRMPermissions.canManageSettings();
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
