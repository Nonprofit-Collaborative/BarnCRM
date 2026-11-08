/**
 * Builds and removes the Event Management sample data set (C-10, canonical model 29EV1 and
 * 29EV8): a conference under way with tracks, sessions, speakers, ticket types, a promo code,
 * registrations whose attendees are partly checked in, sponsorship levels, sponsors with their
 * deliverables, and one speaker application with two reviews; and a small community event with
 * a few registrations. The people are Core's sample people and the sponsors are Core's sample
 * organizations. The events and the registrations carry `Sample_Data__c`; everything else goes
 * with its event. Every record is saved in user mode, as an administrator's would be.
 *
 * Removal deletes the sample registrations first (the registration's lookup to its event
 * restricts delete), then the sample events with everything under them.
 */
public with sharing class EventSampleDataLoader {
	public static final String CONFERENCE = 'Harvest Community Conference';
	public static final String COMMUNITY = 'Neighborhood Garden Night';
	private static final Integer PEOPLE_WANTED = 12;

	/** Records deleted per removeNext() call. Tests lower it. */
	@TestVisible
	private static Integer removeChunkSize = 200;

	// ------------------------------------------------------------------------- load

	/**
	 * The two events and everything under them. Nothing when Core's sample people are not there,
	 * or when the person loading has no Events set yet, so one module never breaks the load.
	 */
	public static void loadEvents() {
		if (!Schema.SObjectType.Event__c.isCreateable()) {
			return;
		}
		List<Contact> people = [
			SELECT Id, FirstName, LastName
			FROM Contact
			WHERE Sample_Data__c = TRUE
			WITH USER_MODE
			ORDER BY Sample_Data_Key__c NULLS LAST, Id
			LIMIT :PEOPLE_WANTED
		];
		if (people.isEmpty()) {
			return;
		}
		Date today = Date.today();
		Event__c conference = new Event__c(
			Name = CONFERENCE,
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = Datetime.newInstance(today.addDays(-1), Time.newInstance(8, 30, 0, 0)),
			End__c = Datetime.newInstance(today.addDays(1), Time.newInstance(17, 0, 0, 0)),
			Registration_Opens__c = Datetime.newInstance(
				today.addDays(-40),
				Time.newInstance(9, 0, 0, 0)
			),
			Registration_Closes__c = Datetime.newInstance(today, Time.newInstance(17, 0, 0, 0)),
			Capacity__c = 150,
			Venue_Name__c = 'Riverside Meeting Hall',
			Venue_Address__c = '100 Example Street',
			Description__c = 'Three days of talks, workshops and panels for small nonprofit teams.',
			Sample_Data__c = true
		);
		Event__c community = new Event__c(
			Name = COMMUNITY,
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = Datetime.newInstance(today.addDays(14), Time.newInstance(18, 0, 0, 0)),
			End__c = Datetime.newInstance(today.addDays(14), Time.newInstance(20, 0, 0, 0)),
			Capacity__c = 40,
			Venue_Name__c = 'Community Garden Pavilion',
			Venue_Address__c = '25 Example Lane',
			Description__c = 'An evening to meet the neighbors and plan the planting season.',
			Sample_Data__c = true
		);
		Database.insert(new List<Event__c>{ conference, community }, AccessLevel.USER_MODE);

		loadConference(conference, people, today);
		loadCommunity(community, people);
	}

	private static void loadConference(Event__c conference, List<Contact> people, Date today) {
		List<Event_Track__c> tracks = new List<Event_Track__c>{
			track(conference, 'Programs', 1),
			track(conference, 'Operations', 2),
			track(conference, 'Technology', 3)
		};
		Database.insert(tracks, AccessLevel.USER_MODE);

		Ticket_Type__c general = ticket(conference, 'General', 45, 120, 1);
		Ticket_Type__c student = ticket(conference, 'Student', 15, 30, 2);
		Ticket_Type__c volunteer = ticket(conference, 'Volunteer', 0, 20, 3);
		Database.insert(
			new List<Ticket_Type__c>{ general, student, volunteer },
			AccessLevel.USER_MODE
		);

		Promo_Code__c code = new Promo_Code__c(
			Name = 'EARLYBIRD',
			Event__c = conference.Id,
			Discount_Type__c = 'Percent',
			Discount_Value__c = 20,
			Max_Uses__c = 25,
			Active__c = true,
			Valid_From__c = Datetime.newInstance(today.addDays(-40), Time.newInstance(9, 0, 0, 0)),
			Valid_Until__c = Datetime.newInstance(today.addDays(30), Time.newInstance(17, 0, 0, 0))
		);
		Database.insert(code, AccessLevel.USER_MODE);

		List<Event_Speaker__c> speakers = loadSpeakers(conference, slice(people, 0, 3));
		loadAgenda(conference, tracks, speakers, today);
		loadRegistrations(conference, code, general, student, volunteer, people);
		loadSponsors(conference, today);
		loadApplication(conference, tracks[2], people);
	}

	private static List<Event_Speaker__c> loadSpeakers(Event__c conference, List<Contact> chosen) {
		List<String> headlines = new List<String>{
			'Executive director and storyteller',
			'Volunteer program manager',
			'Data steward for a neighborhood food bank'
		};
		List<Event_Speaker__c> speakers = new List<Event_Speaker__c>();
		for (Integer i = 0; i < chosen.size(); i++) {
			speakers.add(
				new Event_Speaker__c(
					Event__c = conference.Id,
					Contact__c = chosen[i].Id,
					Name = name(chosen[i]),
					Status__c = 'Confirmed',
					Headline__c = headlines[i],
					Bio__c = 'Has worked with small nonprofit teams for many years.'
				)
			);
		}
		Database.insert(speakers, AccessLevel.USER_MODE);
		return speakers;
	}

	/** Eight sessions over the three days; the speakers are placed on the first four. */
	private static void loadAgenda(
		Event__c conference,
		List<Event_Track__c> tracks,
		List<Event_Speaker__c> speakers,
		Date today
	) {
		List<Event_Session__c> sessions = new List<Event_Session__c>{
			session(
				conference,
				'Opening Keynote',
				'Keynote',
				null,
				today.addDays(-1),
				9,
				10,
				'Main Hall',
				null
			),
			session(
				conference,
				'Fundraising Without Burnout',
				'Talk',
				tracks[0],
				today.addDays(-1),
				10,
				11,
				'Room A',
				60
			),
			session(
				conference,
				'Volunteer Onboarding Clinic',
				'Workshop',
				tracks[1],
				today.addDays(-1),
				10,
				12,
				'Room B',
				25
			),
			session(
				conference,
				'Lunch Break',
				'Break',
				null,
				today.addDays(-1),
				12,
				13,
				'Dining Room',
				null
			),
			session(
				conference,
				'Data Habits for Small Teams',
				'Talk',
				tracks[2],
				today,
				9,
				10,
				'Room A',
				60
			),
			session(
				conference,
				'Panel: Lessons from the First Year',
				'Panel',
				null,
				today,
				11,
				12,
				'Main Hall',
				null
			),
			session(
				conference,
				'Open Space Afternoon',
				'Other',
				null,
				today.addDays(1),
				13,
				15,
				'Main Hall',
				null
			),
			session(
				conference,
				'Closing Session',
				'Talk',
				null,
				today.addDays(1),
				15,
				16,
				'Main Hall',
				null
			)
		};
		sessions[7].Status__c = 'Draft';
		Database.insert(sessions, AccessLevel.USER_MODE);

		List<Session_Speaker__c> assignments = new List<Session_Speaker__c>();
		assignments.add(assignment(sessions[0], speakers, 0, 'Speaker'));
		assignments.add(assignment(sessions[1], speakers, 1, 'Speaker'));
		assignments.add(assignment(sessions[2], speakers, 2, 'Speaker'));
		assignments.add(assignment(sessions[4], speakers, 2, 'Speaker'));
		assignments.add(assignment(sessions[5], speakers, 0, 'Moderator'));
		assignments.add(assignment(sessions[5], speakers, 1, 'Panelist'));
		List<Session_Speaker__c> placed = new List<Session_Speaker__c>();
		for (Session_Speaker__c each : assignments) {
			if (each != null) {
				placed.add(each);
			}
		}
		Database.insert(placed, AccessLevel.USER_MODE);
	}

	/**
	 * Six registrations, one with a guest, partly checked in: the first two attendees, the
	 * student and the volunteer are Attended. A person is registered once per event.
	 */
	private static void loadRegistrations(
		Event__c conference,
		Promo_Code__c code,
		Ticket_Type__c general,
		Ticket_Type__c student,
		Ticket_Type__c volunteer,
		List<Contact> people
	) {
		Datetime now = Datetime.now();
		List<Registration> plan = new List<Registration>();
		plan.add(new Registration(people, 0, general, code, true).addPerson(people, 1, general));
		plan.add(new Registration(people, 2, student, null, true));
		plan.add(new Registration(people, 3, general, null, false));
		plan.add(new Registration(people, 4, general, code, false));
		plan.add(new Registration(people, 5, volunteer, null, true));
		plan.add(new Registration(people, 6, general, null, false));
		saveRegistrations(conference, plan, now);
	}

	private static void loadCommunity(Event__c community, List<Contact> people) {
		Ticket_Type__c free = ticket(community, 'Free Entry', 0, null, 1);
		Database.insert(free, AccessLevel.USER_MODE);
		List<Registration> plan = new List<Registration>();
		for (Integer i = 4; i < 8; i++) {
			plan.add(new Registration(people, i, free, null, false));
		}
		saveRegistrations(community, plan, Datetime.now());
	}

	/** A registration to make: the registrant, an optional guest, the ticket and the code. */
	private class Registration {
		List<Contact> attendees = new List<Contact>();
		List<Ticket_Type__c> tickets = new List<Ticket_Type__c>();
		Promo_Code__c code;
		Boolean checkedIn;

		Registration(
			List<Contact> people,
			Integer index,
			Ticket_Type__c ticket,
			Promo_Code__c code,
			Boolean checkedIn
		) {
			this.code = code;
			this.checkedIn = checkedIn;
			addPerson(people, index, ticket);
		}

		/** Adds the person at this place in the list, when the org has that many sample people. */
		Registration addPerson(List<Contact> people, Integer index, Ticket_Type__c ticket) {
			if (index < people.size()) {
				attendees.add(people[index]);
				tickets.add(ticket);
			}
			return this;
		}
	}

	private static void saveRegistrations(Event__c event, List<Registration> plan, Datetime now) {
		List<Registration> usable = new List<Registration>();
		for (Registration item : plan) {
			if (!item.attendees.isEmpty()) {
				usable.add(item);
			}
		}
		if (usable.isEmpty()) {
			return;
		}
		List<Event_Registration__c> registrations = new List<Event_Registration__c>();
		for (Registration item : usable) {
			registrations.add(
				new Event_Registration__c(
					Event__c = event.Id,
					Contact__c = item.attendees[0].Id,
					Promo_Code__c = item.code == null ? null : item.code.Id,
					Source__c = EventRegistrationService.SOURCE_STAFF,
					Status__c = EventRegistrationService.STATUS_REGISTERED,
					Sample_Data__c = true
				)
			);
		}
		Database.insert(registrations, AccessLevel.USER_MODE);

		List<Event_Attendee__c> attendees = new List<Event_Attendee__c>();
		for (Integer i = 0; i < usable.size(); i++) {
			Decimal owed = 0;
			for (Integer j = 0; j < usable[i].attendees.size(); j++) {
				Ticket_Type__c ticket = usable[i].tickets[j];
				Decimal price = EventPricing.priceWithCode(
					ticket.Price__c,
					usable[i].code,
					ticket.Id,
					now
				);
				owed += price;
				attendees.add(
					new Event_Attendee__c(
						Event_Registration__c = registrations[i].Id,
						Name = name(usable[i].attendees[j]).left(80),
						Contact__c = usable[i].attendees[j].Id,
						Ticket_Type__c = ticket.Id,
						Price__c = price,
						Status__c = usable[i].checkedIn
							? EventRegistrationService.STATUS_ATTENDED
							: EventRegistrationService.STATUS_REGISTERED
					)
				);
			}
			registrations[i].Amount_Owed__c = owed;
		}
		Database.insert(attendees, AccessLevel.USER_MODE);
		Database.update(registrations, AccessLevel.USER_MODE);
	}

	/** Three levels, three of Core's sample organizations as sponsors, and some deliverables. */
	private static void loadSponsors(Event__c conference, Date today) {
		Id organizationType = AccountKinds.organizationRecordTypeId();
		List<Account> organizations = [
			SELECT Id, Name
			FROM Account
			WHERE Sample_Data__c = TRUE AND RecordTypeId = :organizationType
			WITH USER_MODE
			ORDER BY Name
			LIMIT 3
		];
		Sponsorship_Level__c gold = level(
			conference,
			'Gold',
			2500,
			1,
			'Logo on the program\nBooth\nPasses: four conference passes'
		);
		Sponsorship_Level__c silver = level(
			conference,
			'Silver',
			1000,
			2,
			'Logo on the program\nPasses: two conference passes'
		);
		Sponsorship_Level__c supporter = level(
			conference,
			'Supporter',
			250,
			3,
			'Logo on the program'
		);
		Database.insert(
			new List<Sponsorship_Level__c>{ gold, silver, supporter },
			AccessLevel.USER_MODE
		);
		if (organizations.isEmpty()) {
			return;
		}
		List<Sponsorship_Level__c> levels = new List<Sponsorship_Level__c>{
			gold,
			silver,
			supporter
		};
		List<String> statuses = new List<String>{ 'Confirmed', 'Committed', 'Prospect' };
		List<Event_Sponsor__c> sponsors = new List<Event_Sponsor__c>();
		for (Integer i = 0; i < organizations.size(); i++) {
			sponsors.add(
				new Event_Sponsor__c(
					Event__c = conference.Id,
					Account__c = organizations[i].Id,
					Name = organizations[i].Name.left(80),
					Level__c = levels[i].Id,
					Amount__c = levels[i].Amount__c,
					Status__c = statuses[i]
				)
			);
		}
		Database.insert(sponsors, AccessLevel.USER_MODE);

		List<Sponsor_Deliverable__c> deliverables = new List<Sponsor_Deliverable__c>{
			deliverable(
				sponsors[0],
				'Logo on the program',
				'Logo',
				'Done',
				today.addDays(-20),
				null
			),
			deliverable(sponsors[0], 'Booth', 'Booth', 'Requested', today.addDays(-5), null),
			deliverable(
				sponsors[0],
				'Passes: four conference passes',
				'Passes',
				'Pending',
				today,
				4
			)
		};
		if (sponsors.size() > 1) {
			deliverables.add(
				deliverable(
					sponsors[1],
					'Logo on the program',
					'Logo',
					'Received',
					today.addDays(-10),
					null
				)
			);
		}
		Database.insert(deliverables, AccessLevel.USER_MODE);
	}

	/** One proposal for the Technology track, in review, with two scores. */
	private static void loadApplication(
		Event__c conference,
		Event_Track__c track,
		List<Contact> people
	) {
		Contact applicant = people[Math.min(3, people.size() - 1)];
		Speaker_Application__c application = new Speaker_Application__c(
			Event__c = conference.Id,
			Contact__c = applicant.Id,
			Name = 'Small Teams, Big Data',
			Abstract__c = 'How a three person team keeps clean records without a data department.',
			Track__c = track.Id,
			Status__c = 'In Review'
		);
		Database.insert(application, AccessLevel.USER_MODE);
		Database.insert(
			new List<Speaker_Review__c>{
				new Speaker_Review__c(
					Speaker_Application__c = application.Id,
					Reviewer__c = UserInfo.getUserId(),
					Score__c = 4,
					Notes__c = 'Practical and timely.'
				),
				new Speaker_Review__c(
					Speaker_Application__c = application.Id,
					Score__c = 5,
					Notes__c = 'A strong fit for the Technology track.'
				)
			},
			AccessLevel.USER_MODE
		);
	}

	// ------------------------------------------------------------------------- status card

	/** The sample events in the org. */
	public static Integer countSampleEvents() {
		if (!Schema.SObjectType.Event__c.isAccessible()) {
			return 0;
		}
		return [SELECT COUNT() FROM Event__c WHERE Sample_Data__c = TRUE WITH USER_MODE];
	}

	private static Integer countSampleRegistrations() {
		if (!Schema.SObjectType.Event_Registration__c.isAccessible()) {
			return 0;
		}
		return [
			SELECT COUNT()
			FROM Event_Registration__c
			WHERE Sample_Data__c = TRUE
			WITH USER_MODE
		];
	}

	// ------------------------------------------------------------------------- removal

	/** How many removeNext() calls clear every Events sample record. */
	public static Integer removeStageCount() {
		return chunks(countSampleRegistrations()) + chunks(countSampleEvents());
	}

	/**
	 * Deletes the next chunk, sample registrations first and then sample events, and returns how
	 * many went, 0 once none are left.
	 */
	public static Integer removeNext() {
		if (Schema.SObjectType.Event_Registration__c.isDeletable()) {
			List<Event_Registration__c> registrations = [
				SELECT Id
				FROM Event_Registration__c
				WHERE Sample_Data__c = TRUE
				WITH USER_MODE
				LIMIT :removeChunkSize
			];
			if (!registrations.isEmpty()) {
				Database.delete(registrations, AccessLevel.USER_MODE);
				return registrations.size();
			}
		}
		if (!Schema.SObjectType.Event__c.isDeletable()) {
			return 0;
		}
		List<Event__c> events = [
			SELECT Id
			FROM Event__c
			WHERE Sample_Data__c = TRUE
			WITH USER_MODE
			LIMIT :removeChunkSize
		];
		if (!events.isEmpty()) {
			Database.delete(events, AccessLevel.USER_MODE);
		}
		return events.size();
	}

	// ------------------------------------------------------------------------- helpers

	private static Integer chunks(Integer total) {
		return (total + removeChunkSize - 1) / removeChunkSize;
	}

	private static List<Contact> slice(List<Contact> people, Integer start, Integer count) {
		List<Contact> out = new List<Contact>();
		for (Integer i = start; i < start + count && i < people.size(); i++) {
			out.add(people[i]);
		}
		return out;
	}

	private static String name(Contact person) {
		return String.join(
				new List<String>{
					String.isBlank(person.FirstName) ? '' : person.FirstName,
					String.isBlank(person.LastName) ? '' : person.LastName
				},
				' '
			)
			.trim()
			.left(80);
	}

	private static Event_Track__c track(Event__c event, String name, Integer order) {
		return new Event_Track__c(Event__c = event.Id, Name = name, Sort_Order__c = order);
	}

	private static Ticket_Type__c ticket(
		Event__c event,
		String name,
		Decimal price,
		Integer quantity,
		Integer order
	) {
		return new Ticket_Type__c(
			Event__c = event.Id,
			Name = name,
			Price__c = price,
			Quantity__c = quantity,
			Active__c = true,
			Sort_Order__c = order
		);
	}

	private static Event_Session__c session(
		Event__c event,
		String name,
		String type,
		Event_Track__c track,
		Date day,
		Integer startHour,
		Integer endHour,
		String room,
		Integer capacity
	) {
		return new Event_Session__c(
			Event__c = event.Id,
			Name = name,
			Session_Type__c = type,
			Track__c = track == null ? null : track.Id,
			Start__c = Datetime.newInstance(day, Time.newInstance(startHour, 0, 0, 0)),
			End__c = Datetime.newInstance(day, Time.newInstance(endHour, 0, 0, 0)),
			Room__c = room,
			Capacity__c = capacity,
			Status__c = 'Confirmed'
		);
	}

	private static Session_Speaker__c assignment(
		Event_Session__c session,
		List<Event_Speaker__c> speakers,
		Integer speakerIndex,
		String role
	) {
		if (speakerIndex >= speakers.size()) {
			return null;
		}
		return new Session_Speaker__c(
			Event_Session__c = session.Id,
			Event_Speaker__c = speakers[speakerIndex].Id,
			Role__c = role
		);
	}

	private static Sponsorship_Level__c level(
		Event__c event,
		String name,
		Decimal amount,
		Integer order,
		String deliverables
	) {
		return new Sponsorship_Level__c(
			Event__c = event.Id,
			Name = name,
			Amount__c = amount,
			Sort_Order__c = order,
			Deliverables__c = deliverables
		);
	}

	private static Sponsor_Deliverable__c deliverable(
		Event_Sponsor__c sponsor,
		String name,
		String type,
		String status,
		Date due,
		Integer quantity
	) {
		return new Sponsor_Deliverable__c(
			Event_Sponsor__c = sponsor.Id,
			Name = name,
			Type__c = type,
			Status__c = status,
			Due_Date__c = due,
			Quantity__c = quantity
		);
	}
}
