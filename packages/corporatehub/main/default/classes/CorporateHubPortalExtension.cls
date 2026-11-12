/**
 * The board portal's actions (PB-02, CH-18; ADR-0185 decision 9, ADR-0191 and ADR-0199
 * `0199-corporate-hub-board-governance.md` decision 12): mark the packet read and approve the
 * minutes on the person's own attendee row, vote on their own vote row, and acknowledge their own
 * policy or disclosure request. Core finds this class by name
 * (`PortalActionExtensions.EXTENSION_CLASSES`); Portal Builder has already checked that the
 * record is on the verified person's page.
 *
 * `without sharing` and system mode (ADR-0021): the portal's integration user has no object
 * access. Each action re-reads the row by the verified person, refuses when the meeting, motion
 * or request is not open, and writes only that row.
 *
 * `@NamespaceAccessible` with a public no-argument constructor because Core resolves it by name
 * under ADR-0017.
 */
@NamespaceAccessible
public without sharing class CorporateHubPortalExtension implements PortalActionExtension {
	public static final String PACKET = 'CorporateHub.MarkPacketRead';
	public static final String MINUTES = 'CorporateHub.ApproveMinutes';
	public static final String ACKNOWLEDGE = 'CorporateHub.Acknowledge';
	/** The three vote actions and the vote each records. */
	public static final Map<String, String> VOTES = new Map<String, String>{
		'CorporateHub.VoteFor' => 'For',
		'CorporateHub.VoteAgainst' => 'Against',
		'CorporateHub.Abstain' => 'Abstain'
	};

	@NamespaceAccessible
	public CorporateHubPortalExtension() {
		return;
	}

	public Set<String> actionNames() {
		Set<String> names = new Set<String>{ PACKET, MINUTES, ACKNOWLEDGE };
		names.addAll(VOTES.keySet());
		return names;
	}

	public String run(String actionName, Id personId, Id recordId) {
		if (personId == null || recordId == null) {
			throw new System.IllegalArgumentException('A person and a record are needed');
		}
		if (actionName == PACKET || actionName == MINUTES) {
			return attendee(actionName, personId, recordId);
		}
		if (VOTES.containsKey(actionName)) {
			return vote(VOTES.get(actionName), personId, recordId);
		}
		if (actionName == ACKNOWLEDGE) {
			return acknowledge(personId, recordId);
		}
		throw new System.IllegalArgumentException('Unknown action ' + actionName);
	}

	private static String attendee(String actionName, Id personId, Id attendeeId) {
		List<Meeting_Attendee__c> rows = [
			SELECT Id, Meeting__r.Minutes_Status__c
			FROM Meeting_Attendee__c
			WHERE Id = :attendeeId AND Person__c = :personId
			WITH SYSTEM_MODE
		];
		if (rows.isEmpty()) {
			throw new System.QueryException('The meeting is not this person\'s');
		}
		Meeting_Attendee__c row = rows[0];
		if (actionName == PACKET) {
			row.Packet_Read_On__c = System.now();
			update as system row;
			return BarnHelp.text('CorporateHub', 'CorporateHub_Portal_PacketRead');
		}
		if (row.Meeting__r.Minutes_Status__c != HubBoard.MINUTES_SUBMITTED) {
			return BarnHelp.text('CorporateHub', 'CorporateHub_Portal_MinutesClosed');
		}
		row.Minutes_Approved_On__c = System.now();
		update as system row;
		return BarnHelp.text('CorporateHub', 'CorporateHub_Portal_MinutesApproved');
	}

	private static String vote(String choice, Id personId, Id voteId) {
		List<Board_Vote__c> rows = [
			SELECT Id, Motion__r.Status__c
			FROM Board_Vote__c
			WHERE Id = :voteId AND Person__c = :personId
			WITH SYSTEM_MODE
		];
		if (rows.isEmpty()) {
			throw new System.QueryException('The vote is not this person\'s');
		}
		if (rows[0].Motion__r.Status__c != HubBoard.VOTING_OPEN) {
			return BarnHelp.text('CorporateHub', 'CorporateHub_Portal_VotingClosed');
		}
		update as system new Board_Vote__c(
			Id = voteId,
			Vote__c = choice,
			Voted_On__c = System.now()
		);
		return BarnHelp.text(
			'CorporateHub',
			'CorporateHub_Portal_Voted',
			new List<Object>{ choice }
		);
	}

	private static String acknowledge(Id personId, Id requestId) {
		List<Policy_Acknowledgment__c> rows = [
			SELECT Id, Status__c
			FROM Policy_Acknowledgment__c
			WHERE Id = :requestId AND Person__c = :personId
			WITH SYSTEM_MODE
		];
		if (rows.isEmpty()) {
			throw new System.QueryException('The request is not this person\'s');
		}
		if (rows[0].Status__c != HubPolicy.REQUESTED) {
			return BarnHelp.text('CorporateHub', 'CorporateHub_Policy_NotOpen');
		}
		update as system new Policy_Acknowledgment__c(
			Id = requestId,
			Status__c = HubPolicy.ACKNOWLEDGED,
			Acknowledged_On__c = System.now(),
			Answered_In_Portal__c = true
		);
		return BarnHelp.text('CorporateHub', 'CorporateHub_Portal_Acknowledged');
	}
}
