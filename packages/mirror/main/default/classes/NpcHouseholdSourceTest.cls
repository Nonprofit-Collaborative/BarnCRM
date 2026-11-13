/**
 * The Nonprofit Cloud household source, kit and drift report (MIG-02b, canonical model R-HA7,
 * R-HA8, R-H15; ADR-0217 `0217-npc-household-conversion.md`). No test org has Nonprofit Cloud,
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
			Account plain = TestDataFactory.organization(new Account(Name = 'Npc Source Plain'));
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
	static void theSelectNamesOnlyReadableFieldsAndDropsWhatIsMissing() {
		// runs-as: deploying user (no record or permission is read)
		Set<String> all = new Set<String>{
			'accountid',
			'contactid',
			'isprimarymember',
			'roles',
			'isactive',
			'startdate',
			'enddate'
		};
		Assert.areEqual(
			'SELECT AccountId, ContactId, IsPrimaryMember, Roles, IsActive, StartDate, EndDate',
			NpcHouseholdSource.memberSelect(all),
			'everything readable'
		);
		Set<String> noFlag = all.clone();
		noFlag.remove('isprimarymember');
		noFlag.remove('roles');
		Assert.areEqual(
			'SELECT AccountId, ContactId, IsActive, StartDate, EndDate',
			NpcHouseholdSource.memberSelect(noFlag),
			'the primary flag and role are dropped, members still join'
		);
		Set<String> noContact = all.clone();
		noContact.remove('contactid');
		Assert.isNull(NpcHouseholdSource.memberSelect(noContact), 'members cannot be joined');
		Assert.isNull(NpcHouseholdSource.memberSelect(new Set<String>()), 'nothing readable');
	}

	@IsTest
	static void theCountFilterMatchesTheMemberRule() {
		// runs-as: deploying user (no record or permission is read)
		Assert.areEqual(
			' AND (IsActive = true OR EndDate != null)',
			NpcHouseholdSource.memberFilter(new Set<String>{ 'isactive', 'enddate' }),
			'inactive with no end date is not counted'
		);
		Assert.areEqual(
			' AND IsActive = true',
			NpcHouseholdSource.memberFilter(new Set<String>{ 'isactive' }),
			'without End Date only active rows count'
		);
		Assert.areEqual(
			'',
			NpcHouseholdSource.memberFilter(new Set<String>{ 'enddate' }),
			'without Is Active nothing can be filtered'
		);
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
	static void theBindsKeepBarnHouseholdsAndAdministratorChoicesOut() {
		System.runAs(TestUsers.admin()) {
			Map<String, Object> binds = new NpcHouseholdSource().binds();

			Assert.areEqual(
				HouseholdService.householdRecordTypeId(),
				binds.get('barnHousehold'),
				'BarnCRM households are never candidates'
			);
			Assert.areEqual(
				new List<String>{
					HouseholdSelector.MODEL_CONVERTED,
					HouseholdSelector.MODEL_NATIVE
				},
				binds.get('keptModels'),
				'Converted and Nonprofit Cloud households are left as they are'
			);
		}
	}

	@IsTest
	static void nothingIsReadOrCountedForNoAccountsOrWithoutTheNativeObjects() {
		System.runAs(TestUsers.admin()) {
			NpcHouseholdSource source = new NpcHouseholdSource();
			Account plain = TestDataFactory.organization(new Account(Name = 'Npc Source Counted'));
			insert plain;

			Assert.isTrue(source.read(null).isEmpty(), 'no accounts asked for');
			Assert.isTrue(source.read(new Set<Id>()).isEmpty(), 'an empty set asks for none');
			Assert.isTrue(source.memberCounts(null).isEmpty(), 'no counts for no accounts');
			Assert.isTrue(source.memberCounts(new Set<Id>()).isEmpty(), 'an empty set counts none');
			Assert.areEqual(
				0,
				source.verify('somethingElse').source,
				'only the households step is checked'
			);
			Assert.areEqual(0, source.verify('somethingElse').done, 'and nothing is done there');
			if (!source.available()) {
				Assert.isTrue(
					source.memberCounts(new Set<Id>{ plain.Id }).isEmpty(),
					'without the native objects nothing is counted'
				);
				Assert.isNull(
					source.read(new Set<Id>{ plain.Id })[0].primaryContactId,
					'no primary'
				);
			}
			Assert.isFalse(
				NpcHouseholdSource.readable('not_a_real_object__c'),
				'unknown is unreadable'
			);
		}
	}

	@IsTest
	static void rowsWithoutAnAccountOrContactAreSkippedAndFormerMembersWithDatesKept() {
		// runs-as: deploying user (rows only, no record or permission is read)
		Id lee = Id.valueOf('001000000000001');
		Id kim = Id.valueOf('001000000000002');
		Id sam = Id.valueOf('003000000000001');
		Id ann = Id.valueOf('003000000000002');
		Date ended = Date.newInstance(2022, 3, 1);
		Map<Id, List<NpspHouseholdSource.Member>> members = NpcHouseholdSource.members(
			new List<Map<String, Object>>{
				new Map<String, Object>{ 'AccountId' => null, 'ContactId' => sam },
				new Map<String, Object>{ 'AccountId' => lee, 'ContactId' => null },
				new Map<String, Object>{
					'AccountId' => lee,
					'ContactId' => sam,
					'Roles' => ' Mother ; Wife',
					'IsActive' => false,
					'EndDate' => ended
				},
				new Map<String, Object>{
					'AccountId' => kim,
					'ContactId' => ann,
					'Roles' => 'Other'
				}
			}
		);

		Assert.areEqual(2, members.size(), 'two accounts have members');
		Assert.areEqual(1, members.get(lee).size(), 'rows missing a side are skipped');
		Assert.areEqual(ended, members.get(lee)[0].endDate, 'a former member keeps the end date');
		Assert.areEqual('Head', members.get(lee)[0].role, 'roles are trimmed and case-insensitive');
		Assert.isFalse(members.get(lee)[0].isPrimary, 'no flag, not primary');
		Assert.areEqual('Other', members.get(kim)[0].role, 'Other maps to Other');
		Assert.isNull(NpcHouseholdSource.members(new List<Map<String, Object>>()).get(lee), 'none');
	}

	@IsTest
	static void driftShowsOnlyTheFirstFewNamesButCountsAll() {
		System.runAs(TestUsers.admin()) {
			List<Account> back = new List<Account>();
			for (Integer i = 0; i < 3; i++) {
				back.add(
					TestDataFactory.household(
						new Account(
							Name = 'Drift Back ' + i,
							Household_Model__c = HouseholdSelector.MODEL_CONVERTED
						)
					)
				);
			}
			Database.insert(back, AccessLevel.SYSTEM_MODE);
			NpcHouseholdSource.groupedForTest = new Set<Id>();

			NpcHouseholdSource.Drift drift = NpcHouseholdSource.drift(1);

			Assert.areEqual(3, drift.count, 'all three are counted');
			Assert.areEqual(1, drift.names.size(), 'only one name is shown');
		}
	}

	@IsTest
	static void driftListsWhereModelAndGroupDisagreeAndTheCheckCounts() {
		System.runAs(TestUsers.admin()) {
			Account collision = HouseholdTestDataFactory.newHousehold('Drift Collision');
			Account settled = HouseholdTestDataFactory.newHousehold('Drift Settled');
			settled.Household_Model__c = HouseholdSelector.MODEL_CONVERTED;
			Account pinnedNoGroup = TestDataFactory.household(
				new Account(
					Name = 'Drift Pinned',
					Household_Model__c = HouseholdSelector.MODEL_NATIVE
				)
			);
			Account convertedBack = TestDataFactory.household(
				new Account(
					Name = 'Drift Converted Back',
					Household_Model__c = HouseholdSelector.MODEL_CONVERTED
				)
			);
			Account waiting = TestDataFactory.organization(new Account(Name = 'Drift Waiting'));
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
