/**
 * NPSP household adoption (X-05, canonical model R-HA1 to R-HA5). No test org has NPSP, so the
 * NPSP-present path runs through `NpspHouseholdSource`'s seam: a fake names ordinary Accounts
 * as NPSP households and hands back the values NPSP would hold. The real describe path is
 * covered as it behaves without NPSP (nothing available, nothing selected). Runs as a BarnCRM
 * Admin permission set user; verification reads use system mode.
 */
@IsTest(
	testFor='ApexClass:NpspHouseholdAdoptionService, ApexClass:NpspHouseholdAdoptionBatch, ApexClass:NpspHouseholdAdoptionController, ApexClass:NpspHouseholdSource, ApexClass:HouseholdWriter, ApexClass:SettingsController'
)
private class NpspHouseholdAdoptionTest {
	private static final String PREFIX = 'Npsp Adopt Test ';

	@TestSetup
	static void createUsers() {
		TestUsers.admin();
	}

	/** Names the given Accounts as NPSP households, with the NPSP values each should carry. */
	private class FakeSource extends NpspHouseholdSource {
		Map<Id, NpspHouseholdSource.Household> values = new Map<Id, NpspHouseholdSource.Household>();

		public override Boolean available() {
			return true;
		}

		public override String condition() {
			return 'Id IN :fakeIds AND RecordTypeId != :barnHousehold';
		}

		public override Map<String, Object> binds() {
			return new Map<String, Object>{
				'fakeIds' => values.keySet(),
				'barnHousehold' => HouseholdService.householdRecordTypeId()
			};
		}

		public override List<NpspHouseholdSource.Household> read(Set<Id> accountIds) {
			List<NpspHouseholdSource.Household> result = new List<NpspHouseholdSource.Household>();
			for (Id accountId : accountIds) {
				if (values.containsKey(accountId)) {
					result.add(values.get(accountId));
				}
			}
			return result;
		}

		void add(Account account, String formal, String informal, Id primary, Boolean custom) {
			NpspHouseholdSource.Household household = new NpspHouseholdSource.Household();
			household.accountId = account.Id;
			household.name = account.Name;
			household.formalGreeting = formal;
			household.informalGreeting = informal;
			household.primaryContactId = primary;
			household.customNaming = custom;
			values.put(account.Id, household);
		}
	}

	private class Fixture {
		Account smith;
		Account jones;
		Contact ann;
		Contact bob;
		Contact cara;
		FakeSource source = new FakeSource();
	}

	/**
	 * Two NPSP households: the Smiths (Ann and Bob, Ann primary, greetings typed in NPSP) and
	 * the Joneses (Cara, whose NPSP primary contact is Ann, who is not a member).
	 */
	private static Fixture fixture() {
		HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
		Fixture f = new Fixture();
		f.smith = new Account(Name = PREFIX + 'Smith Household');
		f.jones = new Account(Name = PREFIX + 'Jones Household');
		insert new List<Account>{ f.smith, f.jones };
		f.ann = new Contact(FirstName = 'Ann', LastName = 'Smith', AccountId = f.smith.Id);
		f.bob = new Contact(FirstName = 'Bob', LastName = 'Smith', AccountId = f.smith.Id);
		f.cara = new Contact(FirstName = 'Cara', LastName = 'Jones', AccountId = f.jones.Id);
		insert new List<Contact>{ f.ann, f.bob, f.cara };
		f.source.add(f.smith, 'Ms. Ann Smith and Mr. Bob Smith', 'Ann and Bob', f.ann.Id, true);
		f.source.add(f.jones, 'Ms. Cara Jones', 'Cara', f.ann.Id, false);
		NpspHouseholdSource.instance = f.source;
		return f;
	}

	private static Map<Id, Account> accounts(Fixture f) {
		Set<Id> ids = new Set<Id>{ f.smith.Id, f.jones.Id };
		return new Map<Id, Account>(
			[
				SELECT
					Id,
					Name,
					RecordTypeId,
					Custom_Name__c,
					Household_Formal_Greeting__c,
					Household_Informal_Greeting__c,
					Primary_Contact__c,
					Member_Count__c
				FROM Account
				WHERE Id IN :ids
				WITH SYSTEM_MODE
			]
		);
	}

