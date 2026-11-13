/**
 * Tests for Volunteers Home (vis-modules-19): the three figures and where each one goes, for an
 * administrator and for a person with no Volunteers access.
 */
@IsTest(testFor='ApexClass:VolunteersHomeController')
private class VolunteersHomeControllerTest {
	private static Map<String, VolunteersHomeController.Tile> byName(
		List<VolunteersHomeController.Tile> tiles
	) {
		Map<String, VolunteersHomeController.Tile> found = new Map<String, VolunteersHomeController.Tile>();
		for (VolunteersHomeController.Tile tile : tiles) {
			found.put(tile.name, tile);
		}
		return found;
	}

	@IsTest
	static void anAdministratorSeesHoursThisMonthHoursToApproveAndShiftsNeedingPeople() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			Contact person = VolunteersTestData.contact('Rivera', null);
			Volunteer_Job__c job = VolunteersTestData.job('Food pantry');
			insert VolunteersTestData.newShift(job.Id, Datetime.now().addDays(3), 2);

			VolunteersTestData.volunteerSettings(false, true);
			Volunteer_Hours__c approved = VolunteersTestData.newHours(person.Id, job.Id, 3);
			approved.Date_Worked__c = Date.today();
			insert approved;
			VolunteersTestData.volunteerSettings(true, true);
			Volunteer_Hours__c waiting = VolunteersTestData.newHours(person.Id, job.Id, 2);
			waiting.Date_Worked__c = Date.today();
			insert waiting;

			Test.startTest();
			Map<String, VolunteersHomeController.Tile> tiles = byName(
				VolunteersHomeController.getHome()
			);
			Test.stopTest();

			Assert.areEqual(
				new Set<String>{
					'hoursThisMonth',
					'hoursValueThisMonth',
					'hoursToApprove',
					'shiftsNeedingPeople'
				},
				tiles.keySet(),
				'An administrator reads every figure.'
			);
			Assert.areEqual(3, tiles.get('hoursThisMonth').value, 'Only approved hours count.');
			Assert.areEqual(
				3 * 34.79,
				tiles.get('hoursValueThisMonth').value,
				'V-12: hours times the shipped Hour Value, display only.'
			);
			Assert.isNotNull(tiles.get('hoursValueThisMonth').currencyCode, 'In the org currency.');
			Assert.areEqual(1, tiles.get('hoursToApprove').value, 'One entry waits.');
			Assert.areEqual(
				'Volunteer_Approve_Hours',
				tiles.get('hoursToApprove').tabName,
				'A coordinator goes to Approve Hours.'
			);
			Assert.areEqual(1, tiles.get('shiftsNeedingPeople').value, 'The open shift needs 4.');
			Assert.areEqual(
				VolunteersHomeController.SHIFTS_LIST_VIEW,
				tiles.get('shiftsNeedingPeople').filterName,
				'It opens the list view it counts.'
			);
			Assert.isFalse(tiles.get('hoursToApprove').capped, 'Far below the cap.');
		}
	}

	@IsTest
	static void someoneWithoutVolunteersAccessSeesNoFigures() {
		User outsider = TestUsers.standardUserWith(
			'HomeOutsider',
			new List<String>{ VolunteersTestData.CORE_STAFF }
		);
		List<VolunteersHomeController.Tile> tiles;
		Test.startTest();
		System.runAs(outsider) {
			tiles = VolunteersHomeController.getHome();
		}
		Test.stopTest();
		Assert.isTrue(tiles.isEmpty(), 'No figure is shown as zero to someone who cannot read it.');
	}

	@IsTest
	static void aPicklistValueWithoutAnEntryKeepsItsName() {
		System.runAs(TestUsers.admin()) {
			Assert.areEqual(
				'Missing',
				VolunteersHomeController.picklistLabel(
					Schema.SObjectType.Volunteer_Hours__c.fields.Status__c,
					'Missing'
				),
				'An unknown value is shown as it is.'
			);
		}
	}
}
