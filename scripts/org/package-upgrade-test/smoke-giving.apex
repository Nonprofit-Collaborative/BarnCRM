// Template for scripts/org/package-upgrade-test.sh: %%NS%% becomes the namespace. Not deployed.
// Giving smoke assertion, run as the installing admin and rolled back: one gift saved for a new
// person moves their Total Giving in the same save (GiftRealTimeRollupTest, the instant path).
Savepoint before = Database.setSavepoint();
try {
	Contact donor = new Contact(FirstName = 'Ana', LastName = 'Upgradecheck');
	insert donor;
	insert new %%NS%%__Gift__c(
		%%NS%%__Donor_Contact__c = donor.Id,
		%%NS%%__Amount__c = 250,
		%%NS%%__Type__c = 'Check',
		%%NS%%__Status__c = 'Received',
		%%NS%%__Gift_Date__c = Date.today(),
		%%NS%%__Acknowledgment_Status__c = 'To acknowledge'
	);
	Contact saved = [SELECT %%NS%%__Total_Giving__c, %%NS%%__Gift_Count__c FROM Contact WHERE Id = :donor.Id];
	Assert.areEqual(250, saved.%%NS%%__Total_Giving__c, 'The gift rolls up to the donor\'s Total Giving.');
	Assert.areEqual(1, saved.%%NS%%__Gift_Count__c, 'The gift is counted.');
} finally {
	Database.rollback(before);
}
