/**
 * The queries behind the inbound gift API (feature X-03). Every one runs in user mode: the API
 * sees exactly what its integration user may see, like any other person using the product, so a
 * record it cannot see is a record it cannot name.
 */
public with sharing class InboundGiftSelector {
    // detection-only: the person account marker, read by name so Mirror compiles without it
    private static final String PERSON_ACCOUNT_FIELD = 'IsPersonAccount';

    /** Gifts carrying these external ids, keyed by the lower cased external id. */
    public static Map<String, Gift__c> giftsByExternalId(Set<String> externalIds) {
        Map<String, Gift__c> byKey = new Map<String, Gift__c>();
        if (externalIds == null || externalIds.isEmpty()) {
            return byKey;
        }
        for (Gift__c gift : [
            SELECT Id, External_Id__c, Amount__c
            FROM Gift__c
            WHERE External_Id__c IN :externalIds
            WITH USER_MODE
        ]) {
            byKey.put(gift.External_Id__c.toLowerCase(), gift);
        }
        return byKey;
    }

    /** Active funds with these accounting codes, keyed by the lower cased code. */
    public static Map<String, Id> activeFundsByCode(Set<String> codes) {
        Map<String, Id> byCode = new Map<String, Id>();
        if (codes == null || codes.isEmpty()) {
            return byCode;
        }
        for (Fund__c fund : [
            SELECT Id, Accounting_Code__c
            FROM Fund__c
            WHERE Accounting_Code__c IN :codes AND Active__c = TRUE
            WITH USER_MODE
        ]) {
            byCode.put(fund.Accounting_Code__c.toLowerCase(), fund.Id);
        }
        return byCode;
    }

    /** Which of these funds exist, are active, and can be seen. */
    public static Set<Id> activeFundIds(Set<Id> fundIds) {
        if (fundIds == null || fundIds.isEmpty()) {
            return new Set<Id>();
        }
        return new Map<Id, Fund__c>(
                [SELECT Id FROM Fund__c WHERE Id IN :fundIds AND Active__c = TRUE WITH USER_MODE]
            )
            .keySet();
    }

    /** Which of these appeals exist and can be seen. */
    public static Set<Id> appealIds(Set<Id> appealIds) {
        if (appealIds == null || appealIds.isEmpty()) {
            return new Set<Id>();
        }
        return new Map<Id, Appeal__c>(
                [SELECT Id FROM Appeal__c WHERE Id IN :appealIds WITH USER_MODE]
            )
            .keySet();
    }

    /** Which of these accounts exist and can be seen. */
    public static Set<Id> accountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Set<Id>();
        }
        return new Map<Id, Account>([SELECT Id FROM Account WHERE Id IN :accountIds WITH USER_MODE])
            .keySet();
    }

    /**
     * The donor reference a gift should carry for each of these contacts that can be seen: the
     * contact itself, or, for the contact behind a person account, that account, because a
     * person stored as an account is always referenced by the account (canonical model
     * Section 4). The marker field exists only where person accounts are enabled, so it is named
     * as text and only asked for when the org has it.
     */
    public static Map<Id, Id> donorForContacts(Set<Id> contactIds) {
        Map<Id, Id> donorByContact = new Map<Id, Id>();
        if (contactIds == null || contactIds.isEmpty()) {
            return donorByContact;
        }
        Boolean personAccounts = Schema.SObjectType.Account.fields.getMap()
            .containsKey(PERSON_ACCOUNT_FIELD.toLowerCase());
        String query =
            'SELECT Id, AccountId' +
            (personAccounts ? ', Account.' + PERSON_ACCOUNT_FIELD : '') +
            ' FROM Contact WHERE Id IN :contactIds';
        List<Contact> contacts = Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'contactIds' => contactIds },
            AccessLevel.USER_MODE
        );
        for (Contact person : contacts) {
            Boolean heldAsAccount =
                personAccounts &&
                person.Account != null &&
                person.Account.get(PERSON_ACCOUNT_FIELD) == true;
            donorByContact.put(person.Id, heldAsAccount ? person.AccountId : person.Id);
        }
        return donorByContact;
    }
}
