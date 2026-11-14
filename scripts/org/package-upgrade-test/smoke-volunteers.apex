// Template for scripts/org/package-upgrade-test.sh: %%NS%% becomes the namespace. Not deployed.
// Volunteers smoke assertion, run as the installing admin and rolled back: approved hours for a
// new person post to their Volunteer Hours Total (VolunteerTotalsTest).
Savepoint before = Database.setSavepoint();
try {
	Contact volunteer = new Contact(FirstName = 'Ana', LastName = 'Upgradecheck');
	insert volunteer;
	insert new %%NS%%__Volunteer_Hours__c(
		%%NS%%__Contact__c = volunteer.Id,
		%%NS%%__Hours__c = 3,
		%%NS%%__Date_Worked__c = Date.today(),
		%%NS%%__Status__c = 'Approved'
	);
	Contact saved = [SELECT %%NS%%__Volunteer_Hours_Total__c FROM Contact WHERE Id = :volunteer.Id];
	Assert.areEqual(3, saved.%%NS%%__Volunteer_Hours_Total__c, 'Approved hours post to the total.');
} finally {
	Database.rollback(before);
}
