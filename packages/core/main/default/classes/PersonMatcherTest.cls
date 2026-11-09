/**
 * The shared person matcher Forms and Events call: email first, then last name and postal code,
 * each narrowed by first name (R-IB12), a key several people hold never guessed (R-FS2).
 */
@IsTest(testFor='ApexClass:PersonMatcher')
private class PersonMatcherTest {
	@TestSetup
	static void setUp() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.defaultSettings();
			insert new List<Contact>{
				new Contact(
					FirstName = 'Ana',
					LastName = 'Ramirez',
					Email = 'family@example.org',
					MailingPostalCode = '97201'
				),
				new Contact(
					FirstName = 'Luis',
					LastName = 'Ramirez',
					Email = 'family@example.org',
					MailingPostalCode = '97201'
				),
				new Contact(
					FirstName = 'Ben',
					LastName = 'Okafor',
					Email = 'ben@example.org',
					MailingPostalCode = '97202'
				)
			};
		}
	}

	private static PersonMatcher.Person person(String first, String last, String email) {
		PersonMatcher.Person result = new PersonMatcher.Person();
		result.firstName = first;
		result.lastName = last;
		result.email = email;
		return result;
	}

	private static Id contactId(String first) {
		return [SELECT Id FROM Contact WHERE FirstName = :first LIMIT 1].Id;
	}

	@IsTest
	static void findsByEmailNarrowedByFirstName() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Id found = PersonMatcher.find(person('Luis', 'Ramirez', 'FAMILY@example.org'));
			Test.stopTest();
			Assert.areEqual(
				contactId('Luis'),
				found,
				'A shared email is narrowed to the person of that first name.'
			);
		}
	}

	@IsTest
	static void sharedEmailWithoutFirstNameIsNeverGuessed() {
		System.runAs(TestUsers.admin()) {
			Boolean held = false;
			Test.startTest();
			try {
				PersonMatcher.find(person(null, 'Ramirez', 'family@example.org'));
			} catch (PersonMatcher.AmbiguousException several) {
				held = true;
			}
			Test.stopTest();
			Assert.isTrue(held, 'Two people hold the email and no first name narrows it.');
		}
	}

	@IsTest
	static void findsByLastNameAndPostalCodeWhenTheEmailIsNew() {
		System.runAs(TestUsers.admin()) {
			PersonMatcher.Person ben = person('Ben', 'Okafor', 'new@example.org');
			ben.postalCode = '97202';
			Test.startTest();
			Id found = PersonMatcher.find(ben);
			Test.stopTest();
			Assert.areEqual(contactId('Ben'), found, 'Last name and postal code find him.');
		}
	}

	@IsTest
	static void skipsTheNameAndPostalCodeStepWhenTurnedOff() {
		System.runAs(TestUsers.admin()) {
			PersonMatcher.Person ben = person('Ben', 'Okafor', 'new@example.org');
			ben.postalCode = '97202';
			ben.byNameAndPostalCode = false;
			Test.startTest();
			Id found = PersonMatcher.find(ben);
			Test.stopTest();
			Assert.isNull(found, 'Email only: a new email matches nobody.');
		}
	}

	@IsTest
	static void nobodyMatchesAnUnknownPerson() {
		System.runAs(TestUsers.admin()) {
			PersonMatcher.Person stranger = person('Zed', 'Nobody', 'zed@example.org');
			stranger.postalCode = '00001';
			stranger.duplicateRuleValues = new Map<String, String>{
				'FirstName' => 'Zed',
				'LastName' => 'Nobody',
				'Email' => 'zed@example.org'
			};
			Test.startTest();
			Id found = PersonMatcher.find(stranger);
			Test.stopTest();
			Assert.isNull(found, 'Nobody is the unknown person.');
			Assert.isNull(PersonMatcher.find(null), 'No person, no match.');
		}
	}
}
