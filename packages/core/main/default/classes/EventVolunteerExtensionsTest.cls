/**
 * Event Management shows an event's volunteer jobs only when a module keeps them, and a module
 * that fails never breaks the event page (ADR-0177 decision 12). Core has no module, so
 * extensions are injected by class name, as modules register theirs.
 */
@IsTest(testFor='ApexClass:EventVolunteerExtensions')
private class EventVolunteerExtensionsTest {
	private static final String WORKS = 'VolunteersEventExtension';
	private static final String BROKEN = 'BrokenEventVolunteerExtension';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** Keeps one job for any event and remembers what it was asked to create. */
	private class Recording implements EventVolunteerExtension {
		String createdFor;
		Integer shiftsMade = 0;

		public List<EventVolunteerJob> jobsFor(String eventKey) {
			EventVolunteerJob job = new EventVolunteerJob();
			job.name = 'Registration Desk for ' + eventKey;
			EventVolunteerShift shift = new EventVolunteerShift();
			shift.needed = 4;
			shift.filled = 1;
			job.shifts.add(shift);
			return new List<EventVolunteerJob>{ job };
		}

		public Id createJob(String eventKey, String name, String description) {
			createdFor = eventKey;
			return UserInfo.getUserId();
		}

		public Id createShift(Id jobId, Datetime startTime, Datetime endTime, Integer needed) {
			shiftsMade++;
			return jobId;
		}
	}

	private class Failing implements EventVolunteerExtension {
		public List<EventVolunteerJob> jobsFor(String eventKey) {
			throw new System.TypeException('Cannot list');
		}

		public Id createJob(String eventKey, String name, String description) {
			throw new System.TypeException('Cannot create');
		}

		public Id createShift(Id jobId, Datetime startTime, Datetime endTime, Integer needed) {
			throw new System.TypeException('Cannot create');
		}
	}

	private static void register(Map<String, EventVolunteerExtension> byName) {
		EventVolunteerExtensions.EXTENSION_CLASSES.clear();
		EventVolunteerExtensions.EXTENSION_CLASSES.addAll(byName.keySet());
		EventVolunteerExtensions.overrides = byName;
	}

	@IsTest
	static void withNoModuleThereIsNothingToShow() {
		System.runAs(TestUsers.admin()) {
			EventVolunteerExtensions.EXTENSION_CLASSES.clear();
			EventVolunteerExtensions.EXTENSION_CLASSES.add('NoSuchClassAnywhere');
			EventVolunteerExtensions.EXTENSION_CLASSES.add('EventVolunteerJob');
			Assert.isFalse(EventVolunteerExtensions.isAvailable());
			Assert.isTrue(EventVolunteerExtensions.jobsFor('a01000000000001').isEmpty());
			try {
				EventVolunteerExtensions.createJob('a01000000000001', 'Setup', null);
				Assert.fail('No module can create a job');
			} catch (System.NoAccessException expected) {
				Assert.isNotNull(expected);
			}
		}
	}

	@IsTest
	static void aModuleListsAndCreates() {
		System.runAs(TestUsers.admin()) {
			Recording module = new Recording();
			register(
				new Map<String, EventVolunteerExtension>{
					WORKS => (EventVolunteerExtension) module
				}
			);
			Assert.isTrue(EventVolunteerExtensions.isAvailable());
			List<EventVolunteerJob> jobs = EventVolunteerExtensions.jobsFor('a01000000000001');
			Assert.areEqual(1, jobs.size());
			Assert.areEqual(4, jobs[0].shifts[0].needed);
			EventVolunteerExtensions.createJob('a01000000000001', 'Setup', 'Chairs');
			Assert.areEqual('a01000000000001', module.createdFor);
			EventVolunteerExtensions.createShift(
				UserInfo.getUserId(),
				Datetime.now(),
				Datetime.now().addHours(1),
				2
			);
			Assert.areEqual(1, module.shiftsMade);
		}
	}

	@IsTest
	static void aFailingModuleNeverBreaksListing() {
		System.runAs(TestUsers.admin()) {
			register(
				new Map<String, EventVolunteerExtension>{
					BROKEN => (EventVolunteerExtension) new Failing(),
					WORKS => (EventVolunteerExtension) new Recording()
				}
			);
			Assert.areEqual(
				1,
				EventVolunteerExtensions.jobsFor('a01000000000001').size(),
				'The working module still lists'
			);
		}
	}
}
