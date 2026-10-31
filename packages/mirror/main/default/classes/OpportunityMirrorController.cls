/**
 * The Opportunity mirror page (feature X-01, R-OM8, R-OM11): says whether the mirror can work in
 * this org and for this person, starts Run now, schedules and stops the nightly run, compares a
 * range, and copies a range again. Every refusal is in words the page shows as they are.
 */
public with sharing class OpportunityMirrorController {
    private static final String CONTEXT = 'OpportunityMirrorController';
    /**
     * Held through the Opportunity Mirror permission set. Reading the page's status and the
     * reconciliation needs it, as the page's entry in the settings console does (ADR-0038).
     */
    private static final String USE_PERMISSION = 'Use_Opportunity_Mirror';

    /** What the page shows. */
    public class Status {
        @AuraEnabled
        public Boolean available;
        @AuraEnabled
        public String direction;
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Boolean canRun;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean running;
        @AuraEnabled
        public Datetime nextRunAt;
        /** When the last completed run started, and what it did (ADR-0038 point 4). */
        @AuraEnabled
        public Datetime lastRunAt;
        @AuraEnabled
        public String lastSummary;
    }

    @AuraEnabled
    public static Status getStatus() {
        requireUse();
        try {
            return status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    /** Starts a run in the chosen direction, or says in words why it cannot start. */
    @AuraEnabled
    public static Status runNow() {
        Status current = checked(false);
        try {
            OpportunityMirrorBatch.run();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        current.running = true;
        return current;
    }

    /** Copies again every gift in the totals dated in the range (Gifts to Opportunities only). */
    @AuraEnabled
    public static Status copyRangeAgain(Date fromDate, Date toDate) {
        Status current = checked(false);
        if (current.direction != OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES) {
            throw UserErrors.message(Label.Mirror_OpportunityMirror_CopyAgainGiftsOnly);
        }
        if (fromDate == null || toDate == null) {
            throw UserErrors.message(Label.Mirror_OpportunityMirror_ErrorDatesRequired);
        }
        if (fromDate > toDate) {
            throw UserErrors.message(Label.Mirror_OpportunityMirror_ErrorDateOrder);
        }
        try {
            OpportunityMirrorBatch.runRange(fromDate, toDate);
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        current.running = true;
        return current;
    }

    /** Schedules the nightly run at 01:30, as the person clicking (ADR-0038). */
    @AuraEnabled
    public static Status schedule() {
        checked(true);
        try {
            OpportunityMirrorSchedulable.schedule();
            return status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    @AuraEnabled
    public static Status stop() {
        Status current = status();
        if (!current.canManage) {
            throw UserErrors.message(Label.Mirror_OpportunityMirror_NoManagePermission);
        }
        try {
            OpportunityMirrorSchedulable.stop();
            return status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    /** The reconciliation for a range, as the person viewing can see it (R-OM11). */
    @AuraEnabled
    public static OpportunityMirrorReconciliation.Comparison compare(Date fromDate, Date toDate) {
        requireUse();
        try {
            return OpportunityMirrorReconciliation.compare(fromDate, toDate);
        } catch (OpportunityMirrorReconciliation.ReconciliationException refused) {
            throw UserErrors.message(refused.getMessage());
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
    }

    private static void requireUse() {
        if (!FeatureManagement.checkPermission(USE_PERMISSION)) {
            throw UserErrors.message(Label.Mirror_OpportunityMirror_NoUsePermission);
        }
    }

    /** The current status when a run may start, or the refusal in words. */
    private static Status checked(Boolean scheduling) {
        Status current;
        try {
            current = status();
        } catch (Exception unexpected) {
            throw failed(unexpected);
        }
        String refusal = refusal(current, scheduling);
        if (refusal != null) {
            throw UserErrors.message(refusal);
        }
        return current;
    }

    @TestVisible
    private static String refusal(Status current, Boolean scheduling) {
        if (!current.available) {
            return Label.Mirror_OpportunityMirror_Unavailable;
        }
        if (current.direction == OpportunityMirrorService.OFF) {
            return Label.Mirror_OpportunityMirror_SwitchedOff;
        }
        if (!current.canManage) {
            return Label.Mirror_OpportunityMirror_NoManagePermission;
        }
        if (!current.canRun) {
            return Label.Mirror_OpportunityMirror_NoOpportunityAccess;
        }
        if (current.running && !scheduling) {
            return Label.Mirror_OpportunityMirror_Running;
        }
        return null;
    }

    private static Status status() {
        Status current = new Status();
        current.available = OpportunityMirrorService.isAvailable();
        current.direction = OpportunityMirrorService.direction();
        current.startDate = OpportunityGiftService.startDate();
        current.canManage = AutomationControl.canManage();
        current.canRun = canRun(current.direction);
        current.running = OpportunityMirrorSchedulable.isRunning();
        current.nextRunAt = OpportunityMirrorSchedulable.nextRunAt();
        Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
        current.lastRunAt = settings?.Opportunity_Mirror_Last_Run__c;
        current.lastSummary = settings?.Opportunity_Mirror_Last_Summary__c;
        return current;
    }

    /** Whether a run started by this person could do its work in the chosen direction. */
    private static Boolean canRun(String direction) {
        if (direction != OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS) {
            // A run stores each new link on its gift in user mode.
            return OpportunityMirrorService.canCopy() &&
                Gift__c.Opportunity_Id__c.getDescribe().isUpdateable();
        }
        if (!OpportunityMirrorService.isAvailable()) {
            return false;
        }
        Schema.DescribeFieldResult link = Gift__c.Opportunity_Id__c.getDescribe();
        return OpportunityMirrorService.opportunityType().getDescribe().isAccessible() &&
            Schema.SObjectType.Gift__c.isCreateable() &&
            link.isAccessible() &&
            link.isCreateable();
    }

    private static AuraHandledException failed(Exception unexpected) {
        ErrorLogger.log(unexpected, CONTEXT);
        return UserErrors.message(Label.Mirror_OpportunityMirror_ErrorFailed);
    }
}
