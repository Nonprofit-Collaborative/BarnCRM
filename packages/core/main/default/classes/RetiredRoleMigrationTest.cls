/**
 * Holders of the retired Coordinator role are given Team Member (ADR-NEXT, simpler permission
 * sets, D1): active ones by the tab access job, inactive ones only named in the Error Log, and
 * nothing is ever taken away.
 */
@IsTest(testFor='ApexClass:RetiredRoleMigration')
private class RetiredRoleMigrationTest {
	private static final String COORDINATOR = 'Volunteer_Coordinator';
	private static final String TEAM_MEMBER = 'Program_Staff';

	@TestSetup
	static void createTestUsers() {
		System.runAs(TestUsers.admin()) {
			TestUsers.standardUser('Priya');
			TestUsers.standardUser('Both');
			TestUsers.standardUser('Gone');
		}
	}

	@IsTest
	static void activeCoordinatorsGetTeamMemberAndKeepCoordinator() {
		System.runAs(TestUsers.admin()) {
			Id coordinator = TestDataFactory.prepareRoleGroup(COORDINATOR).Id;
			Id teamMember = TestDataFactory.prepareRoleGroup(TEAM_MEMBER).Id;
			Id priya = userId('Priya');
			Id both = userId('Both');
			Id gone = userId('Gone');
			insert new List<PermissionSetAssignment>{
				assignment(priya, coordinator),
				assignment(both, coordinator),
				assignment(both, teamMember),
				assignment(gone, coordinator)
			};
			deactivate(gone);

			Test.startTest();
			RetiredRoleMigration.carryOver(100);
			RetiredRoleMigration.carryOver(100);
			Test.stopTest();

			Assert.areEqual(1, rows(priya, teamMember), 'Priya now holds Team Member');
			Assert.areEqual(1, rows(priya, coordinator), 'And still holds Coordinator');
			Assert.areEqual(1, rows(both, teamMember), 'Someone holding both is left alone');
			Assert.areEqual(0, rows(gone, teamMember), 'An inactive holder is never tried');
			Assert.areEqual(1, rows(gone, coordinator), 'And keeps Coordinator');
		}
	}

	@IsTest
	static void inactiveHoldersAreNamedNotGivenAndNothingThrows() {
		System.runAs(TestUsers.admin()) {
			Id coordinator = TestDataFactory.prepareRoleGroup(COORDINATOR).Id;
			Id teamMember = TestDataFactory.prepareRoleGroup(TEAM_MEMBER).Id;
			Id gone = userId('Gone');
			insert new List<PermissionSetAssignment>{
				assignment(gone, coordinator),
				assignment(userId('Priya'), coordinator)
			};
			deactivate(gone);
			String goneName = [SELECT Name FROM User WHERE Id = :gone].Name;

			Test.startTest();
			List<String> messages = RetiredRoleMigration.logInactiveHolders();
			Test.stopTest();

			Assert.areEqual(1, messages.size(), 'Only the inactive holder is named: ' + messages);
			Assert.isTrue(messages[0].contains(goneName), 'By name: ' + messages[0]);
			Assert.isTrue(messages[0].contains('Team Member'), 'With the role to give later');
			Assert.areEqual(0, rows(gone, teamMember), 'Reading only: nothing is given');
		}
	}

	@IsTest
	static void aRefusedAssignmentIsLoggedByNameAndADuplicateIsNot() {
		System.runAs(TestUsers.admin()) {
			PermissionSetGroup teamMember = TestDataFactory.prepareRoleGroup(TEAM_MEMBER);
			teamMember = [
				SELECT Id, DeveloperName, MasterLabel, Status
				FROM PermissionSetGroup
				WHERE Id = :teamMember.Id
			];
			PermissionSetGroup retired = new PermissionSetGroup(
				MasterLabel = 'Coordinator (Retired)'
			);
			List<RetiredRoleMigration.Holder> tried = new List<RetiredRoleMigration.Holder>();
			for (User person : [
				SELECT Id, Name, IsActive
				FROM User
				WHERE LastName IN ('Gone', 'Priya', 'Both')
				ORDER BY LastName DESC
			]) {
				tried.add(new RetiredRoleMigration.Holder(person.Id, person, retired, teamMember));
			}
			// Salesforce's answer for an inactive user, a duplicate, and a success, as the
			// platform would return them; a test cannot make Salesforce refuse on demand.
			List<Database.SaveResult> results = new List<Database.SaveResult>{
				saveResult(false, 'INACTIVE_OWNER_OR_USER', 'inactive user'),
				saveResult(false, 'DUPLICATE_VALUE', 'duplicate value found'),
				saveResult(true, null, null)
			};

			Test.startTest();
			List<String> messages = RetiredRoleMigration.refusalMessages(tried, results);
			Test.stopTest();

			Assert.areEqual(1, messages.size(), 'Only the refusal is logged: ' + messages);
			Assert.isTrue(messages[0].contains(tried[0].name), 'Names the person: ' + messages[0]);
			Assert.isTrue(messages[0].contains(teamMember.MasterLabel), 'And the role to give');
			Assert.isTrue(messages[0].contains('inactive user'), 'And what Salesforce said');
		}
	}

	@IsTest
	static void theTabAccessJobCarriesCoordinatorsOver() {
		System.runAs(TestUsers.admin()) {
			Id coordinator = TestDataFactory.prepareRoleGroup(COORDINATOR).Id;
			Id teamMember = TestDataFactory.prepareRoleGroup(TEAM_MEMBER).Id;
			Id priya = userId('Priya');
			insert assignment(priya, coordinator);

			Test.startTest();
			System.enqueueJob(new TabAccessService.Job());
			Test.stopTest();

			Assert.areEqual(1, rows(priya, teamMember), 'The install and hourly job gives it');
		}
	}

	private static Id userId(String lastName) {
		return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1].Id;
	}

	private static void deactivate(Id userId) {
		update new User(Id = userId, IsActive = false);
	}

	private static PermissionSetAssignment assignment(Id userId, Id groupId) {
		return new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = groupId);
	}

	private static Integer rows(Id userId, Id groupId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSetGroupId = :groupId
		];
	}

	private static Database.SaveResult saveResult(Boolean success, String code, String message) {
		Map<String, Object> result = new Map<String, Object>{ 'success' => success };
		if (!success) {
			result.put(
				'errors',
				new List<Object>{
					new Map<String, Object>{
						'statusCode' => code,
						'message' => message,
						'fields' => new List<String>()
					}
				}
			);
		}
		return (Database.SaveResult) JSON.deserialize(
			JSON.serialize(result),
			Database.SaveResult.class
		);
	}
}
