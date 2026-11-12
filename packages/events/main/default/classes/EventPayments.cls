/**
 * Paid event registration (EV-20; ADR-0207 `0207-events-paid-registration-proposals-ratings.md`,
 * decisions 1 to 7; canonical model R-ERG5 to R-ERG7). BarnCRM Payments is reached only by name:
 * this class builds `PaymentsApi` with `NamespaceUtil.build` (null when Payments is not
 * installed), and Payments builds `EventPaymentListener` by the name stored on each payment, so
 * neither package depends on the other (ADR-0017).
 *
 * The payment fields (Payment Status, Amount Paid, Payment Key, Payment Link) are written in
 * system mode: no person edits them, and they change only from a checkout this class started for
 * a registration the person could read, or from the processor's report about that registration's
 * current payment.
 */
public with sharing class EventPayments {
	public static final String UNPAID = 'Unpaid';
	public static final String LINK_SENT = 'Link Sent';
	public static final String PAID = 'Paid';
	public static final String FAILED = 'Failed';
	public static final String PARTLY_REFUNDED = 'Partly Refunded';
	public static final String REFUNDED = 'Refunded';
	public static final String CANCELLED = 'Cancelled';
	/** The listener Payments builds by name; permanent once released (ADR decision 5). */
	public static final String LISTENER = 'EventPaymentListener';
	private static final String CONTEXT = 'EventPayments';

	/** A link that cannot be sent, in words for the person asking. */
	public class PaymentLinkException extends Exception {
	}

	@TestVisible
	private static Callable apiForTest;
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();
	@TestVisible
	private static Boolean checkoutsQueued = false;

	/** Payments' seam, or null when Payments is not installed. */
	public static Callable api() {
		return apiForTest != null
			? apiForTest
			: (Callable) NamespaceUtil.build('PaymentsApi', Callable.class, CONTEXT);
	}

	/** R-ERG5: whether a form registration that owes money waits for payment now. */
	public static Boolean takesOnline() {
		if (!EventsSettings.onlinePayments()) {
			return false;
		}
		Callable payments = api();
		try {
			return payments != null && payments.call('isReady', new Map<String, Object>()) == true;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.takesOnline');
			return false;
		}
	}

	/** Queues the checkout job once in this transaction (ADR decision 3). */
	public static void queueCheckouts() {
		if (checkoutsQueued || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
			return;
		}
		checkoutsQueued = true;
		// A test runs the job itself, with its stand-in for Payments.
		if (!Test.isRunningTest()) {
			System.enqueueJob(new EventCheckoutJob());
		}
	}

	/**
	 * Starts a checkout for the registration's amount owed and emails the registrant the link
	 * (R-ERG7). The callout comes first, so nothing may be written before it in the transaction.
	 *
	 * @return how the email went, an `EventTemplateMail` outcome
	 * @throws PaymentLinkException when there is nothing to pay or no checkout can be started
	 */
	public static String sendLink(Id registrationId) {
		List<Event_Registration__c> found = [
			SELECT
				Id,
				Name,
				Status__c,
				Amount_Owed__c,
				Payment_Status__c,
				Contact__c,
				Contact__r.Name,
				Contact__r.Email,
				Event__c,
				Event__r.Name,
				Event__r.Registration_Form_Key__c
			FROM Event_Registration__c
			WHERE Id = :registrationId
			WITH USER_MODE
			LIMIT 1
		];
		if (
			found.isEmpty() ||
			found[0].Amount_Owed__c == null ||
			found[0].Amount_Owed__c <= 0 ||
			found[0].Payment_Status__c == PAID ||
			found[0].Status__c == EventRegistrationService.STATUS_CANCELLED
		) {
			throw new PaymentLinkException(BarnHelp.text('Events', 'Events_Payment_NothingToPay'));
		}
		Callable payments = api();
		if (payments == null) {
			throw new PaymentLinkException(BarnHelp.text('Events', 'Events_Payment_NotReady'));
		}
		Event_Registration__c registration = found[0];
		String back = returnUrl(registration.Event__r);
		Map<String, Object> started;
		try {
			started = (Map<String, Object>) payments.call(
				'startCheckout',
				new Map<String, Object>{
					'amount' => registration.Amount_Owed__c,
					'description' => BarnHelp.text(
							'Events',
							'Events_Payment_Description',
							new List<Object>{ registration.Event__r.Name, registration.Name }
						)
						.abbreviate(255),
					'successUrl' => back,
					'cancelUrl' => back,
					'payerName' => registration.Contact__r?.Name,
					'payerEmail' => registration.Contact__r?.Email,
					'personId' => registration.Contact__c,
					'sourceRecordId' => registration.Id,
					'listener' => LISTENER
				}
			);
		} catch (Exception refused) {
			ErrorLogger.log(refused, CONTEXT + '.sendLink', registration.Id);
			throw new PaymentLinkException(refused.getMessage());
		}
		registration.Payment_Key__c = String.valueOf(started.get('paymentId'));
		registration.Payment_Link__c = String.valueOf(started.get('checkoutUrl'));
		registration.Payment_Status__c = LINK_SENT;
		Database.update(
			new Event_Registration__c(
				Id = registration.Id,
				Payment_Key__c = registration.Payment_Key__c,
				Payment_Link__c = registration.Payment_Link__c,
				Payment_Status__c = LINK_SENT
			),
			true,
			AccessLevel.SYSTEM_MODE
		);
		return emailLink(registration);
	}

	/** Emails the registration's current link to its registrant. */
	public static String emailLink(Event_Registration__c registration) {
		return EventTemplateMail.send(
			emailSender,
			EventsSettings.paymentLinkTemplate(),
			registration.Contact__c,
			registration.Contact__r?.Email,
			registration.Id,
			CONTEXT + '.emailLink'
		);
	}

	/**
	 * Where the payer returns: the event's public page on the Site its registration form uses
	 * (`FormsPublic?record=<event>`), else the org's own address (ADR decision 3).
	 */
	@TestVisible
	private static String returnUrl(Event__c event) {
		String link;
		try {
			link = FormCatalogExtensions.publicLink(
				Id.valueOf(event.Registration_Form_Key__c.trim()),
				null
			);
		} catch (Exception noForm) {
			link = null;
		}
		return link != null && link.contains('/FormsPublic')
			? link.substringBefore('/FormsPublic') + '/FormsPublic?record=' + event.Id
			: Url.getOrgDomainUrl().toExternalForm() + '/' + event.Id;
	}

	/**
	 * R-ERG6: applies what Payments reported about a payment to its registration, when it is the
	 * registration's current payment. Safe to call twice with the same status.
	 *
	 * @param payment the seam's payment map (ADR-0201 `0201-payments-module.md`, decision 8)
	 */
	public static void apply(Map<String, Object> payment) {
		Id registrationId = idOf(payment.get('sourceRecordId'));
		Id paymentId = idOf(payment.get('paymentId'));
		if (registrationId == null || paymentId == null) {
			return;
		}
		List<Event_Registration__c> found = [
			SELECT Id, Status__c, Payment_Key__c
			FROM Event_Registration__c
			WHERE Id = :registrationId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (found.isEmpty() || idOf(found[0].Payment_Key__c) != paymentId) {
			return;
		}
		Event_Registration__c registration = found[0];
		Decimal amount = (Decimal) payment.get('amount');
		// Apex names ignore case, so this may not be called `refunded` (the REFUNDED constant).
		Decimal amountRefunded = payment.get('amountRefunded') == null
			? 0
			: (Decimal) payment.get('amountRefunded');
		String status = String.valueOf(payment.get('status'));
		Event_Registration__c change = new Event_Registration__c(Id = registration.Id);
		Boolean cancel = false;
		Boolean waiting = registration.Status__c == EventRegistrationService.STATUS_PENDING_PAYMENT;
		if (status == PAID) {
			change.Payment_Status__c = amountRefunded > 0 ? PARTLY_REFUNDED : PAID;
			change.Amount_Paid__c = amount - amountRefunded;
			if (waiting) {
				change.Status__c = EventRegistrationService.STATUS_REGISTERED;
			}
		} else if (status == REFUNDED) {
			change.Payment_Status__c = REFUNDED;
			change.Amount_Paid__c = 0;
			cancel = true;
		} else if (status == FAILED) {
			change.Payment_Status__c = FAILED;
		} else if (status == CANCELLED) {
			change.Payment_Status__c = CANCELLED;
			cancel = waiting;
		} else {
			return;
		}
		if (cancel && registration.Status__c != EventRegistrationService.STATUS_CANCELLED) {
			change.Status__c = EventRegistrationService.STATUS_CANCELLED;
			change.Amount_Owed__c = 0;
			List<Event_Attendee__c> attendees = new List<Event_Attendee__c>();
			for (Event_Attendee__c attendee : [
				SELECT Id
				FROM Event_Attendee__c
				WHERE Event_Registration__c = :registration.Id
				WITH SYSTEM_MODE
			]) {
				attendees.add(
					new Event_Attendee__c(
						Id = attendee.Id,
						Status__c = EventRegistrationService.STATUS_CANCELLED
					)
				);
			}
			Database.update(attendees, true, AccessLevel.SYSTEM_MODE);
		}
		Database.update(change, true, AccessLevel.SYSTEM_MODE);
	}

	private static Id idOf(Object value) {
		try {
			return value == null ? null : Id.valueOf(String.valueOf(value));
		} catch (Exception notAnId) {
			return null;
		}
	}
}
