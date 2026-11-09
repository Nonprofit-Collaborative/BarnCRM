/**
 * The Appointments tab of the event page (EV-15, canonical model 29EV8): bookable slots with a
 * host during an event. Thin by design (plan Section 9.9): the browser module
 * `eventAppointmentsModel` cuts a day into slots and finds clashes; this class reads, adds the
 * slots it is given, books a person into an open slot and moves a slot between statuses. Reads
 * and writes run in user mode. Slot details are edited through the platform's record form.
 */
public with sharing class EventAppointmentsController {
	private static final String CONTEXT = 'EventAppointmentsController';
	private static final Integer MAX_SLOTS = 100;
	private static final Set<String> TARGET_STATUSES = new Set<String>{
		'Open',
		'Completed',
		'No-Show',
		'Cancelled'
	};

	/** Everything the tab draws. */
	public class Appointments {
		@AuraEnabled
		public List<Slot> slots = new List<Slot>();
		@AuraEnabled
		public Datetime eventStart;
		@AuraEnabled
		public Datetime eventEnd;
		@AuraEnabled
		public Boolean canAdd = false;
		@AuraEnabled
		public Boolean canBook = false;
		@AuraEnabled
		public Boolean truncated = false;
		/** Field labels by API name, so the tab needs no labels of its own for columns. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One slot. */
	public class Slot {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String hostId;
		@AuraEnabled
		public String hostName;
		@AuraEnabled
		public String contactId;
		@AuraEnabled
		public String contactName;
		@AuraEnabled
		public Datetime start;
		@AuraEnabled
		public Datetime finish;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String location;
	}

	/** A slot to add; `start` and `finish` are the times the browser module cut. */
	public class NewSlot {
		public Datetime start;
		public Datetime finish;
	}

	/**
	 * The event's appointment slots by host and time.
	 *
	 * @param eventId the event
	 * @return the tab's slots, the event's dates and what the person may do
	 */
	@AuraEnabled
	public static Appointments getAppointments(Id eventId) {
		try {
			Appointments result = new Appointments();
			result.canAdd = Schema.SObjectType.Event_Appointment__c.isCreateable();
			result.canBook =
				Schema.SObjectType.Event_Appointment__c.isUpdateable() &&
				Schema.SObjectType.Event_Appointment__c.fields.Contact__c.isUpdateable();
			Map<String, Schema.SObjectField> fields = Schema.SObjectType.Event_Appointment__c.fields.getMap();
			for (
				String name : new List<String>{
					'Host__c',
					'Contact__c',
					'Status__c',
					'Location__c'
				}
			) {
				result.fieldLabels.put(name, fields.get(name).getDescribe().getLabel());
			}
			result.fieldLabels.put('Start__c', fields.get('Start__c').getDescribe().getLabel());
			for (Event__c record : [
				SELECT Start__c, End__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				result.eventStart = record.Start__c;
				result.eventEnd = record.End__c;
			}
			Integer maxRows = MAX_SLOTS * 5 + 1;
			List<Event_Appointment__c> rows = [
				SELECT
					Id,
					Name,
					Host__c,
					Host__r.Name,
					Contact__c,
					Contact__r.Name,
					Start__c,
					End__c,
					Status__c,
					Location__c
				FROM Event_Appointment__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Start__c ASC, Name
				LIMIT :maxRows
			];
			result.truncated = rows.size() > MAX_SLOTS * 5;
			for (Integer i = 0; i < rows.size() && i < MAX_SLOTS * 5; i++) {
				result.slots.add(toSlot(rows[i]));
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getAppointments', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Appointments_LoadFailed')
			);
		}
	}

	/**
	 * Adds open slots for a host at the times given.
	 *
	 * @param eventId the event
	 * @param hostId the Core person who hosts
	 * @param slotsJson the slots as JSON, `[{ "start": "...", "finish": "..." }]`
	 * @param location where they happen, or empty
	 * @return how many slots were added
	 */
	@AuraEnabled
	public static Integer addSlots(Id eventId, Id hostId, String slotsJson, String location) {
		try {
			List<NewSlot> wanted = (List<NewSlot>) JSON.deserialize(slotsJson, List<NewSlot>.class);
			if (wanted == null || wanted.isEmpty() || wanted.size() > MAX_SLOTS) {
				throw new System.IllegalArgumentException(
					BarnHelp.text(
						'Events',
						'Events_Appointments_BadSlots',
						new List<Object>{ MAX_SLOTS }
					)
				);
			}
			String hostName = '';
			for (Contact host : [SELECT Name FROM Contact WHERE Id = :hostId WITH USER_MODE]) {
				hostName = host.Name;
			}
			List<Event_Appointment__c> toAdd = new List<Event_Appointment__c>();
			for (NewSlot slot : wanted) {
				toAdd.add(
					new Event_Appointment__c(
						Event__c = eventId,
						Host__c = hostId,
						Name = title(hostName, slot.start),
						Start__c = slot.start,
						End__c = slot.finish,
						Status__c = 'Open',
						Location__c = String.isBlank(location) ? null : location.left(255)
					)
				);
			}
			insert as user toAdd;
			return toAdd.size();
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.addSlots', eventId);
			throw e instanceof System.IllegalArgumentException
				? UserErrors.message(e.getMessage())
				: UserErrors.wrapShowingDml(
						e,
						BarnHelp.text('Events', 'Events_Appointments_AddFailed')
				  );
		}
	}

	/**
	 * Books a person into an open slot. A person cannot hold two booked slots at the same time
	 * in one event.
	 *
	 * @param appointmentId the slot
	 * @param contactId the Core person
	 */
	@AuraEnabled
	public static void book(Id appointmentId, Id contactId) {
		try {
			Event_Appointment__c slot = locked(appointmentId);
			if (slot.Status__c != 'Open') {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Appointments_NotOpen')
				);
			}
			Integer busy = [
				SELECT COUNT()
				FROM Event_Appointment__c
				WHERE
					Event__c = :slot.Event__c
					AND Contact__c = :contactId
					AND Status__c = 'Booked'
					AND Id != :slot.Id
					AND Start__c < :slot.End__c
					AND End__c > :slot.Start__c
				WITH USER_MODE
			];
			if (busy > 0) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Appointments_PersonBusy')
				);
			}
			// Only the changed fields: the locked row carries Event__c, a master-detail that
			// cannot be reparented, which a user-mode update refuses as not editable.
			update as user new Event_Appointment__c(
				Id = slot.Id,
				Contact__c = contactId,
				Status__c = 'Booked'
			);
		} catch (Exception e) {
			fail(e, '.book', appointmentId);
		}
	}

	/**
	 * Moves a slot to Open (clearing its person), Completed, No-Show or Cancelled. Completed and
	 * No-Show need a booked person; Cancelled keeps the person on the record.
	 *
	 * @param appointmentId the slot
	 * @param status the new status
	 */
	@AuraEnabled
	public static void setStatus(Id appointmentId, String status) {
		try {
			if (!TARGET_STATUSES.contains(status)) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Appointments_BadStatus')
				);
			}
			Event_Appointment__c slot = locked(appointmentId);
			if ((status == 'Completed' || status == 'No-Show') && slot.Contact__c == null) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Appointments_NoPerson')
				);
			}
			Event_Appointment__c change = new Event_Appointment__c(
				Id = slot.Id,
				Status__c = status
			);
			if (status == 'Open') {
				change.Contact__c = null;
			}
			update as user change;
		} catch (Exception e) {
			fail(e, '.setStatus', appointmentId);
		}
	}

	private static Event_Appointment__c locked(Id appointmentId) {
		for (Event_Appointment__c slot : [
			SELECT Id, Event__c, Contact__c, Start__c, End__c, Status__c
			FROM Event_Appointment__c
			WHERE Id = :appointmentId
			WITH USER_MODE
			FOR UPDATE
		]) {
			return slot;
		}
		throw new System.IllegalArgumentException(
			BarnHelp.text('Events', 'Events_Appointments_Gone')
		);
	}

	private static void fail(Exception e, String method, Id recordId) {
		ErrorLogger.log(e, CONTEXT + method, recordId);
		throw e instanceof System.IllegalArgumentException
			? UserErrors.message(e.getMessage())
			: UserErrors.wrapShowingDml(
					e,
					BarnHelp.text('Events', 'Events_Appointments_SaveFailed')
			  );
	}

	private static String title(String hostName, Datetime start) {
		String clock = start == null ? '' : start.format('h:mm a');
		return (hostName + ' ' + clock).trim().left(80);
	}

	private static Slot toSlot(Event_Appointment__c record) {
		Slot slot = new Slot();
		slot.id = record.Id;
		slot.name = record.Name;
		slot.hostId = record.Host__c;
		slot.hostName = record.Host__r == null ? null : record.Host__r.Name;
		slot.contactId = record.Contact__c;
		slot.contactName = record.Contact__r == null ? null : record.Contact__r.Name;
		slot.start = record.Start__c;
		slot.finish = record.End__c;
		slot.status = record.Status__c;
		slot.location = record.Location__c;
		return slot;
	}
}
