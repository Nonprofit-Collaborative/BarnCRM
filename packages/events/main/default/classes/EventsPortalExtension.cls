/**
 * The speaker portal's two actions (PB-07; ADR-0185 decision 9, ADR-0180 and ADR-0191
 * `0191-portal-templates-volunteer-speaker-donor.md`): `Events.ApplyToSpeak` on an open event
 * starts a Submitted proposal for the verified person, and `Events.WithdrawProposal` withdraws
 * one of their own that is not yet decided. Core finds this class by name
 * (`PortalActionExtensions.EXTENSION_CLASSES`); Portal Builder has already checked the record is
 * on the person's page. The person then writes the title and abstract on the proposals page.
 *
 * `without sharing` and system mode (ADR-0021): the portal's integration user has no object
 * access. Writes name only the verified person and touch only that person's own proposals.
 *
 * `@NamespaceAccessible` with a public no-argument constructor because Core resolves it by name
 * under ADR-0017.
 */
@NamespaceAccessible
public without sharing class EventsPortalExtension implements PortalActionExtension {
	public static final String APPLY = 'Events.ApplyToSpeak';
	public static final String WITHDRAW = 'Events.WithdrawProposal';
	/** EV-20: emails the person their own registration's current payment link again. */
	public static final String SEND_LINK = 'Events.SendPaymentLink';
	private static final Integer NAME_LENGTH = 80;

	@NamespaceAccessible
	public EventsPortalExtension() {
		return;
	}

	public Set<String> actionNames() {
		Set<String> names = new Set<String>{ APPLY, WITHDRAW, SEND_LINK };
		names.addAll(EventAttendeeApp.actionNames());
		return names;
	}

	public String run(String actionName, Id personId, Id recordId) {
		if (personId == null || recordId == null) {
			throw new System.IllegalArgumentException('A person and a record are needed');
		}
		if (actionName == APPLY) {
			return apply(personId, recordId);
		}
		if (actionName == WITHDRAW) {
			return withdraw(personId, recordId);
		}
		if (actionName == SEND_LINK) {
			return sendLink(personId, recordId);
		}
		if (EventAttendeeApp.actionNames().contains(actionName)) {
			// EV-22 and EV-29: the attendee app's connections, messages and agenda.
			return EventAttendeeApp.run(actionName, personId, recordId);
		}
		throw new System.IllegalArgumentException('Unknown action ' + actionName);
	}

	/**
	 * Emails the person's own registration's current payment link (EV-20). No checkout is started
	 * here: the portal's integration user makes no callout and queues no job; a registration with
	 * no link yet gets one from the checkout job or from staff.
	 */
	private static String sendLink(Id personId, Id registrationId) {
		List<Event_Registration__c> found = [
			SELECT Id, Contact__c, Contact__r.Email, Payment_Status__c, Payment_Link__c, Status__c
			FROM Event_Registration__c
			WHERE Id = :registrationId AND Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (found.isEmpty()) {
			throw new System.QueryException('The registration is not this person\'s');
		}
		Event_Registration__c registration = found[0];
		if (
			String.isBlank(registration.Payment_Link__c) ||
			registration.Payment_Status__c == EventPayments.PAID ||
			registration.Status__c == EventRegistrationService.STATUS_CANCELLED
		) {
			return BarnHelp.text('Events', 'Events_Portal_NoPaymentLink');
		}
		return EventPayments.emailLink(registration) == EventTemplateMail.SENT
			? BarnHelp.text('Events', 'Events_Portal_PaymentLinkSent')
			: BarnHelp.text('Events', 'Events_Portal_NoPaymentLink');
	}

	private static String apply(Id personId, Id eventId) {
		List<Event__c> events = [
			SELECT Id, Name, Status__c, End__c
			FROM Event__c
			WHERE Id = :eventId
			WITH SYSTEM_MODE
		];
		if (events.isEmpty()) {
			throw new System.QueryException('The event is gone');
		}
		Event__c event = events[0];
		if (event.Status__c != 'Open' || (event.End__c != null && event.End__c < Datetime.now())) {
			return BarnHelp.text('Events', 'Events_Portal_EventClosed');
		}
		Integer current = [
			SELECT COUNT()
			FROM Speaker_Application__c
			WHERE Event__c = :eventId AND Contact__c = :personId AND Status__c != 'Withdrawn'
			WITH SYSTEM_MODE
		];
		if (current > 0) {
			return BarnHelp.text('Events', 'Events_Portal_AlreadyApplied');
		}
		String title = BarnHelp.text(
			'Events',
			'Events_Portal_NewProposal',
			new List<Object>{ event.Name }
		);
		insert as system new Speaker_Application__c(
			Event__c = eventId,
			Contact__c = personId,
			Name = title.abbreviate(NAME_LENGTH),
			Status__c = 'Submitted'
		);
		return BarnHelp.text('Events', 'Events_Portal_Applied');
	}

	private static String withdraw(Id personId, Id applicationId) {
		List<Speaker_Application__c> applications = [
			SELECT Id, Status__c
			FROM Speaker_Application__c
			WHERE Id = :applicationId AND Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (applications.isEmpty()) {
			throw new System.QueryException('The proposal is not this person\'s');
		}
		Speaker_Application__c application = applications[0];
		if (application.Status__c != 'Submitted' && application.Status__c != 'In Review') {
			return BarnHelp.text('Events', 'Events_Portal_CannotWithdraw');
		}
		application.Status__c = 'Withdrawn';
		update as system application;
		return BarnHelp.text('Events', 'Events_Portal_Withdrawn');
	}
}
