/**
 * Participant privacy (P-08, canonical model R-EN7 and R-SD6). Enrollments and service
 * deliveries are Private org-wide, and each one is shared, Read/Write, with the public group
 * `Programs_Participants` through the Apex sharing reason `Programs_Participants__c`. The
 * Participant Privacy preset (`Programs_Settings__c.Private_Participants__c`) decides only
 * whether All Internal Users are in that group, so changing it never touches a record.
 *
 * System mode, `without sharing`, in the manner of ADR-0021: a user cannot write a share with an
 * Apex sharing reason, nor a group member. It writes only those shares, that one group member and
 * the module's own settings record, and is reached from the always-run sharing handler, from the
 * settings page after its caller is checked as a settings manager, and from the install and the
 * hourly access check.
 */
public without sharing class ProgramsSharing {
    /** The public group every enrollment and delivery is shared with. */
    public static final String GROUP_NAME = 'Programs_Participants';
    /** The setting's name in the settings change history. */
    public static final String SETTING_NAME = 'Programs_Settings__c.Private_Participants__c';
    public static final String SHARED = 'Shared';
    public static final String PRIVATE_PRESET = 'Private';
    private static final String CONTEXT = 'ProgramsSharing';
    /** See applyPreset. */
    @TestVisible
    private static Boolean writeGroupInTests = false;

    /** True when the preset is Private. Shared, the default, until an admin saves Private. */
    public static Boolean isPrivate() {
        Programs_Settings__c settings = Programs_Settings__c.getOrgDefaults();
        return settings != null && settings.Private_Participants__c == true;
    }

    /** The preset's name, as the settings page and the change history show it. */
    public static String presetName(Boolean privatePreset) {
        return privatePreset == true ? PRIVATE_PRESET : SHARED;
    }

    /**
     * Saves the preset org-wide, audits the change, and queues the job that applies it. Returns
     * false when it was already so. The caller has checked the user may manage settings.
     */
    public static Boolean savePreset(Boolean privatePreset) {
        Boolean wanted = privatePreset == true;
        Boolean stored = isPrivate();
        if (wanted == stored) {
            return false;
        }
        OrgSettingsSystemWriter.save(
            Programs_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Programs_Settings__c.Private_Participants__c => wanted
            }
        );
        SettingsService.logChange(SETTING_NAME, presetName(stored), presetName(wanted));
        requestApply();
        return true;
    }

    /** Queues the job that sets the group's member and shares any record not shared yet. */
    public static void requestApply() {
        try {
            System.enqueueJob(new ApplyJob());
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT);
        }
    }

    /** Shares each record with the group. A record shared already keeps its one share. */
    public static void share(List<SObject> records) {
        Id groupId = groupId();
        if (records == null || records.isEmpty() || groupId == null) {
            return;
        }
        List<SObject> shares = new List<SObject>();
        for (SObject record : records) {
            SObject share = shareOf(record.Id, groupId);
            if (share != null) {
                shares.add(share);
            }
        }
        if (shares.isEmpty()) {
            return;
        }
        List<String> failures = new List<String>();
        for (Database.SaveResult result : Database.insert(shares, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                failures.add(result.getErrors()[0].getMessage());
            }
        }
        if (!failures.isEmpty()) {
            ErrorLogger.logMessage(
                failures.size() + ' Programs records were not shared: ' + failures[0],
                CONTEXT,
                ErrorLogger.SEVERITY_ERROR
            );
        }
    }

    /**
     * Puts All Internal Users in the group for Shared, or takes them out for Private. Members
     * an admin added are left alone. A group member is a setup object, so this runs in its own
     * transaction (the queued job or the hourly access check).
     *
     * The group is real org data that every test sees, so a test that only passes through here
     * (the access sync, the install) leaves it alone: tests running in parallel would otherwise
     * lock its row. A test of the preset itself turns `writeGroupInTests` on.
     */
    public static void applyPreset() {
        Id groupId = groupId();
        if (groupId == null || (Test.isRunningTest() && !writeGroupInTests)) {
            return;
        }
        Id everyone = [SELECT Id FROM Group WHERE Type = 'Organization' WITH SYSTEM_MODE LIMIT 1]
        .Id;
        List<GroupMember> members = [
            SELECT Id
            FROM GroupMember
            WHERE GroupId = :groupId AND UserOrGroupId = :everyone
            WITH SYSTEM_MODE
        ];
        if (isPrivate() && !members.isEmpty()) {
            Database.delete(members, AccessLevel.SYSTEM_MODE);
        } else if (!isPrivate() && members.isEmpty()) {
            Database.insert(
                new GroupMember(GroupId = groupId, UserOrGroupId = everyone),
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    private static Id groupId() {
        List<Group> groups = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :GROUP_NAME AND Type = 'Regular'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return groups.isEmpty() ? null : groups[0].Id;
    }

    private static SObject shareOf(Id recordId, Id groupId) {
        Schema.SObjectType type = recordId == null ? null : recordId.getSObjectType();
        if (type == Enrollment__c.SObjectType) {
            return new Enrollment__Share(
                ParentId = recordId,
                UserOrGroupId = groupId,
                AccessLevel = 'Edit',
                RowCause = Schema.Enrollment__Share.RowCause.Programs_Participants__c
            );
        }
        if (type == Service_Delivery__c.SObjectType) {
            return new Service_Delivery__Share(
                ParentId = recordId,
                UserOrGroupId = groupId,
                AccessLevel = 'Edit',
                RowCause = Schema.Service_Delivery__Share.RowCause.Programs_Participants__c
            );
        }
        return null;
    }

    /** Sets the group's member, then shares any enrollment or delivery that has no share yet. */
    public without sharing class ApplyJob implements Queueable {
        public void execute(QueueableContext jobContext) {
            try {
                applyPreset();
                Database.executeBatch(new ProgramsSharingBatch(Enrollment__c.SObjectType), 2000);
            } catch (Exception e) {
                ErrorLogger.log(e, CONTEXT);
            }
        }
    }
}
