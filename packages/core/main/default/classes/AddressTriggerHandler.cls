/**
 * Address__c trigger handler, registered as "Copy default address to standard fields"
 * in the automation registry and dispatched by TriggerDispatcher, so an
 * administrator can switch it off from BarnCRM Settings without touching Setup.
 *
 * After insert and after update it copies the default address into the standard address
 * fields. After delete it promotes the most recently created remaining address for that
 * owner: deleting the default is allowed rather than blocked, because refusing the delete
 * would leave a household holding an address it does not use and no way out of the app.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class AddressTriggerHandler extends TriggerHandler {
    public override void afterInsert() {
        sync((List<Address__c>) newRecords());
    }

    public override void afterUpdate() {
        sync(changedAddresses((List<Address__c>) newRecords(), oldRecordsById()));
    }

    public override void afterDelete() {
        List<Address__c> deleted = (List<Address__c>) oldRecords();
        if (deleted == null || deleted.isEmpty()) {
            return;
        }
        try {
            AddressService.promoteDefaultAfterDelete(deleted);
        } catch (Exception thrown) {
            report(thrown, deleted, 'AddressTriggerHandler.afterDelete');
        }
    }

    public override void afterUndelete() {
        sync((List<Address__c>) newRecords());
    }

    private void sync(List<Address__c> addresses) {
        if (addresses == null || addresses.isEmpty()) {
            return;
        }
        try {
            AddressService.syncDefaultToStandardFields(addresses);
        } catch (Exception thrown) {
            report(thrown, addresses, 'AddressTriggerHandler.sync');
        }
    }

    /**
     * The address specific message, rather than the dispatcher's general one, so a person
     * reading the error knows which part of the save failed. The exception is recorded in
     * the Error Log first (R-E1).
     */
    private void report(Exception thrown, List<Address__c> records, String context) {
        ErrorLogger.log(thrown, context);
        for (Address__c address : records) {
            address.addError(Label.Core_Address_PropagationFailed);
        }
    }

    /**
     * Only the addresses whose default flag or address text actually moved. Saving an
     * address without changing where it points should not rewrite every household
     * member's mailing address.
     */
    private List<Address__c> changedAddresses(
        List<Address__c> records,
        Map<Id, SObject> previousById
    ) {
        List<Address__c> changed = new List<Address__c>();
        if (records == null) {
            return changed;
        }
        for (Address__c address : records) {
            Address__c old = previousById == null
                ? null
                : (Address__c) previousById.get(address.Id);
            if (old == null || moved(address, old)) {
                changed.add(address);
            }
        }
        return changed;
    }

    private Boolean moved(Address__c address, Address__c old) {
        return address.Is_Default__c != old.Is_Default__c ||
            address.Street__c != old.Street__c ||
            address.City__c != old.City__c ||
            address.State__c != old.State__c ||
            address.Postal_Code__c != old.Postal_Code__c ||
            address.Country__c != old.Country__c ||
            address.Account__c != old.Account__c ||
            address.Contact__c != old.Contact__c ||
            address.Person_Account__c != old.Person_Account__c;
    }
}
