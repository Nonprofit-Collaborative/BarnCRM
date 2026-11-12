/**
 * BarnCRM's roles get the Memberships sets: BarnCRM Admin holders Memberships Admin, Team Member
 * Memberships Staff and Read Only Memberships Read Only, at install, at Turn on and hourly.
 */
@IsTest(testFor='ApexClass:MembershipsAccessSync')
private class MembershipsAccessSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Map<String, Id> people() {
		Map<String, Id> ids = new Map<String, Id>{
			'Outsider' => TestUsers.standardUser('Outsider').Id
		};
		Map<String, String> groupByName = new Map<String, String>{
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
			WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Memberships_%'
			WITH SYSTEM_MODE
		]) {
			names.add(row.PermissionSet.Name);
		}
		return names;
	}

	@IsTest
	static void givesEachRoleItsMembershipsSet() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			Boolean more = MembershipsAccessSync.syncOnce();
			Boolean again = MembershipsAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isFalse(again, 'And a second pass finds nothing to give');
			Map<String, String> expected = new Map<String, String>{
				'Member' => 'Memberships_Staff',
				'Reader' => 'Memberships_Read_Only',
				'Boss' => MembershipsAccessSync.ADMIN_SET
			};
			for (String name : expected.keySet()) {
				Assert.areEqual(
					new Set<String>{ expected.get(name) },
					setsOf(ids.get(name)),
					name + ' gets their role\'s set and no other'
				);
			}
			Assert.isTrue(setsOf(ids.get('Outsider')).isEmpty(), 'No role, no set');
			Assert.isTrue(
				MembershipsAccessSync.BY_ROLE.get('Memberships_Staff')
					.contains('Fundraising_Staff'),
				'Fundraisers see memberships, as Team Members do'
			);
		}
	}
}
