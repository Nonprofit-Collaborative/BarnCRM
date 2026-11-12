/**
 * The Nonprofit Cloud household source, kit and drift report (MIG-02b, canonical model R-HA7,
 * R-HA8, R-H15; ADR-NEXT `NEXT-npc-household-conversion.md`). No test org has Nonprofit Cloud,
 * so native membership rows are handed in as rows, and the native household group is stood in for
 * by `groupedForTest`; the real path is shown as it behaves without the objects (nothing
 * available, nothing selected, nothing to check).
 */
@IsTest(testFor='ApexClass:NpcHouseholdSource, ApexClass:MirrorHealthCheckExtension')
private class NpcHouseholdSourceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void coreFindsTheSourceAndTheKitByName() {
		System.runAs(TestUsers.admin()) {
			NpspHouseholdSource source = NpspHouseholdSource.forKey(NpspHouseholdSource.NPC);
			Assert.isTrue(source instanceof NpcHouseholdSource, 'Core builds it by name');
			Assert.areEqual(NpspHouseholdSource.NPC, source.key(), 'its key');
			Migration_Kit__mdt kit = MigrationKitService.kitNamed('NPC_Households');
			MigrationKitService.Step step = MigrationKitService.stepNamed(kit, 'households');
			Assert.areEqual('tool', step.kind, 'one tool step');
			Assert.isNull(new NpcHouseholdSource().rows('households', null), 'no rows to shape');
		}
	}

	@IsTest
	static void withoutNonprofitCloudNothingIsSelectedOrChecked() {
		System.runAs(TestUsers.admin()) {
			NpcHouseholdSource source = new NpcHouseholdSource();
			Account plain = new Account(Name = 'Npc Source Plain');
			insert plain;
			List<NpspHouseholdSource.Household> read = source.read(new Set<Id>{ plain.Id });
			Assert.areEqual(1, read.size(), 'the account is read');
			Assert.isTrue(read[0].members.isEmpty(), 'no native members without the object');
			Assert.isFalse(source.createsHouseholds(), 'upkeep never waits for it');
			if (!NpcHouseholdSource.readable('partyrelationshipgroup')) {
				Assert.isFalse(source.available(), 'nothing to convert');
				Assert.areEqual('', source.condition(), 'nothing selected');
				MigrationCheck check = source.verify('households');
				Assert.areEqual(0, check.source, 'nothing wanted');
				Assert.areEqual(0, check.done, 'nothing done');
			}
		}
	}

	@IsTest
	static void membershipRowsBecomeMembersWithRolesAndDates() {
		// runs-as: deploying user (rows only, no record or permission is read)
		Id lee = Id.valueOf('001000000000001');
		Id sam = Id.valueOf('003000000000001');
		Id ann = Id.valueOf('003000000000002');
		Id bo = Id.valueOf('003000000000003');
		Date started = Date.newInstance(2019, 5, 1);
		Map<Id, List<NpspHouseholdSource.Member>> members = NpcHouseholdSource.members(
			new List<Map<String, Object>>{
				new Map<String, Object>{
					'AccountId' => lee,
					'ContactId' => sam,
					'IsPrimaryMember' => true,
					'Roles' => 'Husband;Father',
					'IsActive' => true,
					'StartDate' => started
				},
				new Map<String, Object>{
					'AccountId' => lee,
					'ContactId' => ann,
					'Roles' => 'Cousin;Daughter',
					'IsActive' => true
				},
				new Map<String, Object>{
					'AccountId' => lee,
					'ContactId' => bo,
					'IsActive' => false
				}
			}
		);
		List<NpspHouseholdSource.Member> lees = members.get(lee);
		Assert.areEqual(2, lees.size(), 'an inactive row with no end date is left out');
		Assert.isTrue(lees[0].isPrimary, 'Sam is the primary member');
		Assert.areEqual('Spouse or Partner', lees[0].role, 'the first role that maps');
		Assert.areEqual(started, lees[0].startDate, 'start date kept');
		Assert.areEqual('Child', lees[1].role, 'an unknown role is passed over');
		Assert.isFalse(lees[1].isPrimary, 'Ann is not primary');
	}

	@IsTest
	static void driftListsWhereModelAndGroupDisagreeAndTheCheckCounts() {
		System.runAs(TestUsers.admin()) {
			Account collision = HouseholdTestDataFactory.newHousehold('Drift Collision');
			Account settled = HouseholdTestDataFactory.newHousehold('Drift Settled');
			settled.Household_Model__c = HouseholdSelector.MODEL_CONVERTED;
			Account pinnedNoGroup = new Account(
				Name = 'Drift Pinned',
				Household_Model__c = HouseholdSelector.MODEL_NATIVE
			);
			Account convertedBack = new Account(
				Name = 'Drift Converted Back',
				Household_Model__c = HouseholdSelector.MODEL_CONVERTED
			);
			Account waiting = new Account(Name = 'Drift Waiting');
			Database.insert(
				new List<Account>{ collision, settled, pinnedNoGroup, convertedBack, waiting },
				AccessLevel.SYSTEM_MODE
			);
			NpcHouseholdSource.groupedForTest = new Set<Id>{ collision.Id, settled.Id, waiting.Id };

			Test.startTest();
			NpcHouseholdSource.Drift drift = NpcHouseholdSource.drift(10);
			MigrationCheck check = new NpcHouseholdSource().verify('households');
			List<HealthCheckService.Finding> findings = new MirrorHealthCheckExtension().findings();
			Test.stopTest();

			Assert.areEqual(3, drift.count, 'collision, pinned without a group, converted back');
			Assert.isTrue(drift.names.contains('Drift Collision'), 'both models claim it');
			Assert.isTrue(drift.names.contains('Drift Pinned'), 'no native group');
			Assert.isTrue(drift.names.contains('Drift Converted Back'), 'not a household');
			Assert.isFalse(drift.names.contains('Drift Settled'), 'converted on purpose');
			Assert.isFalse(drift.names.contains('Drift Waiting'), 'native, not yet converted');
			Assert.areEqual(3, check.source, 'three accounts carry a native household group');
			Assert.areEqual(1, check.done, 'one of them is converted');
			Boolean reported = false;
			for (HealthCheckService.Finding finding : findings) {
				reported |= finding.getKey() == MirrorHealthCheckExtension.HOUSEHOLD_DRIFT_KEY;
			}
			Assert.isTrue(reported, 'Health Check shows the drift report');
		}
	}
}
