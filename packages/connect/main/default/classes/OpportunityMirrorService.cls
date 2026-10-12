/**
 * The Opportunity mirror, Gifts to Opportunities (feature X-01, canonical model Section 29C,
 * ADR-0058): a one-way copy of each gift in the totals to a standard
 * Salesforce Opportunity with its primary contact role.
 *
 * Two callers share one copy, as in Campaign sync. The `Opportunity_Mirror` automation calls
 * `syncBeforeSave` while a gift is being saved, so a new Opportunity's identifier is stored with
 * the gift in the same save (R-OM4). `OpportunityMirrorBatch` calls `syncSaved` for a run, and
 * stores the new links itself (R-OM8).
 *
 * Opportunity and its contact roles are reached only through describe and SObject generics, so
 * Connect installs and this class compiles where they do not exist; there the mirror does
 * nothing (plan Section 4.2, R-OM1).
 *
 * Every write is in user mode with partial success (R-OM5, R-OM6): Opportunity is a standard
 * object the package does not own, and an Opportunity the platform refuses must never refuse the
 * gift. Refusals are grouped by the platform's message and written in one statement at the end
 * of the call, or handed to the run to write when it ends.
 */
public with sharing class OpportunityMirrorService {
    /** The registry name of the automation, used to bypass it while a run stores links. */
    public static final String AUTOMATION_NAME = 'Opportunity_Mirror';
    public static final String OFF = 'Off';
    public static final String GIFTS_TO_OPPORTUNITIES = 'GiftsToOpportunities';
    public static final String OPPORTUNITIES_TO_GIFTS = 'OpportunitiesToGifts';
    public static final String CONTEXT = 'Opportunity mirror';

    /** The statuses that count in the giving totals (ADR-0022), which are the ones copied. */
    public static final Set<String> IN_TOTALS = new Set<String>{
        'Received',
        'Refunded',
        'Written off'
    };

    public static final String CAMPAIGN_FIELD = OpportunityMirrorContext.CAMPAIGN_FIELD;
    public static final String DONOR_ROLE = OpportunityMirrorContext.DONOR_ROLE;
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final String WON_STAGE = 'Closed Won';
    private static final String LOST_STAGE = 'Closed Lost';

    /**
     * What one copy costs at most: seven reads (the linked Opportunities, the appeals' Campaigns,
     * contact and account names, person contacts, stages and contact roles), and two Opportunity
     * and two role writes.
     */
    private static final Integer QUERIES_NEEDED = 7;
    private static final Integer DML_STATEMENTS_NEEDED = 4;
    /**
     * The org's own Opportunity automation runs inside the gift's save and its cost is unknown
     * (ADR-0058 decision 3), so a copy starts only with these shares of the limits unspent.
     */
    private static final Decimal CPU_SHARE_NEEDED = 0.4;
    private static final Decimal LIMIT_SHARE_NEEDED = 0.5;

    /** The Opportunity field each copied gift attribute is compared on (R-OM3). */
    public static final List<String> COMPARED = OpportunityMirrorContext.COMPARED;
    /** The gift attributes whose change starts a copy. */
    private static final List<Schema.SObjectField> WATCHED = new List<Schema.SObjectField>{
        Gift__c.Amount__c,
        Gift__c.Gift_Date__c,
        Gift__c.Status__c,
        Gift__c.Donor_Contact__c,
        Gift__c.Donor_Account__c,
        Gift__c.Household__c,
        Gift__c.Appeal__c,
        Gift__c.Opportunity_Id__c
    };

    private static Map<Boolean, String> stageByWon;
    /**
     * The Opportunities this transaction created. A save with partial success that the platform
     * retries has rolled them back, while the gifts it retries can still carry their identifiers.
     */
    private static Set<Id> createdHere = new Set<Id>();

    /** Each once-per-transaction Warning, so a large save does not write it per chunk. */
    private static Boolean noAccessLogged = false;
    private static Boolean noHeadroomLogged = false;

    /** What one call did, for the run summary and the tests. */
    public class Result {
        public Integer created = 0;
        public Integer updated = 0;
        public Integer unchanged = 0;
        public Integer failed = 0;
        public Integer skipped = 0;
        /** The refusals, grouped by message; written by the caller (R-OM6). */
        public ConnectSync.Warnings refusals = new ConnectSync.Warnings();

        public void add(Result other) {
            created += other.created;
            updated += other.updated;
            unchanged += other.unchanged;
            failed += other.failed;
            skipped += other.skipped;
            refusals.addAll(other.refusals);
        }

        /** Writes the grouped refusals of gifts as Warnings, in one statement. */
        public void writeRefusals() {
            refusals.write(
                CONTEXT,
                Label.Connect_OpportunityMirror_LogOne,
                Label.Connect_OpportunityMirror_LogMany
            );
        }

        /** Writes the grouped refusals of Opportunities that could not become gifts. */
        public void writeOpportunityRefusals() {
            refusals.write(
                CONTEXT,
                Label.Connect_OpportunityMirror_LogOneOpportunity,
                Label.Connect_OpportunityMirror_LogManyOpportunities
            );
        }
    }

    // ------------------------------------------------------------------ what the org allows

    /**
     * Set by tests to see the org as having no Opportunity, the Platform-only shape no test org
     * has (dynamic-apex.md section 9), so the absent path is run rather than skipped.
     */
    @TestVisible
    private static Boolean unavailableForTest = false;

    /** The Opportunity object, or null in an org without it (a Platform-only org). */
    public static Schema.SObjectType opportunityType() {
        if (unavailableForTest == true) {
            return null;
        }
        return OpportunityMirrorContext.opportunityType();
    }

    public static Schema.SObjectType roleType() {
        if (unavailableForTest == true) {
            return null;
        }
        return OpportunityMirrorContext.roleType();
    }

    /** The contact role object's name, or null in an org without Opportunity. */
    public static String roleObjectName() {
        return roleType() == null ? null : roleType().getDescribe().getName();
    }

    public static Boolean isAvailable() {
        return opportunityType() != null && roleType() != null;
    }

    /** The chosen direction: Off, GiftsToOpportunities or OpportunitiesToGifts (R-OM1). */
    public static String direction() {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        String chosen = settings == null ? null : settings.Opportunity_Mirror_Direction__c;
        return String.isBlank(chosen) ? OFF : chosen;
    }

    /** Whether gifts are copied to Opportunities in this org. */
    public static Boolean copiesGifts() {
        return isAvailable() && direction() == GIFTS_TO_OPPORTUNITIES;
    }

    /**
     * Whether the running user can make the copy made when a gift is saved: create and edit
     * Opportunities (R-OM5). Nothing more: the Opportunity ID is written onto the gift being
     * saved, which is not checked against the saver's field access, so a gift-entry user without
     * the Opportunity Mirror permission set still has a linked gift's changes copied.
     */
    public static Boolean canCopy() {
        if (!isAvailable()) {
            return false;
        }
        Schema.DescribeSObjectResult opportunity = opportunityType().getDescribe();
        return opportunity.isCreateable() && opportunity.isUpdateable();
    }

    // ------------------------------------------------------------------------- the two callers

    /**
     * The automation's path: gifts in a before-insert or before-update context. New links are
     * written onto the records being saved. Never throws: whatever goes wrong is logged and the
     * gift saves (R-OM6).
     *
     * @param gifts the gifts being saved
     * @param oldById their previous values, or null on insert
     */
    public static Result syncBeforeSave(List<Gift__c> gifts, Map<Id, Gift__c> oldById) {
        Result result = new Result();
        if (gifts == null || gifts.isEmpty() || !copiesGifts()) {
            return result;
        }
        List<Gift__c> scope = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            if (gift.hasErrors() || !normalizeLink(gift)) {
                continue;
            }
            Gift__c old = oldById == null ? null : oldById.get(gift.Id);
            if (
                gift.Opportunity_Id__c != null &&
                (old == null ||
                old.Opportunity_Id__c != gift.Opportunity_Id__c) &&
                createdHere.contains(Id.valueOf(gift.Opportunity_Id__c))
            ) {
                // A link this save wrote, now rolled back by a retry: made again, never left
                // pointing at an Opportunity that no longer exists.
                gift.Opportunity_Id__c = null;
            }
            if (inScope(gift, old)) {
                scope.add(gift);
            }
        }
        if (scope.isEmpty()) {
            return result;
        }
        if (!canCopy()) {
            result.skipped = scope.size();
            logNoAccess(scope.size());
            return result;
        }
        if (!hasHeadroom(scope.size())) {
            // A save too large to copy is left to the next run rather than failed (R-OM6).
            result.skipped = scope.size();
            if (!noHeadroomLogged) {
                noHeadroomLogged = true;
                ErrorLogger.logMessage(
                    Label.Connect_OpportunityMirror_LogNoHeadroom,
                    CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            return result;
        }
        try {
            result = copy(scope);
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            result = new Result();
            result.failed = scope.size();
        }
        result.writeRefusals();
        return result;
    }

    /**
     * A run's path (R-OM8): gifts already saved. Copies them, then stores any new link on the gift
     * with this automation bypassed, since the copy has just been made. The refusals stay on the
     * result, for the run to write once when it ends.
     *
     * The links are stored with partial success, so one gift that cannot be saved never costs the
     * rest of the chunk their links. An Opportunity made here for such a gift is deleted again at
     * once, so the next run does not make a second one (R-OM9). Only a failure that throws rolls
     * the whole chunk back, Opportunities included.
     */
    public static Result syncSaved(List<Gift__c> gifts) {
        Result result = new Result();
        if (gifts == null || gifts.isEmpty() || !isAvailable()) {
            return result;
        }
        Map<Id, String> linkBefore = new Map<Id, String>();
        List<Gift__c> valid = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            linkBefore.put(gift.Id, gift.Opportunity_Id__c);
            if (String.isBlank(gift.Opportunity_Id__c) || idOf(gift) != null) {
                gift.Opportunity_Id__c = String.isBlank(gift.Opportunity_Id__c)
                    ? null
                    : String.valueOf(idOf(gift));
                valid.add(gift);
            } else {
                result.failed++;
                result.refusals.add(
                    Label.Connect_OpportunityMirror_InvalidOpportunityId,
                    gift.Name,
                    gift.Id
                );
            }
        }
        if (valid.isEmpty()) {
            return result;
        }
        Savepoint beforeChunk = Database.setSavepoint();
        try {
            Result copied = copy(valid);
            storeLinks(valid, linkBefore, copied);
            result.add(copied);
        } catch (Exception unexpected) {
            Database.rollback(beforeChunk);
            ErrorLogger.log(unexpected, CONTEXT);
            Result undone = new Result();
            undone.failed = gifts.size();
            undone.refusals = result.refusals;
            result = undone;
        }
        return result;
    }

    /**
     * The automation's after-delete path (R-OM9): the Opportunity of a deleted gift is left in
     * place, and one Warning per message names the gifts and their Opportunities, for the
     * administrator to delete or close. In Opportunities to Gifts it also says the next run makes
     * a new gift from an Opportunity still won.
     */
    public static void warnDeleted(List<Gift__c> deleted) {
        if (deleted == null || deleted.isEmpty() || !isAvailable() || direction() == OFF) {
            return;
        }
        String message = direction() == OPPORTUNITIES_TO_GIFTS
            ? Label.Connect_OpportunityMirror_DeletedRemade
            : Label.Connect_OpportunityMirror_DeletedKept;
        ConnectSync.Warnings warnings = new ConnectSync.Warnings();
        for (Gift__c gift : deleted) {
            if (gift.Opportunity_Id__c != null) {
                warnings.add(message, gift.Name + ' (' + gift.Opportunity_Id__c + ')', gift.Id);
            }
        }
        warnings.write(
            CONTEXT,
            Label.Connect_OpportunityMirror_LogDeletedOne,
            Label.Connect_OpportunityMirror_LogDeletedMany
        );
    }

    // ------------------------------------------------------------------------ which gifts

    /** R-OM2 and R-OM4: whether this save of the gift needs a copy. */
    private static Boolean inScope(Gift__c gift, Gift__c old) {
        if (gift.Opportunity_Id__c == null) {
            return IN_TOTALS.contains(gift.Status__c);
        }
        if (old == null) {
            return true;
        }
        for (Schema.SObjectField field : WATCHED) {
            if (!ConnectSync.same(gift.get(field), old.get(field))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Written when someone who cannot create Opportunities creates or changes gifts in a save of
     * their own, once per transaction; never from a background job, where an import of many
     * chunks would repeat it for every chunk (R-OM5). The next run copies them either way.
     */
    private static void logNoAccess(Integer howMany) {
        if (noAccessLogged || System.isBatch() || System.isQueueable()) {
            return;
        }
        noAccessLogged = true;
        ErrorLogger.logMessage(
            String.format(Label.Connect_OpportunityMirror_LogNoAccess, new List<Object>{ howMany }),
            CONTEXT,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    /**
     * Whether this transaction still has room for one copy of this many gifts: a gift can cost an
     * Opportunity insert or update and a contact role write, with a margin for the other
     * automation on Gift and Opportunity.
     */
    @TestVisible
    private static Boolean hasHeadroom(Integer giftCount) {
        return ConnectSync.hasHeadroom(
            QUERIES_NEEDED,
            DML_STATEMENTS_NEEDED,
            3 * giftCount,
            CPU_SHARE_NEEDED,
            LIMIT_SHARE_NEEDED
        );
    }

    // ------------------------------------------------------------------------------ the copy

    /**
     * Creates or updates the Opportunity of each gift and its primary contact role, and writes a
     * new Opportunity's identifier onto the gift in memory. Four DML statements at most, whatever
     * the number of gifts.
     */
    private static Result copy(List<Gift__c> gifts) {
        Result result = new Result();
        OpportunityMirrorContext context = new OpportunityMirrorContext(gifts);

        List<SObject> inserts = new List<SObject>();
        List<Gift__c> insertedFor = new List<Gift__c>();
        List<SObject> updates = new List<SObject>();
        List<Gift__c> updatedFor = new List<Gift__c>();
        List<Gift__c> linked = new List<Gift__c>();

        for (Gift__c gift : gifts) {
            // A Pending gift leaves its Opportunity's stage alone (R-OM3), so linking an open
            // Opportunity to a pledge never closes it; it never gets a new Opportunity.
            Boolean keepsStage = keepsStage(gift.Status__c);
            if (keepsStage && gift.Opportunity_Id__c == null) {
                result.unchanged++;
                continue;
            }
            String stage = keepsStage ? null : stage(IN_TOTALS.contains(gift.Status__c));
            if (!keepsStage && stage == null) {
                result.failed++;
                result.refusals.add(Label.Connect_OpportunityMirror_NoStage, nameOf(gift), gift.Id);
                continue;
            }
            SObject desired = context.desiredOpportunity(gift, stage);
            if (gift.Opportunity_Id__c == null) {
                context.prepareNew(desired, gift);
                inserts.add(desired);
                insertedFor.add(gift);
                continue;
            }
            SObject existing = context.current.get(Id.valueOf(gift.Opportunity_Id__c));
            if (existing == null) {
                result.failed++;
                result.refusals.add(Label.Connect_OpportunityMirror_Missing, nameOf(gift), gift.Id);
                continue;
            }
            desired.Id = existing.Id;
            if (keepsStage) {
                desired.put('StageName', existing.get('StageName'));
            }
            linked.add(gift);
            if (context.differs(desired, existing)) {
                updates.add(desired);
                updatedFor.add(gift);
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
                    insertedFor[i].Opportunity_Id__c = saved[i].getId();
                    createdHere.add(saved[i].getId());
                    linked.add(insertedFor[i]);
                    result.created++;
                } else {
                    result.failed++;
                    refuse(result, insertedFor[i], saved[i].getErrors());
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
                    refuse(result, updatedFor[i], saved[i].getErrors());
                }
            }
        }
        writeContactRoles(linked, context, result);
        return result;
    }

    /**
     * Gives each linked Opportunity its donor as primary contact role (R-OM3): a new role where it
     * has none, the donor put on the existing one where it names someone else. A role the platform
     * refuses is logged; the Opportunity stays.
     */
    private static void writeContactRoles(
        List<Gift__c> gifts,
        OpportunityMirrorContext context,
        Result result
    ) {
        Map<Id, Gift__c> giftByOpportunity = new Map<Id, Gift__c>();
        for (Gift__c gift : gifts) {
            if (context.personOf(gift) != null) {
                giftByOpportunity.put(Id.valueOf(gift.Opportunity_Id__c), gift);
            }
        }
        if (giftByOpportunity.isEmpty()) {
            return;
        }
        String roleObject = roleType().getDescribe().getName();
        Map<Id, SObject> primaries = OpportunityMirrorSelector.primaryRolesByOpportunity(
            roleObject,
            giftByOpportunity.keySet()
        );
        List<SObject> inserts = new List<SObject>();
        List<SObject> updates = new List<SObject>();
        List<Gift__c> insertedFor = new List<Gift__c>();
        List<Gift__c> updatedFor = new List<Gift__c>();
        for (Id opportunityId : giftByOpportunity.keySet()) {
            Gift__c gift = giftByOpportunity.get(opportunityId);
            Id person = context.personOf(gift);
            SObject primary = primaries.get(opportunityId);
            if (primary == null) {
                SObject role = roleType().newSObject();
                role.put('OpportunityId', opportunityId);
                role.put('ContactId', person);
                role.put('IsPrimary', true);
                if (context.donorRoleExists) {
                    role.put('Role', DONOR_ROLE);
                }
                inserts.add(role);
                insertedFor.add(gift);
            } else if (primary.get('ContactId') != person) {
                SObject role = roleType().newSObject((Id) primary.get('Id'));
                role.put('ContactId', person);
                updates.add(role);
                updatedFor.add(gift);
            }
        }
        if (!inserts.isEmpty()) {
            refuseRoles(
                Database.insert(inserts, false, AccessLevel.USER_MODE),
                insertedFor,
                result
            );
        }
        if (!updates.isEmpty()) {
            refuseRoles(Database.update(updates, false, AccessLevel.USER_MODE), updatedFor, result);
        }
    }

    private static void refuseRoles(
        List<Database.SaveResult> saved,
        List<Gift__c> savedFor,
        Result result
    ) {
        for (Integer i = 0; i < saved.size(); i++) {
            if (!saved[i].isSuccess()) {
                result.refusals.add(
                    String.format(
                        Label.Connect_OpportunityMirror_ContactRole,
                        new List<Object>{ messageOf(saved[i].getErrors()) }
                    ),
                    nameOf(savedFor[i]),
                    savedFor[i].Id
                );
            }
        }
    }

    /**
     * Saves each gift whose link changed, with partial success. A gift that is refused is counted
     * as failed, and an Opportunity created for it in this call is deleted again (R-OM9).
     */
    private static void storeLinks(List<Gift__c> gifts, Map<Id, String> linkBefore, Result result) {
        List<Gift__c> links = new List<Gift__c>();
        List<Gift__c> linkedFor = new List<Gift__c>();
        for (Gift__c gift : gifts) {
            if (!ConnectSync.same(gift.Opportunity_Id__c, linkBefore.get(gift.Id))) {
                links.add(new Gift__c(Id = gift.Id, Opportunity_Id__c = gift.Opportunity_Id__c));
                linkedFor.add(gift);
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
        List<Gift__c> orphanedFor = new List<Gift__c>();
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                continue;
            }
            Gift__c gift = linkedFor[i];
            result.failed++;
            refuse(result, gift, saved[i].getErrors());
            if (linkBefore.get(gift.Id) == null) {
                result.created--;
                orphans.add(opportunityType().newSObject(Id.valueOf(gift.Opportunity_Id__c)));
                orphanedFor.add(gift);
            }
        }
        if (orphans.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> deleted = Database.delete(
            orphans,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < deleted.size(); i++) {
            if (!deleted[i].isSuccess()) {
                result.refusals.add(
                    String.format(
                        Label.Connect_OpportunityMirror_LogOrphan,
                        new List<Object>{
                            String.valueOf(orphans[i].Id),
                            messageOf(deleted[i].getErrors())
                        }
                    ),
                    orphanedFor[i].Name,
                    orphanedFor[i].Id
                );
            }
        }
    }

    // ------------------------------------------------------------------------------- helpers

    /**
     * Tidies a typed Opportunity ID and refuses one that is not an Opportunity's (R-OM10). A 15
     * character identifier is stored as its 18 character form, so uniqueness holds.
     *
     * @return false when the value was refused, with the error on the field
     */
    private static Boolean normalizeLink(Gift__c gift) {
        if (String.isBlank(gift.Opportunity_Id__c)) {
            gift.Opportunity_Id__c = null;
            return true;
        }
        Id typed = idOf(gift);
        if (typed == null) {
            gift.Opportunity_Id__c.addError(Label.Connect_OpportunityMirror_InvalidOpportunityId);
            return false;
        }
        gift.Opportunity_Id__c = String.valueOf(typed);
        return true;
    }

    private static Id idOf(Gift__c gift) {
        return ConnectSync.idOf(gift.Opportunity_Id__c, opportunityType());
    }

    /** The gift's name, or words for a gift not yet saved, whose number is not assigned yet. */
    private static String nameOf(Gift__c gift) {
        if (String.isNotBlank(gift.Name)) {
            return gift.Name;
        }
        return String.format(
            Label.Connect_OpportunityMirror_NewGift,
            new List<Object>{ String.valueOf(gift.Amount__c), String.valueOf(gift.Gift_Date__c) }
        );
    }

    private static void refuse(Result result, Gift__c gift, List<Database.Error> errors) {
        result.refusals.add(messageOf(errors), nameOf(gift), gift.Id);
    }

    private static String messageOf(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return String.join(messages, ' ');
    }

    /** Whether a gift of this status leaves its Opportunity's stage as it is (R-OM3). */
    private static Boolean keepsStage(String status) {
        return !IN_TOTALS.contains(status) && status != STATUS_CANCELLED;
    }

    /** The won or lost stage (R-OM3), read once per transaction. */
    private static String stage(Boolean won) {
        if (stageByWon == null) {
            stageByWon = new Map<Boolean, String>();
            for (SObject stage : OpportunityMirrorSelector.activeStages()) {
                if (stage.get('IsClosed') != true) {
                    continue;
                }
                Boolean isWon = stage.get('IsWon') == true;
                String name = (String) stage.get('ApiName');
                // The stage with the usual name wins; otherwise the first in the org's order.
                if (name == (isWon ? WON_STAGE : LOST_STAGE) || !stageByWon.containsKey(isWon)) {
                    stageByWon.put(isWon, name);
                }
            }
        }
        return stageByWon.get(won);
    }
}
