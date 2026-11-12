/**
 * Event Management's public pages (EV-16; ADR-0190 public event pages, decisions 2, 3, 5 and 6;
 * canonical model R-EV5). Core finds this class by name (`PublicPageExtensions`) and BarnCRM
 * Forms serves what it returns on its Salesforce Site page and REST API; without Forms nothing
 * calls it.
 *
 * `without sharing`, system mode reads, because a Site guest user has no object access. It
 * reads only an event whose Public Page is on and whose status is Open or Closed, and only the
 * fields the ADR lists: never the online link, capacity, codes, registrations, attendees or any
 * person field but a confirmed speaker's name, and speakers only with Show Speakers. Seats left
 * are counts. Every text is finished here, from the help catalog, so a host needs no Events
 * vocabulary.
 */
@NamespaceAccessible
public without sharing class EventPublicPage implements PublicPageExtension {
	public static final String KIND = 'events';
	public static final String OPEN = 'Open';
	public static final String NOT_YET = 'NotYet';
	public static final String CLOSED = 'Closed';
	public static final String NONE = 'None';
	private static final Set<String> SHOWN_STATUSES = new Set<String>{ 'Open', 'Closed' };
	private static final String CONFIRMED = 'Confirmed';
	private static final Integer LIST_LIMIT = 50;
	private static final Integer ITEM_LIMIT = 200;

	/** Set by tests to move the clock. */
	@TestVisible
	private static Datetime nowForTest;

	@NamespaceAccessible
	public EventPublicPage() {
		// Built by name from Core (PublicPageExtensions), so it needs a public constructor.
	}

	public String kind() {
		return KIND;
	}

	public Boolean handles(Schema.SObjectType recordType) {
		return recordType == Event__c.SObjectType;
	}

	public Map<String, Object> page(Id recordId) {
		Datetime current = now();
		// One query for the event with its tickets, sessions and speakers: a public page is the
		// busiest read the module has, and each list used to cost a query of its own.
		List<Event__c> events = [
			SELECT
				Id,
				Name,
				Description__c,
				Start__c,
				End__c,
				Format__c,
				Status__c,
				Venue_Name__c,
				Venue_Address__c,
				Capacity__c,
				Registration_Opens__c,
				Registration_Closes__c,
				Registration_Form_Key__c,
				Public_Speakers__c,
				Public_Seats__c,
				(
					SELECT
						Id,
						Name,
						Description__c,
						Price__c,
						Quantity__c,
						Sales_Start__c,
						Sales_End__c
					FROM Ticket_Types__r
					WHERE Active__c = TRUE AND (Sales_End__c = NULL OR Sales_End__c >= :current)
					ORDER BY Sort_Order__c ASC NULLS LAST, Name
					LIMIT :ITEM_LIMIT
				),
				(
					SELECT
						Id,
						Name,
						Description__c,
						Start__c,
						End__c,
						Room__c,
						Session_Type__c,
						Track__r.Name
					FROM Sessions__r
					WHERE Status__c = :CONFIRMED
					ORDER BY Start__c ASC NULLS LAST, Name
					LIMIT :ITEM_LIMIT
				),
				(
					SELECT Headline__c, Bio__c, Contact__r.FirstName, Contact__r.LastName
					FROM Speakers__r
					WHERE Status__c = :CONFIRMED
					ORDER BY Contact__r.LastName, Contact__r.FirstName
					LIMIT :ITEM_LIMIT
				)
			FROM Event__c
			WHERE Id = :recordId AND Public_Page__c = TRUE AND Status__c IN :SHOWN_STATUSES
			WITH SYSTEM_MODE
		];
		if (events.isEmpty()) {
			return null;
		}
		Event__c event = events[0];
		Map<String, Object> view = new Map<String, Object>{
			'kind' => KIND,
			'recordId' => event.Id,
			'title' => event.Name,
			'description' => event.Description__c,
			'start' => event.Start__c,
			'end' => event.End__c,
			'timeZone' => UserInfo.getTimeZone().getID(),
			'facts' => facts(event)
		};
		List<Object> sections = new List<Object>();
		addSection(
			sections,
			'tickets',
			BarnHelp.text('Events', 'Events_Public_Tickets'),
			tickets(event)
		);
		Map<Id, List<String>> speakersBySession = event.Public_Speakers__c
			? speakerNamesBySession(event.Id)
			: new Map<Id, List<String>>();
		addSection(
			sections,
			'agenda',
			BarnHelp.text('Events', 'Events_Public_Agenda'),
			sessions(event, speakersBySession)
		);
		if (event.Public_Speakers__c) {
			addSection(
				sections,
				'speakers',
				BarnHelp.text('Events', 'Events_Public_Speakers'),
				speakers(event)
			);
		}
		view.put('sections', sections);
		String registration = registrationState(event);
		view.put('registration', registration);
		view.put('formId', registration == NONE ? null : formIdOf(event));
		view.put('message', registrationMessage(registration));
		view.put('offlineMessage', BarnHelp.text('Events', 'Events_Public_RegisterOffline'));
		return view;
	}

	public Map<String, Object> listPage() {
		Datetime current = now();
		List<Object> items = new List<Object>();
		for (Event__c event : [
			SELECT Id, Name, Start__c, End__c, Format__c, Venue_Name__c
			FROM Event__c
			WHERE Public_Page__c = TRUE AND Status__c IN :SHOWN_STATUSES AND End__c >= :current
			WITH SYSTEM_MODE
			ORDER BY Start__c ASC
			LIMIT :LIST_LIMIT
		]) {
			items.add(
				new Map<String, Object>{
					'recordId' => event.Id,
					'title' => event.Name,
					'subtitle' => String.isNotBlank(event.Venue_Name__c)
						? event.Venue_Name__c
						: event.Format__c,
					'start' => event.Start__c,
					'end' => event.End__c
				}
			);
		}
		return new Map<String, Object>{
			'kind' => KIND,
			'title' => BarnHelp.text('Events', 'Events_Public_ListTitle'),
			'empty' => BarnHelp.text('Events', 'Events_Public_ListEmpty'),
			'timeZone' => UserInfo.getTimeZone().getID(),
			'items' => items
		};
	}

	/** Open, NotYet, Closed or None (no form named): when the form is shown (R-EV5). */
	@TestVisible
	private static String registrationState(Event__c event) {
		if (formIdOf(event) == null) {
			return NONE;
		}
		Datetime current = now();
		if (
			event.Status__c != OPEN ||
			current > event.End__c ||
			(event.Registration_Closes__c != null &&
			current > event.Registration_Closes__c)
		) {
			return CLOSED;
		}
		if (event.Registration_Opens__c != null && current < event.Registration_Opens__c) {
			return NOT_YET;
		}
		return OPEN;
	}

	private static String registrationMessage(String state) {
		if (state == NONE) {
			return BarnHelp.text('Events', 'Events_Public_RegisterOffline');
		}
		if (state == CLOSED) {
			return BarnHelp.text('Events', 'Events_Public_RegisterClosed');
		}
		if (state == NOT_YET) {
			return BarnHelp.text('Events', 'Events_Public_RegisterNotYet');
		}
		return BarnHelp.text('Events', 'Events_Public_RegisterOpen');
	}

	private static Id formIdOf(Event__c event) {
		if (String.isBlank(event.Registration_Form_Key__c)) {
			return null;
		}
		try {
			return Id.valueOf(event.Registration_Form_Key__c.trim());
		} catch (Exception notAnId) {
			return null;
		}
	}

	private static List<Object> facts(Event__c event) {
		List<Object> found = new List<Object>();
		List<String> place = new List<String>();
		if (String.isNotBlank(event.Venue_Name__c)) {
			place.add(event.Venue_Name__c);
		}
		if (String.isNotBlank(event.Venue_Address__c)) {
			place.add(event.Venue_Address__c);
		}
		if (!place.isEmpty()) {
			found.add(
				fact(BarnHelp.text('Events', 'Events_Public_Where'), String.join(place, ', '))
			);
		}
		if (String.isNotBlank(event.Format__c)) {
			found.add(fact(BarnHelp.text('Events', 'Events_Public_Format'), event.Format__c));
		}
		return found;
	}

	private static Map<String, Object> fact(String label, String value) {
		return new Map<String, Object>{ 'label' => label, 'value' => value };
	}

	/**
	 * Active tickets whose sales have not ended (read with the event), with price and, if
	 * published, seats left.
	 */
	private static List<Object> tickets(Event__c event) {
		Datetime current = now();
		List<Ticket_Type__c> tickets = event.Ticket_Types__r;
		Map<Id, Integer> left = event.Public_Seats__c
			? EventRegistrationService.seatsLeft(event, tickets)
			: new Map<Id, Integer>();
		String currencyCode = UserInfo.getDefaultCurrency();
		// EV-20: with payment taken online, the note says the link is emailed after registering.
		String note = EventPayments.takesOnline()
			? BarnHelp.text('Events', 'Events_Public_PayOnlineNote')
			: EventsSettings.publicPaymentNote();
		List<Object> items = new List<Object>();
		for (Ticket_Type__c ticket : tickets) {
			Decimal price = ticket.Price__c == null ? 0 : ticket.Price__c;
			List<String> badges = new List<String>();
			Map<String, Object> item = new Map<String, Object>{
				'title' => ticket.Name,
				'text' => ticket.Description__c
			};
			if (price > 0) {
				item.put('amount', price);
				item.put('currency', currencyCode);
				item.put('note', note);
			} else {
				badges.add(BarnHelp.text('Events', 'Events_Public_Free'));
			}
			if (ticket.Sales_Start__c != null && ticket.Sales_Start__c > current) {
				badges.add(BarnHelp.text('Events', 'Events_Public_NotOnSale'));
			}
			if (left.containsKey(ticket.Id)) {
				Integer seats = left.get(ticket.Id);
				badges.add(
					seats > 0
						? BarnHelp.text(
								'Events',
								'Events_Public_SeatsLeft',
								new List<Object>{ seats }
						  )
						: BarnHelp.text('Events', 'Events_Public_Full')
				);
			}
			item.put('badges', badges);
			items.add(item);
		}
		return items;
	}

	/** Confirmed sessions, read with the event. */
	private static List<Object> sessions(Event__c event, Map<Id, List<String>> speakersBySession) {
		List<Object> items = new List<Object>();
		for (Event_Session__c session : event.Sessions__r) {
			List<String> parts = new List<String>();
			for (
				String part : new List<String>{
					session.Track__r?.Name,
					session.Room__c,
					session.Session_Type__c
				}
			) {
				if (String.isNotBlank(part)) {
					parts.add(part);
				}
			}
			List<String> names = speakersBySession.get(session.Id);
			items.add(
				new Map<String, Object>{
					'title' => session.Name,
					'subtitle' => String.join(parts, ', '),
					'text' => session.Description__c,
					'start' => session.Start__c,
					'end' => session.End__c,
					'badges' => names == null
						? new List<String>()
						: new List<String>{
								BarnHelp.text(
									'Events',
									'Events_Public_With',
									new List<Object>{ String.join(names, ', ') }
								)
						  }
				}
			);
		}
		return items;
	}

	/** Confirmed speakers' names by confirmed session: names only. */
	private static Map<Id, List<String>> speakerNamesBySession(Id eventId) {
		Map<Id, List<String>> names = new Map<Id, List<String>>();
		for (Session_Speaker__c assignment : [
			SELECT
				Event_Session__c,
				Event_Speaker__r.Contact__r.FirstName,
				Event_Speaker__r.Contact__r.LastName
			FROM Session_Speaker__c
			WHERE
				Event_Session__r.Event__c = :eventId
				AND Event_Session__r.Status__c = :CONFIRMED
				AND Event_Speaker__r.Status__c = :CONFIRMED
			WITH SYSTEM_MODE
			ORDER BY Event_Speaker__r.Contact__r.LastName
			LIMIT 1000
		]) {
			if (!names.containsKey(assignment.Event_Session__c)) {
				names.put(assignment.Event_Session__c, new List<String>());
			}
			names.get(assignment.Event_Session__c)
				.add(
					nameOf(
						assignment.Event_Speaker__r.Contact__r.FirstName,
						assignment.Event_Speaker__r.Contact__r.LastName
					)
				);
		}
		return names;
	}

	/** Confirmed speakers, read with the event. */
	private static List<Object> speakers(Event__c event) {
		List<Object> items = new List<Object>();
		for (Event_Speaker__c speaker : event.Speakers__r) {
			items.add(
				new Map<String, Object>{
					'title' => nameOf(speaker.Contact__r.FirstName, speaker.Contact__r.LastName),
					'subtitle' => speaker.Headline__c,
					'text' => speaker.Bio__c
				}
			);
		}
		return items;
	}

	private static String nameOf(String first, String last) {
		return String.isBlank(first) ? last : first + ' ' + last;
	}

	private static void addSection(
		List<Object> sections,
		String key,
		String title,
		List<Object> items
	) {
		if (!items.isEmpty()) {
			sections.add(
				new Map<String, Object>{ 'key' => key, 'title' => title, 'items' => items }
			);
		}
	}

	private static Datetime now() {
		return nowForTest != null ? nowForTest : Datetime.now();
	}
}
