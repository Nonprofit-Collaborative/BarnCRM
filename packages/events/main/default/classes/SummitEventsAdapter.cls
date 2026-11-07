/**
 * Summit Events compatibility (EV-10; ADR-NEXT `NEXT-event-registrations.md`, decision 7).
 *
 * Summit Events is a separate package many orgs do not have, so its objects are named only in
 * strings built at run time and read with dynamic SOQL: nothing here is checked by the compiler,
 * the package installs and runs without Summit, and with Summit absent `isInstalled()` is false
 * and no step is added to the nightly run.
 *
 * With Summit present, each Summit registration (not Started or Cancelled) becomes a registration
 * with one attendee through `EventRegistrationService`, so the registrant lands in Core people by
 * Core's matcher and is never a duplicate. Its Summit instance becomes an event, created once and
 * found again by `Event__c.External_Key__c`; the registration is keyed by
 * `Event_Registration__c.External_Key__c` and imported once. The matched person is written back
 * to Summit's contact field when it is blank. Summit's own person handling outside its contact
 * field is not read or written here (the standard-object rule, plan 4.2).
 *
 * Records are read as plain maps of lower-case field names, so the tests (no test org has
 * Summit) give the same maps.
 */
public with sharing class SummitEventsAdapter {
	/** Every external key this adapter writes starts with this. */
	public static final String KEY_PREFIX = 'summit:';
	/** Registrations changed within this many days are looked at each morning. */
	public static final Integer CHANGED_DAYS = 2;
	private static final String SUMMIT = 'summit';
	private static final String SEPARATOR = '__';
	@TestVisible
	private static final String REGISTRATION_OBJECT = summitName('Summit_Events_Registration', 'c');
	@TestVisible
	private static final String INSTANCE_OBJECT = summitName('Summit_Events_Instance', 'c');
	@TestVisible
	private static final String R_INSTANCE = summitName('Event_Instance', 'c');
	@TestVisible
	private static final String R_CONTACT = summitName('Contact', 'c');
	@TestVisible
	private static final String R_STATUS = summitName('Status', 'c');
	@TestVisible
	private static final String R_FIRST = summitName('Registrant_First_Name', 'c');
	@TestVisible
	private static final String R_LAST = summitName('Registrant_Last_Name', 'c');
	@TestVisible
	private static final String R_EMAIL = summitName('Registrant_Email', 'c');
	@TestVisible
	private static final String R_POSTAL = summitName('Registrant_Zip', 'c');
	private static final String I_EVENT = summitName('Event', 'c');
	@TestVisible
	private static final String I_EVENT_RELATION = summitName('Event', 'r');
	@TestVisible
	private static final String I_TITLE = summitName('Instance_Title', 'c');
	@TestVisible
	private static final String I_START_DATE = summitName('Instance_Start_Date', 'c');
	@TestVisible
	private static final String I_START_TIME = summitName('Instance_Start_Time', 'c');
	@TestVisible
	private static final String I_END_DATE = summitName('Instance_End_Date', 'c');
	@TestVisible
	private static final String I_END_TIME = summitName('Instance_End_Time', 'c');
	private static final List<String> REGISTRATION_FIELDS = new List<String>{
		R_INSTANCE,
		R_CONTACT,
		R_STATUS,
		R_FIRST,
		R_LAST,
		R_EMAIL,
		R_POSTAL
	};
	private static final List<String> INSTANCE_FIELDS = new List<String>{
		I_TITLE,
		I_START_DATE,
		I_START_TIME,
		I_END_DATE,
		I_END_TIME
	};
	private static final Set<String> NOT_IMPORTED = new Set<String>{
		'started',
		'cancelled',
		'canceled'
	};
	private static final Integer NAME_LENGTH = 80;
	private static final String LOG_CONTEXT = 'SummitEventsAdapter';

	/** A test stands in for Summit's instances: rows as `instanceRow` makes them, by identifier. */
	@TestVisible
	private static Map<String, Map<String, Object>> instancesForTest;
	/** The contacts to write back to Summit, by registration; a test reads them. */
	@TestVisible
	private static Map<String, Id> writtenBack = new Map<String, Id>();

	private static Map<String, Schema.SObjectType> typesByName;

	private static String summitName(String name, String suffix) {
		return (SUMMIT + SEPARATOR + name + SEPARATOR + suffix).toLowerCase();
	}

	/** Whether Summit Events is installed, with the fields this adapter needs. */
	public static Boolean isInstalled() {
		Set<String> registration = fieldsOf(REGISTRATION_OBJECT);
		return registration.contains(R_INSTANCE) &&
			registration.contains(R_LAST) &&
			fieldsOf(INSTANCE_OBJECT).contains(I_START_DATE);
	}

	/** Whether the morning import has work: Event Management is on and Summit is installed. */
	public static Boolean isActive() {
		return EventEmailService.moduleOn() && isInstalled();
	}

	/** Summit's registrations to look at, in system mode: the import acts for the organization. */
	public static Database.QueryLocator locator() {
		String query =
			'SELECT ' +
			String.join(present(REGISTRATION_OBJECT, REGISTRATION_FIELDS, 'Id'), ', ') +
			' FROM ' +
			REGISTRATION_OBJECT +
			' WHERE ' +
			R_INSTANCE +
			' != NULL';
		// The first import takes every registration; later ones only those changed lately.
		if (importedBefore()) {
			query += ' AND LastModifiedDate >= :since';
		}
		return Database.getQueryLocatorWithBinds(
			query,
			new Map<String, Object>{ 'since' => Datetime.now().addDays(-CHANGED_DAYS) },
			AccessLevel.SYSTEM_MODE
		);
	}

	private static List<String> present(String objectName, List<String> wanted, String first) {
		Set<String> fields = fieldsOf(objectName);
		List<String> found = new List<String>{ first };
		for (String name : wanted) {
			if (fields.contains(name)) {
				found.add(name);
			}
		}
		return found;
	}

	private static Boolean importedBefore() {
		String prefix = KEY_PREFIX + '%';
		return ![
				SELECT Id
				FROM Event__c
				WHERE External_Key__c LIKE :prefix
				WITH SYSTEM_MODE
				LIMIT 1
			]
			.isEmpty();
	}

	/** Imports one chunk of Summit registrations. Returns how many were imported. */
	public static Integer importRecords(List<SObject> records) {
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		for (SObject record : records) {
			rows.add(registrationRow(lowerKeys(record.getPopulatedFieldsAsMap())));
		}
		return importRows(rows);
	}

	private static Map<String, Object> lowerKeys(Map<String, Object> fields) {
		Map<String, Object> lower = new Map<String, Object>();
		for (String name : fields.keySet()) {
			lower.put(name.toLowerCase(), fields.get(name));
		}
		return lower;
	}

	/** A Summit registration's fields (lower-case names) as the row `importRows` takes. */
	@TestVisible
	private static Map<String, Object> registrationRow(Map<String, Object> fields) {
		return new Map<String, Object>{
			'id' => fields.get('id'),
			'instanceId' => fields.get(R_INSTANCE),
			'contactId' => fields.get(R_CONTACT),
			'status' => fields.get(R_STATUS),
			'firstName' => fields.get(R_FIRST),
			'lastName' => fields.get(R_LAST),
			'email' => fields.get(R_EMAIL),
			'postalCode' => fields.get(R_POSTAL)
		};
	}

	/**
	 * Imports Summit registrations given as rows (keys id, instanceId, contactId, status,
	 * firstName, lastName, email, postalCode). A registration already imported, Started or
	 * Cancelled, or with no person, is left out; one that cannot be registered is counted and
	 * logged once for the chunk, and the rest still import.
	 */
	@TestVisible
	private static Integer importRows(List<Map<String, Object>> rows) {
		Map<String, Map<String, Object>> byKey = new Map<String, Map<String, Object>>();
		for (Map<String, Object> row : rows) {
			if (wanted(row)) {
				byKey.put(KEY_PREFIX + String.valueOf(row.get('id')), row);
			}
		}
		for (Event_Registration__c done : [
			SELECT External_Key__c
			FROM Event_Registration__c
			WHERE External_Key__c IN :byKey.keySet()
			WITH SYSTEM_MODE
		]) {
			byKey.remove(done.External_Key__c);
		}
		if (byKey.isEmpty()) {
			return 0;
		}
		Set<String> instanceIds = new Set<String>();
		for (Map<String, Object> row : byKey.values()) {
			instanceIds.add(String.valueOf(row.get('instanceId')));
		}
		Map<String, Id> eventsByInstance = eventsFor(instanceIds);

		Integer imported = 0;
		Integer failed = 0;
		String lastReason;
		for (String key : byKey.keySet()) {
			Map<String, Object> row = byKey.get(key);
			try {
				Id eventId = eventsByInstance.get(String.valueOf(row.get('instanceId')));
				EventRegistrationService.Result result = EventRegistrationService.register(
					request(eventId, key, row)
				);
				imported++;
				if (row.get('contactId') == null && result.registrantId != null) {
					writtenBack.put(String.valueOf(row.get('id')), result.registrantId);
				}
			} catch (Exception notRegistered) {
				failed++;
				lastReason = notRegistered.getMessage();
			}
		}
		writeBack();
		if (failed > 0) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Events',
					'Events_Summit_ImportFailed',
					new List<Object>{ failed, byKey.size(), lastReason }
				),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		return imported;
	}

	private static Boolean wanted(Map<String, Object> row) {
		String status = row.get('status') == null
			? ''
			: String.valueOf(row.get('status')).toLowerCase();
		Boolean hasPerson =
			row.get('contactId') != null || String.isNotBlank((String) row.get('lastName'));
		return row.get('id') != null &&
			row.get('instanceId') != null &&
			hasPerson &&
			!NOT_IMPORTED.contains(status);
	}

	private static EventRegistrationService.Request request(
		Id eventId,
		String key,
		Map<String, Object> row
	) {
		EventPersonMatcher.PersonInput person = new EventPersonMatcher.PersonInput();
		person.contactId = row.get('contactId') == null
			? null
			: String.valueOf(row.get('contactId'));
		person.firstName = (String) row.get('firstName');
		person.lastName = (String) row.get('lastName');
		person.email = (String) row.get('email');
		person.postalCode = (String) row.get('postalCode');
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		// An instance with no event (it could not be read or saved) fails here, counted.
		request.eventId = String.valueOf(eventId);
		request.registrant = person;
		request.source = EventRegistrationService.SOURCE_SUMMIT;
		request.attendeeStatus = attendeeStatus((String) row.get('status'));
		request.registrationValues.put('External_Key__c', key);
		return request;
	}

	/** Summit's status as an attendee status: Attended, No-Show or Registered. */
	@TestVisible
	private static String attendeeStatus(String summitStatus) {
		String word = summitStatus == null
			? ''
			: summitStatus.toLowerCase().replaceAll('[^a-z]', '');
		if (word.contains('noshow') || word.contains('notattend')) {
			return EventRegistrationService.STATUS_NO_SHOW;
		}
		if (word.contains('attend')) {
			return EventRegistrationService.STATUS_ATTENDED;
		}
		return EventRegistrationService.STATUS_REGISTERED;
	}

	/** The event for each Summit instance, created the first time it is seen. */
	private static Map<String, Id> eventsFor(Set<String> instanceIds) {
		Map<String, String> keyToInstance = new Map<String, String>();
		for (String instanceId : instanceIds) {
			keyToInstance.put(KEY_PREFIX + instanceId, instanceId);
		}
		Map<String, Id> byInstance = new Map<String, Id>();
		for (Event__c event : [
			SELECT Id, External_Key__c
			FROM Event__c
			WHERE External_Key__c IN :keyToInstance.keySet()
			WITH SYSTEM_MODE
		]) {
			byInstance.put(keyToInstance.get(event.External_Key__c), event.Id);
		}
		Set<String> missing = new Set<String>(instanceIds);
		missing.removeAll(byInstance.keySet());
		if (missing.isEmpty()) {
			return byInstance;
		}
		List<Event__c> created = new List<Event__c>();
		List<String> createdFor = new List<String>();
		for (Map<String, Object> instance : instances(missing)) {
			created.add(eventFrom(instance));
			createdFor.add(String.valueOf(instance.get('id')));
		}
		List<Database.SaveResult> saved = Database.insert(created, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < saved.size(); i++) {
			if (saved[i].isSuccess()) {
				byInstance.put(createdFor[i], saved[i].getId());
			}
		}
		return byInstance;
	}

	@TestVisible
	private static Event__c eventFrom(Map<String, Object> instance) {
		Date startDate = (Date) instance.get('startDate');
		Date endDate = instance.get('endDate') == null ? startDate : (Date) instance.get('endDate');
		Time startTime = instance.get('startTime') == null
			? Time.newInstance(0, 0, 0, 0)
			: (Time) instance.get('startTime');
		Time endTime = instance.get('endTime') == null
			? Time.newInstance(23, 59, 0, 0)
			: (Time) instance.get('endTime');
		Datetime starts = Datetime.newInstance(startDate, startTime);
		Datetime ends = Datetime.newInstance(endDate, endTime);
		if (ends <= starts) {
			ends = starts.addHours(1);
		}
		String name = String.isNotBlank((String) instance.get('title'))
			? (String) instance.get('title')
			: (String) instance.get('eventName');
		return new Event__c(
			Name = String.isBlank(name) ? KEY_PREFIX + instance.get('id') : name.left(NAME_LENGTH),
			Start__c = starts,
			End__c = ends,
			Status__c = ends < Datetime.now() ? 'Completed' : 'Open',
			Format__c = 'In Person',
			External_Key__c = KEY_PREFIX + instance.get('id')
		);
	}

	/** Summit's instances as rows; an instance without a start date is left out. */
	private static List<Map<String, Object>> instances(Set<String> instanceIds) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		for (Map<String, Object> fields : instanceFields(instanceIds)) {
			Map<String, Object> row = instanceRow(fields);
			if (row != null) {
				found.add(row);
			}
		}
		return found;
	}

	private static List<Map<String, Object>> instanceFields(Set<String> instanceIds) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		if (instancesForTest != null) {
			for (String instanceId : instanceIds) {
				if (instancesForTest.containsKey(instanceId)) {
					found.add(instancesForTest.get(instanceId));
				}
			}
			return found;
		}
		List<String> fields = present(INSTANCE_OBJECT, INSTANCE_FIELDS, 'Id');
		fields.add('Name');
		if (fieldsOf(INSTANCE_OBJECT).contains(I_EVENT)) {
			fields.add(I_EVENT_RELATION + '.Name');
		}
		for (
			SObject record : Database.queryWithBinds(
				'SELECT ' +
					String.join(fields, ', ') +
					' FROM ' +
					INSTANCE_OBJECT +
					' WHERE Id IN :ids',
				new Map<String, Object>{ 'ids' => instanceIds },
				AccessLevel.SYSTEM_MODE
			)
		) {
			found.add(lowerKeys(record.getPopulatedFieldsAsMap()));
		}
		return found;
	}

	/** A Summit instance's fields (lower-case names) as an event row, or null with no start. */
	@TestVisible
	private static Map<String, Object> instanceRow(Map<String, Object> fields) {
		if (!(fields.get(I_START_DATE) instanceof Date)) {
			return null;
		}
		Object parent = fields.get(I_EVENT_RELATION);
		return new Map<String, Object>{
			'id' => String.valueOf(fields.get('id')),
			'title' => fields.get(I_TITLE),
			'eventName' => parent instanceof SObject
				? ((SObject) parent).get('Name')
				: fields.get('name'),
			'startDate' => fields.get(I_START_DATE),
			'startTime' => fields.get(I_START_TIME),
			'endDate' => fields.get(I_END_DATE),
			'endTime' => fields.get(I_END_TIME)
		};
	}

	/** Writes each matched person to Summit's contact field, where it was blank. */
	private static void writeBack() {
		if (writtenBack.isEmpty() || !fieldsOf(REGISTRATION_OBJECT).contains(R_CONTACT)) {
			return;
		}
		Schema.SObjectType registrationType = typesByName.get(REGISTRATION_OBJECT);
		List<SObject> updates = new List<SObject>();
		for (String registrationId : writtenBack.keySet()) {
			SObject record = registrationType.newSObject(Id.valueOf(registrationId));
			record.put(R_CONTACT, writtenBack.get(registrationId));
			updates.add(record);
		}
		Database.update(updates, false, AccessLevel.SYSTEM_MODE);
		writtenBack.clear();
	}

	/** The lower-case field names of an object, or none when it is not in this org. */
	private static Set<String> fieldsOf(String objectName) {
		if (typesByName == null) {
			typesByName = Schema.getGlobalDescribe();
		}
		Schema.SObjectType objectType = typesByName.get(objectName);
		if (objectType == null) {
			return new Set<String>();
		}
		return objectType.getDescribe().fields.getMap().keySet();
	}
}
