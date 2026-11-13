/**
 * The shared test data's own behavior: records saved past duplicate rules with the org's
 * required custom fields filled (architect review RT-02).
 */
// runs-as: deploying user (pure logic: builds records in memory and reads field describes; no DML or SOQL)
@IsTest(testFor='ApexClass:TestDataFactory')
private class TestDataFactoryTest {
	@IsTest
	static void sampleValuesFitEachFieldType() {
		Assert.areEqual('Test', TestDataFactory.sampleValue(Schema.DisplayType.STRING, 80, null));
		Assert.areEqual('Te', TestDataFactory.sampleValue(Schema.DisplayType.STRING, 2, null));
		Assert.areEqual(
			'barncrm.test@example.com',
			TestDataFactory.sampleValue(Schema.DisplayType.EMAIL, 80, null)
		);
		Assert.areEqual(0, TestDataFactory.sampleValue(Schema.DisplayType.INTEGER, 0, null));
		Assert.areEqual(0.0, TestDataFactory.sampleValue(Schema.DisplayType.CURRENCY, 0, null));
		Assert.areEqual(
			Date.today(),
			TestDataFactory.sampleValue(Schema.DisplayType.DATE, 0, null)
		);
		Assert.areEqual(
			'East',
			TestDataFactory.sampleValue(Schema.DisplayType.PICKLIST, 0, 'East')
		);
		Assert.isNull(
			TestDataFactory.sampleValue(Schema.DisplayType.REFERENCE, 18, null),
			'A required lookup cannot be given a sample value.'
		);
	}

	@IsTest
	static void firstActiveValueIsAPicklistValue() {
		List<Schema.PicklistEntry> entries = Contact.Salutation.getDescribe().getPicklistValues();
		String value = TestDataFactory.firstActiveValue(entries);
		Set<String> active = new Set<String>();
		for (Schema.PicklistEntry entry : entries) {
			if (entry.isActive()) {
				active.add(entry.getValue());
			}
		}
		Assert.isTrue(
			active.isEmpty() ? value == null : active.contains(value),
			'The value chosen is one of the active values, or none when there are none.'
		);
	}

	@IsTest
	static void aValueTheTestSetIsKept() {
		Contact person = TestDataFactory.person(
			new Contact(LastName = 'Keepme', FirstName = 'Ann')
		);
		Contact same = (Contact) TestDataFactory.pastDuplicateRules(person);
		Assert.areEqual(person, same, 'The same record comes back.');
		Assert.areEqual('Keepme', same.LastName);
		Assert.areEqual('Ann', same.FirstName);
	}
}
