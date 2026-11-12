/**
 * Maria runs the board of directors: three current seats and one ended, a meeting with the
 * board invited and quorum counted, minutes submitted and approved, a motion voted and closed,
 * an availability poll, an action item carried to the next meeting, a self-assessment and the
 * annual conflict-of-interest disclosure (CH-09 to CH-17, CH-19, CH-20; R-BM1, R-BMT1 to
 * R-BMT4, R-MO1, R-AI1, R-BA1, R-PAK4).
 */
@IsTest(testFor='ApexClass:HubBoard, ApexClass:HubBoardController')
private class HubBoardTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static User maria() {
		return TestUsers.adminWith(ADMIN_SET);
	}

	/** A board with three current voting seats and one that ended last year. */
	private static Board__c board() {
		Board__c board = new Board__c(
			Name = 'Board of Directors',
			Type__c = 'Board',
			Status__c = 'Active',
			Term_Limit__c = 2,
			Quorum_Percent__c = 51,
			Needed_Skills__c = 'Finance;Legal'
		);
		insert as user board;
		List<Contact> people = new List<Contact>();
		for (String name : new List<String>{ 'Ade', 'Bea', 'Cy', 'Dee' }) {
			people.add(new Contact(FirstName = name, LastName = 'Member'));
		}
		insert as user people;
		List<Board_Member__c> seats = new List<Board_Member__c>();
		for (Integer i = 0; i < 3; i++) {
			seats.add(
				new Board_Member__c(
					Board__c = board.Id,
					Person__c = people[i].Id,
					Role__c = i == 0 ? 'Chair' : 'Member',
					Term_Start__c = Date.today().addYears(-1),
					Term_End__c = Date.today().addYears(2),
					Term_Number__c = i == 0 ? 2 : 1,
					Skills__c = 'Finance'
				)
			);
		}
		seats.add(
			new Board_Member__c(
				Board__c = board.Id,
				Person__c = people[3].Id,
				Role__c = 'Member',
				Term_Start__c = Date.today().addYears(-4),
				Term_End__c = Date.today().addYears(-1)
			)
		);
		insert as user seats;
		return board;
	}

	private static Board_Meeting__c meeting(Id boardId, Integer inDays) {
		Board_Meeting__c meeting = new Board_Meeting__c(
			Name = 'Board Meeting',
			Board__c = boardId,
			Status__c = 'Planned',
			Minutes_Status__c = 'Draft',
			Start__c = inDays == null ? null : Datetime.now().addDays(inDays)
		);
		insert as user meeting;
		return meeting;
	}

	@IsTest
	static void theBoardIsInvitedQuorumCountedAndMinutesApproved() {
		System.runAs(maria()) {
			Board__c board = board();
			Board_Meeting__c meeting = meeting(board.Id, 7);
			Assert.areEqual(3, HubBoardController.inviteBoard(meeting.Id), 'Only current seats');
			Assert.areEqual(0, HubBoard.inviteBoard(meeting.Id), 'Nobody is invited twice');

			HubBoardController.MeetingView view = HubBoardController.getMeeting(meeting.Id);
			Assert.areEqual(3, view.attendees.size(), 'Three attendees');
			Assert.areEqual(2, view.meeting.Quorum_Needed__c, 'Two of three is quorum at 51%');
			Assert.isFalse(view.meeting.Quorum_Met__c, 'Nobody is present yet');

			HubBoardController.setAttendance(view.attendees[0].id, 'Present');
			HubBoardController.setAttendance(view.attendees[1].id, 'Present');
			Assert.isTrue(HubBoard.meeting(meeting.Id).Quorum_Met__c, 'Two present meets quorum');

			HubBoardController.setMinutesStatus(meeting.Id, HubBoard.MINUTES_SUBMITTED);
			HubBoardController.setMinutesStatus(meeting.Id, HubBoard.MINUTES_APPROVED);
			Board_Meeting__c saved = [
				SELECT Minutes_Status__c, Minutes_Approved_On__c
				FROM Board_Meeting__c
				WHERE Id = :meeting.Id
				WITH USER_MODE
			];
			Assert.areEqual('Approved', saved.Minutes_Status__c, 'Approved');
			Assert.areEqual(Date.today(), saved.Minutes_Approved_On__c, 'Approval dated today');
		}
	}

	@IsTest
	static void aMotionIsVotedAndClosedAndVotesLockWhenClosed() {
		System.runAs(maria()) {
			Board__c board = board();
			Board_Meeting__c meeting = meeting(board.Id, 0);
			HubBoard.inviteBoard(meeting.Id);
			Board_Motion__c motion = new Board_Motion__c(
				Meeting__c = meeting.Id,
				Name = 'Approve the budget',
				Status__c = 'Proposed'
			);
			insert as user motion;
			Assert.areEqual(
				3,
				HubBoardController.openVoting(motion.Id),
				'One vote per voting member'
			);
			Assert.areEqual(0, HubBoard.openVoting(motion.Id), 'Opening again adds nobody');
			List<Board_Vote__c> votes = [
				SELECT Id
				FROM Board_Vote__c
				WHERE Motion__c = :motion.Id
				WITH USER_MODE
			];
			votes[0].Vote__c = 'For';
			votes[1].Vote__c = 'For';
			votes[2].Vote__c = 'Against';
			update as user votes;
			HubBoard.CloseResult result = HubBoardController.closeVoting(motion.Id);
			Assert.areEqual('Passed', result.outcome, 'Two for, one against');
			Board_Motion__c closed = [
				SELECT Decided_On__c, Votes_For__c, Closed_Without_Quorum__c
				FROM Board_Motion__c
				WHERE Id = :motion.Id
				WITH USER_MODE
			];
			Assert.areEqual(Date.today(), closed.Decided_On__c, 'Decided today');
			Assert.areEqual(2, closed.Votes_For__c, 'Counted by roll-up');
			// CH-21: nobody was marked present, so the vote still counts but warns.
			Assert.isNotNull(result.warning, 'No quorum warns');
			Assert.isTrue(closed.Closed_Without_Quorum__c, 'The motion records it');
			try {
				HubBoard.closeVoting(motion.Id);
				Assert.fail('A closed motion cannot be closed again');
			} catch (HubPolicy.PolicyException expected) {
				Assert.isNotNull(expected.getMessage(), 'Told why');
			}
		}
	}

	@IsTest
	static void closingWithQuorumGivesNoWarning() {
		System.runAs(maria()) {
			Board_Meeting__c meeting = meeting(board().Id, 0);
			HubBoard.inviteBoard(meeting.Id);
			for (Meeting_Attendee__c attendee : [
				SELECT Id
				FROM Meeting_Attendee__c
				WHERE Meeting__c = :meeting.Id
				WITH USER_MODE
			]) {
				HubBoardController.setAttendance(attendee.Id, 'Present');
			}
			Board_Motion__c motion = new Board_Motion__c(
				Meeting__c = meeting.Id,
				Name = 'Approve the budget',
				Status__c = 'Proposed'
			);
			insert as user motion;
			HubBoard.openVoting(motion.Id);
			HubBoard.CloseResult result = HubBoard.closeVoting(motion.Id);
			Assert.areEqual('Failed', result.outcome, 'No votes were cast');
			Assert.isNull(result.warning, 'Quorum was met');
			Assert.isFalse(
				[
					SELECT Closed_Without_Quorum__c
					FROM Board_Motion__c
					WHERE Id = :motion.Id
					WITH USER_MODE
				]
				.Closed_Without_Quorum__c,
				'Not flagged'
			);
		}
	}

	@IsTest
	static void aMotionNotOpenForVotingCannotBeClosed() {
		System.runAs(maria()) {
			Board_Meeting__c meeting = meeting(board().Id, 0);
			Board_Motion__c motion = new Board_Motion__c(
				Meeting__c = meeting.Id,
				Name = 'Approve the budget',
				Status__c = 'Proposed'
			);
			insert as user motion;
			try {
				HubBoard.closeVoting(motion.Id);
				Assert.fail('Voting was never opened');
			} catch (HubPolicy.PolicyException expected) {
				Assert.isNotNull(expected.getMessage(), 'Told why');
			}
		}
	}

	@IsTest
	static void thePollChoosesATimeAndItemsCarryForward() {
		System.runAs(maria()) {
			Board__c board = board();
			Board_Meeting__c first = meeting(board.Id, -30);
			Board_Meeting__c next = meeting(board.Id, null);
			try {
				HubBoardController.sendPoll(next.Id);
				Assert.fail('A poll needs a time');
			} catch (AuraHandledException expected) {
				Assert.isNotNull(expected.getMessage(), 'Told why');
			}
			Datetime chosen = Datetime.now().addDays(14);
			update as user new Board_Meeting__c(
				Id = next.Id,
				Poll_Time_1__c = chosen.addDays(-1),
				Poll_Time_2__c = chosen
			);
			HubBoardController.sendPoll(next.Id);
			Assert.isTrue(HubBoard.meeting(next.Id).Poll_Open__c, 'Open');
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Meeting_Attendee__c
					WHERE Meeting__c = :next.Id
					WITH USER_MODE
				],
				'The board was invited for the poll'
			);
			HubBoardController.chooseTime(next.Id, 2);
			Board_Meeting__c fixed = HubBoard.meeting(next.Id);
			Assert.areEqual(chosen, fixed.Start__c, 'The second time');
			Assert.isFalse(fixed.Poll_Open__c, 'Closed');

			insert as user new Meeting_Action_Item__c(
				Board__c = board.Id,
				Meeting__c = first.Id,
				Name = 'Send the audit letter',
				Status__c = 'Open'
			);
			insert as user new Meeting_Action_Item__c(
				Board__c = board.Id,
				Meeting__c = next.Id,
				Name = 'Raised at the next one',
				Status__c = 'Open'
			);
			HubBoardController.MeetingView view = HubBoardController.getMeeting(next.Id);
			Assert.areEqual(1, view.carried.size(), 'The earlier meeting\'s open item is carried');
			Assert.areEqual('Send the audit letter', view.carried[0].name, 'By name');
			Assert.areEqual(2, view.pollTimes.size(), 'Two poll times shown');
		}
	}

	@IsTest
	static void theBoardPanelShowsSeatsGapsAndAStartedSelfAssessment() {
		System.runAs(maria()) {
			Board__c board = board();
			HubBoardController.BoardView view = HubBoardController.getBoard(board.Id);
			Assert.areEqual(3, view.seats.size(), 'The ended seat is not current');
			Assert.areEqual(
				new List<String>{ 'Finance', 'Legal' },
				view.neededSkills,
				'Skills wanted'
			);
			Assert.isTrue(view.seats[0].flag, 'The chair is at the two-term limit');
			Assert.isFalse(view.showDemographics, 'Demographics ship off');
			Id assessmentId = HubBoardController.startAssessment(board.Id);
			Integer answers = [
				SELECT COUNT()
				FROM Assessment_Answer__c
				WHERE Assessment__c = :assessmentId
				WITH USER_MODE
			];
			Assert.isTrue(
				answers > 0 && Math.mod(answers, 3) == 0,
				'Every question for each of three seats: ' + answers
			);
		}
	}

	@IsTest
	static void thePanelsShowDemographicsActionItemsAttendeeMarksAndMotions() {
		System.runAs(maria()) {
			insert new Corporate_Hub_Settings__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Board_Demographics__c = true
			);
			SettingsService.clearCaches();
			Board__c board = board();
			Board_Member__c seat = [
				SELECT Id, Person__c
				FROM Board_Member__c
				WHERE Board__c = :board.Id AND Role__c = 'Chair'
				WITH USER_MODE
			];
			update as user new Board_Member__c(
				Id = seat.Id,
				Age_Range__c = '45 to 59',
				Gender__c = 'Woman'
			);
			Board_Meeting__c meeting = meeting(board.Id, 0);
			HubBoard.inviteBoard(meeting.Id);
			insert as user new Meeting_Action_Item__c(
				Board__c = board.Id,
				Meeting__c = meeting.Id,
				Name = 'File the 990',
				Status__c = 'Open',
				Assigned_To__c = seat.Person__c,
				Due_Date__c = Date.today().addDays(10)
			);
			insert as user new Board_Motion__c(
				Meeting__c = meeting.Id,
				Name = 'Approve the budget',
				Status__c = 'Proposed'
			);
			Meeting_Attendee__c attendee = [
				SELECT Id
				FROM Meeting_Attendee__c
				WHERE Meeting__c = :meeting.Id
				WITH USER_MODE
				LIMIT 1
			];
			update as user new Meeting_Attendee__c(
				Id = attendee.Id,
				Packet_Read_On__c = Date.today(),
				Minutes_Approved_On__c = Date.today()
			);

			HubBoardController.BoardView boardView = HubBoardController.getBoard(board.Id);
			HubBoardController.MeetingView meetingView = HubBoardController.getMeeting(meeting.Id);

			Assert.isTrue(boardView.showDemographics, 'The setting is on');
			Boolean shown = false;
			for (HubBoardController.Line line : boardView.seats) {
				shown = shown || line.detail == '45 to 59, Woman';
			}
			Assert.isTrue(shown, 'The seat shows age range and gender');
			Assert.areEqual(1, boardView.actionItems.size(), 'The open item');
			Assert.areEqual('File the 990', boardView.actionItems[0].name, 'By name');
			Assert.isNotNull(boardView.actionItems[0].status, 'Shows who it is assigned to');
			Assert.areEqual(1, meetingView.motions.size(), 'The motion');
			Assert.areEqual(
				new List<String>{ '0', '0', '0' },
				meetingView.motions[0].values,
				'No votes counted yet'
			);
			Boolean marked = false;
			for (HubBoardController.Line line : meetingView.attendees) {
				marked = marked || line.values == new List<String>{ 'packet', 'minutes' };
			}
			Assert.isTrue(marked, 'The attendee read the packet and approved the minutes');
		}
	}

	@IsTest
	static void staffSeeNoDisclosureListAndCannotApproveMinutes() {
		Board__c board;
		Board_Meeting__c meeting;
		System.runAs(maria()) {
			board = board();
			meeting = meeting(board.Id, 3);
		}
		User sam = TestUsers.standardUserWith(
			'Sam',
			new List<String>{ 'BarnCRM_Staff', 'Corporate_Hub_Staff' }
		);
		System.runAs(sam) {
			HubBoardController.BoardView view = HubBoardController.getBoard(board.Id);
			String refusal;
			try {
				HubBoardController.setMinutesStatus(meeting.Id, HubBoard.MINUTES_APPROVED);
			} catch (AuraHandledException expected) {
				refusal = expected.getMessage();
			}

			Assert.isFalse(view.canManage, 'Staff do not manage the hub');
			Assert.isTrue(view.documents.isEmpty(), 'No disclosure list for staff');
			Assert.isNotNull(refusal, 'Approving minutes is refused in words');
		}
	}

	@IsTest
	static void anUnexpectedFailureIsShownAsOneMessage() {
		System.runAs(maria()) {
			Contact notABoard = new Contact(LastName = 'Member');
			insert as user notABoard;

			String message;
			try {
				HubBoardController.getBoard(notABoard.Id);
			} catch (AuraHandledException expected) {
				message = expected.getMessage();
			}

			Assert.areEqual(
				BarnHelp.text('CorporateHub', 'CorporateHub_Error_Generic'),
				message,
				'One message for anything unexpected'
			);
		}
	}

	@IsTest
	static void theAnnualDisclosureAsksTheBoardOncePerYear() {
		System.runAs(maria()) {
			Board__c board = board();
			Hub_Document__c policy = new Hub_Document__c(
				Name = 'Conflict of Interest',
				Type__c = 'Policy',
				Status__c = 'Active',
				Version__c = 1,
				Requires_Acknowledgment__c = true,
				Annual__c = true
			);
			insert as user policy;
			Assert.areEqual(
				1,
				HubBoardController.getBoard(board.Id).documents.size(),
				'Offered for disclosure'
			);
			Assert.areEqual(
				3,
				HubBoardController.requestFromBoard(board.Id, policy.Id),
				'Three current seats'
			);
			Assert.areEqual(
				0,
				HubPolicy.requestFromBoard(policy.Id, board.Id),
				'Not twice in a year'
			);
			Policy_Acknowledgment__c row = [
				SELECT Key__c, Person__c, User__c
				FROM Policy_Acknowledgment__c
				WHERE Document__c = :policy.Id
				WITH USER_MODE
				LIMIT 1
			];
			Assert.isTrue(
				row.Key__c.contains(':' + Date.today().year() + ':'),
				'The year is in the key'
			);
			Assert.isNull(row.User__c, 'A board member is a person, not a user');
		}
	}
}
