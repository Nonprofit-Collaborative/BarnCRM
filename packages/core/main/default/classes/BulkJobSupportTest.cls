/**
 * The comparison and failure text the bulk jobs share.
 */
@IsTest(testFor='ApexClass:BulkJobSupport')
private class BulkJobSupportTest {
	@IsTest
	static void numbersCompareAsNumbersAndTextExactly() {
		// runs-as: deploying user (pure logic: compares two values, no DML or SOQL)
		Assert.isTrue(BulkJobSupport.same(5, 5.0), 'Five is five');
		Assert.isTrue(BulkJobSupport.same(null, null), 'Two blanks are the same');
		Assert.isFalse(BulkJobSupport.same(null, 'a'), 'A blank is not a value');
		Assert.isFalse(BulkJobSupport.same('Ana', 'ana'), 'A change in capitals is a change');
		Assert.isFalse(BulkJobSupport.same(5, 'five'), 'A number is not text');
	}

	@IsTest
	static void aRefusalIsJournaledWithItsReasons() {
		System.runAs(TestUsers.admin()) {
			// No last name: the platform refuses, and nothing is saved.
			Database.SaveResult refused = Database.insert(
				TestDataFactory.person(new Contact()),
				false,
				AccessLevel.USER_MODE
			);
			List<Map<String, Object>> journal = new List<Map<String, Object>>();

			BulkJobSupport.journalFailure(journal, 'Contact', null, refused.getErrors());

			Assert.areEqual(1, journal.size(), 'One entry');
			Assert.areEqual(
				ImportJournalService.ACTION_FAILED,
				journal[0].get('action'),
				'A failure'
			);
			Assert.isFalse(
				String.isBlank((String) journal[0].get('reason')),
				'With the reason given'
			);
		}
	}
}
