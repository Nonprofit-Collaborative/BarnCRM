/**
 * One trigger for Shift_Schedule__c. It does nothing itself: the Core dispatcher reads the
 * automation registry and runs the handlers registered for this object, in order, each of them
 * bypassable from the settings console unless its row always runs (ADR-0017, ADR-0024).
 */
trigger ShiftScheduleTrigger on Shift_Schedule__c(
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    TriggerDispatcher.run('Shift_Schedule__c');
}
