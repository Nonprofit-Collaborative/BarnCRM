/**
 * Shares every enrollment, then every service delivery, with the Programs Participant Records
 * group (P-08, canonical model R-EN7 and R-SD6), so records made before the privacy preset, or
 * copied in with their automation off, are covered. A record shared already keeps its one
 * share. Queued at install and each time the preset is saved (`ProgramsSharing.ApplyJob`).
 * System mode, as `ProgramsSharing`.
 */
public without sharing class ProgramsSharingBatch implements Database.Batchable<SObject> {
    private final Schema.SObjectType type;

    public ProgramsSharingBatch(Schema.SObjectType type) {
        this.type = type;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            'SELECT Id FROM ' + type.getDescribe().getName(),
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        ProgramsSharing.share(records);
    }

    /** Enrollments first, then deliveries. A test cannot chain a batch from a batch. */
    public void finish(Database.BatchableContext context) {
        if (type == Enrollment__c.SObjectType && !Test.isRunningTest()) {
            Database.executeBatch(new ProgramsSharingBatch(Service_Delivery__c.SObjectType), 2000);
        }
    }
}
