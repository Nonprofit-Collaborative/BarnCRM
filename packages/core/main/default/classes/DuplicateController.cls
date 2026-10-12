/**
 * The Duplicates panel on the Households page of BarnCRM Settings (C-20).
 *
 * It answers three questions: are duplicate rules switched on, what have they found, and what
 * do I do about each pair. Everything it shows was found by the org's own rules (R-DP1), and
 * the only merge it performs is the household merge C-09 ships, one pair at a time with a
 * person confirming it (R-DP4).
 *
 * Every action on the panel needs `Manage_BarnCRM_Settings`: scanning and dismissing are
 * configuration, and a merge from here also closes the suggestion. Merging households from
 * the household record page stays open to anyone who can edit both, as C-09 decided.
 *
 * Suggestions also need access to the platform's duplicate record sets, which Salesforce
 * grants only to Sales Cloud and Service Cloud licenses, through the optional Nonprofit
 * Duplicate Review permission set. Without it the panel still shows the rules and says why
 * there is nothing else, rather than failing (ADR-0013, ADR-0050).
 */
public with sharing class DuplicateController {
    private static final String EDIT_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final String SCAN_CLASS = 'DuplicateScanBatch';
    private static final Integer MAX_SUGGESTIONS = 50;
    /**
     * How many suggestions are read before the ones the panel cannot show (organizations,
     * records this person cannot see) are filtered out, so that fifty shown are fifty usable.
     */
    private static final Integer MAX_READ = 500;
    private static final Set<String> FINISHED = new Set<String>{ 'Completed', 'Failed', 'Aborted' };

    /** One record in a suggestion, as the panel shows it. */
    public class RecordView {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Boolean isHousehold;
    }

    /** One suggestion: records the org's rules say are the same person or household. */
    public class SuggestionView {
        @AuraEnabled
        public Id setId;
        @AuraEnabled
        public Datetime foundAt;
        @AuraEnabled
        public String ruleLabel;
        @AuraEnabled
        public List<RecordView> records = new List<RecordView>();
        @AuraEnabled
        public Boolean canMerge = false;
    }

    /** One duplicate rule and whether it is switched on. */
    public class RuleView {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String ruleLabel;
        @AuraEnabled
        public Boolean active;
    }

    /** The whole panel, in one round trip. */
    public class DuplicateView {
        @AuraEnabled
        public Boolean canManage = false;
        @AuraEnabled
        public Boolean anyRuleActive = false;
        @AuraEnabled
        public List<RuleView> rules = new List<RuleView>();
        @AuraEnabled
        public List<SuggestionView> suggestions = new List<SuggestionView>();
        @AuraEnabled
        public Integer dismissedCount = 0;
        @AuraEnabled
        public Boolean scanRunning = false;
        @AuraEnabled
        public Datetime lastScanFinished;
        /** False when this person has no access to duplicate record sets (license bound). */
        @AuraEnabled
        public Boolean canReviewSuggestions = false;
        /** How many usable suggestions were found, of which at most fifty are listed. */
        @AuraEnabled
        public Integer totalSuggestions = 0;
        /** True when more suggestions were waiting than were read, so the total is a floor. */
        @AuraEnabled
        public Boolean moreNotCounted = false;
        /** What the latest scan said when it finished, and whether it could not check a chunk. */
        @AuraEnabled
        public String lastScanSummary;
        @AuraEnabled
        public Boolean lastScanHadFailures = false;
    }

    @AuraEnabled
    public static DuplicateView getView() {
        try {
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Duplicates panel');
        }
    }

    /**
     * Starts a scan of the records already in the org. Refused when no duplicate rule is
     * active, because the scan would then report a clean org rather than an unchecked one.
     */
    @AuraEnabled
    public static DuplicateView startScan() {
        try {
            requirePermission();
            requireSuggestionAccess();
            if (DuplicateScanBatch.start() == null) {
                throw new DuplicateService.DuplicateException(
                    Label.Core_Duplicates_ErrorNoActiveRule
                );
            }
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Start a duplicate scan');
        }
    }

    /** Records that these records are not duplicates, and takes the suggestion away. */
    @AuraEnabled
    public static DuplicateView dismiss(Id duplicateRecordSetId, String reason) {
        try {
            requirePermission();
            requireSuggestionAccess();
            DuplicateService.dismiss(duplicateRecordSetId, reason);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Dismiss a duplicate suggestion');
        }
    }

    /** The two households side by side, from the household merge's own comparison (C-09). */
    @AuraEnabled
    public static HouseholdMergeService.MergePreview previewMerge(Id survivorId, Id victimId) {
        try {
            requirePermission();
            return HouseholdMergeService.preview(survivorId, victimId);
        } catch (Exception caught) {
            throw asUserError(caught, 'Preview a household merge from the Duplicates panel');
        }
    }

    /**
     * Merges the two households with C-09's merge, unchanged, and takes the suggestion away
     * without a dismissal: the pair no longer exists (R-DP5).
     */
    @AuraEnabled
    public static DuplicateView mergeHouseholds(
        Id duplicateRecordSetId,
        Id survivorId,
        Id victimId,
        Map<String, String> fieldChoices
    ) {
        try {
            requirePermission();
            requireSuggestionAccess();
            // Checked before the merge: afterwards one of the two records no longer exists.
            DuplicateService.requireSetOf(
                duplicateRecordSetId,
                new Set<Id>{ survivorId, victimId }
            );
            HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(fieldChoices)
            );
            DuplicateService.closeSet(duplicateRecordSetId);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Merge two households from the Duplicates panel');
        }
    }

    // ------------------------------------------------------------------ the view

    private static DuplicateView currentView() {
        DuplicateView view = new DuplicateView();
        view.canManage = FeatureManagement.checkPermission(EDIT_PERMISSION);
        for (
            DuplicateRule rule : DuplicateSelector.rulesFor(
                new Set<String>(DuplicateSelector.REVIEWED_OBJECTS)
            )
        ) {
            RuleView ruleView = new RuleView();
            ruleView.objectName = rule.SobjectType;
            ruleView.ruleLabel = rule.MasterLabel;
            ruleView.active = rule.IsActive == true;
            view.anyRuleActive = view.anyRuleActive || ruleView.active;
            view.rules.add(ruleView);
        }
        view.dismissedCount = DuplicateSelector.dismissalCount();
        Error_Log__c lastResult = DuplicateSelector.latestScanResult(
            DuplicateScanBatch.LOG_CONTEXT
        );
        if (lastResult != null) {
            view.lastScanSummary = lastResult.Message__c;
            view.lastScanHadFailures = lastResult.Severity__c != ErrorLogger.SEVERITY_INFO;
        }
        for (AsyncApexJob job : DuplicateSelector.recentScanJobs(SCAN_CLASS, 5)) {
            if (job.CompletedDate != null && view.lastScanFinished == null) {
                view.lastScanFinished = job.CompletedDate;
            }
            if (!FINISHED.contains(job.Status)) {
                view.scanRunning = true;
            }
        }
        view.canReviewSuggestions = canReviewSuggestions();
        if (!view.canReviewSuggestions) {
            return view;
        }
        List<DuplicateRecordSet> sets = DuplicateSelector.openSets(MAX_READ);
        List<SuggestionView> usable = suggestions(sets);
        view.totalSuggestions = usable.size();
        view.moreNotCounted = sets.size() >= MAX_READ;
        for (Integer index = 0; index < usable.size() && index < MAX_SUGGESTIONS; index++) {
            view.suggestions.add(usable[index]);
        }
        return view;
    }

    /** Whether this person can read and write the platform's duplicate record sets. */
    private static Boolean canReviewSuggestions() {
        return Schema.SObjectType.DuplicateRecordSet.isAccessible() &&
            Schema.SObjectType.DuplicateRecordSet.isCreateable() &&
            Schema.SObjectType.DuplicateRecordSet.isDeletable() &&
            Schema.SObjectType.DuplicateRecordItem.isAccessible() &&
            Schema.SObjectType.DuplicateRecordItem.isCreateable();
    }

    private static void requireSuggestionAccess() {
        if (!canReviewSuggestions()) {
            throw new DuplicateService.DuplicateException(
                Label.Core_Duplicates_ErrorNoSuggestionAccess
            );
        }
    }

    /**
     * The suggestions, with their records named. A suggestion naming a record the person
     * cannot see, a deleted record, an organization or anything but a person or a household is
     * left out rather than shown with a hole in it: half a pair is nothing to decide about.
     */
    private static List<SuggestionView> suggestions(List<DuplicateRecordSet> sets) {
        Set<Id> recordIds = new Set<Id>();
        for (DuplicateRecordSet found : sets) {
            for (DuplicateRecordItem item : found.DuplicateRecordItems) {
                recordIds.add(item.RecordId);
            }
        }
        Map<Id, RecordView> byRecord = describeRecords(recordIds);
        List<SuggestionView> result = new List<SuggestionView>();
        for (DuplicateRecordSet found : sets) {
            SuggestionView view = new SuggestionView();
            view.setId = found.Id;
            view.foundAt = found.CreatedDate;
            view.ruleLabel = found.DuplicateRule == null ? null : found.DuplicateRule.MasterLabel;
            Boolean complete = found.DuplicateRecordItems.size() > 1;
            for (DuplicateRecordItem item : found.DuplicateRecordItems) {
                RecordView record = byRecord.get(item.RecordId);
                if (record == null) {
                    complete = false;
                    break;
                }
                view.records.add(record);
            }
            if (complete) {
                view.canMerge =
                    view.records.size() == 2 &&
                    view.records[0].isHousehold &&
                    view.records[1].isHousehold;
                result.add(view);
            }
        }
        return result;
    }

    private static Map<Id, RecordView> describeRecords(Set<Id> recordIds) {
        Map<Id, RecordView> result = new Map<Id, RecordView>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Id recordId : recordIds) {
            if (recordId.getSObjectType() == Account.SObjectType) {
                accountIds.add(recordId);
            } else if (recordId.getSObjectType() == Contact.SObjectType) {
                contactIds.add(recordId);
            }
        }
        for (Account household : DuplicateSelector.householdsByIds(accountIds)) {
            result.put(
                household.Id,
                recordView(
                    household.Id,
                    household.Name,
                    place(household.BillingCity, household.BillingPostalCode),
                    true
                )
            );
        }
        for (Contact person : DuplicateSelector.contactsByIds(contactIds)) {
            String detail = String.isNotBlank(person.Email)
                ? person.Email
                : place(
                      person.Account == null ? null : person.Account.Name,
                      person.MailingPostalCode
                  );
            result.put(person.Id, recordView(person.Id, person.Name, detail, false));
        }
        return result;
    }

    private static RecordView recordView(
        Id recordId,
        String name,
        String detail,
        Boolean isHousehold
    ) {
        RecordView view = new RecordView();
        view.recordId = recordId;
        view.name = name;
        view.detail = detail;
        view.isHousehold = isHousehold;
        return view;
    }

    private static String place(String first, String second) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(first)) {
            parts.add(first);
        }
        if (String.isNotBlank(second)) {
            parts.add(second);
        }
        return String.join(parts, ', ');
    }

    // ------------------------------------------------------------------ helpers

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw new DuplicateService.DuplicateException(
                Label.Core_Duplicates_ErrorPermissionRequired
            );
        }
    }

    /**
     * Anything the person can act on is shown as it is. Anything else is logged and answered
     * with one sentence, because a stack trace in a toast helps nobody (plan Section 7.2).
     */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        Boolean expected =
            caught instanceof DuplicateService.DuplicateException ||
            caught instanceof HouseholdException;
        if (!expected) {
            ErrorLogger.log(caught, context);
            message = Label.Core_Duplicates_ErrorUnexpected;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
