/**
 * Every query the nightly seasonal address swap makes (C-18).
 *
 * ADR-0021 (system mode writes for package owned data) extends to scheduled reconciliation of
 * package owned data, recorded in ADR-0027. The swap is a scheduled reconciliation: it runs as
 * whoever pressed the button that scheduled it, in a transaction no user is in. A `WITH USER_MODE`
 * query returns fewer rows rather than failing, so a household whose records that user cannot see
 * would not be reported as skipped, it would simply not be there, and their winter mail would keep
 * going to the wrong state with nothing to look at afterwards. Reading in system mode is what makes
 * "nothing to do" mean nothing to do.
 *
 * Nothing here is reachable from an LWC, and nothing here takes user-supplied input: the batch
 * hands it identifiers that came from its own query locator.
 */
public without sharing class SeasonalAddressSelector {
    /**
     * Every seasonal address in the org, grouped by owner.
     *
     * Seasonal addresses are the whole working set. An owner whose season is starting has one,
     * and so does an owner whose season has just ended and whose ordinary address has to be put
     * back, because the address the default flag is being moved away from is the seasonal one.
     *
     * The order keeps an owner's seasonal addresses together, so an owner with two of them is
     * usually handled in one chunk rather than two. Handling them in two would be correct
     * anyway: the swap is idempotent and the second pass finds nothing to do.
     */
    public Database.QueryLocator seasonalLocator() {
        String seasonal = AddressService.TYPE_SEASONAL;
        return Database.getQueryLocator(
            [
                SELECT Id, Account__c, Contact__c, Person_Account__c
                FROM Address__c
                WHERE Type__c = :seasonal
                WITH SYSTEM_MODE
                ORDER BY
                    Account__c NULLS LAST,
                    Contact__c NULLS LAST,
                    Person_Account__c NULLS LAST,
                    CreatedDate
            ]
        );
    }

    /**
     * Every address belonging to the given owners, not only the seasonal ones: the swap has to
     * see the address it is moving the default away from and the address it is putting back.
     */
    public static List<Address__c> selectAllForOwners(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Address__c>();
        }
        return (List<Address__c>) Database.queryWithBinds(
            'SELECT ' +
                AddressSelector.FIELDS +
                ', Replaced_By_Seasonal__c FROM Address__c WHERE Account__c IN :ownerIds' +
                ' OR Contact__c IN :ownerIds OR Person_Account__c IN :ownerIds' +
                ' ORDER BY CreatedDate LIMIT 10000',
            new Map<String, Object>{ 'ownerIds' => ownerIds },
            AccessLevel.SYSTEM_MODE
        );
    }
}
