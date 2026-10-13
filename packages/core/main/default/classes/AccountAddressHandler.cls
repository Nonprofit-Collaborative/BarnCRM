/**
 * Account trigger handler, registered as "Keep the address an account started with" in
 * the automation registry and dispatched by TriggerDispatcher on the
 * one Account trigger.
 *
 * A household or organization created with its billing address already filled in, by
 * staff or by an import, gets that address kept as its first address record, marked
 * default, so the records are the truth from the first save (canonical model R-AD3). A person
 * held as an account is captured from their mailing address, on insert and when it changes,
 * because the contact triggers never fire for a person account save (R-AD5, PEOPLE-17).
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler.
 */
public with sharing class AccountAddressHandler extends TriggerHandler {
    public override void afterInsert() {
        List<Account> accounts = (List<Account>) newRecords();
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        try {
            AddressService.captureFromStandardFields(accounts, null);
        } catch (Exception thrown) {
            ErrorLogger.log(thrown, 'AccountAddressHandler.afterInsert');
            for (Account account : accounts) {
                account.addError(Label.Core_Address_PropagationFailed);
            }
        }
    }

    /**
     * A person account whose mailing address changed gets an address record of their own. The
     * household and organization billing address is captured on insert only, as before.
     */
    public override void afterUpdate() {
        List<Account> accounts = (List<Account>) newRecords();
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        try {
            AddressService.capturePersonMailingChanges(accounts, oldRecordsById());
        } catch (Exception thrown) {
            ErrorLogger.log(thrown, 'AccountAddressHandler.afterUpdate');
            for (Account account : accounts) {
                account.addError(Label.Core_Address_PropagationFailed);
            }
        }
    }
}
