/**
 * The Nonprofit Cloud source of household adoption (MIG-02b, canonical model R-HA7 to R-HA9,
 * ADR-NEXT `NEXT-npc-household-conversion.md`). Mirror's source is not in Core, so a fake with
 * the NPC key names ordinary Accounts as Nonprofit Cloud households: a conversion runs in
 * Junction mode, marks the Account Converted and journals the model it had, keeps its runs
 * apart from NPSP's, and its undo puts the model back except on a household with members.
 */
@IsTest(
	testFor='ApexClass:NpspHouseholdAdoptionService, ApexClass:NpspHouseholdAdoptionBatch, ApexClass:NpspHouseholdSource'
)
private class NpcHouseholdConversionTest {
	@TestSetup
	static void createUsers() {
		TestUsers.admin();
	}

	private class FakeNpcSource extends NpspHouseholdSource {
		Map<Id, NpspHouseholdSource.Household> values = new Map<Id, NpspHouseholdSource.Household>();

		public override String key() {
			return NpspHouseholdSource.NPC;
		}

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
	}

	private static List<Account> households(FakeNpcSource source) {
		HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
		Account lee = new Account(Name = 'Npc Convert Lee Household');
		Account kim = new Account(
			Name = 'Npc Convert Kim Household',
			Household_Model__c = 'Automatic'
		);
		insert new List<Account>{ lee, kim };
		Contact sam = new Contact(FirstName = 'Sam', LastName = 'Lee');
		insert sam;
		for (Account account : new List<Account>{ lee, kim }) {
			NpspHouseholdSource.Household household = new NpspHouseholdSource.Household();
			household.accountId = account.Id;
			household.name = account.Name;
			source.values.put(account.Id, household);
		}
		NpspHouseholdSource.Member member = new NpspHouseholdSource.Member();
		member.contactId = sam.Id;
		member.isPrimary = true;
		member.role = 'Head';
		member.startDate = Date.newInstance(2020, 1, 1);
		source.values.get(lee.Id).members.add(member);
		NpspHouseholdSource.npcInstance = source;
		return new List<Account>{ lee, kim };
	}

	private static List<Household_Member__c> membersOf(Id householdId) {
		return [
			SELECT Id, Is_Primary__c, Role__c, Start_Date__c
			FROM Household_Member__c
			WHERE Household__c = :householdId
			WITH SYSTEM_MODE
		];
	}

	private static Map<Id, Account> read(List<Account> accounts) {
		return new Map<Id, Account>(
			[
				SELECT Id, RecordTypeId, Household_Model__c, Custom_Name__c
				FROM Account
				WHERE Id IN :accounts
				WITH SYSTEM_MODE
			]
		);
	}

	@IsTest
	static void convertsInJunctionModeAndKeepsItsRunsApart() {
		System.runAs(TestUsers.admin()) {
			List<Account> accounts = households(new FakeNpcSource());
			OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();

			NpspHouseholdAdoptionService.Status status = NpspHouseholdAdoptionService.getStatus(
				NpspHouseholdSource.NPC
			);
			Assert.isNull(status.blockedReason, 'Junction membership stops NPSP only');
			Assert.areEqual(2, status.candidateCount, 'both households are candidates');

			Test.startTest();
			String runId = NpspHouseholdAdoptionService.start(NpspHouseholdSource.NPC, true, 2);
			Test.stopTest();

			Assert.isTrue(runId.startsWith('NPC-'), 'an NPC run carries its key');
			Assert.areEqual(36, runId.length(), 'and fits the Run ID field');
			Assert.areEqual(NpspHouseholdSource.NPC, NpspHouseholdSource.keyOfRun(runId), 'key');
			for (Account account : read(accounts).values()) {
				Assert.areEqual(
					HouseholdService.householdRecordTypeId(),
					account.RecordTypeId,
					'now a BarnCRM household'
				);
				Assert.areEqual('Converted', account.Household_Model__c, 'BarnCRM owns it');
				Assert.isTrue(account.Custom_Name__c, 'its hand-typed name is kept');
			}
			List<Household_Member__c> lees = membersOf(accounts[0].Id);
			Assert.areEqual(1, lees.size(), 'Sam joined in Junction mode');
			Assert.isTrue(lees[0].Is_Primary__c, 'as the primary member');
			Assert.areEqual('Head', lees[0].Role__c, 'with the role the source holds');
			Assert.areEqual(Date.newInstance(2020, 1, 1), lees[0].Start_Date__c, 'and its date');
			for (Household_Adoption__c row : [
				SELECT Previous_Values__c
				FROM Household_Adoption__c
				WITH SYSTEM_MODE
			]) {
				Assert.isTrue(
					row.Previous_Values__c.contains('Household_Model__c'),
					'the model it had is journaled'
				);
			}
			Assert.areEqual(
				2,
				NpspHouseholdAdoptionService.getStatus(NpspHouseholdSource.NPC).lastRun.adopted,
				'the NPC panel shows its run'
			);
			Assert.isNull(
				NpspHouseholdAdoptionService.getStatus(null).lastRun,
				'the NPSP panel does not'
			);
			Assert.isTrue(NpspHouseholdAdoptionService.isNpcOffered(), 'NPC panel offered');
		}
	}

