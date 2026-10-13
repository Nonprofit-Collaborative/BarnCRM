/**
 * Copies the preferred email into the standard email for people held as contacts, registered as
 * "Copy preferred email on a person" in the automation registry (PEOPLE-28).
 *
 * It has its own registry row so that switching off household upkeep no longer stops the copy
 * as a side effect: the household handler used to call it, so the two shared one switch. The
 * work is in PreferredEmailService (R-C6). Context methods take no arguments and read the
 * trigger collections through the accessors on TriggerHandler.
 */
public with sharing class PreferredEmailContactHandler extends TriggerHandler {
    public override void beforeInsert() {
        PreferredEmailService.apply((List<Contact>) newRecords());
    }

    public override void beforeUpdate() {
        PreferredEmailService.apply((List<Contact>) newRecords());
    }
}
