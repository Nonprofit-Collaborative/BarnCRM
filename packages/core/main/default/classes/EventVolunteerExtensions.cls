/**
 * Finds the event volunteer extension a module installed (ADR-0177 decision 12), or answers that
 * there is none, which is the ordinary case in an org without Volunteers. A class that is not
 * installed, cannot be built or does not implement the interface is absent, and a failure is
 * logged: an event page must load whatever a module does.
 */
@NamespaceAccessible
public with sharing class EventVolunteerExtensions {
	/** The class names modules register. Volunteers registers its class here (EV-08). */
	@NamespaceAccessible
	public static final List<String> EXTENSION_CLASSES = new List<String>{
		'VolunteersEventExtension'
	};

	/** Injected by tests by class name, since no module is there to resolve. */
	@TestVisible
	private static Map<String, EventVolunteerExtension> overrides = new Map<String, EventVolunteerExtension>();

	/** Whether any module can keep volunteer jobs for an event. */
	@NamespaceAccessible
	public static Boolean isAvailable() {
		return !installed().isEmpty();
	}

	/** The jobs every installed extension keeps for the event, with their shifts. */
	@NamespaceAccessible
	public static List<EventVolunteerJob> jobsFor(String eventKey) {
		List<EventVolunteerJob> jobs = new List<EventVolunteerJob>();
		for (EventVolunteerExtension extension : installed()) {
			try {
				jobs.addAll(extension.jobsFor(eventKey));
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'EventVolunteerExtensions.jobsFor');
			}
		}
		return jobs;
	}

	/**
	 * Adds a volunteer job through the first installed extension; its failure is the caller's to
	 * report, since the person asked for exactly this.
	 */
	@NamespaceAccessible
	public static Id createJob(String eventKey, String name, String description) {
		return first().createJob(eventKey, name, description);
	}

	/** Adds a shift to a job, through the first installed extension. */
	@NamespaceAccessible
	public static Id createShift(Id jobId, Datetime startTime, Datetime endTime, Integer needed) {
		return first().createShift(jobId, startTime, endTime, needed);
	}

	private static EventVolunteerExtension first() {
		List<EventVolunteerExtension> found = installed();
		if (found.isEmpty()) {
			throw new System.NoAccessException();
		}
		return found[0];
	}

	private static List<EventVolunteerExtension> installed() {
		List<EventVolunteerExtension> found = new List<EventVolunteerExtension>();
		for (String className : EXTENSION_CLASSES) {
			EventVolunteerExtension extension = overrides.containsKey(className)
				? overrides.get(className)
				: resolve(className);
			if (extension != null) {
				found.add(extension);
			}
		}
		return found;
	}

	private static EventVolunteerExtension resolve(String className) {
		Type extensionType = NamespaceUtil.resolveType(className);
		if (extensionType == null) {
			return null;
		}
		Object candidate;
		try {
			candidate = extensionType.newInstance();
		} catch (Exception cannotBuild) {
			ErrorLogger.log(cannotBuild, 'EventVolunteerExtensions.resolve');
			return null;
		}
		if (candidate instanceof EventVolunteerExtension) {
			return (EventVolunteerExtension) candidate;
		}
		ErrorLogger.log(
			new System.TypeException(className + ' does not implement EventVolunteerExtension'),
			'EventVolunteerExtensions.resolve'
		);
		return null;
	}
}
