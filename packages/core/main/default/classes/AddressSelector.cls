/**
 * All SOQL against Address__c. Feature code never queries the object directly
 * (plan Section 7.2: every query lives in a Selector).
 */
public with sharing class AddressSelector {
    /**
     * Every address belonging to any of the given owners, whether the owner is a
     * household or organization account, a contact, or a person account. Ordered so the
     * address in use comes first and the newest address comes next, which is the order
     * the address panel shows and the order the delete promotion relies on.
     */
    public static List<Address__c> selectByOwnerIds(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Address__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Seasonal_Start_Month__c,
                Seasonal_Start_Day__c,
                Seasonal_End_Month__c,
                Seasonal_End_Day__c,
                Is_Default__c,
                Verification_Status__c,
                Latest_Verified_Date__c,
                Status__c,
                CreatedDate
            FROM Address__c
            WHERE
                Account__c IN :ownerIds
                OR Contact__c IN :ownerIds
                OR Person_Account__c IN :ownerIds
            WITH USER_MODE
            ORDER BY Is_Default__c DESC, CreatedDate DESC
            LIMIT 10000
        ];
    }

    /**
     * The addresses currently marked default for the given owners, leaving out any
     * address in excludeAddressIds. Used to keep one default per owner.
     */
    public static List<Address__c> selectDefaultsByOwnerIds(
        Set<Id> ownerIds,
        Set<Id> excludeAddressIds
    ) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Address__c>();
        }
        Set<Id> skip = excludeAddressIds == null ? new Set<Id>() : excludeAddressIds;
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Seasonal_Start_Month__c,
                Seasonal_Start_Day__c,
                Seasonal_End_Month__c,
                Seasonal_End_Day__c,
                Is_Default__c,
                Status__c,
                End_Date__c,
                CreatedDate
            FROM Address__c
            WHERE
                Is_Default__c = TRUE
                AND Id NOT IN :skip
                AND (Account__c IN :ownerIds
                OR Contact__c IN :ownerIds
                OR Person_Account__c IN :ownerIds)
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 10000
        ];
    }

    /**
     * The ordinary addresses waiting for these owners' seasons to end (marked Replaced By
     * Seasonal): the homes a move made while a seasonal address was primary leaves (R-AD10).
     */
    public static List<Address__c> selectWaitingForSeason(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Address__c>();
        }
        String seasonal = AddressService.TYPE_SEASONAL;
        return [
            SELECT
                Id,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Status__c,
                End_Date__c
            FROM Address__c
            WHERE
                Replaced_By_Seasonal__c = TRUE
                AND Type__c != :seasonal
                AND (Account__c IN :ownerIds
                OR Contact__c IN :ownerIds
                OR Person_Account__c IN :ownerIds)
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 10000
        ];
    }

    /** The billing address in the standard fields of these accounts. */
    public static List<Account> selectAccountBillingAddresses(Set<Id> accountIds) {
        return selectAccountBillingAddresses(accountIds, null);
    }

    /**
     * The billing address in the standard fields of these accounts, and the named extra fields.
     * The extra fields are a person account's mailing fields, named as strings by the caller and
     * read with get, so this class compiles and runs in an org without person accounts; the
     * caller names them only where the org has them.
     *
     * @param accountIds the accounts
     * @param extraFields further Account fields to read; null or empty for none
     */
    public static List<Account> selectAccountBillingAddresses(
        Set<Id> accountIds,
        List<String> extraFields
    ) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        List<String> fields = new List<String>{
            'Id',
            'BillingStreet',
            'BillingCity',
            'BillingPostalCode'
        };
        if (extraFields != null) {
            fields.addAll(extraFields);
        }
        return Database.queryWithBinds(
            'SELECT ' +
                String.join(fields, ', ') +
                ' FROM Account WHERE Id IN :accountIds LIMIT 10000',
            new Map<String, Object>{ 'accountIds' => accountIds },
            AccessLevel.USER_MODE
        );
    }

    /** The mailing address in the standard fields of these contacts. */
    public static List<Contact> selectContactMailingAddresses(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, MailingStreet, MailingCity, MailingPostalCode
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /** These addresses, as the user may read them; one they cannot read is left out. */
    public static List<Address__c> selectByIds(Set<Id> addressIds) {
        if (addressIds == null || addressIds.isEmpty()) {
            return new List<Address__c>();
        }
        return [
            SELECT
                Id,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Seasonal_Start_Month__c,
                Seasonal_Start_Day__c,
                Seasonal_End_Month__c,
                Seasonal_End_Day__c,
                Is_Default__c
            FROM Address__c
            WHERE Id IN :addressIds
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /**
     * The name of each of these people and households, as the user may read them, for a
     * screen that lists them (R-AD9). A record the user cannot read is left out.
     */
    public static Map<Id, String> selectNames(Set<Id> contactIds, Set<Id> accountIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (contactIds != null && !contactIds.isEmpty()) {
            for (Contact person : [
                SELECT Id, Name
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
                ORDER BY Name
                LIMIT 10000
            ]) {
                names.put(person.Id, person.Name);
            }
        }
        if (accountIds != null && !accountIds.isEmpty()) {
            for (Account record : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
                ORDER BY Name
                LIMIT 10000
            ]) {
                names.put(record.Id, record.Name);
            }
        }
        return names;
    }
}
