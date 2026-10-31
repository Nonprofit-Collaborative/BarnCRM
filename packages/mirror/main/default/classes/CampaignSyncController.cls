/**
 * The Campaign sync page (feature X-02, R-CS6): says whether the sync can work in this org and
 * for this person, counts the appeals with and without a Campaign, and starts Sync all appeals.
 * Every refusal is in words the page shows as they are.
 */
public with sharing class CampaignSyncController {
    private static final String CONTEXT = 'CampaignSyncController';

    /** What the page shows. The counts are empty when they cannot be read. */
    public class Status {
        @AuraEnabled
        public Boolean available;
        @AuraEnabled
        public Boolean switchedOn;
        @AuraEnabled
        public Boolean canSync;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public Boolean running;
        @AuraEnabled
        public Integer appealCount;
        @AuraEnabled
        public Integer linkedCount;
        /** True when there are more appeals than `appealCount`, the most the page counts. */
        @AuraEnabled
        public Boolean appealCountCapped;
        /** True when more appeals have a Campaign than `linkedCount`. */
        @AuraEnabled
        public Boolean linkedCountCapped;
    }

    /** The page counts this many appeals and then says "more". A test lowers it. */
    @TestVisible
    private static Integer countCap = 10000;

    @AuraEnabled
    public static Status getStatus() {
        try {
            return status();
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            throw UserErrors.message(Label.Mirror_CampaignSync_ErrorFailed);
        }
    }

    /** Starts Sync all appeals, or says in words why it cannot start. */
    @AuraEnabled
    public static Status syncAll() {
        Status current;
        try {
            current = status();
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            throw UserErrors.message(Label.Mirror_CampaignSync_ErrorFailed);
        }
        String refusal = refusal(current);
        if (refusal != null) {
            throw UserErrors.message(refusal);
        }
        try {
            CampaignSyncBatch.start();
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            throw UserErrors.message(Label.Mirror_CampaignSync_ErrorFailed);
        }
        current.running = true;
        return current;
    }

    @TestVisible
    private static String refusal(Status current) {
        if (!current.available) {
            return Label.Mirror_CampaignSync_Unavailable;
        }
        if (!current.switchedOn) {
            return Label.Mirror_CampaignSync_SwitchedOff;
        }
        if (!current.canManage) {
            return Label.Mirror_CampaignSync_NoManagePermission;
        }
        if (!current.canSync) {
            return Label.Mirror_CampaignSync_NoCampaignAccess;
        }
        if (current.running) {
            return Label.Mirror_CampaignSync_Running;
        }
        return null;
    }

    private static Status status() {
        Status current = new Status();
        current.available = CampaignSyncService.isAvailable();
        current.switchedOn = CampaignSyncService.isSwitchedOn();
        current.canSync = CampaignSyncService.canSync();
        current.canManage = AutomationControl.canManage();
        current.running = CampaignSyncSelector.hasRunningJob(CampaignSyncBatch.CLASS_NAME);
        if (Schema.SObjectType.Appeal__c.isAccessible()) {
            Integer appeals = CampaignSyncSelector.countAppeals(false, countCap + 1);
            current.appealCountCapped = appeals > countCap;
            current.appealCount = current.appealCountCapped ? countCap : appeals;
            if (Appeal__c.Campaign_Id__c.getDescribe().isAccessible()) {
                Integer linked = CampaignSyncSelector.countAppeals(true, countCap + 1);
                current.linkedCountCapped = linked > countCap;
                current.linkedCount = current.linkedCountCapped ? countCap : linked;
            }
        }
        return current;
    }
}
