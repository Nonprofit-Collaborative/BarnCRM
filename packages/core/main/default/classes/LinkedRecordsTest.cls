/**
 * A module holds the record of an optional module (a Giving gift, a Funders award) by identifier
 * as text, and Core labels it when it can: only for the supported objects, only when they are in
 * the org and readable, and never with an error for anything else (EV-09).
 */
@IsTest(testFor='ApexClass:LinkedRecords')
private class LinkedRecordsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void labelsARecordOfASupportedObject() {
		System.runAs(TestUsers.admin()) {
			Contact person = new Contact(FirstName = 'Ana', LastName = 'Garcia');
			insert as user person;
			// Contact stands in for a supported module object: the seam is the same.
			LinkedRecords.supported = new List<String>{ 'Contact' };

			Test.startTest();
			Map<String, LinkedRecords.Link> links = LinkedRecords.resolve(
				new List<String>{ person.Id, ' ' + person.Id + ' ' }
			);
			Test.stopTest();

			Assert.areEqual('Ana Garcia', links.get(person.Id).label, 'Labelled by its name');
			Assert.areEqual('Contact', links.get(person.Id).objectLabel, 'With its object label');
			Assert.isTrue(links.containsKey(' ' + person.Id + ' '), 'Keyed as given');
		}
	}

	@IsTest
	static void leavesOutWhateverItCannotLabel() {
		System.runAs(TestUsers.admin()) {
			Account other = new Account(Name = 'Not Supported');
			insert as user other;
			Contact person = new Contact(LastName = 'Gone');
			insert as user person;
			Id deleted = person.Id;
			delete as user person;
			LinkedRecords.supported = new List<String>{ 'Contact', 'No_Such_Module_Object__c' };

			Test.startTest();
			Map<String, LinkedRecords.Link> links = LinkedRecords.resolve(
				new List<String>{ null, '', 'not an id', other.Id, deleted }
			);
			Map<String, LinkedRecords.Link> none = LinkedRecords.resolve(null);
			Test.stopTest();

			Assert.isTrue(links.isEmpty(), 'Blank, malformed, unsupported and deleted: no label');
			Assert.isTrue(none.isEmpty(), 'No list: no labels');
		}
	}

	@IsTest
	static void labelsNothingWhenTheModuleIsAbsent() {
		System.runAs(TestUsers.admin()) {
			Contact person = new Contact(LastName = 'Present');
			insert as user person;
			LinkedRecords.supported = new List<String>{ 'Gift_Not_In_This_Org__c' };

			Test.startTest();
			Map<String, LinkedRecords.Link> links = LinkedRecords.resolve(
				new List<String>{ person.Id }
			);
			Test.stopTest();

			Assert.isTrue(links.isEmpty(), 'An object that is not in the org resolves nothing');
		}
	}
}
