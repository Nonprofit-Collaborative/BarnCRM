/**
 * The Board and Meeting panels (CH-09 to CH-20; ADR-0199 `0199-corporate-hub-board-governance.md`
 * decision 13). Thin by design (plan Section 9.9): plain shapes out, the work in `HubBoard` and
 * `HubPolicy`, all in user mode. Skills gaps, expiring terms and percentages are worked out in
 * the framework-free `corporateHubModel` module.
 */
public with sharing class HubBoardController {
	private static final String CONTEXT = 'HubBoardController';

	/** One person or record line on a panel. */
	public class Line {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String detail;
		@AuraEnabled
		public Date due;
		@AuraEnabled
		public Boolean flag = false;
		@AuraEnabled
		public List<String> values = new List<String>();
	}

	/** The Board panel. */
	public class BoardView {
		@AuraEnabled
		public List<Line> seats = new List<Line>();
		@AuraEnabled
		public List<String> neededSkills = new List<String>();
		@AuraEnabled
		public List<Line> actionItems = new List<Line>();
		@AuraEnabled
		public List<Line> documents = new List<Line>();
		@AuraEnabled
		public Integer givers;
		@AuraEnabled
		public Integer alertDays;
		@AuraEnabled
		public Boolean showDemographics = false;
		@AuraEnabled
		public Boolean canManage = false;
	}

	/** The Meeting panel. */
	public class MeetingView {
		@AuraEnabled
		public List<Line> attendees = new List<Line>();
		@AuraEnabled
		public List<Line> motions = new List<Line>();
		@AuraEnabled
		public List<Line> carried = new List<Line>();
		@AuraEnabled
		public List<Line> pollTimes = new List<Line>();
		@AuraEnabled
		public Board_Meeting__c meeting;
		@AuraEnabled
		public Boolean canManage = false;
	}

	@AuraEnabled
	public static BoardView getBoard(Id boardId) {
		try {
			BoardView view = new BoardView();
			Board__c board = [
				SELECT Id, Needed_Skills__c
				FROM Board__c
				WHERE Id = :boardId
				WITH USER_MODE
			];
			view.neededSkills = split(board.Needed_Skills__c);
			view.canManage = HubPolicy.canManage();
			view.showDemographics = CorporateHubSettings.boardDemographics();
			view.alertDays = CorporateHubSettings.reminderDays();
			Set<Id> people = new Set<Id>();
			for (Board_Member__c seat : HubBoard.currentSeats(boardId)) {
				people.add(seat.Person__c);
				Line line = line(seat.Id, seat.Person__r.Name, seat.Role__c, seat.Term_End__c);
				line.flag = seat.At_Term_Limit__c;
				if (view.showDemographics) {
					line.detail = joined(new List<String>{ seat.Age_Range__c, seat.Gender__c });
				}
				line.values = split(seat.Skills__c);
				view.seats.add(line);
			}
			view.givers = people.isEmpty() ? null : HubBoard.giversAmong(people);
			for (Meeting_Action_Item__c item : [
				SELECT Id, Name, Due_Date__c, Assigned_To__r.Name
				FROM Meeting_Action_Item__c
				WHERE Board__c = :boardId AND Status__c = 'Open'
				WITH USER_MODE
				ORDER BY Due_Date__c NULLS LAST
				LIMIT 100
			]) {
				view.actionItems.add(
					line(item.Id, item.Name, item.Assigned_To__r?.Name, item.Due_Date__c)
				);
			}
			if (view.canManage) {
				for (Hub_Document__c document : [
					SELECT Id, Name
					FROM Hub_Document__c
					WHERE Status__c = 'Active' AND Requires_Acknowledgment__c = TRUE
					WITH USER_MODE
					ORDER BY Name
					LIMIT 200
				]) {
					view.documents.add(line(document.Id, document.Name, null, null));
				}
			}
			return view;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static MeetingView getMeeting(Id meetingId) {
		try {
			MeetingView view = new MeetingView();
			view.meeting = HubBoard.meeting(meetingId);
			view.canManage = HubPolicy.canManage();
			for (Meeting_Attendee__c row : [
				SELECT
					Id,
					Person__r.Name,
					Attendance__c,
					Voting__c,
					Packet_Read_On__c,
					Minutes_Approved_On__c
				FROM Meeting_Attendee__c
				WHERE Meeting__c = :meetingId
				WITH USER_MODE
				ORDER BY Person__r.LastName
				LIMIT 500
			]) {
				Line line = line(row.Id, row.Person__r?.Name, row.Attendance__c, null);
				line.flag = row.Voting__c;
				if (row.Packet_Read_On__c != null) {
					line.values.add('packet');
				}
				if (row.Minutes_Approved_On__c != null) {
					line.values.add('minutes');
				}
				view.attendees.add(line);
			}
			for (Board_Motion__c motion : [
				SELECT Id, Name, Status__c, Votes_For__c, Votes_Against__c, Abstentions__c
				FROM Board_Motion__c
				WHERE Meeting__c = :meetingId
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 200
			]) {
				Line line = line(motion.Id, motion.Name, motion.Status__c, null);
				line.values = new List<String>{
					count(motion.Votes_For__c),
					count(motion.Votes_Against__c),
					count(motion.Abstentions__c)
				};
				view.motions.add(line);
			}
			for (Meeting_Action_Item__c item : HubBoard.carriedItems(view.meeting)) {
				view.carried.add(
					line(item.Id, item.Name, item.Assigned_To__r?.Name, item.Due_Date__c)
				);
			}
			for (Integer i = 1; i <= 3; i++) {
				Datetime slot = (Datetime) view.meeting.get('Poll_Time_' + i + '__c');
				if (slot != null) {
					Line line = line(String.valueOf(i), slot.format(), null, null);
					line.detail = count((Decimal) view.meeting.get('Poll_Yes_' + i + '__c'));
					view.pollTimes.add(line);
				}
			}
			return view;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Integer inviteBoard(Id meetingId) {
		try {
			return HubBoard.inviteBoard(meetingId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void setAttendance(Id attendeeId, String attendance) {
		try {
			HubBoard.setAttendance(attendeeId, attendance);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void setMinutesStatus(Id meetingId, String status) {
		try {
			HubBoard.setMinutesStatus(meetingId, status);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Integer openVoting(Id motionId) {
		try {
			return HubBoard.openVoting(motionId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static String closeVoting(Id motionId) {
		try {
			return HubBoard.closeVoting(motionId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void sendPoll(Id meetingId) {
		try {
			HubBoard.sendPoll(meetingId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void chooseTime(Id meetingId, Integer option) {
		try {
			HubBoard.chooseTime(meetingId, option);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Integer requestFromBoard(Id boardId, Id documentId) {
		try {
			return HubPolicy.requestFromBoard(documentId, boardId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id startAssessment(Id boardId) {
		try {
			return HubBoard.startAssessment(boardId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	private static Line line(String id, String name, String status, Date due) {
		Line line = new Line();
		line.id = id;
		line.name = name;
		line.status = status;
		line.due = due;
		return line;
	}

	private static String joined(List<String> parts) {
		List<String> kept = new List<String>();
		for (String part : parts) {
			if (String.isNotBlank(part)) {
				kept.add(part);
			}
		}
		return String.join(kept, ', ');
	}

	private static List<String> split(String multi) {
		return String.isBlank(multi) ? new List<String>() : multi.split(';');
	}

	private static String count(Decimal value) {
		return String.valueOf(value == null ? 0 : value.intValue());
	}

	/** A refusal or a save's own message as it is; anything else logged, then one message. */
	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof HubPolicy.PolicyException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(
			e,
			BarnHelp.text('CorporateHub', 'CorporateHub_Error_Generic')
		);
	}
}
