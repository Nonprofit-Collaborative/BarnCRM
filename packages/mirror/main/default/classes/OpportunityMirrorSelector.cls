/**
 * The queries behind the Opportunity mirror (feature X-01, canonical model Section 29C). Every
 * one runs in user mode: the copy is made with the access of the person saving the gift or
 * running the mirror, so a record they cannot see is a record the mirror does not touch (R-OM5).
 *
 * Opportunity, its contact roles and its stages are never named at compile time. Their queries
 * are built from the object names the service resolved through describe, so Mirror compiles and
 * installs where they do not exist (plan Section 4.2, ADR-0013).
 */
public with sharing class OpportunityMirrorSelector {
    /** The gift attributes R-OM3 copies, plus the link. */
    public static final String GIFT_FIELDS = 'Id, Name, Amount__c, Gift_Date__c, Status__c, Donor_Contact__c, Donor_Account__c, Household__c, Appeal__c, Opportunity_Id__c';

    // detection-only: stage records are read by name so Mirror installs without Opportunity
    private static final String STAGE_OBJECT = 'OpportunityStage';
    private static final String PERSON_CONTACT_FIELD = 'PersonContactId';
    private static final String IS_PERSON_ACCOUNT_FIELD = 'IsPersonAccount'; // detection-only: field map key, queried only where it exists

    /**
     * The Opportunities with these identifiers that the running user can see, keyed by Id.
     *
     * @param fields the fields to read, from the service, which knows which ones the org has
     */
    public static Map<Id, SObject> opportunitiesById(
        String opportunityObject,
        List<String> fields,
        Set<Id> ids
    ) {
        if (String.isBlank(opportunityObject) || ids == null || ids.isEmpty()) {
            return new Map<Id, SObject>();
        }
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    String.escapeSingleQuotes(String.join(fields, ', ')) +
                    ' FROM ' +
                    String.escapeSingleQuotes(opportunityObject) +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /** The primary contact role of each of these Opportunities, keyed by Opportunity. */
    public static Map<Id, SObject> primaryRolesByOpportunity(String roleObject, Set<Id> ids) {
        Map<Id, SObject> byOpportunity = new Map<Id, SObject>();
        if (String.isBlank(roleObject) || ids == null || ids.isEmpty()) {
            return byOpportunity;
        }
        for (
            SObject role : Database.queryWithBinds(
                'SELECT Id, OpportunityId, ContactId FROM ' +
                    String.escapeSingleQuotes(roleObject) +
                    ' WHERE OpportunityId IN :ids AND IsPrimary = TRUE',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            byOpportunity.put((Id) role.get('OpportunityId'), role);
        }
        return byOpportunity;
    }

    /** The org's active Opportunity stages, in the order the org sorts them. */
    public static List<SObject> activeStages() {
        return Database.query(
            'SELECT ApiName, IsWon, IsClosed, SortOrder FROM ' +
                STAGE_OBJECT +
                ' WHERE IsActive = TRUE ORDER BY SortOrder',
            AccessLevel.USER_MODE
        );
    }

    /** The name of each of these people and accounts that the running user can see. */
    public static Map<Id, String> namesById(Set<Id> contactIds, Set<Id> accountIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (contactIds != null && !contactIds.isEmpty()) {
            for (Contact person : [
                SELECT Id, Name
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
            ]) {
                names.put(person.Id, person.Name);
            }
        }
        if (accountIds != null && !accountIds.isEmpty()) {
            for (Account account : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]) {
                names.put(account.Id, account.Name);
            }
        }
        return names;
    }

    /**
     * The contact behind each of these accounts that holds a person, by account. Empty in an org
     * that does not store people as accounts, where the field does not exist.
     */
    public static Map<Id, Id> personContactIds(Set<Id> accountIds) {
        Map<Id, Id> byAccount = new Map<Id, Id>();
        if (
            accountIds == null ||
            accountIds.isEmpty() ||
            !Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_CONTACT_FIELD)
        ) {
            return byAccount;
        }
        for (
            SObject account : Database.queryWithBinds(
                'SELECT Id, ' +
                    PERSON_CONTACT_FIELD +
                    ' FROM Account WHERE Id IN :accountIds AND ' +
                    PERSON_CONTACT_FIELD +
                    ' != NULL',
                new Map<String, Object>{ 'accountIds' => accountIds },
                AccessLevel.USER_MODE
            )
        ) {
            byAccount.put(account.Id, (Id) account.get(PERSON_CONTACT_FIELD));
        }
        return byAccount;
    }

    /** The same, without the linked gifts changed since the last run. */
    public static String giftsToCopyQuery(Boolean inRange) {
        return giftsToCopyQuery(inRange, false);
    }

    /**
     * The gifts a Gifts to Opportunities run copies (R-OM8, R-OM11). Without a range: those in the
     * totals with no Opportunity, and, when `sinceLastRun`, every linked gift changed since the
     * last completed run started (bind `since`), which puts right a change whose copy was skipped.
     * Given a range (binds `fromDate`, `toDate`): every gift dated in it that is in the totals or
     * linked, so a Cancelled gift's Opportunity is moved to the lost stage too.
     */
    public static String giftsToCopyQuery(Boolean inRange, Boolean sinceLastRun) {
        String query = 'SELECT ' + GIFT_FIELDS + ' FROM Gift__c WHERE ';
        if (inRange == true) {
            query +=
                'Gift_Date__c >= :fromDate AND Gift_Date__c <= :toDate' +
                ' AND (Status__c IN :statuses OR Opportunity_Id__c != NULL)';
        } else {
            query += '(Opportunity_Id__c = NULL AND Status__c IN :statuses)';
            if (sinceLastRun == true) {
                query += ' OR (Opportunity_Id__c != NULL AND LastModifiedDate >= :since)';
            }
        }
        return query + ' ORDER BY Gift_Date__c, Id';
    }

    /**
     * The won Opportunities an Opportunities to Gifts run turns into gifts: closed on or after the
     * start date, oldest first (R-OM7), and when `byRecordType` of the record types bound as
     * `recordTypeIds`. Those already named by a gift are left out per chunk.
     */
    public static String wonOpportunitiesQuery(
        String opportunityObject,
        List<String> fields,
        Boolean byRecordType
    ) {
        return 'SELECT ' +
            String.escapeSingleQuotes(String.join(fields, ', ')) +
            ' FROM ' +
            String.escapeSingleQuotes(opportunityObject) +
            ' WHERE IsWon = TRUE AND CloseDate >= :startDate' +
            (byRecordType == true ? ' AND RecordTypeId IN :recordTypeIds' : '') +
            ' ORDER BY CloseDate, Id';
    }

    /** The Opportunity ID of every gift that names one of these, the running user can see. */
    public static Set<String> linkedOpportunityIds(Set<String> opportunityIds) {
        Set<String> linked = new Set<String>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return linked;
        }
        for (Gift__c gift : [
            SELECT Opportunity_Id__c
            FROM Gift__c
            WHERE Opportunity_Id__c IN :opportunityIds
            WITH USER_MODE
        ]) {
            linked.add(gift.Opportunity_Id__c);
        }
        return linked;
    }

    /** The appeal whose Campaign ID is each of these Campaigns, keyed by Campaign ID. */
    public static Map<String, Id> appealIdsByCampaignId(Set<String> campaignIds) {
        Map<String, Id> byCampaign = new Map<String, Id>();
        if (campaignIds == null || campaignIds.isEmpty()) {
            return byCampaign;
        }
        for (Appeal__c appeal : [
            SELECT Id, Campaign_Id__c
            FROM Appeal__c
            WHERE Campaign_Id__c IN :campaignIds
            WITH USER_MODE
        ]) {
            byCampaign.put(appeal.Campaign_Id__c, appeal.Id);
        }
        return byCampaign;
    }

    /**
     * The account of each of these contacts that is the contact half of a person account, by
     * contact. Empty in an org that does not store people as accounts.
     */
    public static Map<Id, Id> personAccountByContact(Set<Id> contactIds) {
        Map<Id, Id> byContact = new Map<Id, Id>();
        if (
            contactIds == null ||
            contactIds.isEmpty() ||
            !Schema.SObjectType.Contact.fields.getMap().containsKey(IS_PERSON_ACCOUNT_FIELD)
        ) {
            return byContact;
        }
        for (
            SObject person : Database.queryWithBinds(
                'SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds AND ' +
                    IS_PERSON_ACCOUNT_FIELD +
                    ' = TRUE',
                new Map<String, Object>{ 'contactIds' => contactIds },
                AccessLevel.USER_MODE
            )
        ) {
            byContact.put(person.Id, (Id) person.get('AccountId'));
        }
        return byContact;
    }

    /**
     * The gifts in the totals dated in the range that the running user can see, oldest first, for
     * a SOQL for loop through `Database.query`, which reads them 200 at a time, no more than
     * `cap` (R-OM11). Binds `statuses`, `fromDate`, `toDate` and `cap` from the caller's scope.
     */
    public static final String GIFTS_IN_RANGE_QUERY =
        'SELECT Id, Name, Amount__c, Gift_Date__c, Opportunity_Id__c FROM Gift__c' +
        ' WHERE Status__c IN :statuses AND Gift_Date__c >= :fromDate AND Gift_Date__c <= :toDate' +
        ' WITH USER_MODE ORDER BY Gift_Date__c, Id LIMIT :cap';

    /**
     * The won Opportunities closed in the range the running user can see, oldest first, no more
     * than `cap`.
     */
    public static List<SObject> wonInRange(
        String opportunityObject,
        Date fromDate,
        Date toDate,
        Integer cap
    ) {
        return Database.queryWithBinds(
            'SELECT Id, Name, Amount, CloseDate, IsWon FROM ' +
                String.escapeSingleQuotes(opportunityObject) +
                ' WHERE IsWon = TRUE AND CloseDate >= :fromDate AND CloseDate <= :toDate' +
                ' ORDER BY CloseDate, Id LIMIT :cap',
            new Map<String, Object>{ 'fromDate' => fromDate, 'toDate' => toDate, 'cap' => cap },
            AccessLevel.USER_MODE
        );
    }
}
