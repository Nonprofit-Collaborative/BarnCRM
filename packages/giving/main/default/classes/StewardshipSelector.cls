/**
 * Every query stewardship plans need (plan Section 9.3).
 *
 * The reads the automatic starter uses run in system mode, for the reason ADR-0021 gives for the
 * rest of the module's package-owned data: a plan that quietly stopped starting because the person
 * entering a gift cannot see the template records would be a follow-up nobody knows was skipped.
 * The reads a page shows to somebody run in user mode, so what they see is what they may see.
 */
public with sharing class StewardshipSelector {
    /** How many templates one org is expected to have. Well past any real ladder of sequences. */
    private static final Integer TEMPLATE_LIMIT = 200;

    /**
     * The active templates listening for any of the given events, with their steps already loaded
     * in the order they are laid out. One query for templates and their children, so starting
     * plans for two hundred gifts costs the same two queries as starting one.
     */
    public static List<Stewardship_Plan_Template__c> selectActiveTemplatesForEvents(
        Set<String> events
    ) {
        if (events == null || events.isEmpty()) {
            return new List<Stewardship_Plan_Template__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Trigger_Event__c,
                Minimum_Amount__c,
                (
                    SELECT
                        Id,
                        Order__c,
                        Subject__c,
                        Days_After_Start__c,
                        Assign_To__c,
                        Assigned_User__c,
                        Priority__c,
                        Comments__c
                    FROM Steps__r
                    ORDER BY Order__c ASC, Name ASC
                )
            FROM Stewardship_Plan_Template__c
            WHERE Active__c = TRUE AND Trigger_Event__c IN :events
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT :TEMPLATE_LIMIT
        ];
    }

    /** One template with its steps, for a start somebody asked for by hand. */
    public static List<Stewardship_Plan_Template__c> selectTemplateById(Id templateId) {
        if (templateId == null) {
            return new List<Stewardship_Plan_Template__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Active__c,
                Trigger_Event__c,
                (
                    SELECT
                        Id,
                        Order__c,
                        Subject__c,
                        Days_After_Start__c,
                        Assign_To__c,
                        Assigned_User__c,
                        Priority__c,
                        Comments__c
                    FROM Steps__r
                    ORDER BY Order__c ASC, Name ASC
                )
            FROM Stewardship_Plan_Template__c
            WHERE Id = :templateId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    /**
     * The running plans for the given donors, which is what R-SP6 is checked against. Both donor
     * sides are asked for in one query rather than two, because a gift list mixes them.
     */
    public static List<Stewardship_Plan__c> selectRunningPlansFor(
        Set<Id> contactIds,
        Set<Id> accountIds
    ) {
        Set<Id> contacts = contactIds == null ? new Set<Id>() : contactIds;
        Set<Id> accounts = accountIds == null ? new Set<Id>() : accountIds;
        if (contacts.isEmpty() && accounts.isEmpty()) {
            return new List<Stewardship_Plan__c>();
        }
        return [
            SELECT Id, Stewardship_Plan_Template__c, Contact__c, Account__c
            FROM Stewardship_Plan__c
            WHERE
                Status__c = :StewardshipService.STATUS_RUNNING
                AND (Contact__c IN :contacts
                OR Account__c IN :accounts)
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /**
     * Whether each of the given donors has any gift besides the one being considered. This is what
     * "first gift" means in R-SP3: the gift being saved is the only one the donor has that counts
     * toward giving totals.
     *
     * The status set is the one the packaged rollups use (canonical model Section 26 and
     * ADR-0022), so a donor whose only other gift was refunded is still a first-time donor by the
     * same reckoning the totals use.
     */
    public static Map<String, Integer> countCountableGifts(Set<Id> donorIds, Set<Id> excludeGifts) {
        Map<String, Integer> counts = new Map<String, Integer>();
        if (donorIds == null || donorIds.isEmpty()) {
            return counts;
        }
        Set<Id> exclude = excludeGifts == null ? new Set<Id>() : excludeGifts;
        Set<String> statuses = StewardshipService.COUNTABLE_STATUSES;
        for (Gift__c gift : [
            SELECT Id, Donor_Contact__c, Donor_Account__c
            FROM Gift__c
            WHERE
                Status__c IN :statuses
                AND Amount__c > 0
                AND Id NOT IN :exclude
                AND (Donor_Contact__c IN :donorIds
                OR Donor_Account__c IN :donorIds)
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            String key = String.valueOf(
                gift.Donor_Contact__c == null ? gift.Donor_Account__c : gift.Donor_Contact__c
            );
            Integer seen = counts.get(key);
            counts.put(key, seen == null ? 1 : seen + 1);
        }
        return counts;
    }

    /**
     * Who each donor record belongs to, which is what a Record owner step means. One query for
     * both donor sides, so a step that assigns to the record owner costs the same whether one plan
     * starts or two hundred do.
     */
    public static Map<Id, Id> selectOwners(Set<Id> contactIds, Set<Id> accountIds) {
        Map<Id, Id> owners = new Map<Id, Id>();
        Set<Id> contacts = contactIds == null ? new Set<Id>() : contactIds;
        Set<Id> accounts = accountIds == null ? new Set<Id>() : accountIds;
        if (!contacts.isEmpty()) {
            for (Contact person : [
                SELECT Id, OwnerId
                FROM Contact
                WHERE Id IN :contacts
                WITH SYSTEM_MODE
                LIMIT 10000
            ]) {
                owners.put(person.Id, person.OwnerId);
            }
        }
        if (!accounts.isEmpty()) {
            for (Account organization : [
                SELECT Id, OwnerId
                FROM Account
                WHERE Id IN :accounts
                WITH SYSTEM_MODE
                LIMIT 10000
            ]) {
                owners.put(organization.Id, organization.OwnerId);
            }
        }
        return owners;
    }

    /**
     * Every template with its steps, for the Stewardship Plans page in the settings console.
     *
     * Read as the person looking at the page rather than in system mode: this is an
     * administrator's own configuration surface, so what the page shows is what she may see, and
     * a field she cannot read is a field she is not offered.
     */
    public static List<Stewardship_Plan_Template__c> selectTemplatesForPage() {
        return [
            SELECT
                Id,
                Name,
                Plan_Key__c,
                Active__c,
                Trigger_Event__c,
                Minimum_Amount__c,
                Description__c,
                (
                    SELECT
                        Id,
                        Name,
                        Order__c,
                        Subject__c,
                        Days_After_Start__c,
                        Assign_To__c,
                        Assigned_User__c,
                        Assigned_User__r.Name,
                        Priority__c,
                        Comments__c
                    FROM Steps__r
                    ORDER BY Order__c ASC, Name ASC
                )
            FROM Stewardship_Plan_Template__c
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT :TEMPLATE_LIMIT
        ];
    }

    /**
     * How many plans are running from each template, which is the number that tells an
     * administrator what an edit will not reach (R-SP7). One grouped query rather than one per
     * template.
     */
    public static Map<Id, Integer> countRunningPlansByTemplate() {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Stewardship_Plan_Template__c template, COUNT(Id) total
            FROM Stewardship_Plan__c
            WHERE Status__c = :StewardshipService.STATUS_RUNNING
            WITH USER_MODE
            GROUP BY Stewardship_Plan_Template__c
            LIMIT :TEMPLATE_LIMIT
        ]) {
            Id templateId = (Id) row.get('template');
            if (templateId != null) {
                counts.put(templateId, (Integer) row.get('total'));
            }
        }
        return counts;
    }

    /**
     * Every plan key that starts with `prefix`, in lower case, so a generated key can be made
     * unique. In system mode on purpose: the key field is unique across the org, so a key held by
     * a plan the running user cannot see would still refuse the save. Only the keys are read.
     */
    public static Set<String> selectPlanKeysStartingWith(String prefix) {
        Set<String> keys = new Set<String>();
        String pattern = prefix + '%';
        for (Stewardship_Plan_Template__c template : [
            SELECT Plan_Key__c
            FROM Stewardship_Plan_Template__c
            WHERE Plan_Key__c LIKE :pattern
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            keys.add(template.Plan_Key__c.toLowerCase());
        }
        return keys;
    }

    /** One template's steps, in the order they are laid out, for a reorder or an edit. */
    public static List<Stewardship_Plan_Step__c> selectStepsFor(Id templateId) {
        if (templateId == null) {
            return new List<Stewardship_Plan_Step__c>();
        }
        return [
            SELECT Id, Order__c
            FROM Stewardship_Plan_Step__c
            WHERE Stewardship_Plan_Template__c = :templateId
            WITH USER_MODE
            ORDER BY Order__c ASC, Name ASC
            LIMIT 1000
        ];
    }

    /**
     * The people a step can be assigned to, for the picker on the settings page. Active users
     * only, because a step naming somebody who has left falls back to the plan starter (R-SP4) and
     * offering that name would be offering a setting that quietly does nothing.
     */
    public static List<User> selectAssignableUsers() {
        return [
            SELECT Id, Name
            FROM User
            WHERE IsActive = TRUE
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];
    }

    /** The templates a person may start by hand, read as that person. */
    public static List<Stewardship_Plan_Template__c> selectManualTemplates() {
        return [
            SELECT Id, Name, Description__c, Trigger_Event__c
            FROM Stewardship_Plan_Template__c
            WHERE Active__c = TRUE
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT :TEMPLATE_LIMIT
        ];
    }
}
