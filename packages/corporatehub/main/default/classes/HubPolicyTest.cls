/**
 * Maria publishes the conflict of interest policy and asks the team to read it; Sam, on the
 * program staff, says he has read it; a new version asks everyone again (R-HD1, R-PAK1 to R-PAK3).
 */
@IsTest(testFor='ApexClass:HubPolicy')
private class HubPolicyTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Hub_Document__c policy(String status, Boolean needsAcknowledgment) {
		Hub_Document__c document = new Hub_Document__c(
			Name = 'Conflict of Interest',
			Type__c = 'Policy',
			Status__c = status,
			Version__c = 1,
			Review_Months__c = 24,
			Requires_Acknowledgment__c = needsAcknowledgment
		);
		insert document;
		return document;
	}

	private static User staffer() {
		return TestUsers.standardUserWith(
			'Sam',
			new List<String>{ 'BarnCRM_Staff', 'Corporate_Hub_Staff' }
		);
	}

	private static List<Policy_Acknowledgment__c> requests(Id documentId) {
		return [
			SELECT User__c, Version__c, Status__c, Due_Date__c, OwnerId
			FROM Policy_Acknowledgment__c
			WHERE Document__c = :documentId
			WITH SYSTEM_MODE
			ORDER BY Version__c
		];
	}

	@IsTest
	static void everyoneWithARoleIsAskedOnceAndCanSayTheyHaveReadIt() {
		User sam = staffer();
		Hub_Document__c document;
		Integer asked;
		Integer askedAgain;
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			document = policy('Active', true);
			asked = HubPolicy.requestAcknowledgments(document.Id, null);
			askedAgain = HubPolicy.requestAcknowledgments(document.Id, '');
		}
		Assert.isTrue(asked >= 2, 'Sam and Maria both hold a BarnCRM set: ' + asked);
		Assert.areEqual(0, askedAgain, 'Nobody is asked twice for one version');
		Assert.isTrue(HubReminders.sentTitles.size() >= 1, 'The bell went off');

		System.runAs(sam) {
			List<Policy_Acknowledgment__c> mine = HubPolicy.myRequests();
			Assert.areEqual(1, mine.size(), 'Sam sees his own request');
			Assert.areEqual(
				Date.today().addDays(30),
				mine[0].Due_Date__c,
				'Due in the shipped 30 days'
			);
			HubPolicy.acknowledge(mine[0].Id);
			Assert.areEqual(0, HubPolicy.myRequests().size(), 'Nothing left to read');
			try {
				HubPolicy.acknowledge(mine[0].Id);
				Assert.fail('A done request cannot be done again');
			} catch (HubPolicy.PolicyException expected) {
				Assert.isNotNull(expected.getMessage(), 'Told why');
			}
		}
		Policy_Acknowledgment__c samsRow = [
			SELECT Status__c, Acknowledged_On__c, OwnerId
			FROM Policy_Acknowledgment__c
			WHERE User__c = :sam.Id
			WITH SYSTEM_MODE
		];
		Assert.areEqual(HubPolicy.ACKNOWLEDGED, samsRow.Status__c, 'Recorded');
		Assert.isNotNull(samsRow.Acknowledged_On__c, 'With the time');
		Assert.areEqual(sam.Id, samsRow.OwnerId, 'Sam owns his request, so he can see it');
	}

	@IsTest
	static void staffCannotAskAndADraftCannotBeAskedFor() {
		User sam = staffer();
		Hub_Document__c draft;
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			draft = policy('Draft', true);
			try {
				HubPolicy.requestAcknowledgments(draft.Id, null);
				Assert.fail('A draft asks nobody');
			} catch (HubPolicy.PolicyException expected) {
				Assert.areEqual(0, requests(draft.Id).size(), 'Nobody asked');
			}
		}
		System.runAs(sam) {
			Assert.isFalse(HubPolicy.canManage(), 'Staff do not manage the library');
			try {
				HubPolicy.retire(draft.Id);
				Assert.fail('Only a manager retires');
			} catch (HubPolicy.PolicyException expected) {
				Assert.isNotNull(expected.getMessage(), 'Told why');
			}
		}
	}

	@IsTest
	static void aNewVersionSupersedesTheOldRequestsAndAsksTheSamePeopleAgain() {
		User sam = staffer();
		Hub_Document__c document;
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			document = policy('Active', true);
			HubPolicy.requestAcknowledgments(document.Id, null);
			Integer firstRound = requests(document.Id).size();

			HubPolicy.publishNewVersion(document.Id);

			Hub_Document__c after = HubPolicy.document(document.Id);
			Assert.areEqual(2, after.Version__c, 'Version 2');
			Assert.areEqual(Date.today(), after.Effective_Date__c, 'Effective today');
			Integer superseded = 0;
			Integer open = 0;
			for (Policy_Acknowledgment__c row : requests(document.Id)) {
				if (row.Version__c == 1) {
					Assert.areEqual(HubPolicy.SUPERSEDED, row.Status__c, 'Version 1 is closed');
					superseded++;
				} else {
					Assert.areEqual(HubPolicy.REQUESTED, row.Status__c, 'Version 2 is asked');
					open++;
				}
			}
			Assert.areEqual(firstRound, superseded, 'Every old request closed');
			Assert.areEqual(firstRound, open, 'The same people asked again');
		}
	}

	@IsTest
	static void reviewingMovesTheNextReviewAndRetiringClosesOpenRequests() {
		staffer();
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Hub_Document__c document = policy('Active', true);
			HubPolicy.requestAcknowledgments(document.Id, null);

			HubPolicy.markReviewed(document.Id);
			Hub_Document__c reviewed = HubPolicy.document(document.Id);
			Assert.areEqual(
				Date.today().addMonths(24),
				reviewed.Review_Date__c,
				'Next review in 24 months'
			);

			HubPolicy.retire(document.Id);
			Assert.areEqual('Retired', HubPolicy.document(document.Id).Status__c, 'Retired');
			for (Policy_Acknowledgment__c row : requests(document.Id)) {
				Assert.areEqual(
					HubPolicy.SUPERSEDED,
					row.Status__c,
					'A retired policy asks no one'
				);
			}
		}
	}

	@IsTest
	static void aPublicGroupNarrowsWhoIsAsked() {
		User sam = staffer();
		User outsider = TestUsers.standardUserWith(
			'Riley',
			new List<String>{ 'Corporate_Hub_Staff' }
		);
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Group board = new Group(
				Name = 'Hub Test Board',
				DeveloperName = 'Hub_Test_Board',
				Type = 'Regular'
			);
			insert board;
			insert new GroupMember(GroupId = board.Id, UserOrGroupId = sam.Id);
		}
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Hub_Document__c document = policy('Active', true);
			Integer asked = HubPolicy.requestAcknowledgments(document.Id, 'Hub_Test_Board');

			Assert.areEqual(1, asked, 'Only the group member');
			List<Policy_Acknowledgment__c> rows = requests(document.Id);
			Assert.areEqual(sam.Id, rows[0].User__c, 'Sam');
			Assert.areNotEqual(outsider.Id, rows[0].User__c, 'Not Riley');
		}
	}
}
