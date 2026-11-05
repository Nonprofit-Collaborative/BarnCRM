trigger HouseholdMemberTrigger on Household_Member__c(
	before insert,
	before update,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Household_Member__c');
}
