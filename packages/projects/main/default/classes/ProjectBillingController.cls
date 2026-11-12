/**
 * The billing and financials screens (PM-10, PM-11; ADR-0219 `0219-projects-psa.md` decisions 6
 * and 7): New Invoice on the project page, the actions on an invoice, Export Invoices on Projects
 * Home and the Financials card. Thin by design (plan Section 9.9): plain maps in user mode; the
 * CSV, margin and the open month are worked out by `c/projectsBillingModel`. A refusal written
 * for the person, or a save's own message, is shown as it is; anything else is logged.
 */
public with sharing class ProjectBillingController {
	private static final String CONTEXT = 'ProjectBillingController';

	/**
	 * What the billing parts show: nothing unless invoices are on. With no project (Projects
	 * Home), only whether they are on and the person manages projects.
	 */
	@AuraEnabled
	public static Map<String, Object> getProjectBilling(Id projectId) {
		try {
			Boolean enabled = ProjectsSettings.billingEnabled();
			String type = null;
			if (enabled && projectId != null) {
				Project__c project = [
					SELECT Billing_Type__c
					FROM Project__c
					WHERE Id = :projectId
					WITH USER_MODE
				];
				type = ProjectBilling.billingType(project);
			}
			return new Map<String, Object>{
				'enabled' => enabled,
				'canManage' => Projects.canManage(),
				'billingType' => type
			};
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id buildInvoice(Id projectId, Date periodStart, Date periodEnd) {
		try {
			return ProjectBilling.build(projectId, periodStart, periodEnd);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** The invoice page's actions: which show, for the invoice's status. */
	@AuraEnabled
	public static Map<String, Object> getInvoiceActions(Id invoiceId) {
		try {
			Project_Invoice__c invoice = [
				SELECT Status__c, Total__c, Amount_Paid__c
				FROM Project_Invoice__c
				WHERE Id = :invoiceId
				WITH USER_MODE
			];
			Boolean enabled = ProjectsSettings.billingEnabled();
			return new Map<String, Object>{
				'enabled' => enabled,
				'canManage' => enabled && Projects.canManage(),
				'status' => invoice.Status__c,
				'balance' => ProjectInvoicePayments.balance(invoice),
				'online' => enabled && ProjectInvoicePayments.available()
			};
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void sendInvoice(Id invoiceId) {
		try {
			ProjectBilling.send(invoiceId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void markPaid(Id invoiceId, Date paidDate) {
		try {
			ProjectBilling.markPaid(invoiceId, paidDate);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void voidInvoice(Id invoiceId) {
		try {
			ProjectBilling.voidInvoice(invoiceId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id printInvoice(Id invoiceId) {
		try {
			return ProjectInvoiceDocument.print(invoiceId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static String sendPaymentLink(Id invoiceId) {
		try {
			return ProjectInvoicePayments.sendLink(invoiceId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/**
	 * Export Invoices (R-PM17): Sent and Paid invoices dated in the range, not yet exported unless
	 * asked, each with its lines; stamps Exported Date. The CSV is built in the browser.
	 */
	@AuraEnabled
	public static List<Project_Invoice__c> exportInvoices(
		Date fromDate,
		Date toDate,
		Boolean includeExported
	) {
		try {
			ProjectBilling.requireBilling();
			if (fromDate == null || toDate == null || toDate < fromDate) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Range_Invalid'));
			}
			List<String> billed = new List<String>{ ProjectBilling.SENT, ProjectBilling.PAID };
			List<Project_Invoice__c> invoices = new List<Project_Invoice__c>();
			List<Project_Invoice__c> stamps = new List<Project_Invoice__c>();
			for (Project_Invoice__c invoice : [
				SELECT
					Name,
					Status__c,
					Invoice_Date__c,
					Due_Date__c,
					Paid_Date__c,
					Total__c,
					Amount_Paid__c,
					Exported_Date__c,
					Account__r.Name,
					Project__r.Name,
					(
						SELECT
							Line_Type__c,
							Description__c,
							Service_Date__c,
							Quantity__c,
							Unit_Price__c,
							Amount__c
						FROM Lines__r
						ORDER BY Service_Date__c
						LIMIT 500
					)
				FROM Project_Invoice__c
				WHERE
					Status__c IN :billed
					AND Invoice_Date__c >= :fromDate
					AND Invoice_Date__c <= :toDate
				WITH USER_MODE
				ORDER BY Invoice_Date__c, Name
				LIMIT 2000
			]) {
				if (includeExported == true || invoice.Exported_Date__c == null) {
					invoices.add(invoice);
					stamps.add(
						new Project_Invoice__c(Id = invoice.Id, Exported_Date__c = Date.today())
					);
				}
			}
			update as user stamps;
			return invoices;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** The Financials card's figures (R-PM21); only `enabled` false while financials are off. */
	@AuraEnabled
	public static Map<String, Object> getFinancials(Id projectId) {
		try {
			return ProjectFinancials.card(projectId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Recognize Revenue (R-PM19): writes or redoes the project's row for a closed month. */
	@AuraEnabled
	public static Id recognizeRevenue(Id projectId, Date month) {
		try {
			return ProjectRevenue.recognizeMonth(projectId, month);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof Projects.ProjectsException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(e, BarnHelp.text('Projects', 'Projects_Error_Generic'));
	}
}