	/** A source that fails in a way no BarnCRM message covers, as a platform fault would. */
	private class FailingSource extends NpspHouseholdSource {
		public override Boolean available() {
			throw new QueryException('The source could not be read');
		}
	}

	@IsTest
	static void anUnexpectedFailureIsLoggedAndShownAsTheUnexpectedError() {
		System.runAs(TestUsers.admin()) {
			NpspHouseholdSource.instance = new FailingSource();
			String statusMessage;
			String adoptMessage;

			Test.startTest();
			try {
				NpspHouseholdAdoptionController.getStatus();
			} catch (AuraHandledException e) {
				statusMessage = e.getMessage();
			}
			try {
				NpspHouseholdAdoptionController.adopt(true, 1);
			} catch (AuraHandledException e) {
				adoptMessage = e.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(Label.Core_UnexpectedError, statusMessage, 'Status: the plain error');
			Assert.areEqual(Label.Core_UnexpectedError, adoptMessage, 'Adopt: the plain error');
			Assert.isTrue(
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE] >= 2,
				'Both failures are written to the Error Log'
			);
		}
	}

	@IsTest
	static void previewCountsAndSamplesCandidates() {
		System.runAs(TestUsers.admin()) {
			Fixture f = fixture();
			NpspHouseholdAdoptionService.Status status = NpspHouseholdAdoptionController.getStatus();
			Assert.isTrue(status.available, 'the fake source has households');
			Assert.areEqual(2, status.candidateCount, 'both households are candidates');
			Assert.isFalse(status.moreThanLimit, 'two is under the run limit');
			Assert.isNull(status.blockedReason, 'contact mode with a Household record type');
			Assert.isNull(status.lastRun, 'nothing adopted yet');
			Assert.areEqual(2, status.sample.size(), 'both are sampled');
			for (NpspHouseholdAdoptionService.Candidate candidate : status.sample) {
				if (candidate.accountId == f.smith.Id) {
					Assert.areEqual(2, candidate.contactCount, 'Ann and Bob');
					Assert.areEqual('Ann Smith', candidate.primaryContactName, 'NPSP primary');
					Assert.areEqual('Ann and Bob', candidate.informalGreeting, 'NPSP greeting');
				} else {
					Assert.areEqual(1, candidate.contactCount, 'Cara');
				}
			}
		}
	}

	@IsTest
	static void adoptKeepingNamesConvertsInPlace() {
		System.runAs(TestUsers.admin()) {
			Fixture f = fixture();
			Id original = accounts(f).get(f.smith.Id).RecordTypeId;
			Test.startTest();
			String runId = NpspHouseholdAdoptionController.adopt(true, 2);
			Test.stopTest();

			Map<Id, Account> after = accounts(f);
			Id household = HouseholdService.householdRecordTypeId();
			Account smith = after.get(f.smith.Id);
			Assert.areEqual(household, smith.RecordTypeId, 'now a BarnCRM household');
			Assert.areEqual(PREFIX + 'Smith Household', smith.Name, 'NPSP name kept');
			Assert.isTrue(smith.Custom_Name__c, 'kept names are marked custom');
			Assert.areEqual(
				'Ms. Ann Smith and Mr. Bob Smith',
				smith.Household_Formal_Greeting__c,
				'NPSP formal greeting copied'
			);
			Assert.areEqual('Ann and Bob', smith.Household_Informal_Greeting__c, 'informal copied');
			Assert.areEqual(f.ann.Id, smith.Primary_Contact__c, 'NPSP primary is a member');
			Assert.areEqual(2, smith.Member_Count__c, 'upkeep counted the members');

			Account jones = after.get(f.jones.Id);
			Assert.areEqual(household, jones.RecordTypeId, 'Joneses adopted too');
			Assert.areNotEqual(f.ann.Id, jones.Primary_Contact__c, 'Ann is not a Jones');

			List<Household_Adoption__c> journal = [
				SELECT Account_Id__c, Run_Id__c, Status__c, Previous_Record_Type_Id__c
				FROM Household_Adoption__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, journal.size(), 'one row per adopted account');
			for (Household_Adoption__c row : journal) {
				Assert.areEqual(runId, row.Run_Id__c, 'the run started');
				Assert.areEqual('Adopted', row.Status__c, 'adopted');
				if (row.Account_Id__c == String.valueOf(f.smith.Id)) {
					Assert.areEqual(
						original == null ? null : String.valueOf(original),
						row.Previous_Record_Type_Id__c,
						'previous record type kept for undo'
					);
				}
			}

			NpspHouseholdAdoptionService.Status status = NpspHouseholdAdoptionService.getStatus();
			Assert.areEqual(0, status.candidateCount, 'nothing left to adopt');
			Assert.areEqual(2, status.lastRun.adopted, 'the run can be undone');
			Assert.isTrue(NpspHouseholdAdoptionService.isOffered(), 'rows keep the panel offered');
		}
	}

