/**
 * Copies the preferred phone into the standard phone, registered as "Copy preferred phone on a
 * person" in the automation registry (R-C6a). The work is in PreferredPhoneService. Context
 * methods take no arguments and read the trigger collections through the accessors on
 * TriggerHandler.
 */
public with sharing class PreferredPhoneContactHandler extends TriggerHandler {
    public override void beforeInsert() {
        PreferredPhoneService.apply((List<Contact>) newRecords());
    }

    public override void beforeUpdate() {
        PreferredPhoneService.apply((List<Contact>) newRecords());
    }
}
