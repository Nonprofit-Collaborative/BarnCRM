/**
 * The Hours part of the engagement score counts each person's Approved hours in the window
 * (C-64, canonical model R-ES2), and Core finds it by name.
 */
@IsTest(testFor='ApexClass:VolunteersEngagementSignal')
private class VolunteersEngagementSignalTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.job('Food pantry sort');
		}
	}

	@IsTest
	static void sumsApprovedHoursInTheWindowOnly() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Id jobId = [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
			Contact ana = VolunteersTestData.contact('Rivera', null);
			List<Volunteer_Hours__c> hours = new List<Volunteer_Hours__c>{
				VolunteersTestData.newHours(ana.Id, jobId, 3),
				VolunteersTestData.newHours(ana.Id, jobId, 4),
				VolunteersTestData.newHours(ana.Id, jobId, 5)
			};
			hours[0].Date_Worked__c = Date.today().addDays(-3);
			hours[1].Date_Worked__c = Date.today().addYears(-2);
			hours[2].Date_Worked__c = Date.today().addDays(-1);
			VolunteersTestData.volunteerSettings(true, false);
			insert hours;
			VolunteerHoursService.approve(new Set<Id>{ hours[0].Id, hours[1].Id });

			Test.startTest();
			EngagementSignalExtension signal = (EngagementSignalExtension) NamespaceUtil.resolveType(
					'VolunteersEngagementSignal'
				)
				.newInstance();
			Map<Id, Decimal> totals = signal.totals(
				new Set<Id>{ ana.Id },
				Date.today().addMonths(-12)
			);
			Test.stopTest();

			Assert.areEqual('Hours', signal.key(), 'The Hours part');
			Assert.areEqual(3, totals.get(ana.Id), 'Only Approved hours in the window count');
		}
	}
}
