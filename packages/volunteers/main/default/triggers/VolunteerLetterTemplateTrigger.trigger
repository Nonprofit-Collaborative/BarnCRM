/**
 * One trigger for Volunteer_Letter_Template__c. It does nothing itself: the Core dispatcher reads
 * the automation registry and runs the handlers registered for this object (ADR-0017, ADR-0024).
 */
trigger VolunteerLetterTemplateTrigger on Volunteer_Letter_Template__c(
    before insert,
    before update,
    after insert,
    after update
) {
    TriggerDispatcher.run('Volunteer_Letter_Template__c');
}
