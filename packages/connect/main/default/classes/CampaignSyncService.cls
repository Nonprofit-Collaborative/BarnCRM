/**
 * Campaign sync (feature X-02, canonical model Section 29B, ADR-0056 on where the link lives):
 * a one-way copy of each appeal to a standard Salesforce Campaign.
 *
 * Two callers share one copy. The `Campaign_Sync` automation calls `syncBeforeSave` while an
 * appeal is being saved, so a new Campaign's identifier is stored with the appeal in the same
 * save (R-CS3). `CampaignSyncBatch` calls `syncSaved` for Sync all appeals, and stores the new
 * links itself (R-CS6).
 *
 * Campaign is reached only through describe and SObject generics, never named at compile time,
 * so Connect installs and this class compiles where Campaign does not exist; there the sync
 * does nothing (plan Section 4.2, R-CS1).
 *
 * Every Campaign write is in user mode with partial success (R-CS4, R-CS5): Campaign is a
 * standard object the package does not own, so ADR-0021's elevated writers do not apply, and
 * a Campaign the platform refuses must never refuse the appeal. Each refusal is logged at
 * Warning with the appeal and the platform's own message, and all of one call's Warnings are
 * written together in a single statement, so a refusal of every appeal in a 200-appeal save
 * costs one log write (R-CS5).
 */
