// Template for scripts/org/package-upgrade-test.sh: %%NS%% becomes the namespace. Not deployed.
// Core smoke assertion, run as the installing admin and rolled back: a person saved without a
// household gets one named for them (ContactInsertHouseholdSaveTest). In contact mode the
// household is the person's account; in junction mode (person accounts) it is reached through
// Household Member.
Savepoint before = Database.setSavepoint();
try {
	String lastName = 'Upgradecheck' + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
	Contact person = new Contact(FirstName = 'Ana', LastName = lastName);
	insert person;
	Contact saved = [SELECT Id, AccountId, Account.Name FROM Contact WHERE Id = :person.Id];
	String household = saved.AccountId == null ? null : saved.Account.Name;
	if (household == null || !household.contains(lastName)) {
		for (%%NS%%__Household_Member__c member : [
			SELECT %%NS%%__Household__r.Name
			FROM %%NS%%__Household_Member__c
			WHERE %%NS%%__Contact__c = :person.Id
		]) {
			household = member.%%NS%%__Household__r.Name;
		}
	}
	Assert.isNotNull(household, 'A person saved without a household gets one.');
	Assert.isTrue(household.contains(lastName), 'The household is named for them: ' + household);
} finally {
	Database.rollback(before);
}
