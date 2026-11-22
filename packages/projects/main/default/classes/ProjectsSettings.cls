/**
 * The Project Management settings as the module's code reads them (canonical model 29PM7), from
 * the settings store by Setting Definition name (`ModuleSettings`, ADR-NEXT settings as custom
 * metadata): an org that never saved one reads its shipped default, and a blank or out of range
 * number reads as that default, the range being its Setting Definition's.
 */
public with sharing class ProjectsSettings {
	public static final String SETTINGS_OBJECT = 'Projects_Settings__c';

	/** Whether Log Time, budgets, utilization and the billable export show. Ships on. */
	public static Boolean timeTracking() {
		return ModuleSettings.flag('Projects_Time_Tracking_Enabled');
	}

	/** Days past due before an open task puts its project At Risk. */
	public static Integer atRiskDays() {
		return ModuleSettings.integerValue('Projects_At_Risk_Days');
	}

	/** The share of Budget Hours that, once used, puts a project At Risk. */
	public static Integer budgetWarningPercent() {
		return ModuleSettings.integerValue('Projects_Budget_Warning_Percent');
	}

	/** One person's working hours in a week. */
	public static Integer weeklyCapacity() {
		return ModuleSettings.integerValue('Projects_Weekly_Capacity_Hours');
	}

	/** PM-06: rate cards. Each PSA part ships off and needs time tracking on (ADR-0219 projects-psa). */
	public static Boolean ratesEnabled() {
		return part('Projects_Rates_Enabled');
	}

	/**
	 * The Use rate cards setting alone, without time tracking: what a project's Actual Cost
	 * follows (`ProjectCostHandler`), as the cost always has.
	 */
	public static Boolean ratesSetting() {
		return ModuleSettings.flag('Projects_Rates_Enabled');
	}

	/** PM-07: time and expense approvals. */
	public static Boolean approvalsEnabled() {
		return part('Projects_Approvals_Enabled');
	}

	/** PM-08: expenses. */
	public static Boolean expensesEnabled() {
		return part('Projects_Expenses_Enabled');
	}

	/** PM-09: resources, requests, staffing and allocation. */
	public static Boolean resourcesEnabled() {
		return part('Projects_Resources_Enabled');
	}

	/** PM-10: billing types and invoices. */
	public static Boolean billingEnabled() {
		return part('Projects_Billing_Enabled');
	}

	/** PM-10: Pay Online on invoices through BarnCRM Payments; needs billing on. */
	public static Boolean onlinePaymentsEnabled() {
		return billingEnabled() && part('Projects_Online_Payments_Enabled');
	}

	/** PM-11: the financials card and recognized revenue. */
	public static Boolean revenueEnabled() {
		return part('Projects_Revenue_Enabled');
	}

	/** PM-12: change requests. */
	public static Boolean changeRequestsEnabled() {
		return part('Projects_Change_Requests_Enabled');
	}

	/**
	 * The Track change requests setting alone, without time tracking: whether a new change
	 * request may be saved (`ProjectChangeRequestHandler`).
	 */
	public static Boolean changeRequestsSetting() {
		return ModuleSettings.flag('Projects_Change_Requests_Enabled');
	}

	/** D-201: requests and issues. Does not need time tracking. */
	public static Boolean requestsEnabled() {
		return ModuleSettings.flag('Projects_Requests_Enabled');
	}

	/** D-201: requests from the portal and request connections; needs requests on. */
	public static Boolean requestsExternalEnabled() {
		return requestsEnabled() && ModuleSettings.flag('Projects_Requests_External_Enabled');
	}

	/** Weekdays from a request's creation to its due date, by its priority. */
	public static Integer requestDueDays(String priority) {
		switch on priority {
			when 'Urgent' {
				return days('Projects_Request_Days_Urgent', 1);
			}
			when 'High' {
				return days('Projects_Request_Days_High', 2);
			}
			when 'Low' {
				return days('Projects_Request_Days_Low', 10);
			}
			when else {
				return days('Projects_Request_Days_Medium', 5);
			}
		}
	}

	/** A due-day setting, 0 to 365, or the shipped default when unreadable. */
	private static Integer days(String name, Integer fallback) {
		Decimal stored = ModuleSettings.number(name);
		return stored == null ? fallback : Math.min(Math.max(stored.intValue(), 0), 365);
	}

	/** Days from an invoice's date to its due date. */
	public static Integer invoiceDueDays() {
		return ModuleSettings.integerValue('Projects_Invoice_Due_Days');
	}

	/**
	 * Where a client lands after paying online: the saved address, else the org's My Domain
	 * address, which is the shipped value (computed here, as no definition can ship it).
	 */
	public static String invoiceReturnUrl() {
		String stored = ModuleSettings.text('Projects_Invoice_Return_Url');
		return String.isBlank(stored) ? myDomain() : stored;
	}

	/** The org's My Domain address, the shipped Invoice payment return page. */
	public static String myDomain() {
		return Url.getOrgDomainUrl().toExternalForm();
	}

	private static Boolean part(String name) {
		return timeTracking() && ModuleSettings.flag(name);
	}
}
