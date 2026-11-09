/**
 * The Registrations tab of the event page (EV-02, canonical model 29EV8 and 29EV9). Thin by
 * design (plan Section 9.9): it reads the event's attendees as plain shapes and hands changes to
 * `EventRegistrationService`; counts, badges and menus are worked out in the browser module
 * `eventRegistrationsModel`. Reads are user mode, so a person without an Events set sees none.
 */
public with sharing class EventRegistrationsController {
	private static final String CONTEXT = 'EventRegistrationsController';
	private static final Integer ROW_LIMIT = 2000;

	/** Everything the tab draws. */
	public class Registrations {
		@AuraEnabled
		public Decimal capacity;
		@AuraEnabled
		public String currencyCode;
		@AuraEnabled
		public Boolean canRegister = false;
		@AuraEnabled
		public Boolean canChange = false;
		@AuraEnabled
		public Boolean truncated = false;
		@AuraEnabled
		public List<Option> tickets = new List<Option>();
		@AuraEnabled
		public List<AttendeeRow> attendees = new List<AttendeeRow>();
		/** Field labels by `Object.Field`, so the tab needs no labels of its own for columns. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One ticket type to choose. */
	public class Option {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;
	}

	/** One attendee, with their registration. */
	public class AttendeeRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String contactId;
		@AuraEnabled
		public String ticketName;
		@AuraEnabled
		public Decimal price;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String registrationId;
		@AuraEnabled
		public String registrationName;
		@AuraEnabled
		public String registrationStatus;
		@AuraEnabled
		public String source;
	}

	/**
	 * The event's attendees, newest registration first, and its active ticket types.
	 *
	 * @param eventId the event
	 */
	@AuraEnabled
	public static Registrations getRegistrations(Id eventId) {
		try {
			Registrations result = new Registrations();
			result.canRegister =
				Schema.SObjectType.Event_Registration__c.isCreateable() &&
				Schema.SObjectType.Event_Attendee__c.isCreateable();
			result.canChange = Schema.SObjectType.Event_Attendee__c.isUpdateable();
			result.currencyCode = UserInfo.getDefaultCurrency();
			labels(
				result,
				Schema.SObjectType.Event_Attendee__c.fields.getMap(),
				'Event_Attendee__c',
				new List<String>{ 'Name', 'Ticket_Type__c', 'Price__c', 'Status__c' }
			);
			labels(
				result,
				Schema.SObjectType.Event_Registration__c.fields.getMap(),
				'Event_Registration__c',
				new List<String>{ 'Name', 'Contact__c', 'Promo_Code__c', 'Source__c' }
			);
			labels(
				result,
				Schema.SObjectType.Contact.fields.getMap(),
				'Contact',
				new List<String>{ 'FirstName', 'LastName', 'Email', 'MailingPostalCode' }
			);
			for (Event__c record : [
				SELECT Capacity__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				result.capacity = record.Capacity__c;
			}
			for (Ticket_Type__c ticket : [
				SELECT Id, Name, Price__c
				FROM Ticket_Type__c
				WHERE Event__c = :eventId AND Active__c = TRUE
				WITH USER_MODE
				ORDER BY Sort_Order__c ASC NULLS LAST, Name
				LIMIT 200
			]) {
				Option option = new Option();
				option.value = ticket.Id;
				option.label = ticket.Name;
				result.tickets.add(option);
			}
			List<Event_Attendee__c> rows = [
				SELECT
					Id,
					Name,
					Contact__c,
					Ticket_Type__r.Name,
					Price__c,
					Status__c,
					Event_Registration__c,
					Event_Registration__r.Name,
					Event_Registration__r.Status__c,
					Event_Registration__r.Source__c
				FROM Event_Attendee__c
				WHERE Event_Registration__r.Event__c = :eventId
				WITH USER_MODE
				ORDER BY Event_Registration__r.CreatedDate DESC, Name
				LIMIT :ROW_LIMIT + 1
			];
			result.truncated = rows.size() > ROW_LIMIT;
			for (Integer i = 0; i < Math.min(rows.size(), ROW_LIMIT); i++) {
				result.attendees.add(toRow(rows[i]));
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getRegistrations', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Registrations_LoadFailed')
			);
		}
	}

	/**
	 * Registers people for the event.
	 *
	 * @param requestJson an `EventRegistrationService.Request` as JSON
	 * @return what was registered
	 */
	@AuraEnabled
	public static EventRegistrationService.Result register(String requestJson) {
		EventRegistrationService.Request request;
		try {
			request = (EventRegistrationService.Request) JSON.deserialize(
				requestJson,
				EventRegistrationService.Request.class
			);
		} catch (Exception unreadable) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
		// A page never sets an import's status or keys.
		request.attendeeStatus = null;
		request.registrationValues = new Map<String, Object>();
		request.source = EventRegistrationService.SOURCE_STAFF;
		request.formSubmissionKey = null;
		try {
			return EventRegistrationService.register(request);
		} catch (EventRegistrationService.RegistrationException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (EventPersonMatcher.AmbiguousPersonException ambiguous) {
			throw UserErrors.message(ambiguous.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Changes one attendee's status.
	 *
	 * @return the attendee's status now
	 */
	@AuraEnabled
	public static String setStatus(Id attendeeId, String status) {
		try {
			return EventRegistrationService.setStatus(attendeeId, status);
		} catch (EventRegistrationService.RegistrationException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** Cancels a registration and everyone on it. */
	@AuraEnabled
	public static void cancelRegistration(Id registrationId) {
		try {
			EventRegistrationService.cancelRegistration(registrationId);
		} catch (Exception e) {
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	private static void labels(
		Registrations result,
		Map<String, Schema.SObjectField> fields,
		String objectName,
		List<String> names
	) {
		for (String name : names) {
			Schema.SObjectField token = fields.get(name);
			if (token != null) {
				result.fieldLabels.put(objectName + '.' + name, token.getDescribe().getLabel());
			}
		}
	}

	private static AttendeeRow toRow(Event_Attendee__c record) {
		AttendeeRow row = new AttendeeRow();
		row.id = record.Id;
		row.name = record.Name;
		row.contactId = record.Contact__c;
		row.ticketName = record.Ticket_Type__r?.Name;
		row.price = record.Price__c;
		row.status = record.Status__c;
		row.registrationId = record.Event_Registration__c;
		row.registrationName = record.Event_Registration__r?.Name;
		row.registrationStatus = record.Event_Registration__r?.Status__c;
		row.source = record.Event_Registration__r?.Source__c;
		return row;
	}
}
