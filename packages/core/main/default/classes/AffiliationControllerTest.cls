/**
 * The affiliation card's one server call: which lookups a new affiliation fills in, decided
 * from the record itself.
 */
@IsTest(testFor='ApexClass:AffiliationController')
private class AffiliationControllerTest {
	// The lookups by the names the card's form needs, with the namespace once it is set.
	private static final String CONTACT = NamespaceUtil.qualify('Contact__c');
	private static final String ORGANIZATION = NamespaceUtil.qualify('Organization__c');
	private static final String PERSON_ACCOUNT = NamespaceUtil.qualify('Person_Account__c');
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** D-185: the card is hidden while Affiliations is off and shown while it is on. */
	@IsTest
	static void theCardIsHiddenWhileAffiliationsIsOff() {
		System.runAs(TestUsers.admin()) {
			SettingsService.saveSystemValue(
				'Features_Turned_On__c',
				FeatureSwitchService.RELATIONSHIPS
			);
			Boolean whileOff = AffiliationController.isFeatureOn();
			SettingsService.saveSystemValue(
				'Features_Turned_On__c',
				FeatureSwitchService.AFFILIATIONS
			);
			Boolean whileOn = AffiliationController.isFeatureOn();

			Assert.isFalse(whileOff, 'The card is hidden while the feature is off');
			Assert.isTrue(whileOn, 'The card shows once the feature is on');
		}
	}

	@IsTest
	static void aContactsCardAddsAnOrganization() {
		System.runAs(TestUsers.admin()) {
			RelationshipTestDataFactory.quietOtherAutomations();
			List<Contact> people = RelationshipTestDataFactory.contacts(1, 'Garcia');

			Test.startTest();
			AffiliationController.CardContext context = AffiliationController.getCardContext(
				people[0].Id
			);
			Test.stopTest();

			Assert.areEqual(CONTACT, context.ownerField, 'The contact is the person end');
			Assert.areEqual(ORGANIZATION, context.otherEndField, 'An organization is added');
		}
	}

	/**
	 * An organization with no affiliations on file is still read as an organization: the
	 * card used to guess from the affiliations already shown and saved it as a person.
	 */
	@IsTest
	static void anOrganizationWithNoAffiliationsYetIsStillTheOrganizationEnd() {
		System.runAs(TestUsers.admin()) {
			RelationshipTestDataFactory.quietOtherAutomations();
			List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');

			Test.startTest();
			AffiliationController.CardContext context = AffiliationController.getCardContext(
				orgs[0].Id
			);
			Test.stopTest();

			Assert.areEqual(ORGANIZATION, context.ownerField, 'The organization end');
			Assert.areEqual(
				HouseholdService.isPersonAccountOrg() ? PERSON_ACCOUNT : CONTACT,
				context.otherEndField,
				'The person end is the lookup this org stores people through'
			);
		}
	}

	/**
	 * The org shape is stubbed, so the person account branch runs whether or not the org has
	 * Person Accounts: an account whose record type the shape calls a person type is the
	 * person end.
	 */
	@IsTest
	static void anAccountOfAPersonRecordTypeIsThePersonEnd() {
		System.runAs(TestUsers.admin()) {
			RelationshipTestDataFactory.quietOtherAutomations();
			List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Garcia Household');
			Id recordTypeId = [SELECT RecordTypeId FROM Account WHERE Id = :orgs[0].Id]
			.RecordTypeId;
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
			shape.personAccountRecordTypeIds = new Set<Id>{ recordTypeId };
			OrgShapeDetector.overrideShape = shape;

			Test.startTest();
			AffiliationController.CardContext context = AffiliationController.getCardContext(
				orgs[0].Id
			);
			Test.stopTest();

			Assert.areEqual(PERSON_ACCOUNT, context.ownerField, 'The person account is owner');
			Assert.areEqual(ORGANIZATION, context.otherEndField, 'An organization is added');
		}
	}

	@IsTest
	static void anOrganizationAccountInAPersonAccountOrgPicksPeopleThroughPersonAccounts() {
		System.runAs(TestUsers.admin()) {
			RelationshipTestDataFactory.quietOtherAutomations();
			List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
			// A person type that is not this account's, so the account stays an organization.
			shape.personAccountRecordTypeIds = new Set<Id>{ FakeIds.of(Account.SObjectType, 1) };
			OrgShapeDetector.overrideShape = shape;
			HouseholdService.personAccountOverride = true;

			Test.startTest();
			AffiliationController.CardContext context = AffiliationController.getCardContext(
				orgs[0].Id
			);
			Test.stopTest();

			Assert.areEqual(ORGANIZATION, context.ownerField, 'The organization end');
			Assert.areEqual(PERSON_ACCOUNT, context.otherEndField, 'People are accounts here');
		}
	}

	@IsTest
	static void anOrganizationAccountInAContactOrgPicksPeopleThroughContacts() {
		System.runAs(TestUsers.admin()) {
			RelationshipTestDataFactory.quietOtherAutomations();
			List<Account> orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
			OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();
			HouseholdService.personAccountOverride = false;

			Test.startTest();
			AffiliationController.CardContext context = AffiliationController.getCardContext(
				orgs[0].Id
			);
			Test.stopTest();

			Assert.areEqual(ORGANIZATION, context.ownerField, 'The organization end');
			Assert.areEqual(CONTACT, context.otherEndField, 'People are contacts here');
		}
	}

	@IsTest
	static void noRecordIsTreatedAsAContact() {
		System.runAs(TestUsers.admin()) {
			AffiliationController.CardContext context = AffiliationController.getCardContext(null);

			Assert.areEqual(CONTACT, context.ownerField, 'The default is the person end');
			Assert.areEqual(ORGANIZATION, context.otherEndField, 'An organization is added');
		}
	}
}
