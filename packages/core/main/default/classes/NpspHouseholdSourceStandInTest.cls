/**
 * NpspHouseholdSource's own reads and rules (X-05, RT-04, R-HA1, R-HA6), run on any org shape.
 *
 * No test org has NPSP, so the class's NPSP names (its household marker, record type, greeting
 * and primary contact fields, and the Account Model setting and field) are pointed at Core's
 * own: an Account text field stands for NPSP's account type, Core's Organization record type for
 * NPSP's household record type, and a text field of BarnCRM Settings for the Account Model.
 * That makes the selection, the reads and the Account Model rule run for real. The use rule
 * built on top of it (Household Upkeep waits) is in NpspHouseholdUseTest.
 */
@IsTest(testFor='ApexClass:NpspHouseholdSource')
private class NpspHouseholdSourceStandInTest {
	private static final String ORGANIZATION_TYPE = 'BarnCRM_Organization';
	private static final String ABSENT_FIELD = 'No_Such_Field__c';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** A source that says which source it is, to tell it from the default. */
	private class NamedSource extends NpspHouseholdSource {
		private final String name;

		NamedSource(String name) {
			this.name = name;
		}

		public override String key() {
			return name;
		}
	}

	private static void useCoreStandIns() {
		NpspHouseholdSource.ACCOUNT_TYPE_FIELD = 'Sample_Data_Key__c';
		NpspHouseholdSource.HOUSEHOLD_RECORD_TYPE = ORGANIZATION_TYPE;
		NpspHouseholdSource.FORMAL_GREETING_FIELD = 'Household_Formal_Greeting__c';
		NpspHouseholdSource.INFORMAL_GREETING_FIELD = 'Household_Informal_Greeting__c';
		NpspHouseholdSource.PRIMARY_CONTACT_FIELD = 'Primary_Contact__c';
		NpspHouseholdSource.CUSTOM_NAMING_FIELD = 'Preferred_Name__c';
		NpspHouseholdSource.ACCOUNT_MODEL_SETTING = 'BarnCRM_Settings__c';
		NpspHouseholdSource.ACCOUNT_MODEL_FIELD = 'Account_Tabs__c';
		NpspHouseholdSource.clearCache();
	}

	private static Id organizationType() {
		return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(ORGANIZATION_TYPE).getRecordTypeId();
	}

	/** An account the stand-ins select, with the values the reads hand back. */
	private static Account standInHousehold(String name, Id primaryContactId) {
		Account account = TestDataFactory.organization(
			new Account(
				Name = name,
				RecordTypeId = organizationType(),
				Sample_Data_Key__c = NpspHouseholdSource.HOUSEHOLD_ACCOUNT_TYPE,
				Household_Formal_Greeting__c = 'Dear Garcias',
				Household_Informal_Greeting__c = 'Hi Garcias',
				Preferred_Name__c = 'Typed by hand',
				Primary_Contact__c = primaryContactId
			)
		);
		Database.insert(account, AccessLevel.SYSTEM_MODE);
		return account;
	}

	private static void accountModel(String value) {
		BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
		settings.Account_Tabs__c = value;
		HouseholdTestDataFactory.save(settings);
	}

	private static Set<Id> selected() {
		NpspHouseholdSource source = NpspHouseholdSource.get();
		Set<Id> ids = new Set<Id>();
		for (
			SObject found : Database.queryWithBinds(
				'SELECT Id FROM Account WHERE ' + source.condition(),
				source.binds(),
				AccessLevel.SYSTEM_MODE
			)
		) {
			ids.add(found.Id);
		}
		return ids;
	}

	@IsTest
	static void selectsAccountsByEitherMarkerButNotBarnCRMHouseholds() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			Account npsp = standInHousehold('Garcia Household', null);
			Account barn = HouseholdTestDataFactory.newHousehold('The Lee Family');
			barn.Sample_Data_Key__c = NpspHouseholdSource.HOUSEHOLD_ACCOUNT_TYPE;
			Database.insert(barn, AccessLevel.SYSTEM_MODE);
			NpspHouseholdSource source = NpspHouseholdSource.get();

