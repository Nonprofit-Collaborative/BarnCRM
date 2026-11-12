/**
 * The morning thank-you run (V-13, R-VP4): one open Task per Contact that reached a new hour
 * milestone, and one per Contact whose Volunteer Since falls on today one or more years ago.
 * Last Hour Milestone records the milestone thanked; an anniversary Task already there today is
 * not made twice. Started at 7:30 AM by `VolunteerRecognitionScheduler`; does nothing while Send
 * Thank-You Tasks or the module is off.
 *
 * Reads and writes in system mode: Last Hour Milestone is read only to people, and the run
 * belongs to whoever scheduled the nightly jobs. Record sharing still applies to the reads.
 */
public with sharing class VolunteerRecognitionJob implements Database.Batchable<SObject> {
	public static final Integer CHUNK_SIZE = 200;
	private static final String LOG_CONTEXT = 'VolunteerRecognitionJob';

	/** Starts the run; null when the module or the setting is off. */
	public static Id startMorning() {
		if (ShiftScheduleService.isTurnedOff() || !VolunteerSettings.recognitionEnabled()) {
			return null;
		}
		return AsyncStarter.batch(
			new VolunteerRecognitionJob(),
			CHUNK_SIZE,
			'VolunteerRecognitionJob'
		);
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		List<Integer> milestones = VolunteerSettings.hourMilestones();
		Integer lowest = milestones[0];
		Integer highest = milestones[milestones.size() - 1];
		Date today = Date.today();
		Integer month = today.month();
		Integer day = today.day();
		return Database.getQueryLocator(
			[
				SELECT Id
				FROM Contact
				WHERE
					(Volunteer_Hours_Total__c >= :lowest
					AND (Last_Hour_Milestone__c = NULL
					OR Last_Hour_Milestone__c < :highest))
					OR (CALENDAR_MONTH(Volunteer_Since__c) = :month
					AND DAY_IN_MONTH(Volunteer_Since__c) = :day
					AND Volunteer_Since__c < :today)
				WITH SYSTEM_MODE
			]
		);
	}

	public void execute(Database.BatchableContext context, List<Contact> scope) {
		try {
			thank(new Map<Id, Contact>(scope).keySet());
		} catch (Exception chunkFailure) {
			ErrorLogger.log(chunkFailure, LOG_CONTEXT);
		}
	}

	public void finish(Database.BatchableContext context) {
		return;
	}

	/** Makes the thank-you Tasks for these Contacts and returns how many. */
	public static Integer thank(Set<Id> contactIds) {
		List<Integer> milestones = VolunteerSettings.hourMilestones();
		Date today = Date.today();
		List<Task> tasks = new List<Task>();
		List<Task> milestoneTasks = new List<Task>();
		List<Contact> stamped = new List<Contact>();
		List<Task> anniversaries = new List<Task>();
		List<Contact> people = [
			SELECT
				Id,
				Name,
				OwnerId,
				Owner.IsActive,
				Volunteer_Hours_Total__c,
				Last_Hour_Milestone__c,
				Volunteer_Since__c
			FROM Contact
			WHERE Id IN :contactIds
			WITH SYSTEM_MODE
		];
		for (Contact person : people) {
			Integer reached = highestReached(milestones, person.Volunteer_Hours_Total__c);
			if (
				reached != null &&
				(person.Last_Hour_Milestone__c == null ||
				reached > person.Last_Hour_Milestone__c)
			) {
				List<Object> args = new List<Object>{ person.Name, reached.format() };
				milestoneTasks.add(
					task(
						person,
						BarnHelp.text('Volunteers', 'Volunteers_Recognition_Milestone', args)
					)
				);
				stamped.add(new Contact(Id = person.Id, Last_Hour_Milestone__c = reached));
			}
			Date since = person.Volunteer_Since__c;
			if (
				since != null &&
				since < today &&
				since.month() == today.month() &&
				since.day() == today.day()
			) {
				List<Object> args = new List<Object>{
					person.Name,
					(today.year() - since.year()).format()
				};
				anniversaries.add(
					task(
						person,
						today.year() - since.year() == 1
							? BarnHelp.text(
									'Volunteers',
									'Volunteers_Recognition_AnniversaryOne',
									args
							  )
							: BarnHelp.text(
									'Volunteers',
									'Volunteers_Recognition_Anniversary',
									args
							  )
					)
				);
			}
		}
		// An anniversary has no stamp: a Task with the same subject due today is the one made.
		Set<String> alreadyToday = subjectsToday(contactIds);
		for (Task anniversary : anniversaries) {
			if (!alreadyToday.contains(anniversary.WhoId + anniversary.Subject)) {
				tasks.add(anniversary);
			}
		}
		// The milestone is stamped first: a person whose stamp fails is not thanked, and is tried
		// again the next morning.
		List<Database.SaveResult> stamps = Database.update(stamped, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < stamps.size(); i++) {
			if (stamps[i].isSuccess()) {
				tasks.add(milestoneTasks[i]);
			}
		}
		ErrorLogger.logFailures(stamps, null, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
		Integer made = 0;
		List<Database.SaveResult> results = Database.insert(tasks, false, AccessLevel.SYSTEM_MODE);
		for (Database.SaveResult result : results) {
			made += result.isSuccess() ? 1 : 0;
		}
		ErrorLogger.logFailures(results, null, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
		return made;
	}

	/** The highest milestone at or below the total, or null when none is reached. */
	private static Integer highestReached(List<Integer> milestones, Decimal total) {
		Integer reached = null;
		for (Integer milestone : milestones) {
			if (total != null && total >= milestone) {
				reached = milestone;
			}
		}
		return reached;
	}

	private static Set<String> subjectsToday(Set<Id> contactIds) {
		Set<String> found = new Set<String>();
		Date today = Date.today();
		for (Task existing : [
			SELECT WhoId, Subject
			FROM Task
			WHERE WhoId IN :contactIds AND ActivityDate = :today
			WITH SYSTEM_MODE
		]) {
			found.add(existing.WhoId + existing.Subject);
		}
		return found;
	}

	private static Task task(Contact person, String subject) {
		return new Task(
			WhoId = person.Id,
			Subject = subject.abbreviate(255),
			Description = BarnHelp.text('Volunteers', 'Volunteers_Recognition_Description'),
			ActivityDate = Date.today(),
			Status = 'Not Started',
			Priority = 'Normal',
			OwnerId = person.Owner.IsActive == true ? person.OwnerId : UserInfo.getUserId()
		);
	}
}
