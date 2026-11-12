/**
 * The donor portal's Pay Online action (PAY-03; ADR-0210 `0210-donor-portal-payments.md`,
 * decisions 2 and 3): `Giving.PayOnline` on a pledge or recurring gift emails the donor a link to
 * the organization's own hosted checkout for the next payment due. Portal Builder calls `run`
 * only for a verified person and a commitment it found on that person's page; the commitment is
 * read again here, and only when it is that person's. The checkout is started by this class as a
 * queued job, because the portal has already written in this transaction and no callout may
 * follow (the Memberships Pay Dues pattern). The gift is written by `GivingDonations` when
 * Payments reports the payment Paid.
 *
 * The portal's integration user has no record access of its own (ADR-0185 decision 9), so reads
 * are in system mode, limited to the person given; this class writes no record.
 */
@NamespaceAccessible
public with sharing class GivingPortalPayments implements PortalActionExtension, Queueable, Database.AllowsCallouts {
	public static final String PAY_ONLINE = 'Giving.PayOnline';
	private static final String CONTEXT = 'GivingPortalPayments';
	/** A Pending checkout this recent for the commitment means its link was just sent. */
	private static final Integer RECENT_MINUTES = 10;
	private static final Set<String> DUE = new Set<String>{
		'Scheduled',
		'Partially paid',
		'Overdue'
	};

	/** Stands in for the email sender in tests. */
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	/** Update Card (PAY-04; ADR-0218 `0218-payments-subscriptions.md`, decision 6). */
	public static final String UPDATE_CARD = 'Giving.UpdateCard';
	/** A recurring gift's Frequency as the processor's interval and count (PAY-04). */
	private static final Map<String, List<Object>> EVERY = new Map<String, List<Object>>{
		'Weekly' => new List<Object>{ 'week', 1 },
		'Every two weeks' => new List<Object>{ 'week', 2 },
		'Monthly' => new List<Object>{ 'month', 1 },
		'Quarterly' => new List<Object>{ 'month', 3 },
		'Twice a year' => new List<Object>{ 'month', 6 },
		'Yearly' => new List<Object>{ 'year', 1 }
	};

	private Id commitmentId;
	private Boolean card = false;

	@NamespaceAccessible
	public GivingPortalPayments() {
		// Built by name from Core (PortalActionExtensions), so it needs a public constructor.
	}

	private GivingPortalPayments(Id commitmentId, Boolean card) {
		this.commitmentId = commitmentId;
		this.card = card;
	}

	public Set<String> actionNames() {
		return new Set<String>{ PAY_ONLINE, UPDATE_CARD };
	}

	/**
	 * Checks the commitment and queues the checkout or the card update; the message is shown to
	 * the donor. Pay Online is refused on a gift charged automatically, Update Card on any other.
	 */
	public String run(String actionName, Id personId, Id recordId) {
		Commitment__c commitment = actionNames().contains(actionName) ? load(recordId) : null;
		Boolean card = actionName == UPDATE_CARD;
		String problem;
		if (commitment == null || personId == null || commitment.Donor_Contact__c != personId) {
			problem = BarnHelp.text('Giving', 'Giving_PayOnline_NotFound');
		} else if (commitment.Status__c != 'Active') {
			problem = BarnHelp.text('Giving', 'Giving_PayOnline_NotActive');
		} else if (String.isBlank(commitment.Donor_Contact__r.Email)) {
			problem = BarnHelp.text('Giving', 'Giving_PayOnline_NoEmail');
		} else if (card && !automatic(commitment)) {
			problem = BarnHelp.text('Giving', 'Giving_UpdateCard_NoSubscription');
		} else if (!card && automatic(commitment)) {
			problem = BarnHelp.text('Giving', 'Giving_PayOnline_Automatic');
		} else if (!card && amountDue(commitment) <= 0) {
			problem = BarnHelp.text('Giving', 'Giving_PayOnline_NothingDue');
		} else if (!GivingDonations.paymentsReady()) {
			problem = BarnHelp.text('Giving', 'Giving_PayOnline_NotReady');
		}
		if (problem != null) {
			throw new PortalPaymentException(problem);
		}
		System.enqueueJob(new GivingPortalPayments(commitment.Id, card));
		return card
			? BarnHelp.text('Giving', 'Giving_UpdateCard_Sent')
			: BarnHelp.text('Giving', 'Giving_PayOnline_Sent');
	}

	/** A recurring gift the processor charges automatically (PAY-04). */
	private static Boolean automatic(Commitment__c commitment) {
		return commitment.Type__c == 'Recurring' &&
			String.isNotBlank(commitment.Processor_Subscription_Id__c) &&
			commitment.Processor_Cancelled__c == null;
	}

	/** Starts the checkout (or gets the card page), then emails its address to the donor. */
	public void execute(QueueableContext queued) {
		Commitment__c commitment = load(commitmentId);
		if (commitment == null || String.isBlank(commitment.Donor_Contact__r.Email)) {
			return;
		}
		if (card) {
			try {
				Map<String, Object> page = (Map<String, Object>) GivingDonations.payments()
					.call(
						'updateCard',
						new Map<String, Object>{
							'subscriptionId' => commitment.Processor_Subscription_Id__c,
							'customerId' => commitment.Processor_Customer_Id__c,
							'returnUrl' => GivingDonations.returnUrl()
						}
					);
				email(
					commitment,
					BarnHelp.text('Giving', 'Giving_UpdateCard_EmailSubject'),
					BarnHelp.text('Giving', 'Giving_UpdateCard_EmailBody'),
					new List<Object>{ commitment.Name, page.get('url') }
				);
			} catch (Exception e) {
				ErrorLogger.log(e, CONTEXT, commitment.Id);
			}
			return;
		}
		Decimal amount = amountDue(commitment);
		if (amount <= 0) {
			return;
		}
		String url;
		String subject = BarnHelp.text('Giving', 'Giving_PayOnline_EmailSubject');
		String body = BarnHelp.text('Giving', 'Giving_PayOnline_EmailBody');
		String amountText;
		try {
			Callable payments = GivingDonations.payments();
			// PAY-04: with Automatic Recurring Payments on, a recurring gift sets up automatic
			// payments of its own amount, each period (Payments ignores the interval otherwise).
			List<Object> every = commitment.Type__c == 'Recurring'
				? EVERY.get(commitment.Frequency__c)
				: null;
			if (
				every != null &&
				(commitment.Amount__c ?? 0) > 0 &&
				payments.call('isReady', new Map<String, Object>{ 'recurring' => true }) == true
			) {
				subject = BarnHelp.text('Giving', 'Giving_AutoPay_EmailSubject');
				body = BarnHelp.text('Giving', 'Giving_AutoPay_EmailBody');
				amount = commitment.Amount__c;
			} else {
				every = null;
			}
			amountText = amount.setScale(2).format();
			Object recent = payments.call(
				'countRecent',
				new Map<String, Object>{
					'sourceRecordId' => commitment.Id,
					'minutes' => RECENT_MINUTES,
					'status' => 'Pending'
				}
			);
			if (recent instanceof Integer && (Integer) recent > 0) {
				// A link sent minutes ago is still open: a second click sends no second one.
				return;
			}
			String back = GivingDonations.returnUrl();
			Map<String, Object> started = (Map<String, Object>) payments
				.call(
					'startCheckout',
					new Map<String, Object>{
						'amount' => amount,
						'description' => BarnHelp.text(
							'Giving',
							'Giving_PayOnline_Description',
							new List<Object>{ commitment.Name }
						),
						'successUrl' => back,
						'cancelUrl' => back,
						'payerName' => commitment.Donor_Contact__r.Name,
						'payerEmail' => commitment.Donor_Contact__r.Email,
						'personId' => commitment.Donor_Contact__c,
						'sourceRecordId' => commitment.Id,
						'listener' => GivingDonations.LISTENER,
						// The scheduled payment charged, so the gift pays that one (GivingDonations).
						'detail' => nextDue(commitment)?.Id,
						'interval' => every?.get(0),
						'intervalCount' => every?.get(1)
					}
				);
			url = String.valueOf(started.get('checkoutUrl'));
			Map<String, Object> payment = (Map<String, Object>) payments.call(
				'getPayment',
				new Map<String, Object>{ 'paymentId' => started.get('paymentId') }
			);
			if (payment?.get('amount') instanceof Decimal) {
				// The amount as charged: no decimals for a currency without them.
				amountText =
					((Decimal) payment.get('amount')).format() +
					' ' +
					String.valueOf(payment.get('currency'));
			}
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT, commitment.Id);
			return;
		}
		email(commitment, subject, body, new List<Object>{ amountText, commitment.Name, url });
	}

	/** Emails the donor `subject` and `body`, its {0} the first name and {1} on the `words`. */
	private static void email(
		Commitment__c commitment,
		String subject,
		String body,
		List<Object> words
	) {
		words.add(0, commitment.Donor_Contact__r.FirstName ?? '');
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setToAddresses(new List<String>{ commitment.Donor_Contact__r.Email });
		message.setSubject(subject);
		message.setPlainTextBody(String.format(body, words));
		message.setSaveAsActivity(false);
		List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>{
			message
		};
		for (EmailSendOutcome outcome : emailSender.send(messages)) {
			if (outcome != null && outcome.sent != true) {
				ErrorLogger.logMessage(
					BarnHelp.text('Giving', 'Giving_PayOnline_NotSent'),
					CONTEXT,
					ErrorLogger.SEVERITY_WARNING
				);
			}
		}
	}

	/**
	 * The next payment due: the earliest unpaid scheduled payment's amount left, or, with none, a
	 * pledge's balance or a recurring gift's amount (decision 3).
	 */
	@TestVisible
	private static Decimal amountDue(Commitment__c commitment) {
		Installment__c next = nextDue(commitment);
		if (next != null) {
			return next.Expected_Amount__c - (next.Paid_Amount__c ?? 0);
		}
		Decimal fallback = commitment.Type__c == 'Pledge'
			? commitment.Balance__c
			: commitment.Amount__c;
		return fallback ?? 0;
	}

	/** The earliest scheduled payment with an amount left to pay, or null. */
	private static Installment__c nextDue(Commitment__c commitment) {
		for (Installment__c next : commitment.Installments__r) {
			if ((next.Expected_Amount__c ?? 0) - (next.Paid_Amount__c ?? 0) > 0) {
				return next;
			}
		}
		return null;
	}

	private static Commitment__c load(Id recordId) {
		if (recordId == null || recordId.getSObjectType() != Commitment__c.SObjectType) {
			return null;
		}
		List<Commitment__c> found = [
			SELECT
				Id,
				Name,
				Status__c,
				Type__c,
				Amount__c,
				Balance__c,
				Frequency__c,
				Processor_Subscription_Id__c,
				Processor_Customer_Id__c,
				Processor_Cancelled__c,
				Donor_Contact__c,
				Donor_Contact__r.Name,
				Donor_Contact__r.FirstName,
				Donor_Contact__r.Email,
				(
					SELECT Id, Expected_Amount__c, Paid_Amount__c
					FROM Installments__r
					WHERE Status__c IN :DUE
					ORDER BY Due_Date__c ASC NULLS LAST
					LIMIT 5
				)
			FROM Commitment__c
			WHERE Id = :recordId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return found.isEmpty() ? null : found[0];
	}

	/** A refusal the portal shows only as refused. */
	public class PortalPaymentException extends Exception {
	}
}
