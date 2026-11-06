/**
 * The Grants at a Glance card on Core's record pages (modules-21, ADR-0167): a funder
 * organization's grants and a funder contact's, counted, open ones and the amount awarded, with
 * the button to the grant list; no card without grants or for someone who cannot read them.
 */
@IsTest(testFor='ApexClass:FundersRecordGlanceExtension')
private class FundersRecordGlanceExtensionTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.standardUserWith('Nofunders', new List<String>{ 'BarnCRM_Read_Only' });
	}

	private static Contact contact(String lastName) {
		Contact person = (Contact) TestDataFactory.pastDuplicateRules(
			new Contact(FirstName = 'Glance', LastName = lastName)
		);
		insert person;
		return person;
	}

	/** Lakeside: one prospect, one applied, two awarded (10,000 and 2,500), one declined. */
	private static Account lakeside(Id contactId) {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		List<Grant__c> grants = new List<Grant__c>{
			GrantTestData.grant('Prospect', funder.Id, GrantService.STAGE_PROSPECT),
			GrantTestData.grant('Applied', funder.Id, GrantService.STAGE_APPLIED),
			GrantTestData.grant('Award One', funder.Id, GrantService.STAGE_AWARDED),
			GrantTestData.grant('Award Two', funder.Id, GrantService.STAGE_AWARDED),
			GrantTestData.grant('Declined', funder.Id, GrantService.STAGE_DECLINED)
		};
		grants[2].Amount_Awarded__c = 10000;
		grants[3].Amount_Awarded__c = 2500;
		grants[1].Funder_Contact__c = contactId;
		grants[2].Funder_Contact__c = contactId;
		insert grants;
		return funder;
	}

	/**
	 * The card as the page reads it (JSON): Core's card fields are Core's own, so a module test
	 * reads what the card says rather than its fields.
	 */
	private static Map<String, Object> drawn(RecordGlance.Card card) {
		return card == null
			? null
			: (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(card));
	}

	/** The card's figures by label, as whole numbers. */
	private static Map<String, Integer> figures(Map<String, Object> card) {
		Map<String, Integer> byLabel = new Map<String, Integer>();
		for (Object tile : (List<Object>) card.get('tiles')) {
			Map<String, Object> figure = (Map<String, Object>) tile;
			Object value = figure.get('numberValue');
			byLabel.put(
				(String) figure.get('label'),
				value == null ? null : Decimal.valueOf(String.valueOf(value)).intValue()
			);
		}
		return byLabel;
	}

	private static String grantsLabel() {
		return Schema.SObjectType.Grant__c.getLabelPlural();
	}

	@IsTest
	static void aFunderOrganizationShowsItsGrants() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = lakeside(contact('Officer').Id);

			Test.startTest();
			Map<String, Object> card = drawn(new FundersRecordGlanceExtension().glance(funder.Id));
			Test.stopTest();

			Assert.areEqual(FundersRecordGlanceExtension.KEY, card.get('key'), 'The Funders card');
			Assert.areEqual(Label.Funders_Glance_Title, card.get('title'), 'Grants at a Glance');
			Map<String, Integer> byLabel = figures(card);
			Assert.areEqual(5, byLabel.get(grantsLabel()), 'Every grant to the funder');
			Assert.areEqual(
				2,
				byLabel.get(Label.Funders_Glance_OpenGrants),
				'Prospect and applied are open; awarded and declined are not'
			);
			Assert.areEqual(
				12500,
				byLabel.get(Schema.SObjectType.Grant__c.fields.Amount_Awarded__c.getLabel()),
				'Awarded grants only'
			);
			List<Object> actions = (List<Object>) card.get('actions');
			Assert.areEqual(1, actions.size(), 'One button to the grant list');
			Map<String, Object> page = (Map<String, Object>) JSON.deserializeUntyped(
				(String) ((Map<String, Object>) actions[0]).get('pageReference')
			);
			Map<String, Object> attributes = (Map<String, Object>) page.get('attributes');
			Assert.areEqual('standard__recordRelationshipPage', page.get('type'), 'A related list');
			Assert.areEqual(funder.Id, attributes.get('recordId'), 'Of this funder');
			Assert.isNotNull(attributes.get('relationshipApiName'), 'Its grants');
		}
	}

	@IsTest
	static void aFunderContactShowsTheGrantsTheyAreContactOn() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Contact officer = contact('Officer');
			lakeside(officer.Id);
			Contact nobody = contact('Nobody');

			Test.startTest();
			Map<String, Object> card = drawn(new FundersRecordGlanceExtension().glance(officer.Id));
			RecordGlance.Card none = new FundersRecordGlanceExtension().glance(nobody.Id);
			Test.stopTest();

			Map<String, Integer> byLabel = figures(card);
			Assert.areEqual(2, byLabel.get(grantsLabel()), 'The two grants they are contact on');
			Assert.areEqual(1, byLabel.get(Label.Funders_Glance_OpenGrants), 'One of them open');
			Assert.isNull(none, 'No grants, no card');
			Assert.isNull(new FundersRecordGlanceExtension().glance(null), 'No record, no card');
		}
	}

	@IsTest
	static void someoneWhoCannotReadGrantsSeesNoCard() {
		Account funder;
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			funder = lakeside(contact('Officer').Id);
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Nofunders' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Assert.isNull(
				new FundersRecordGlanceExtension().glance(funder.Id),
				'No Funders access, no card'
			);
		}
	}

	@IsTest
	static void coreFindsTheCard() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = lakeside(contact('Officer').Id);
			Boolean found = false;
			for (RecordGlance.Card card : RecordGlanceExtensions.cardsFor(funder.Id)) {
				found = found || drawn(card).get('key') == FundersRecordGlanceExtension.KEY;
			}
			Assert.isTrue(found, 'Registered in RecordGlanceExtensions');
		}
	}
}
