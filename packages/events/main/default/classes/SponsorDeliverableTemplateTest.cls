/**
 * A sponsorship level's deliverables text, one per line, becomes a new sponsor's checklist
 * (EV-09, R-SP3): types guessed from the first word, blanks and repeats dropped, the list capped.
 */
@IsTest(testFor='ApexClass:SponsorDeliverableTemplate')
private class SponsorDeliverableTemplateTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	@IsTest
	static void turnsEachLineIntoAnItemWithAType() {
		System.runAs(TestUsers.adminWith(EventsAccessSync.ADMIN_SET)) {
			Test.startTest();
			List<SponsorDeliverableTemplate.Item> items = SponsorDeliverableTemplate.parse(
				'Logo on the program\r\n\r\n  booth, 10 by 10  \nPasses (4)\nLogo on the program\nThank you post'
			);
			Test.stopTest();

			Assert.areEqual(4, items.size(), 'Blank and repeated lines are dropped');
			Assert.areEqual('Logo', items[0].type, 'Logo');
			Assert.areEqual('booth, 10 by 10', items[1].name, 'Trimmed');
			Assert.areEqual('Booth', items[1].type, 'Booth, even with punctuation');
			Assert.areEqual('Passes', items[2].type, 'Passes');
			Assert.areEqual('Other', items[3].type, 'Anything else is Other');
		}
	}

	@IsTest
	static void handlesEmptyTextAndCapsTheList() {
		System.runAs(TestUsers.adminWith(EventsAccessSync.ADMIN_SET)) {
			List<String> lines = new List<String>();
			for (Integer i = 0; i < 80; i++) {
				lines.add('Item ' + i + ' ' + 'x'.repeat(100));
			}

			Test.startTest();
			Integer none = SponsorDeliverableTemplate.parse(null).size();
			Integer blank = SponsorDeliverableTemplate.parse('  \n ').size();
			List<SponsorDeliverableTemplate.Item> capped = SponsorDeliverableTemplate.parse(
				String.join(lines, '\n')
			);
			Test.stopTest();

			Assert.areEqual(0, none, 'No text, no items');
			Assert.areEqual(0, blank, 'Blank text, no items');
			Assert.areEqual(SponsorDeliverableTemplate.MAX_ITEMS, capped.size(), 'Capped');
			Assert.areEqual(80, capped[0].name.length(), 'A name is cut to what a name holds');
		}
	}
}
