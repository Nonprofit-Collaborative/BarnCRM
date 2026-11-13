/**
 * Name search through the search index (D-200 P5): the text sent is escaped, each word is a
 * prefix, short input searches nothing, and the search runs as the user.
 */
@IsTest(testFor='ApexClass:NameSearch')
private class NameSearchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}
	@IsTest
	static void eachWordIsMatchedAsAPrefix() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual('garc*', NameSearch.prefixTerm(' garc '));
			Assert.areEqual('Wei* Lee*', NameSearch.prefixTerm('Wei  Lee'));
			Assert.areEqual(
				'J Smith*',
				NameSearch.prefixTerm('J Smith'),
				'One letter is kept whole'
			);
		}
	}

	@IsTest
	static void shortInputSearchesNothing() {
		System.runAs(TestUsers.admin()) {
			Assert.isNull(NameSearch.prefixTerm(null));
			Assert.isNull(NameSearch.prefixTerm(' W '));
		}
	}

	@IsTest
	static void reservedCharactersAreSearchedForNotParsed() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual('O\\\'Brien*', NameSearch.prefixTerm('O\'Brien'));
			Assert.areEqual(
				'a\\}b*',
				NameSearch.prefixTerm('a}b'),
				'A brace cannot end the search'
			);
			Assert.areEqual('Smith\\-Jones*', NameSearch.prefixTerm('Smith-Jones'));
		}
	}

	@IsTest
	static void theSearchReturnsWhatTheIndexHolds() {
		System.runAs(TestUsers.admin()) {
			Contact person = new Contact(FirstName = 'Indra', LastName = 'Searchwell');
			TestDataFactory.pastDuplicateRules(person);
			insert person;
			Test.setFixedSearchResults(new List<Id>{ person.Id });

			List<SObject> found = NameSearch.find(
				NameSearch.prefixTerm('Search'),
				'Contact(Id, Name LIMIT 10)'
			)[0];

			Assert.areEqual(1, found.size(), 'The indexed contact');
			Assert.areEqual(person.Id, found[0].Id);
		}
	}
}
