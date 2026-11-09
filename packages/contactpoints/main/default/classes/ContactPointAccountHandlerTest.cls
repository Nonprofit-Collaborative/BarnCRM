/**
 * Contact Point Sync on Account watches only the person fields this org's Account has, found
 * once a transaction (ADR-0176 decision 16): an org without person accounts or Individuals
 * skips the missing ones instead of failing to read them.
 */
@IsTest(testFor='ApexClass:ContactPointAccountHandler')
private class ContactPointAccountHandlerTest {
	// runs-as: deploying user (pure describe logic: no DML or SOQL)

	@IsTest
	static void watchesOnlyTheFieldsAccountHasAndDescribesOnce() {
		Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();

		List<String> watched = ContactPointAccountHandler.watchedFields();

		Assert.isFalse(
			ContactPointPlan.accountFields().isEmpty(),
			'The plan names fields to watch'
		);
		for (String field : ContactPointPlan.accountFields()) {
			Assert.areEqual(
				fields.containsKey(field.toLowerCase()),
				watched.contains(field),
				field + ' is watched exactly when Account has it'
			);
		}
		Assert.isTrue(
			ContactPointAccountHandler.watchedFields() === watched,
			'Found once a transaction, then reused'
		);
	}
}