	@IsTest
	static void undoPutsTheModelBackButNotOnAHouseholdWithMembers() {
		System.runAs(TestUsers.admin()) {
			List<Account> accounts = households(new FakeNpcSource());
			Account lee = accounts[0];
			Account kim = accounts[1];
			String runId = 'NPC-' + '0'.repeat(32);
			String leeModelBefore = [SELECT Household_Model__c FROM Account WHERE Id = :lee.Id]
			.Household_Model__c;
			NpspHouseholdAdoptionBatch.adopt(runId, true, 2).execute(null, accounts);
			Contact ann = new Contact(LastName = 'Kim', FirstName = 'Ann');
			insert ann;
			insert new Household_Member__c(Household__c = kim.Id, Contact__c = ann.Id);

			Test.startTest();
			Database.executeBatch(NpspHouseholdAdoptionBatch.undo(runId));
			Test.stopTest();

			Map<Id, Account> after = read(accounts);
			Assert.areNotEqual(
				HouseholdService.householdRecordTypeId(),
				after.get(lee.Id).RecordTypeId,
				'Lee is no longer a household'
			);
			Assert.areEqual(
				leeModelBefore,
				after.get(lee.Id).Household_Model__c,
				'Lee gets the model it had before the run'
			);
			Assert.isTrue(membersOf(lee.Id).isEmpty(), 'the membership the run made is removed');
			Assert.areEqual('Converted', after.get(kim.Id).Household_Model__c, 'Kim kept');
			Household_Adoption__c kept = [
				SELECT Status__c, Note__c
				FROM Household_Adoption__c
				WHERE Account_Id__c = :String.valueOf(kim.Id)
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Not Restored', kept.Status__c, 'Kim has a member');
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_NpspAdoption_NoteHasMembers'),
				kept.Note__c,
				'why'
			);
		}
	}

	@IsTest
	static void aFailedMembershipDeleteIsReportedPerHousehold() {
		// runs-as: deploying user (plain in-memory results, no record or permission is read)
		Id first = '001000000000001AAA';
		Id second = '001000000000002AAA';
		List<Household_Member__c> removals = new List<Household_Member__c>{
			new Household_Member__c(Household__c = first),
			new Household_Member__c(Household__c = second),
			new Household_Member__c(Household__c = second)
		};
		List<Database.DeleteResult> results = new List<Database.DeleteResult>{
			(Database.DeleteResult) JSON.deserialize(
				'{"success":true}',
				Database.DeleteResult.class
			),
			(Database.DeleteResult) JSON.deserialize(
				'{"success":false,"errors":[{"message":"locked","statusCode":"ENTITY_IS_LOCKED"}]}',
				Database.DeleteResult.class
			),
			(Database.DeleteResult) JSON.deserialize(
				'{"success":false,"errors":[{"message":"again","statusCode":"ENTITY_IS_LOCKED"}]}',
				Database.DeleteResult.class
			)
		};

		Map<Id, String> failed = NpspHouseholdAdoptionBatch.deleteFailures(removals, results);

		Assert.areEqual(1, failed.size(), 'only the household with a failed delete');
		Assert.areEqual('locked', failed.get(second), 'the first error is kept');
		Assert.isFalse(failed.containsKey(first), 'a clean delete is not reported');
	}
}
