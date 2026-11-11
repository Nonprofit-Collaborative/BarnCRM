/**
 * Ade, a board member with no Salesforce login, uses the board portal: marks the packet read,
 * approves submitted minutes, votes while voting is open, and acknowledges the conflict-of-interest
 * policy (PB-02, CH-18). Each action touches only Ade's own row and refuses what is closed.
 */
@IsTest(testFor='ApexClass:CorporateHubPortalExtension')
private class CorporateHubPortalExtensionTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(ADMIN_SET);
	}

	private static CorporateHubPortalExtension portal() {
		return new CorporateHubPortalExtension();
	}

	@IsTest
	static void adeReadsApprovesVotesAndAcknowledges() {
		Contact ade;
		Contact bea;
		Meeting_Attendee__c attendee;
		Board_Vote__c vote;
		Policy_Acknowledgment__c request;
		Board_Meeting__c meeting;
		Board_Motion__c motion;
		System.runAs(staff()) {
			ade = new Contact(FirstName = 'Ade', LastName = 'Member');
			bea = new Contact(FirstName = 'Bea', LastName = 'Member');
			insert as user new List<Contact>{ ade, bea };
			Board__c board = new Board__c(Name = 'Board', Type__c = 'Board', Status__c = 'Active');
			insert as user board;
			meeting = new Board_Meeting__c(
				Name = 'March',
				Board__c = board.Id,
				Status__c = 'Held',
				Minutes_Status__c = 'Draft'
			);
			insert as user meeting;
			attendee = new Meeting_Attendee__c(
				Meeting__c = meeting.Id,
				Person__c = ade.Id,
				Attendance__c = 'Present',
				Voting__c = true,
				Key__c = meeting.Id + ':' + ade.Id
			);
			insert as user attendee;
			motion = new Board_Motion__c(
				Meeting__c = meeting.Id,
				Name = 'Budget',
				Status__c = HubBoard.VOTING_OPEN
			);
			insert as user motion;
			vote = new Board_Vote__c(
				Motion__c = motion.Id,
				Person__c = ade.Id,
				Key__c = motion.Id + ':' + ade.Id
			);
			insert as user vote;
			Hub_Document__c policy = new Hub_Document__c(
				Name = 'Conflict of Interest',
				Type__c = 'Policy',
				Status__c = 'Active',
				Version__c = 1
			);
			insert as user policy;
			request = new Policy_Acknowledgment__c(
				Document__c = policy.Id,
				Version__c = 1,
				Person__c = ade.Id,
				Status__c = HubPolicy.REQUESTED,
				Key__c = policy.Id + ':1:' + ade.Id
			);
			insert as user request;
		}
		// The portal's integration user holds no Corporate Hub access and no Manage permission.
		User integration = TestUsers.minimumAccessUserWith('Integration', new List<String>());
		System.runAs(integration) {
			Assert.isTrue(
				portal().actionNames().contains(CorporateHubPortalExtension.ACKNOWLEDGE),
				'Offered'
			);
			portal().run(CorporateHubPortalExtension.PACKET, ade.Id, attendee.Id);
			String closed = portal().run(CorporateHubPortalExtension.MINUTES, ade.Id, attendee.Id);
			Assert.areEqual(
				BarnHelp.text('CorporateHub', 'CorporateHub_Portal_MinutesClosed'),
				closed,
				'Draft minutes are not approvable'
			);
		}
		System.runAs(staff()) {
			update as user new Board_Meeting__c(
				Id = meeting.Id,
				Minutes_Status__c = HubBoard.MINUTES_SUBMITTED
			);
		}
		System.runAs(integration) {
			portal().run(CorporateHubPortalExtension.MINUTES, ade.Id, attendee.Id);
			portal().run('CorporateHub.VoteAgainst', ade.Id, vote.Id);
			portal().run(CorporateHubPortalExtension.ACKNOWLEDGE, ade.Id, request.Id);
			try {
				portal().run(CorporateHubPortalExtension.PACKET, bea.Id, attendee.Id);
				Assert.fail('Bea cannot act on Ade\'s row');
			} catch (QueryException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused');
			}
		}
		System.runAs(staff()) {
			update as user new Board_Motion__c(Id = motion.Id, Status__c = 'Failed');
		}
		System.runAs(integration) {
			Assert.areEqual(
				BarnHelp.text('CorporateHub', 'CorporateHub_Portal_VotingClosed'),
				portal().run('CorporateHub.VoteFor', ade.Id, vote.Id),
				'No vote after voting closes'
			);
		}
		Meeting_Attendee__c savedAttendee = [
			SELECT Packet_Read_On__c, Minutes_Approved_On__c
			FROM Meeting_Attendee__c
			WHERE Id = :attendee.Id
			WITH SYSTEM_MODE
		];
		Assert.isNotNull(savedAttendee.Packet_Read_On__c, 'Packet read (CH-18)');
		Assert.isNotNull(savedAttendee.Minutes_Approved_On__c, 'Minutes approved');
		Board_Vote__c savedVote = [
			SELECT Vote__c, Voted_On__c
			FROM Board_Vote__c
			WHERE Id = :vote.Id
			WITH SYSTEM_MODE
		];
		Assert.areEqual('Against', savedVote.Vote__c, 'The vote cast while open stands');
		Assert.isNotNull(savedVote.Voted_On__c, 'Dated');
		Policy_Acknowledgment__c savedRequest = [
			SELECT Status__c, Answered_In_Portal__c
			FROM Policy_Acknowledgment__c
			WHERE Id = :request.Id
			WITH SYSTEM_MODE
		];
		Assert.areEqual(HubPolicy.ACKNOWLEDGED, savedRequest.Status__c, 'Acknowledged');
		Assert.isTrue(savedRequest.Answered_In_Portal__c, 'Marked as answered in the portal');
	}
}