public with sharing class CampaignSyncService {
    /** The registry name of the automation, used to bypass it while the batch stores links. */
    public static final String AUTOMATION_NAME = 'Campaign_Sync';

    // detection-only: Campaign is resolved through describe so Connect installs without it
    private static final String CAMPAIGN_OBJECT = 'Campaign';
    private static final String CONTEXT = 'Campaign sync';
    private static final Integer DESCRIPTION_LIMIT = 32000;

    /** What one copy costs at most: two reads, and an insert, an update and a parent fix. */
    private static final Integer QUERIES_NEEDED = 2;
    private static final Integer DML_STATEMENTS_NEEDED = 3;

    /** The Campaign field each copied appeal attribute is written to (R-CS2). */
    private static final Map<Schema.SObjectField, String> COPIED = new Map<Schema.SObjectField, String>{
        Appeal__c.Name => 'Name',
        Appeal__c.Description__c => 'Description',
        Appeal__c.Start_Date__c => 'StartDate',
        Appeal__c.End_Date__c => 'EndDate',
        Appeal__c.Goal__c => 'ExpectedRevenue',
        Appeal__c.Cost__c => 'ActualCost',
        Appeal__c.Active__c => 'IsActive'
    };
    private static final String PARENT_FIELD = 'ParentId';

    private static Schema.SObjectType resolvedType;
    private static Boolean typeResolved = false;

    /**
     * Set by tests to see the org as having no Campaign, the Platform-only shape no test org
     * has (dynamic-apex.md section 9), so the absent path is run rather than skipped.
     */
    @TestVisible
    private static Boolean unavailableForTest = false;

    /** Warnings collected during one call and written together by `flushLog`. */
    private static List<String> pendingMessages = new List<String>();
    private static List<Id> pendingRecordIds = new List<Id>();

    /** Each once-per-transaction Warning, so a large save does not write it per chunk. */
    private static Boolean noAccessLogged = false;
    private static Boolean noHeadroomLogged = false;

    /** What one call did, for the batch summary and the tests. */
    public class Result {
        public Integer created = 0;
        public Integer updated = 0;
        public Integer unchanged = 0;
        public Integer failed = 0;
        public Integer skipped = 0;

        public void add(Result other) {
            created += other.created;
            updated += other.updated;
            unchanged += other.unchanged;
            failed += other.failed;
            skipped += other.skipped;
        }
    }

    // ------------------------------------------------------------------ what the org allows

    /** The Campaign object, or null in an org without it (a Platform-only org). */
    public static Schema.SObjectType campaignType() {
        if (unavailableForTest == true) {
            return null;
        }
        if (!typeResolved) {
            resolvedType = Schema.getGlobalDescribe().get(CAMPAIGN_OBJECT);
            typeResolved = true;
        }
        return resolvedType;
    }

    public static Boolean isAvailable() {
        return campaignType() != null;
    }

    /** The Copy appeals to Campaigns setting, off at install (R-CS1). */
    public static Boolean isSwitchedOn() {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        return settings != null && settings.Campaign_Sync_Enabled__c == true;
    }

    /**
     * Whether the running user can make the copy at all: create and edit Campaigns (which in
     * Salesforce also takes the Marketing User box), and read and edit the appeal's Campaign ID,
     * which the Campaign Sync permission set grants.
     */
    public static Boolean canSync() {
        if (!isAvailable()) {
            return false;
        }
        Schema.DescribeSObjectResult campaign = campaignType().getDescribe();
        Schema.DescribeFieldResult link = Appeal__c.Campaign_Id__c.getDescribe();
        return campaign.isCreateable() &&
            campaign.isUpdateable() &&
            link.isAccessible() &&
            link.isUpdateable();
    }

    // ------------------------------------------------------------------------- the two callers

    /**
     * The automation's path: appeals in a before-insert or before-update context. New links are
     * written onto the records being saved. Never throws: whatever goes wrong is logged and the
     * appeal saves (R-CS5).
     *
     * @param appeals the appeals being saved
     * @param oldById their previous values, or null on insert
     */
    public static Result syncBeforeSave(List<Appeal__c> appeals, Map<Id, Appeal__c> oldById) {
        Result result = new Result();
        if (appeals == null || appeals.isEmpty() || !isAvailable() || !isSwitchedOn()) {
            return result;
        }
        List<Appeal__c> scope = new List<Appeal__c>();
        for (Appeal__c appeal : appeals) {
            if (appeal.hasErrors() || !normalizeLink(appeal)) {
                continue;
            }
            Appeal__c old = oldById == null ? null : oldById.get(appeal.Id);
            if (old == null || appeal.Campaign_Id__c == null || copiedValuesChanged(appeal, old)) {
                scope.add(appeal);
            }
        }
        if (scope.isEmpty()) {
            return result;
        }
        if (!canSync()) {
            result.skipped = scope.size();
            // Logged when appeals are created, once per transaction: otherwise every edit by
            // someone without Campaign access would add a Warning (R-CS4).
            if (oldById == null && !noAccessLogged) {
                noAccessLogged = true;
                ErrorLogger.logMessage(
                    String.format(
                        Label.Connect_CampaignSync_LogNoAccess,
                        new List<Object>{ scope.size() }
                    ),
                    CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            return result;
        }
        if (!hasHeadroom(scope.size())) {
            // A save too large to copy is left to Sync all appeals rather than failed (R-CS5).
            result.skipped = scope.size();
            if (!noHeadroomLogged) {
                noHeadroomLogged = true;
                ErrorLogger.logMessage(
                    Label.Connect_CampaignSync_LogNoHeadroom,
                    CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            return result;
        }
        try {
            return copy(scope);
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            result.failed = scope.size();
            return result;
        } finally {
            flushLog();
        }
    }

    /**
     * Whether this transaction still has room for one copy of this many appeals, with a margin
     * for the other automation on Appeal and Campaign. A single Apex insert of thousands of
     * appeals runs this trigger once per 200, and without the check it would run out of queries
     * and fail the whole save.
     */
    @TestVisible
    private static Boolean hasHeadroom(Integer appealCount) {
        return ConnectSync.hasHeadroom(QUERIES_NEEDED, DML_STATEMENTS_NEEDED, 3 * appealCount);
    }

    /**
     * Sync all appeals: appeals already saved. Copies them, then stores any new link on the
     * appeal with this automation bypassed, since the copy has just been made.
     *
     * The links are stored with partial success, so one appeal that cannot be saved (a rule on
     * Appeal refuses it, or the runner cannot edit it) never costs the rest of the chunk their
     * links. A Campaign made here for such an appeal is deleted again at once, so the next run
     * does not make a second one (R-CS7); one that cannot be deleted is named in a Warning. Only
     * a failure that throws rolls the whole chunk back, Campaigns included.
     */
    public static Result syncSaved(List<Appeal__c> appeals) {
        Result result = new Result();
        if (appeals == null || appeals.isEmpty() || !isAvailable()) {
            return result;
        }
        try {
            result = syncSavedChunk(appeals);
        } finally {
            flushLog();
        }
        return result;
    }

    private static Result syncSavedChunk(List<Appeal__c> appeals) {
        Result result = new Result();
        Map<Id, String> linkBefore = new Map<Id, String>();
        List<Appeal__c> valid = new List<Appeal__c>();
        for (Appeal__c appeal : appeals) {
            linkBefore.put(appeal.Id, appeal.Campaign_Id__c);
            // A value typed while the sync was off was never checked (R-CS8).
            if (normalizeLink(appeal)) {
                valid.add(appeal);
            } else {
                result.failed++;
                log(
                    String.format(
                        Label.Connect_CampaignSync_LogFailed,
                        new List<Object>{
                            appeal.Name,
                            Label.Connect_CampaignSync_InvalidCampaignId
                        }
                    ),
                    appeal
                );
            }
        }
        if (valid.isEmpty()) {
            return result;
        }
        Integer refused = result.failed;
        Integer queuedBefore = pendingMessages.size();
        Savepoint beforeChunk = Database.setSavepoint();
        try {
            result = copy(valid);
            result.failed += refused;
            storeLinks(valid, linkBefore, result);
        } catch (Exception unexpected) {
            Database.rollback(beforeChunk);
            // What was queued after the savepoint describes writes that are now undone.
            while (pendingMessages.size() > queuedBefore) {
                pendingMessages.remove(pendingMessages.size() - 1);
                pendingRecordIds.remove(pendingRecordIds.size() - 1);
            }
            ErrorLogger.log(unexpected, CONTEXT);
            result = new Result();
            result.failed = appeals.size();
        }
        return result;
    }

    /**
     * Saves each appeal whose link changed, with partial success. An appeal that is refused is
     * counted as failed, and a Campaign created for it in this call is deleted again.
     */
    private static void storeLinks(
        List<Appeal__c> appeals,
        Map<Id, String> linkBefore,
        Result result
    ) {
        List<Appeal__c> links = new List<Appeal__c>();
        List<Appeal__c> linkedFor = new List<Appeal__c>();
        for (Appeal__c appeal : appeals) {
            if (!ConnectSync.same(appeal.Campaign_Id__c, linkBefore.get(appeal.Id))) {
                links.add(new Appeal__c(Id = appeal.Id, Campaign_Id__c = appeal.Campaign_Id__c));
                linkedFor.add(appeal);
            }
        }
        if (links.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saved;
        AutomationControl.bypass(AUTOMATION_NAME);
        try {
            saved = Database.update(links, false, AccessLevel.USER_MODE);
        } finally {
            AutomationControl.clearBypass(AUTOMATION_NAME);
        }
        List<SObject> orphans = new List<SObject>();
        List<Appeal__c> orphanedFor = new List<Appeal__c>();
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                continue;
            }
            Appeal__c appeal = linkedFor[i];
            result.failed++;
            logRefusal(appeal, saved[i].getErrors());
            if (linkBefore.get(appeal.Id) == null) {
                // The Campaign was created in this call for an appeal that will not point at it.
                result.created--;
                orphans.add(campaignType().newSObject(Id.valueOf(appeal.Campaign_Id__c)));
                orphanedFor.add(appeal);
            }
        }
        deleteOrphans(orphans, orphanedFor);
    }

    private static void deleteOrphans(List<SObject> orphans, List<Appeal__c> orphanedFor) {
        if (orphans.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> deleted = Database.delete(
            orphans,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < deleted.size(); i++) {
            if (deleted[i].isSuccess()) {
                continue;
            }
            List<String> messages = new List<String>();
            for (Database.Error error : deleted[i].getErrors()) {
                messages.add(error.getMessage());
            }
            log(
                String.format(
                    Label.Connect_CampaignSync_LogOrphan,
                    new List<Object>{
                        String.valueOf(orphans[i].Id),
                        orphanedFor[i].Name,
                        String.join(messages, ' ')
                    }
                ),
                orphanedFor[i]
            );
        }
    }

    // ------------------------------------------------------------------------------ the copy

    /**
     * Creates or updates the Campaign of each appeal, and writes a new Campaign's identifier onto
     * the appeal in memory. Three DML statements at most, whatever the number of appeals.
     */
    private static Result copy(List<Appeal__c> appeals) {
        Result result = new Result();
        String campaignObject = campaignType().getDescribe().getName();

        Map<Id, Appeal__c> inScope = new Map<Id, Appeal__c>();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> linkedIds = new Set<Id>();
        for (Appeal__c appeal : appeals) {
            if (appeal.Id != null) {
                inScope.put(appeal.Id, appeal);
            }
            if (appeal.Parent_Appeal__c != null) {
                parentIds.add(appeal.Parent_Appeal__c);
            }
            if (appeal.Campaign_Id__c != null) {
                linkedIds.add(Id.valueOf(appeal.Campaign_Id__c));
            }
        }
        parentIds.removeAll(inScope.keySet());
        Map<Id, String> parentCampaigns = CampaignSyncSelector.campaignIdsByAppealId(parentIds);
        Map<Id, SObject> current = CampaignSyncSelector.campaignsById(campaignObject, linkedIds);

        List<SObject> inserts = new List<SObject>();
        List<Appeal__c> insertedFor = new List<Appeal__c>();
        List<SObject> updates = new List<SObject>();
        List<Appeal__c> updatedFor = new List<Appeal__c>();
        Map<Integer, Id> parentWritten = new Map<Integer, Id>();

        for (Integer i = 0; i < appeals.size(); i++) {
            Appeal__c appeal = appeals[i];
            Id parentCampaignId = parentCampaignId(appeal, inScope, parentCampaigns);
            parentWritten.put(i, parentCampaignId);
            SObject desired = desiredCampaign(appeal, parentCampaignId);
            if (appeal.Campaign_Id__c == null) {
                inserts.add(desired);
                insertedFor.add(appeal);
                continue;
            }
            SObject existing = current.get(Id.valueOf(appeal.Campaign_Id__c));
            if (existing == null) {
                result.failed++;
                log(
                    String.format(
                        Label.Connect_CampaignSync_LogMissing,
                        new List<Object>{ appeal.Name }
                    ),
                    appeal
                );
                continue;
            }
            desired.Id = existing.Id;
            if (differs(desired, existing)) {
                updates.add(desired);
                updatedFor.add(appeal);
            } else {
                result.unchanged++;
            }
        }

        if (!inserts.isEmpty()) {
            List<Database.SaveResult> saved = Database.insert(
                inserts,
                false,
                AccessLevel.USER_MODE
            );
            for (Integer i = 0; i < saved.size(); i++) {
                if (saved[i].isSuccess()) {
                    insertedFor[i].Campaign_Id__c = saved[i].getId();
                    result.created++;
                } else {
                    result.failed++;
                    logRefusal(insertedFor[i], saved[i].getErrors());
                }
            }
        }
        if (!updates.isEmpty()) {
            List<Database.SaveResult> saved = Database.update(
                updates,
                false,
                AccessLevel.USER_MODE
            );
            for (Integer i = 0; i < saved.size(); i++) {
                if (saved[i].isSuccess()) {
                    result.updated++;
                } else {
                    result.failed++;
                    logRefusal(updatedFor[i], saved[i].getErrors());
                }
            }
        }
        result.failed += fixParentsCreatedHere(appeals, inScope, parentWritten, campaignObject);
        return result;
    }

    /**
     * A parent appeal in the same call may have had its Campaign created only now, after its
     * children's Campaigns were built without a parent. One more update puts them under it.
     *
     * @return how many of those updates the platform refused
     */
    private static Integer fixParentsCreatedHere(
        List<Appeal__c> appeals,
        Map<Id, Appeal__c> inScope,
        Map<Integer, Id> parentWritten,
        String campaignObject
    ) {
        List<SObject> fixes = new List<SObject>();
        List<Appeal__c> fixedFor = new List<Appeal__c>();
        for (Integer i = 0; i < appeals.size(); i++) {
            Appeal__c appeal = appeals[i];
            Appeal__c parent = appeal.Parent_Appeal__c == null
                ? null
                : inScope.get(appeal.Parent_Appeal__c);
            if (appeal.Campaign_Id__c == null || parent == null || parent.Campaign_Id__c == null) {
                continue;
            }
            Id parentCampaignId = Id.valueOf(parent.Campaign_Id__c);
            if (parentCampaignId == parentWritten.get(i)) {
                continue;
            }
            SObject fix = campaignType().newSObject(Id.valueOf(appeal.Campaign_Id__c));
            fix.put(PARENT_FIELD, parentCampaignId);
            fixes.add(fix);
            fixedFor.add(appeal);
        }
        if (fixes.isEmpty()) {
            return 0;
        }
        Integer refused = 0;
        List<Database.SaveResult> saved = Database.update(fixes, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saved.size(); i++) {
            if (!saved[i].isSuccess()) {
                refused++;
                logRefusal(fixedFor[i], saved[i].getErrors());
            }
        }
        return refused;
    }

    // ------------------------------------------------------------------------------- helpers

    /**
     * Tidies a typed Campaign ID and refuses one that is not a Campaign's (R-CS8). A 15 character
     * identifier is stored as its 18 character form, so uniqueness holds whichever was pasted.
     *
     * @return false when the value was refused, with the error on the field
     */
    @TestVisible
    private static Boolean normalizeLink(Appeal__c appeal) {
        if (String.isBlank(appeal.Campaign_Id__c)) {
            appeal.Campaign_Id__c = null;
            return true;
        }
        Id typed = ConnectSync.idOf(appeal.Campaign_Id__c, campaignType());
        if (typed == null) {
            appeal.Campaign_Id__c.addError(Label.Connect_CampaignSync_InvalidCampaignId);
            return false;
        }
        appeal.Campaign_Id__c = String.valueOf(typed);
        return true;
    }

    private static Boolean copiedValuesChanged(Appeal__c appeal, Appeal__c old) {
        for (Schema.SObjectField field : COPIED.keySet()) {
            if (!ConnectSync.same(appeal.get(field), old.get(field))) {
                return true;
            }
        }
        return appeal.Parent_Appeal__c != old.Parent_Appeal__c ||
            !ConnectSync.same(appeal.Campaign_Id__c, old.Campaign_Id__c);
    }

    private static Id parentCampaignId(
        Appeal__c appeal,
        Map<Id, Appeal__c> inScope,
        Map<Id, String> parentCampaigns
    ) {
        if (appeal.Parent_Appeal__c == null) {
            return null;
        }
        String link = inScope.containsKey(appeal.Parent_Appeal__c)
            ? inScope.get(appeal.Parent_Appeal__c).Campaign_Id__c
            : parentCampaigns.get(appeal.Parent_Appeal__c);
        return link == null ? null : Id.valueOf(link);
    }

    @TestVisible
    private static SObject desiredCampaign(Appeal__c appeal, Id parentCampaignId) {
        SObject campaign = campaignType().newSObject();
        for (Schema.SObjectField field : COPIED.keySet()) {
            Object value = appeal.get(field);
            if (field == Appeal__c.Description__c && value != null) {
                value = ((String) value).left(DESCRIPTION_LIMIT);
            }
            if (field == Appeal__c.Active__c) {
                value = value == true;
            }
            campaign.put(COPIED.get(field), value);
        }
        campaign.put(PARENT_FIELD, parentCampaignId);
        return campaign;
    }

    /** True when any copied value differs. */
    @TestVisible
    private static Boolean differs(SObject desired, SObject existing) {
        List<String> fields = new List<String>(COPIED.values());
        fields.add(PARENT_FIELD);
        for (String field : fields) {
            if (!ConnectSync.same(desired.get(field), existing.get(field))) {
                return true;
            }
        }
        return false;
    }

    private static void logRefusal(Appeal__c appeal, List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        log(
            String.format(
                Label.Connect_CampaignSync_LogFailed,
                new List<Object>{ appeal.Name, String.join(messages, ' ') }
            ),
            appeal
        );
    }

    /** Queues a Warning about one appeal; `flushLog` writes the queue. */
    private static void log(String message, Appeal__c appeal) {
        pendingMessages.add(message);
        pendingRecordIds.add(appeal.Id);
    }

    /** Writes every queued Warning in one statement (R-CS5). */
    private static void flushLog() {
        if (pendingMessages.isEmpty()) {
            return;
        }
        List<String> messages = pendingMessages;
        List<Id> recordIds = pendingRecordIds;
        pendingMessages = new List<String>();
        pendingRecordIds = new List<Id>();
        ErrorLogger.logMessages(messages, recordIds, CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }
}
