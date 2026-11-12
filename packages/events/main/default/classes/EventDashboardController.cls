/**
 * The event dashboard and the event templates (EV-11, ADR-0177). The dashboard is the Details
 * tab's top: what the event has so far. A template is JSON (`BarnEventTemplates`) an admin
 * applies on request; nothing applies one by default. Thin by design (plan Section 9.9): the
 * browser module `eventDashboardModel` turns a template into a plan with real dates, and this
 * class only counts, hands over the JSON and writes the plan, in user mode.
 */
public with sharing class EventDashboardController {
	private static final String CONTEXT = 'EventDashboardController';
	private static final String TEMPLATES_RESOURCE = 'BarnEventTemplates';

	/** Replaces the resource body in tests. */
	@TestVisible
	private static String templatesForTest;

	/** Everything the dashboard draws. */
	public class Dashboard {
		@AuraEnabled
		public String eventStatus;
		@AuraEnabled
		public Datetime startsAt;
		@AuraEnabled
		public Datetime endsAt;
		@AuraEnabled
		public Decimal capacity;
		@AuraEnabled
		public Integer ticketTypes = 0;
		@AuraEnabled
		public Integer promoCodes = 0;
		@AuraEnabled
		public Integer tracks = 0;
		@AuraEnabled
		public Integer sessions = 0;
		@AuraEnabled
		public Integer speakers = 0;
		@AuraEnabled
		public Integer confirmedSpeakers = 0;
		/** R-EXP1: actual spend less funding received and registrations paid; null with no budget. */
		@AuraEnabled
		public Decimal netCost;
		/** The templates as JSON text, for the browser module to read. */
		@AuraEnabled
		public String templatesJson;
		@AuraEnabled
		public Boolean canApplyTemplate = false;
	}

	/** What applying a template adds; built by the browser module. */
	public class Plan {
		public List<TrackPlan> tracks = new List<TrackPlan>();
		public List<TicketPlan> ticketTypes = new List<TicketPlan>();
		public List<SessionPlan> sessions = new List<SessionPlan>();
	}

	public class TrackPlan {
		public String name;
		public Decimal sortOrder;
	}

	public class TicketPlan {
		public String name;
		public Decimal price;
		public Decimal quantity;
		public Decimal sortOrder;
	}

	public class SessionPlan {
		public String name;
		public String sessionType;
		public String room;
		public String trackName;
		public Datetime startTime;
		public Datetime endTime;
	}

	/**
	 * The event's counts, its dates and the templates.
	 *
	 * @param eventId the event
	 * @return the dashboard and whether the person may apply a template
	 */
	@AuraEnabled
	public static Dashboard getDashboard(Id eventId) {
		try {
			Dashboard result = new Dashboard();
			for (Event__c record : [
				SELECT Status__c, Start__c, End__c, Capacity__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				result.eventStatus = record.Status__c;
				result.startsAt = record.Start__c;
				result.endsAt = record.End__c;
				result.capacity = record.Capacity__c;
			}
			result.ticketTypes = [
				SELECT COUNT()
				FROM Ticket_Type__c
				WHERE Event__c = :eventId
				WITH USER_MODE
			];
			result.promoCodes = [
				SELECT COUNT()
				FROM Promo_Code__c
				WHERE Event__c = :eventId
				WITH USER_MODE
			];
			result.tracks = [
				SELECT COUNT()
				FROM Event_Track__c
				WHERE Event__c = :eventId
				WITH USER_MODE
			];
			result.sessions = [
				SELECT COUNT()
				FROM Event_Session__c
				WHERE Event__c = :eventId
				WITH USER_MODE
			];
			for (AggregateResult row : [
				SELECT Status__c status, COUNT(Id) total
				FROM Event_Speaker__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				GROUP BY Status__c
			]) {
				Integer total = (Integer) row.get('total');
				result.speakers += total;
				if ((String) row.get('status') == 'Confirmed') {
					result.confirmedSpeakers += total;
				}
			}
			result.netCost = netCost(eventId);
			result.templatesJson = templates();
			result.canApplyTemplate =
				Schema.SObjectType.Event_Track__c.isCreateable() &&
				Schema.SObjectType.Ticket_Type__c.isCreateable() &&
				Schema.SObjectType.Event_Session__c.isCreateable();
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getDashboard', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Dashboard_LoadFailed')
			);
		}
	}

	/**
	 * Adds a template's tracks, ticket types and sessions to an event that has none of them. All
	 * or nothing: a failure rolls back what was added.
	 *
	 * @param eventId the event
	 * @param planJson the plan the browser module built from the template
	 * @return how many sessions were added
	 */
	@AuraEnabled
	public static Integer applyPlan(Id eventId, String planJson) {
		System.Savepoint before = Database.setSavepoint();
		try {
			Plan plan = parse(planJson);
			if (hasRecords(eventId)) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Dashboard_NotEmpty')
				);
			}
			Map<String, Event_Track__c> tracks = new Map<String, Event_Track__c>();
			for (TrackPlan item : plan.tracks) {
				tracks.put(
					item.name,
					new Event_Track__c(
						Event__c = eventId,
						Name = item.name,
						Sort_Order__c = item.sortOrder
					)
				);
			}
			insert as user tracks.values();
			List<Ticket_Type__c> tickets = new List<Ticket_Type__c>();
			for (TicketPlan item : plan.ticketTypes) {
				tickets.add(
					new Ticket_Type__c(
						Event__c = eventId,
						Name = item.name,
						Price__c = item.price,
						Quantity__c = item.quantity,
						Sort_Order__c = item.sortOrder,
						Active__c = true
					)
				);
			}
			insert as user tickets;
			List<Event_Session__c> sessions = new List<Event_Session__c>();
			for (SessionPlan item : plan.sessions) {
				Event_Track__c track = item.trackName == null ? null : tracks.get(item.trackName);
				sessions.add(
					new Event_Session__c(
						Event__c = eventId,
						Name = item.name,
						Session_Type__c = item.sessionType,
						Room__c = item.room,
						Track__c = track == null ? null : track.Id,
						Start__c = item.startTime,
						End__c = item.endTime,
						Status__c = 'Draft'
					)
				);
			}
			insert as user sessions;
			return sessions.size();
		} catch (Exception e) {
			Database.rollback(before);
			ErrorLogger.log(e, CONTEXT + '.applyPlan', eventId);
			if (e instanceof System.IllegalArgumentException) {
				throw UserErrors.message(e.getMessage());
			}
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Dashboard_ApplyFailed')
			);
		}
	}

	/** R-EXP1 Net Cost, the Budget panel's figure, or null when the event has no budget lines. */
	private static Decimal netCost(Id eventId) {
		AggregateResult spend = [
			SELECT COUNT(Id) lines, SUM(Actual__c) actual
			FROM Event_Expense__c
			WHERE Event__c = :eventId
			WITH USER_MODE
		];
		AggregateResult money = [
			SELECT COUNT(Id) lines, SUM(Received__c) received
			FROM Event_Funding__c
			WHERE Event__c = :eventId
			WITH USER_MODE
		];
		if ((Integer) spend.get('lines') == 0 && (Integer) money.get('lines') == 0) {
			return null;
		}
		Decimal actual = (Decimal) spend.get('actual');
		Decimal received = (Decimal) money.get('received');
		return (actual == null ? 0 : actual) -
			(received == null ? 0 : received) -
			EventBudgetController.registrationsPaid(eventId);
	}

	private static Boolean hasRecords(Id eventId) {
		return [SELECT COUNT() FROM Ticket_Type__c WHERE Event__c = :eventId WITH USER_MODE] > 0 ||
			[SELECT COUNT() FROM Event_Track__c WHERE Event__c = :eventId WITH USER_MODE] > 0 ||
			[SELECT COUNT() FROM Event_Session__c WHERE Event__c = :eventId WITH USER_MODE] > 0;
	}

	private static Plan parse(String planJson) {
		Plan plan = (Plan) JSON.deserialize(planJson, Plan.class);
		if (plan == null) {
			throw new System.IllegalArgumentException(
				BarnHelp.text('Events', 'Events_Dashboard_ApplyFailed')
			);
		}
		return plan;
	}

	private static String templates() {
		if (templatesForTest != null) {
			return templatesForTest;
		}
		String prefix = NamespaceUtil.prefix().removeEnd('__');
		String namespace = String.isBlank(prefix) ? null : prefix;
		// System mode: a static resource is packaged text every user may read, and reading
		// StaticResource in user mode needs a setup permission (the BarnHelp reasoning).
		for (StaticResource resource : [
			SELECT Body
			FROM StaticResource
			WHERE Name = :TEMPLATES_RESOURCE AND NamespacePrefix = :namespace
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return resource.Body.toString();
		}
		return '{"templates":[]}';
	}
}
