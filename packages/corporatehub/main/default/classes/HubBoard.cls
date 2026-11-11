/**
 * Board governance (CH-09 to CH-20; ADR-NEXT `NEXT-corporate-hub-board-governance.md`, canonical
 * model R-BM1, R-BMT1 to R-BMT4, R-MO1, R-AI1, R-BA1): current seats, inviting the board to a
 * meeting, minutes, voting, the availability poll, carried action items, self-assessments and
 * giving participation. Everything runs as the person, in user mode; approving minutes and
 * recording votes after voting closes also need Manage Corporate Hub.
 */
public with sharing class HubBoard {
	public static final String VOTING_OPEN = 'Voting Open';
	public static final String MINUTES_SUBMITTED = 'Submitted for Approval';
	public static final String MINUTES_APPROVED = 'Approved';
	public static final String ASSESSMENT_TEMPLATE = 'board-self-assessment';
	private static final Integer POLL_TIMES = 3;

	/** R-BM1: the board's current seats with a person, officers first. */
	public static List<Board_Member__c> currentSeats(Id boardId) {
		return [
			SELECT
				Id,
				Person__c,
				Person__r.Name,
				Role__c,
				Term_Start__c,
				Term_End__c,
				Term_Number__c,
				Voting__c,
				At_Term_Limit__c,
				Skills__c,
				Age_Range__c,
				Gender__c
			FROM Board_Member__c
			WHERE Board__c = :boardId AND Is_Current__c = TRUE AND Person__c != NULL
			WITH USER_MODE
			ORDER BY Role__c, Person__r.LastName
			LIMIT 500
		];
	}

	/** R-BMT1: one attendee per current seat not yet invited. Returns how many were added. */
	public static Integer inviteBoard(Id meetingId) {
		Board_Meeting__c meeting = meeting(meetingId);
		Set<String> invited = new Set<String>();
		for (Meeting_Attendee__c row : [
			SELECT Person__c
			FROM Meeting_Attendee__c
			WHERE Meeting__c = :meetingId
			WITH USER_MODE
		]) {
			invited.add(row.Person__c);
		}
		List<Meeting_Attendee__c> rows = new List<Meeting_Attendee__c>();
		for (Board_Member__c seat : currentSeats(meeting.Board__c)) {
			if (invited.add(seat.Person__c)) {
				rows.add(
					new Meeting_Attendee__c(
						Meeting__c = meetingId,
						Person__c = seat.Person__c,
						Voting__c = seat.Voting__c == true,
						Attendance__c = 'Invited',
						Key__c = meetingId + ':' + seat.Person__c
					)
				);
			}
		}
		insert as user rows;
		return rows.size();
	}

	/** One attendee's attendance, from the meeting panel. */
	public static void setAttendance(Id attendeeId, String attendance) {
		update as user new Meeting_Attendee__c(Id = attendeeId, Attendance__c = attendance);
	}

	/** R-BMT3: Draft to Submitted for Approval (edit access), or Approved (Manage Corporate Hub). */
	public static void setMinutesStatus(Id meetingId, String status) {
		Board_Meeting__c meeting = new Board_Meeting__c(Id = meetingId, Minutes_Status__c = status);
		if (status == MINUTES_APPROVED) {
			requireManage();
			meeting.Minutes_Approved_On__c = Date.today();
		} else if (status != MINUTES_SUBMITTED) {
			throw new HubPolicy.PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Board_NotAllowed')
			);
		}
		update as user meeting;
	}

	/** R-MO1: Voting Open, and one blank vote per voting attendee not yet given one. */
	public static Integer openVoting(Id motionId) {
		Board_Motion__c motion = [
			SELECT Id, Meeting__c, Status__c
			FROM Board_Motion__c
			WHERE Id = :motionId
			WITH USER_MODE
		];
		Set<String> keys = new Set<String>();
		for (Board_Vote__c row : [
			SELECT Key__c
			FROM Board_Vote__c
			WHERE Motion__c = :motionId
			WITH USER_MODE
		]) {
			keys.add(row.Key__c);
		}
		List<Board_Vote__c> votes = new List<Board_Vote__c>();
		for (Meeting_Attendee__c attendee : [
			SELECT Person__c
			FROM Meeting_Attendee__c
			WHERE Meeting__c = :motion.Meeting__c AND Voting__c = TRUE AND Person__c != NULL
			WITH USER_MODE
		]) {
			String key = motionId + ':' + attendee.Person__c;
			if (keys.add(key)) {
				votes.add(
					new Board_Vote__c(
						Motion__c = motionId,
						Person__c = attendee.Person__c,
						Key__c = key
					)
				);
			}
		}
		motion.Status__c = VOTING_OPEN;
		update as user motion;
		insert as user votes;
		return votes.size();
	}

	/** R-MO1: Passed when For is greater than Against, otherwise Failed; decided today. */
	public static String closeVoting(Id motionId) {
		Board_Motion__c motion = [
			SELECT Id, Votes_For__c, Votes_Against__c
			FROM Board_Motion__c
			WHERE Id = :motionId
			WITH USER_MODE
		];
		Decimal votesFor = motion.Votes_For__c == null ? 0 : motion.Votes_For__c;
		Decimal against = motion.Votes_Against__c == null ? 0 : motion.Votes_Against__c;
		motion.Status__c = votesFor > against ? 'Passed' : 'Failed';
		motion.Decided_On__c = Date.today();
		update as user motion;
		return motion.Status__c;
	}

	/** R-BMT4: opens the poll, inviting the board first when nobody is invited yet. */
	public static void sendPoll(Id meetingId) {
		Board_Meeting__c meeting = meeting(meetingId);
		if (meeting.Poll_Time_1__c == null) {
			throw new HubPolicy.PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Board_NoPollTimes')
			);
		}
		if (
			[
				SELECT COUNT()
				FROM Meeting_Attendee__c
				WHERE Meeting__c = :meetingId
				WITH USER_MODE
			] == 0
		) {
			inviteBoard(meetingId);
		}
		update as user new Board_Meeting__c(Id = meetingId, Poll_Open__c = true);
	}

	/** R-BMT4: the chosen poll time becomes the start, and the poll closes. */
	public static void chooseTime(Id meetingId, Integer option) {
		Board_Meeting__c meeting = meeting(meetingId);
		Datetime chosen = option == null ||
			option < 1 ||
			option > POLL_TIMES
			? null
			: (Datetime) meeting.get('Poll_Time_' + option + '__c');
		if (chosen == null) {
			throw new HubPolicy.PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Board_NoPollTimes')
			);
		}
		update as user new Board_Meeting__c(
			Id = meetingId,
			Start__c = chosen,
			Poll_Open__c = false
		);
	}

	/** R-AI1: the board's open items raised before this meeting, or at no meeting, oldest first. */
	public static List<Meeting_Action_Item__c> carriedItems(Board_Meeting__c meeting) {
		List<Meeting_Action_Item__c> items = new List<Meeting_Action_Item__c>();
		for (Meeting_Action_Item__c item : [
			SELECT Id, Name, Due_Date__c, Assigned_To__r.Name, Meeting__c, Meeting__r.Start__c
			FROM Meeting_Action_Item__c
			WHERE Board__c = :meeting.Board__c AND Status__c = 'Open' AND Meeting__c != :meeting.Id
			WITH USER_MODE
			ORDER BY CreatedDate
			LIMIT 200
		]) {
			Datetime raised = item.Meeting__r?.Start__c;
			if (meeting.Start__c == null || raised == null || raised < meeting.Start__c) {
				items.add(item);
			}
		}
		return items;
	}

	/** R-BA1: a self-assessment for the board with every question for every current seat. */
	public static Id startAssessment(Id boardId) {
		Map<String, Object> template = HubTemplates.assessment(ASSESSMENT_TEMPLATE);
		List<Object> questions = template == null
			? new List<Object>()
			: (List<Object>) template.get('questions');
		List<Board_Member__c> seats = currentSeats(boardId);
		if (questions == null || questions.isEmpty() || seats.isEmpty()) {
			throw new HubPolicy.PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Board_NothingToAsk')
			);
		}
		Board_Assessment__c assessment = new Board_Assessment__c(
			Board__c = boardId,
			Name = (String.valueOf(template.get('title')) +
				' ' +
				Date.today().year())
				.abbreviate(80),
			Status__c = 'Open',
			Template_Key__c = ASSESSMENT_TEMPLATE
		);
		insert as user assessment;
		List<Assessment_Answer__c> answers = new List<Assessment_Answer__c>();
		for (Board_Member__c seat : seats) {
			for (Integer i = 0; i < questions.size(); i++) {
				answers.add(
					new Assessment_Answer__c(
						Assessment__c = assessment.Id,
						Person__c = seat.Person__c,
						Question__c = String.valueOf(questions[i]).abbreviate(255),
						Sort_Order__c = i + 1
					)
				);
			}
		}
		insert as user answers;
		return assessment.Id;
	}

	/**
	 * CH-13: how many of these people gave this fiscal year, read through Giving's Contact field
	 * by describe, so this package never depends on Giving. Null when Giving is not installed or
	 * the field is not readable.
	 */
	public static Integer giversAmong(Set<Id> personIds) {
		Schema.SObjectField field = Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.fields.getMap()
			.get(NamespaceUtil.qualify('Giving_This_Year__c'));
		if (field == null || !field.getDescribe().isAccessible()) {
			return null;
		}
		String name = field.getDescribe().getName();
		return Database.countQueryWithBinds(
			'SELECT COUNT() FROM Contact WHERE Id IN :personIds AND ' + name + ' > 0',
			new Map<String, Object>{ 'personIds' => personIds },
			AccessLevel.USER_MODE
		);
	}

	public static Board_Meeting__c meeting(Id meetingId) {
		return [
			SELECT
				Id,
				Name,
				Board__c,
				Start__c,
				Minutes_Status__c,
				Poll_Open__c,
				Poll_Time_1__c,
				Poll_Time_2__c,
				Poll_Time_3__c,
				Poll_Yes_1__c,
				Poll_Yes_2__c,
				Poll_Yes_3__c,
				Voting_Count__c,
				Present_Count__c,
				Quorum_Needed__c,
				Quorum_Met__c,
				Approvals_Count__c,
				Packet_Reads__c
			FROM Board_Meeting__c
			WHERE Id = :meetingId
			WITH USER_MODE
		];
	}

	private static void requireManage() {
		if (!HubPolicy.canManage()) {
			throw new HubPolicy.PolicyException(
				BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NoPermission')
			);
		}
	}
}