			Assert.isTrue(source.available(), 'Either marker makes adoption possible');
			Assert.isTrue(source.condition().contains('Sample_Data_Key__c = :npspAccountType'), source.condition());
			Assert.isTrue(source.condition().contains('RecordTypeId = :npspRecordType'), source.condition());
			Assert.isTrue(source.condition().endsWith('AND RecordTypeId != :barnHousehold'), source.condition());
			Map<String, Object> binds = source.binds();
			Assert.areEqual(3, binds.size(), 'Exactly the binds the condition names');
			Assert.areEqual(HouseholdService.householdRecordTypeId(), binds.get('barnHousehold'));
			Assert.areEqual(NpspHouseholdSource.HOUSEHOLD_ACCOUNT_TYPE, binds.get('npspAccountType'));
			Assert.areEqual(organizationType(), binds.get('npspRecordType'));
			Assert.areEqual(
				new Set<Id>{ npsp.Id },
				selected(),
				'The NPSP household is selected, the BarnCRM one is not'
			);
			Assert.isTrue(source.unadoptedHouseholdsExist(), 'An NPSP household not yet adopted exists');
		}
	}

	@IsTest
	static void eitherMarkerAloneStillSelects() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			Account npsp = standInHousehold('Garcia Household', null);
			NpspHouseholdSource source = NpspHouseholdSource.get();

			NpspHouseholdSource.HOUSEHOLD_RECORD_TYPE = 'No_Such_Type';
			Assert.isTrue(source.available(), 'The account type marker alone is enough');
			Assert.isFalse(source.condition().contains('npspRecordType'), source.condition());
			Assert.isFalse(source.binds().containsKey('npspRecordType'), 'No record type bind without the type');
			Assert.areEqual(new Set<Id>{ npsp.Id }, selected(), 'Selected by the account type');

			NpspHouseholdSource.HOUSEHOLD_RECORD_TYPE = ORGANIZATION_TYPE;
			NpspHouseholdSource.ACCOUNT_TYPE_FIELD = ABSENT_FIELD;
			Assert.isTrue(source.available(), 'The record type alone is enough');
			Assert.isFalse(source.condition().contains('npspAccountType'), source.condition());
			Assert.isFalse(source.binds().containsKey('npspAccountType'), 'No type bind without the field');
			Assert.areEqual(new Set<Id>{ npsp.Id }, selected(), 'Selected by the record type');
		}
	}

	@IsTest
	static void withoutEitherMarkerNothingIsSelectedOrQueried() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			standInHousehold('Garcia Household', null);
			NpspHouseholdSource.ACCOUNT_TYPE_FIELD = ABSENT_FIELD;
			NpspHouseholdSource.HOUSEHOLD_RECORD_TYPE = 'No_Such_Type';
			NpspHouseholdSource source = NpspHouseholdSource.get();

			Assert.isFalse(source.available(), 'An org without NPSP has nothing to adopt');
			Assert.areEqual('', source.condition(), 'No condition');
			Assert.areEqual(
				new Set<String>{ 'barnHousehold' },
				source.binds().keySet(),
				'Only the BarnCRM household bind is left'
			);
			Assert.isFalse(source.unadoptedHouseholdsExist(), 'And no query is made');
		}
	}

	@IsTest
	static void readsTheValuesNpspKeepsOnAnAccount() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			Contact primary = HouseholdTestDataFactory.newContact('Ana', 'Garcia');
			insert primary;
			Account npsp = standInHousehold('Garcia Household', primary.Id);

			List<NpspHouseholdSource.Household> read = NpspHouseholdSource.get().read(new Set<Id>{ npsp.Id });

			Assert.areEqual(1, read.size(), 'One household');
			NpspHouseholdSource.Household household = read[0];
			Assert.areEqual(npsp.Id, household.accountId);
			Assert.areEqual('Garcia Household', household.name);
			Assert.areEqual(organizationType(), household.recordTypeId);
			Assert.areEqual('Dear Garcias', household.formalGreeting);
			Assert.areEqual('Hi Garcias', household.informalGreeting);
			Assert.areEqual(primary.Id, household.primaryContactId);
			Assert.isTrue(household.customNaming, 'A hand typed name is custom naming');
			Assert.isTrue(household.members.isEmpty(), 'Members are held on the contacts here');
		}
	}

	@IsTest
	static void valuesTheOrgDoesNotHaveAreReadAsBlank() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			Account npsp = standInHousehold('Garcia Household', null);
			NpspHouseholdSource.FORMAL_GREETING_FIELD = ABSENT_FIELD;
			NpspHouseholdSource.INFORMAL_GREETING_FIELD = ABSENT_FIELD;
			NpspHouseholdSource.PRIMARY_CONTACT_FIELD = ABSENT_FIELD;
			NpspHouseholdSource.CUSTOM_NAMING_FIELD = ABSENT_FIELD;

			NpspHouseholdSource.Household household = NpspHouseholdSource.get().read(new Set<Id>{ npsp.Id })[0];

			Assert.areEqual('Garcia Household', household.name, 'The name is always there');
			Assert.isNull(household.formalGreeting, 'No formal greeting field, no value');
			Assert.isNull(household.informalGreeting, 'No informal greeting field, no value');
			Assert.isNull(household.primaryContactId, 'No primary contact field, no value');
			Assert.isFalse(household.customNaming, 'No marker, no custom naming');
		}
	}

	@IsTest
	static void readingNothingAsksForNothing() {
		System.runAs(TestUsers.admin()) {
			Assert.isTrue(NpspHouseholdSource.get().read(null).isEmpty(), 'No ids');
			Assert.isTrue(NpspHouseholdSource.get().read(new Set<Id>()).isEmpty(), 'An empty set of ids');
		}
	}

	@IsTest
	static void countsTheContactsEachAccountHas() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			Account withPeople = standInHousehold('Garcia Household', null);
			Account empty = standInHousehold('Empty Household', null);
			List<Contact> people = new List<Contact>{
				HouseholdTestDataFactory.newContact('Ana', 'Garcia'),
				HouseholdTestDataFactory.newContact('Leo', 'Garcia')
			};
			people[0].AccountId = withPeople.Id;
			people[1].AccountId = withPeople.Id;
			insert people;

			Map<Id, Integer> counts = NpspHouseholdSource.get().memberCounts(new Set<Id>{ withPeople.Id, empty.Id });

			Assert.areEqual(2, counts.get(withPeople.Id), 'Two contacts');
			Assert.isFalse(counts.containsKey(empty.Id), 'An account with nobody is left out');
		}
	}

	@IsTest
	static void theAccountModelIsReadFromTheOrgDefault() {
		System.runAs(TestUsers.admin()) {
			useCoreStandIns();
			NpspHouseholdSource source = NpspHouseholdSource.get();
			Database.delete(
				[SELECT Id FROM BarnCRM_Settings__c WHERE SetupOwnerId = :UserInfo.getOrganizationId()],
				AccessLevel.SYSTEM_MODE
			);

			Assert.isTrue(source.createsHouseholds(), 'No org default row means NPSP default: Household Account');

			accountModel(NpspHouseholdSource.HOUSEHOLD_ACCOUNT_TYPE);
			Assert.isTrue(source.createsHouseholds(), 'Household Account creates households');

			accountModel('One-to-One');
			Assert.isFalse(source.createsHouseholds(), 'Any other model does not');

			accountModel(null);
			Assert.isTrue(source.createsHouseholds(), 'A blank model is the default');

			NpspHouseholdSource.ACCOUNT_MODEL_FIELD = ABSENT_FIELD;
			Assert.isFalse(source.createsHouseholds(), 'A setting without the field is not NPSP');

			NpspHouseholdSource.ACCOUNT_MODEL_SETTING = 'No_Such_Object__c';
			Assert.isFalse(source.createsHouseholds(), 'No setting object, no NPSP');
		}
	}

	@IsTest
	static void householdsAreInUseWhileNpspCreatesThemOrOnesAreUnadopted() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			useCoreStandIns();
			accountModel(NpspHouseholdSource.HOUSEHOLD_ACCOUNT_TYPE);
			Assert.isTrue(NpspHouseholdSource.householdsInUse(), 'NPSP still creates households');

			accountModel('One-to-One');
			NpspHouseholdSource.clearCache();
			Assert.isFalse(NpspHouseholdSource.householdsInUse(), 'Not creating, and none left to adopt');

			standInHousehold('Garcia Household', null);
			NpspHouseholdSource.clearCache();
			Assert.isTrue(NpspHouseholdSource.householdsInUse(), 'Not creating, but one is not yet adopted');
		}
	}

	@IsTest
	static void sourcesAreFoundByKeyAndRunId() {
		System.runAs(TestUsers.admin()) {
			NpspHouseholdSource npspSource = new NamedSource('NPSP stand-in');
			NpspHouseholdSource npcSource = new NamedSource('NPC stand-in');

			Assert.areEqual('NPSP', new NpspHouseholdSource().key(), 'NPSP is the base source');
			Assert.areEqual(NpspHouseholdSource.get(), NpspHouseholdSource.get(), 'One source per transaction');

			NpspHouseholdSource.useForTest(NpspHouseholdSource.NPSP, npspSource);
			NpspHouseholdSource.useForTest(NpspHouseholdSource.NPC, npcSource);

			Assert.areEqual(npspSource, NpspHouseholdSource.get(), 'The NPSP source was replaced');
			Assert.areEqual(npspSource, NpspHouseholdSource.forKey(null), 'A blank key is NPSP');
			Assert.areEqual(npspSource, NpspHouseholdSource.forKey(NpspHouseholdSource.NPSP), 'NPSP by key');
			Assert.areEqual(npcSource, NpspHouseholdSource.forKey(NpspHouseholdSource.NPC), 'NPC by key');
			Assert.areEqual('NPC', NpspHouseholdSource.keyOfRun('NPC-0001'), 'An NPC run starts with its key');
			Assert.areEqual('NPSP', NpspHouseholdSource.keyOfRun('0001'), 'Any other run is NPSP');
			Assert.areEqual('NPSP', NpspHouseholdSource.keyOfRun(null), 'No run is NPSP');
		}
	}

	@IsTest
	static void theNpcSourceIsOnlyThereWhenMirrorIs() {
		System.runAs(TestUsers.admin()) {
			NpspHouseholdSource found = NpspHouseholdSource.forKey(NpspHouseholdSource.NPC);

			Assert.isTrue(
				found == null || found.key() == NpspHouseholdSource.NPC,
				'Null without the Mirror package, its source with it'
			);
		}
	}

	@IsTest
	static void aSourceKeepsWhatItReadsInItsRecords() {
		System.runAs(TestUsers.admin()) {
			NpspHouseholdSource.Household household = new NpspHouseholdSource.Household();
			NpspHouseholdSource.Member member = new NpspHouseholdSource.Member();

			Assert.isFalse(household.customNaming, 'Not custom until NPSP says so');
			Assert.isTrue(household.members.isEmpty(), 'No members until a source names them');
			Assert.isFalse(member.isPrimary, 'Not primary until a source says so');
		}
	}
}
