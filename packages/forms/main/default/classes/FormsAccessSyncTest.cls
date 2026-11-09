/**
 * BarnCRM's roles get the Forms sets (ADR-0175 `0175-forms-module.md` decision 11): BarnCRM Admin
 * holders Forms Admin, the Team Member and Coordinator roles Forms Staff and the Read Only role
 * Forms Read Only, at install, at Turn on and with the hourly access check.
 */
@IsTest(testFor='ApexClass:FormsAccessSync')
private class FormsAccessSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** The people, by last name: one per role, and one with none. */
	private static Map<String, Id> people() {
		Map<String, Id> ids = new Map<String, Id>{
			'Outsider' => TestUsers.standardUser('Outsider').Id
		};
		Map<String, String> groupByName = new Map<String, String>{
			'Coordinator' => 'Volunteer_Coordinator',
			'Member' => 'Program_Staff',
			'Reader' => 'Read_Only',
			'Boss' => 'BarnCRM_Admin_Group'
		};
		List<PermissionSetAssignment> roles = new List<PermissionSetAssignment>();
		for (String name : groupByName.keySet()) {
			Id userId = TestUsers.standardUser(name).Id;
			ids.put(name, userId);
			roles.add(
				new PermissionSetAssignment(
					AssigneeId = userId,
					PermissionSetGroupId = TestDataFactory.prepareRoleGroup(groupByName.get(name))
						.Id
				)
			);
		}
		insert roles;
		return ids;
	}

	private static Set<String> setsOf(Id userId) {
		Set<String> names = new Set<String>();
		for (PermissionSetAssignment row : [
			SELECT PermissionSet.Name
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Forms_%'
			WITH SYSTEM_MODE
		]) {
			names.add(row.PermissionSet.Name);
		}
		return names;
	}

	@IsTest
	static void givesEachRoleItsFormsSet() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			Boolean more = FormsAccessSync.syncOnce();
			Boolean again = FormsAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isFalse(again, 'And a second pass finds nothing to give');
			Map<String, String> expected = new Map<String, String>{
				'Coordinator' => 'Forms_Staff',
				'Member' => 'Forms_Staff',
				'Reader' => 'Forms_Read_Only',
				'Boss' => FormsAccessSync.ADMIN_SET
			};
			for (String name : expected.keySet()) {
				Assert.areEqual(
					new Set<String>{ expected.get(name) },
					setsOf(ids.get(name)),
					name + ' gets their role\'s set and no other'
				);
			}
			Assert.isTrue(setsOf(ids.get('Outsider')).isEmpty(), 'No role, no set');
		}
	}

	@IsTest
	static void theHourlyAccessCheckQueuesTheSync() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			// What Core's hourly access check (TabAccessScheduler) asks of every module.
			ModuleAccessSyncs.requestAll();
			Test.stopTest();

			Assert.isTrue(
				setsOf(ids.get('Member')).contains('Forms_Staff'),
				'Someone given a role since the install gets the set within the hour'
			);
		}
	}

	/** ADR-NEXT D3: Fundraising Staff (Giving's role, when installed) gets Forms Staff. */
	@IsTest
	static void fundraisingStaffGetsFormsStaff() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			List<String> roles = FormsAccessSync.BY_ROLE.get('Forms_Staff');
			Test.stopTest();

			Assert.isTrue(roles.contains('Fundraising_Staff'), 'Fundraisers fill in forms');
			Assert.isTrue(roles.contains('Program_Staff'), 'As Team Members do');
		}
	}
}