	@IsTest
	static void adoptWithoutKeepingNamesLetsBarnCrmName() {
		System.runAs(TestUsers.admin()) {
			Fixture f = fixture();
			Test.startTest();
			NpspHouseholdAdoptionService.start(false, 2);
			Test.stopTest();

			Map<Id, Account> after = accounts(f);
			Account jones = after.get(f.jones.Id);
			Assert.isFalse(jones.Custom_Name__c, 'NPSP had no custom naming');
			Assert.areEqual('The Jones Family', jones.Name, 'named by BarnCRM patterns');
			Assert.isTrue(after.get(f.smith.Id).Custom_Name__c, 'NPSP custom naming is kept');
		}
	}

	@IsTest
	static void undoPutsAccountsBack() {
		System.runAs(TestUsers.admin()) {
			Fixture f = fixture();
			Map<Id, Account> before = accounts(f);
			NpspHouseholdAdoptionBatch adopt = NpspHouseholdAdoptionBatch.adopt('run-1', true, 2);
			adopt.execute(null, new List<Account>{ f.smith, f.jones });
			Assert.areEqual(
				HouseholdService.householdRecordTypeId(),
				accounts(f).get(f.smith.Id).RecordTypeId,
				'adopted'
			);
			// The Joneses are deleted, so their row cannot be put back.
			delete [SELECT Id FROM Contact WHERE AccountId = :f.jones.Id WITH SYSTEM_MODE];
			delete new Account(Id = f.jones.Id);

			Test.startTest();
			NpspHouseholdAdoptionController.undo('run-1', 2);
			Test.stopTest();

			Account smith = accounts(f).get(f.smith.Id);
			Account was = before.get(f.smith.Id);
			// A blank record type saves as whatever the org gives a blank on update (its default
			// where it has record types), so a probe account saved the same way says what to expect.
			Id expectedType = was.RecordTypeId;
			if (expectedType == null) {
				Account probe = new Account(Name = PREFIX + 'Probe');
				insert probe;
				Database.update(
					new Account(Id = probe.Id, RecordTypeId = null),
					true,
					AccessLevel.SYSTEM_MODE
				);
				expectedType = [
					SELECT RecordTypeId
					FROM Account
					WHERE Id = :probe.Id
					WITH SYSTEM_MODE
				]
				.RecordTypeId;
			}
			Assert.areEqual(expectedType, smith.RecordTypeId, 'record type put back');
			Assert.areEqual(was.Custom_Name__c, smith.Custom_Name__c, 'custom name put back');
			Assert.isNull(smith.Household_Formal_Greeting__c, 'greeting put back to blank');
			Assert.isNull(smith.Primary_Contact__c, 'primary put back to blank');

			Map<String, Household_Adoption__c> rows = new Map<String, Household_Adoption__c>();
			for (Household_Adoption__c row : [
				SELECT Account_Id__c, Status__c, Note__c
				FROM Household_Adoption__c
				WITH SYSTEM_MODE
			]) {
				rows.put(row.Account_Id__c, row);
			}
			Assert.areEqual('Undone', rows.get(String.valueOf(f.smith.Id)).Status__c, 'undone');
			Household_Adoption__c gone = rows.get(String.valueOf(f.jones.Id));
			Assert.areEqual('Not Restored', gone.Status__c, 'deleted account not restored');
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_NpspAdoption_NoteGone'),
				gone.Note__c,
				'says why'
			);
		}
	}

	@IsTest
	static void refusesWhenItShould() {
		System.runAs(TestUsers.admin()) {
			fixture();
			assertRefused(
				String.format(
					BarnHelp.text('Core', 'Core_NpspAdoption_ErrorCountChanged'),
					new List<Object>{ 2, 1 }
				),
				1,
				'count grew'
			);
			assertRefused(
				String.format(
					BarnHelp.text('Core', 'Core_NpspAdoption_ErrorCountChanged'),
					new List<Object>{ 2, 0 }
				),
				null,
				'unconfirmed'
			);

			NpspHouseholdAdoptionService.runningOverride = true;
			assertRefused(
				BarnHelp.text('Core', 'Core_NpspAdoption_ErrorRunning'),
				2,
				'a run is in progress'
			);
			NpspHouseholdAdoptionService.runningOverride = null;

			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
			assertRefused(
				BarnHelp.text('Core', 'Core_NpspAdoption_ErrorJunctionMode'),
				2,
				'junction mode'
			);
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

			NpspHouseholdAdoptionService.permissionOverride = false;
			assertRefused(
				BarnHelp.text('Core', 'Core_NpspAdoption_ErrorNoPermission'),
				2,
				'no permission'
			);
			try {
				NpspHouseholdAdoptionController.getStatus();
				Assert.fail('status needs the permission too');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_NpspAdoption_ErrorNoPermission'),
					e.getMessage(),
					'why'
				);
			}
			NpspHouseholdAdoptionService.permissionOverride = null;

			try {
				NpspHouseholdAdoptionController.undo('no-such-run', 1);
				Assert.fail('nothing to undo');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_NpspAdoption_ErrorNothingToUndo'),
					e.getMessage(),
					'why'
				);
			}

			NpspHouseholdSource.instance = new FakeSource();
			assertRefused(
				BarnHelp.text('Core', 'Core_NpspAdoption_ErrorNothingToAdopt'),
				2,
				'nothing to adopt'
			);
		}
	}

	private static void assertRefused(String expected, Integer confirmed, String why) {
		try {
			NpspHouseholdAdoptionController.adopt(true, confirmed);
			Assert.fail('refused: ' + why);
		} catch (AuraHandledException e) {
			Assert.areEqual(expected, e.getMessage(), why);
		}
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Household_Adoption__c WITH SYSTEM_MODE],
			'nothing adopted: ' + why
		);
	}

	@IsTest
	static void realSourceWithoutNpspFindsNothing() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
			Account plain = new Account(Name = PREFIX + 'Plain');
			insert plain;
			NpspHouseholdSource source = NpspHouseholdSource.get();
			List<NpspHouseholdSource.Household> read = source.read(new Set<Id>{ plain.Id });
			Assert.areEqual(1, read.size(), 'the account is read');
			Assert.isNull(read[0].formalGreeting, 'no NPSP field in this org reads as blank');
			Assert.isFalse(read[0].customNaming, 'no NPSP custom naming');
			if (!source.available()) {
				Assert.areEqual('', source.condition(), 'nothing to select without NPSP');
				NpspHouseholdAdoptionService.Status status = NpspHouseholdAdoptionService.getStatus();
				Assert.isFalse(status.available, 'nothing to adopt without NPSP');
				Assert.areEqual(0, status.candidateCount, 'nothing counted');
			}
			Test.startTest();
			Database.executeBatch(NpspHouseholdAdoptionBatch.adopt('run-empty', true, 10));
			Test.stopTest();
			if (!source.available()) {
				Assert.areEqual(
					0,
					[SELECT COUNT() FROM Household_Adoption__c WITH SYSTEM_MODE],
					'an org without NPSP adopts nothing'
				);
			}
		}
	}

	private static Boolean adoptionRowShown() {
		for (SettingsController.SearchHit hit : SettingsController.search('adopt npsp')) {
			if (hit.label == 'Adopt NPSP Households') {
				return true;
			}
		}
		return false;
	}

	@IsTest
	static void offeredOnlyWhereNpspApplies() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
			shape.hasNpsp = true;
			OrgShapeDetector.overrideShape = shape;
			Assert.isTrue(NpspHouseholdAdoptionService.isOffered(), 'NPSP detected');
			Assert.isTrue(adoptionRowShown(), 'the settings row shows where NPSP is');
			OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();
			Assert.areEqual(
				NpspHouseholdAdoptionService.isOffered(),
				adoptionRowShown(),
				'the settings row follows isOffered'
			);
			Assert.areEqual(
				CoexistenceService.MODE_NPSP.equals(CoexistenceService.getCurrentMode()),
				NpspHouseholdAdoptionService.isOffered(),
				'otherwise only in NPSP mode, with no rows yet'
			);
		}
	}
}
