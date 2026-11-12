/**
 * Dues paid online through BarnCRM Payments (PAY-02; ADR-NEXT `NEXT-memberships-module.md`,
 * decision 6; canonical model R-MEM7). `request` checks the term and that Payments is ready, then
 * queues this job, because the staff page and the portal both write before a callout could run.
 * The job asks `PaymentsApi` (found by name, so Memberships never depends on Payments) for a
 * hosted checkout for one term, stores its address on the term and emails it to the member.
 * One term per job: Payments writes the payment after its callout, and no second callout may
 * follow that write in the same transaction.
 */
public with sharing class MembershipPayments implements Queueable, Database.AllowsCallouts {
	public static final String LISTENER = 'MembershipPaymentListener';
	private static final String CONTEXT = 'MembershipPayments';

	/** Set by tests: the Payments API, since Payments is not in this package's org. */
	@TestVisible
	private static Callable apiOverride;
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	private final Id termId;

	public MembershipPayments(Id termId) {
		this.termId = termId;
	}

	/** Payments' API, or null when it is not installed. */
	public static Callable api() {
		return apiOverride != null
			? apiOverride
			: (Callable) NamespaceUtil.build('PaymentsApi', Callable.class, CONTEXT);
	}

	/** True when Payments is installed and its chosen processor's keys are entered. */
	public static Boolean ready() {
		Callable payments = api();
		try {
			return payments != null && payments.call('isReady', null) == true;
		} catch (Exception notReady) {
			return false;
		}
	}

	/**
	 * Queues the payment link for the term, or throws with the reason in plain words. The term is
	 * read in system mode: callers have already checked the person may act on it.
	 */
	public static void request(Id termId) {
		Membership_Term__c term = load(termId);
		String problem;
		if (term == null) {
			problem = BarnHelp.text('Memberships', 'Memberships_Error_NotFound');
		} else if (!ready()) {
			problem = BarnHelp.text('Memberships', 'Memberships_Error_PaymentsNotReady');
		} else if (
			term.Status__c == MembershipService.RENEWED ||
			term.Status__c == MembershipService.CANCELLED
		) {
			problem = BarnHelp.text('Memberships', 'Memberships_Error_CannotRenew');
		} else if (term.Contact__r?.Email == null) {
			problem = BarnHelp.text('Memberships', 'Memberships_Error_NoEmail');
		} else if (amountFor(term) <= 0) {
			problem = BarnHelp.text('Memberships', 'Memberships_Error_NoDues');
		}
		if (problem != null) {
			throw new MembershipService.MembershipException(problem);
		}
		System.enqueueJob(new MembershipPayments(termId));
	}

	public void execute(QueueableContext queued) {
		Membership_Term__c term = load(termId);
		Id templateId = MembershipEmails.templateId(MembershipsSettings.PAYMENT_LINK_TEMPLATE);
		Callable payments = api();
		if (term == null || payments == null || templateId == null) {
			ErrorLogger.logMessage(
				BarnHelp.text('Memberships', 'Memberships_Error_LinkNotSent'),
				CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
			return;
		}
		String url;
		try {
			Map<String, Object> started = (Map<String, Object>) payments.call(
				'startCheckout',
				new Map<String, Object>{
					'amount' => amountFor(term),
					'description' => term.Level__r.Name,
					'successUrl' => returnUrl(),
					'cancelUrl' => returnUrl(),
					'payerName' => term.Member_Name__c,
					'payerEmail' => term.Contact__r.Email,
					'personId' => term.Contact__c,
					'sourceRecordId' => term.Id,
					'listener' => LISTENER
				}
			);
			url = (String) started.get('checkoutUrl');
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT, term.Id);
			return;
		}
		update as system new Membership_Term__c(Id = term.Id, Pay_Link__c = url);
		MembershipEmails.send(new List<Membership_Term__c>{ term }, templateId, null, emailSender);
	}

	/** A Pending term pays its own dues; any other pays the level's dues for the next term. */
	private static Decimal amountFor(Membership_Term__c term) {
		Decimal amount = term.Status__c == MembershipService.PENDING &&
			term.Dues__c != null
			? term.Dues__c
			: term.Level__r.Dues__c;
		return amount == null ? 0 : amount;
	}

	private static Membership_Term__c load(Id termId) {
		List<Membership_Term__c> found = [
			SELECT
				Id,
				Status__c,
				Dues__c,
				End_Date__c,
				Member_Name__c,
				Contact__c,
				Contact__r.Email,
				Level__r.Name,
				Level__r.Dues__c
			FROM Membership_Term__c
			WHERE Id = :termId
			WITH SYSTEM_MODE
		];
		return found.isEmpty() ? null : found[0];
	}

	/** Where the payer returns: the first active Salesforce Site's home page, else the org. */
	@TestVisible
	private static String returnUrl() {
		List<Site> sites = [
			SELECT Id
			FROM Site
			WHERE Status = 'Active' AND SiteType = 'Visualforce'
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
			LIMIT 1
		];
		if (!sites.isEmpty()) {
			// The durable id is the site's id; matched both ways since its length is not documented.
			Set<String> ids = new Set<String>{
				String.valueOf(sites[0].Id),
				String.valueOf(sites[0].Id).left(15)
			};
			for (SiteDetail detail : [
				SELECT SecureUrl
				FROM SiteDetail
				WHERE DurableId IN :ids
				WITH SYSTEM_MODE
			]) {
				if (String.isNotBlank(detail.SecureUrl)) {
					return detail.SecureUrl;
				}
			}
		}
		return Url.getOrgDomainUrl().toExternalForm();
	}
}
