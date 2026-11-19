/**
 * One org-wide date for Core date rules (plan D-208, N-03): today is read in the org's time
 * zone, whoever is running. Pacific/Kiritimati (UTC+14) and Pacific/Honolulu (UTC-10) are
 * exactly 24 hours apart and keep no daylight saving, so a person in Honolulu is always one
 * calendar day behind an org in Kiritimati, at any hour the test runs.
 */
@IsTest(testFor='ApexClass:OrgDate')
private class OrgDateTest {
	private static final String ORG_ZONE = 'Pacific/Kiritimati';
	private static final String USER_ZONE = 'Pacific/Honolulu';

	private static User personInHonolulu() {
		User person = TestUsers.admin();
		person.TimeZoneSidKey = USER_ZONE;
		System.runAs(new User(Id = UserInfo.getUserId())) {
			update person;
		}
		return person;
	}

	private static void orgIn(String zoneId) {
		OrgDate.zoneOverride = zoneId;
		OrgDate.todayOverride = null;
		OrgDate.reset();
	}

	@IsTest
	static void todayIsTheOrgDateNotTheRunningUsersDate() {
		User person = personInHonolulu();
		orgIn(ORG_ZONE);

		System.runAs(person) {
			Assert.areEqual(
				Date.today().addDays(1),
				OrgDate.today(),
				'A person a day behind the org still gets the org date'
			);
			Assert.areEqual(ORG_ZONE, OrgDate.zone().getID(), 'The org time zone is used');
		}
	}

	@IsTest
	static void everyoneGetsTheSameDate() {
		User person = personInHonolulu();
		orgIn(ORG_ZONE);
		Date mine = OrgDate.today();

		Date theirs;
		System.runAs(person) {
			OrgDate.reset();
			theirs = OrgDate.today();
		}

		Assert.areEqual(mine, theirs, 'Two people in different time zones read one date');
	}

	@IsTest
	static void aMomentFallsOnTheDateOfTheZone() {
		// runs-as: deploying user (pure date arithmetic, no DML or SOQL)
		Datetime earlyNewYear = Datetime.newInstanceGmt(2026, 1, 1, 5, 0, 0);

		Assert.areEqual(
			Date.newInstance(2025, 12, 31),
			OrgDate.dateIn(earlyNewYear, TimeZone.getTimeZone('America/Los_Angeles')),
			'Still New Year Eve in Los Angeles'
		);
		Assert.areEqual(
			Date.newInstance(2026, 1, 1),
			OrgDate.dateIn(earlyNewYear, TimeZone.getTimeZone('GMT')),
			'Already New Year in London'
		);
	}

	@IsTest
	static void readsTheOrgTimeZoneWithoutAnOverride() {
		// runs-as: deploying user (reads the org's own time zone, the same for every user)
		orgIn(null);
		String expected = [SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1].TimeZoneSidKey;

		Assert.areEqual(expected, OrgDate.zone().getID(), 'The org default time zone');
		Assert.areEqual(
			OrgDate.dateIn(Datetime.now(), TimeZone.getTimeZone(expected)),
			OrgDate.today(),
			'Today in the org default time zone'
		);
	}

	@IsTest
	static void aTestCanFixToday() {
		// runs-as: deploying user (a static override, no DML or SOQL)
		OrgDate.todayOverride = Date.newInstance(2030, 6, 15);

		Assert.areEqual(Date.newInstance(2030, 6, 15), OrgDate.today(), 'The fixed date');
	}

	/**
	 * The rule that found the problem: a membership ended today, org-wide, is no longer
	 * current, even to a person whose own date is still yesterday.
	 */
	@IsTest
	static void aMembershipEndedTodayIsOverForAPersonADayBehind() {
		User person = personInHonolulu();
		orgIn(ORG_ZONE);

		System.runAs(person) {
			HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
			Account household = HouseholdTestDataFactory.newHousehold('Org Date');
			Database.insert(household, AccessLevel.SYSTEM_MODE);
			Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Org Date');
			insert ana;
			insert new Household_Member__c(
				Household__c = household.Id,
				Contact__c = ana.Id,
				Role__c = 'Head',
				Start_Date__c = OrgDate.today().addDays(-30),
				End_Date__c = OrgDate.today()
			);
			Assert.isTrue(OrgDate.today() > Date.today(), 'By her own date the membership has not ended yet');

			Assert.areEqual(
				0,
				CoexistenceService.countPeopleWithMembershipRecords(),
				'Ended today in the org, so not current for anyone'
			);
		}
	}
}
