/**
 * Pay Online on a project invoice (PM-10, D-197 as amended 2026-11-12; ADR-0219
 * `0219-projects-psa.md` decision 6; canonical model R-PM22). BarnCRM Payments is reached only by
 * name, as Events reaches it (ADR-0207): `PaymentsApi` is built with `NamespaceUtil.build` (null
 * when Payments is not installed), and Payments builds `ProjectInvoicePaymentListener` by the name
 * stored on each payment, so neither package depends on the other. Projects charges nothing and
 * keeps no card data.
 *
 * Send Payment Link runs in user mode (Manage Projects). A payment report is applied in system
 * mode: it arrives as whoever runs Payments' event processing, not a Projects Admin, and it
 * writes only Amount Paid, Status and Paid Date of the invoice whose current Payment Key is the
 * reported payment.
 */
public with sharing class ProjectInvoicePayments {
	/** The listener Payments builds by name; permanent once released. */
	public static final String LISTENER = 'ProjectInvoicePaymentListener';
	private static final String CONTEXT = 'ProjectInvoicePayments';

	@TestVisible
	private static Callable apiForTest;
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	/** Payments' seam, or null when Payments is not installed. */
	public static Callable api() {
		return apiForTest != null
			? apiForTest
			: (Callable) NamespaceUtil.build('PaymentsApi', Callable.class, CONTEXT);
	}

	/** Whether Send Payment Link shows: the setting is on and Payments is installed. */
	public static Boolean available() {
		return ProjectsSettings.onlinePaymentsEnabled() && api() != null;
	}

	/**
	 * Starts a checkout for the balance due of a Sent invoice and emails the link to its Bill To
	 * Contact. The callout comes first, so nothing is written before it.
	 *
	 * @return the message to show: emailed, or created but not emailed and why
	 */
	public static String sendLink(Id invoiceId) {
		ProjectBilling.requireBilling();
		Callable payments = available() ? api() : null;
		if (payments == null) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_OnlineOff'));
		}
		Project_Invoice__c invoice = [
			SELECT
				Id,
				Name,
				Status__c,
				Total__c,
				Amount_Paid__c,
				Contact__c,
				Contact__r.Name,
				Contact__r.Email,
				Project__r.Name
			FROM Project_Invoice__c
			WHERE Id = :invoiceId
			WITH USER_MODE
		];
		Decimal owed = balance(invoice);
		if (invoice.Status__c != ProjectBilling.SENT || owed <= 0) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_NothingToPay'));
		}
		if (String.isBlank(invoice.Contact__r?.Email)) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Invoice_NoEmail'));
		}
		String back = ProjectsSettings.invoiceReturnUrl();
		Map<String, Object> started;
		try {
			started = (Map<String, Object>) payments.call(
				'startCheckout',
				new Map<String, Object>{
					'amount' => owed,
					'description' => BarnHelp.text(
							'Projects',
							'Projects_Invoice_PaymentDescription',
							new List<Object>{ invoice.Name, invoice.Project__r.Name }
						)
						.abbreviate(255),
					'successUrl' => back,
					'cancelUrl' => back,
					'payerName' => invoice.Contact__r.Name,
					'payerEmail' => invoice.Contact__r.Email,
					'personId' => invoice.Contact__c,
					'sourceRecordId' => invoice.Id,
					'listener' => LISTENER
				}
			);
		} catch (Exception refused) {
			ErrorLogger.log(refused, CONTEXT + '.sendLink', invoice.Id);
			throw Projects.refuse(refused.getMessage());
		}
		String link = String.valueOf(started.get('checkoutUrl'));
		update as user new Project_Invoice__c(
			Id = invoice.Id,
			Payment_Key__c = String.valueOf(started.get('paymentId')),
			Payment_Link__c = link
		);
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		mail.setTargetObjectId(invoice.Contact__c);
		mail.setWhatId(invoice.Id);
		mail.setSaveAsActivity(false);
		List<Object> args = new List<Object>{
			invoice.Name,
			UserInfo.getOrganizationName(),
			String.valueOf(owed.setScale(2)),
			link
		};
		mail.setSubject(BarnHelp.text('Projects', 'Projects_Invoice_LinkSubject', args));
		mail.setPlainTextBody(BarnHelp.text('Projects', 'Projects_Invoice_LinkBody', args));
		EmailSendOutcome outcome;
		try {
			outcome = emailSender.send(new List<Messaging.SingleEmailMessage>{ mail })[0];
		} catch (Exception e) {
			outcome = EmailSendOutcome.failed(e.getMessage());
		}
		if (outcome.sent) {
			return BarnHelp.text(
				'Projects',
				'Projects_Invoice_LinkSent',
				new List<Object>{ invoice.Contact__r.Email }
			);
		}
		ErrorLogger.logMessage(outcome.error, CONTEXT + '.sendLink', ErrorLogger.SEVERITY_WARNING);
		return BarnHelp.text(
			'Projects',
			'Projects_Invoice_LinkNotEmailed',
			new List<Object>{ outcome.error }
		);
	}

	/**
	 * R-PM22: applies what Payments reported, in bulk, to each invoice whose current Payment Key
	 * is the payment. The link was for the balance then due, so after a report Amount Paid is
	 * Total less the refunded amount when paid, or Total less the payment's amount when fully
	 * refunded; reporting the same status twice changes nothing more. Failed and Cancelled change
	 * nothing. A Void invoice is never changed (the report is logged).
	 *
	 * @param payments the seam's payment maps (ADR-0201 `0201-payments-module.md`, decision 8)
	 */
	public static void apply(List<Map<String, Object>> payments) {
		Set<Id> invoiceIds = new Set<Id>();
		for (Map<String, Object> payment : payments) {
			Id invoiceId = idOf(payment.get('sourceRecordId'));
			if (invoiceId != null) {
				invoiceIds.add(invoiceId);
			}
		}
		Map<Id, Project_Invoice__c> invoices = new Map<Id, Project_Invoice__c>(
			[
				SELECT Id, Name, Status__c, Total__c, Amount_Paid__c, Paid_Date__c, Payment_Key__c
				FROM Project_Invoice__c
				WHERE Id IN :invoiceIds
				WITH SYSTEM_MODE
			]
		);
		Map<Id, Project_Invoice__c> changes = new Map<Id, Project_Invoice__c>();
		for (Map<String, Object> payment : payments) {
			Project_Invoice__c invoice = invoices.get(idOf(payment.get('sourceRecordId')));
			String status = String.valueOf(payment.get('status'));
			if (
				invoice == null ||
				idOf(invoice.Payment_Key__c) != idOf(payment.get('paymentId')) ||
				(status != ProjectBilling.PAID &&
				status != 'Refunded')
			) {
				continue;
			}
			if (invoice.Status__c == ProjectBilling.VOIDED) {
				ErrorLogger.logMessage(
					BarnHelp.text(
						'Projects',
						'Projects_Invoice_VoidReport',
						new List<Object>{ invoice.Name }
					),
					CONTEXT,
					ErrorLogger.SEVERITY_WARNING
				);
				continue;
			}
			Decimal total = invoice.Total__c == null ? 0 : invoice.Total__c;
			Decimal amount = number(payment.get('amount'));
			invoice.Amount_Paid__c = status == ProjectBilling.PAID
				? total - number(payment.get('amountRefunded'))
				: total - amount;
			if (invoice.Amount_Paid__c >= total) {
				invoice.Status__c = ProjectBilling.PAID;
				invoice.Paid_Date__c = paidOn(payment.get('paidAt'));
			} else if (invoice.Status__c == ProjectBilling.PAID) {
				invoice.Status__c = ProjectBilling.SENT;
				invoice.Paid_Date__c = null;
			}
			changes.put(
				invoice.Id,
				new Project_Invoice__c(
					Id = invoice.Id,
					Amount_Paid__c = invoice.Amount_Paid__c,
					Status__c = invoice.Status__c,
					Paid_Date__c = invoice.Paid_Date__c
				)
			);
		}
		Database.update(changes.values(), true, AccessLevel.SYSTEM_MODE);
	}

	/** Total less Amount Paid. */
	public static Decimal balance(Project_Invoice__c invoice) {
		return (invoice.Total__c == null ? 0 : invoice.Total__c) -
			(invoice.Amount_Paid__c == null ? 0 : invoice.Amount_Paid__c);
	}

	private static Date paidOn(Object paidAt) {
		return paidAt instanceof Datetime ? ((Datetime) paidAt).date() : Date.today();
	}

	private static Decimal number(Object value) {
		return value == null ? 0 : Decimal.valueOf(String.valueOf(value));
	}

	private static Id idOf(Object value) {
		try {
			return value == null ? null : Id.valueOf(String.valueOf(value));
		} catch (Exception notAnId) {
			return null;
		}
	}
}
