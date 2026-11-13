/**
 * The Project Management settings as the module's code reads them (canonical model 29PM7),
 * through Core's typed `SettingsService` readers, which serve an org that never saved them the
 * record its first save would store (ADR-0035). A blank or out of range number reads as the
 * field's declared default, the range being its Setting Definition's.
 */
public with sharing class ProjectsSettings {
	public static final String SETTINGS_OBJECT = 'Projects_Settings__c';

	/** Whether Log Time, budgets, utilization and the billable export show. Ships on. */
	public static Boolean timeTracking() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Time_Tracking_Enabled__c');
	}

	/** Days past due before an open task puts its project At Risk. */
	public static Integer atRiskDays() {
		return whole('At_Risk_Days__c');
	}

	/** The share of Budget Hours that, once used, puts a project At Risk. */
	public static Integer budgetWarningPercent() {
		return whole('Budget_Warning_Percent__c');
	}

	/** One person's working hours in a week. */
	public static Integer weeklyCapacity() {
		return whole('Weekly_Capacity_Hours__c');
	}

	/** PM-06: rate cards. Each PSA part ships off and needs time tracking on (ADR-0219 projects-psa). */
	public static Boolean ratesEnabled() {
		return part('Rates_Enabled__c');
	}

	/** PM-07: time and expense approvals. */
	public static Boolean approvalsEnabled() {
		return part('Approvals_Enabled__c');
	}

	/** PM-08: expenses. */
	public static Boolean expensesEnabled() {
		return part('Expenses_Enabled__c');
	}

	/** PM-09: resources, requests, staffing and allocation. */
	public static Boolean resourcesEnabled() {
		return part('Resources_Enabled__c');
	}

	/** PM-10: billing types and invoices. */
	public static Boolean billingEnabled() {
		return part('Billing_Enabled__c');
	}

	/** PM-10: Pay Online on invoices through BarnCRM Payments; needs billing on. */
	public static Boolean onlinePaymentsEnabled() {
		return billingEnabled() && part('Online_Payments_Enabled__c');
	}

	/** PM-11: the financials card and recognized revenue. */
	public static Boolean revenueEnabled() {
		return part('Revenue_Enabled__c');
	}

	/** PM-12: change requests. */
	public static Boolean changeRequestsEnabled() {
		return part('Change_Requests_Enabled__c');
	}

	/** D-201: requests and issues. Does not need time tracking. */
	public static Boolean requestsEnabled() {
		return flag('Requests_Enabled__c');
	}

	/** D-201: requests from the portal and request connections; needs requests on. */
	public static Boolean requestsExternalEnabled() {
		return requestsEnabled() && flag('Requests_External_Enabled__c');
	}

	/** Weekdays from a request's creation to its due date, by its priority. */
	public static Integer requestDueDays(String priority) {
		switch on priority {
			when 'Urgent' {
				return days('Request_Days_Urgent__c', 1);
			}
			when 'High' {
				return days('Request_Days_High__c', 2);
			}
			when 'Low' {
				return days('Request_Days_Low__c', 10);
			}
			when else {
				return days('Request_Days_Medium__c', 5);
			}
		}
	}

	private static Boolean flag(String key) {
		return SettingsService.flag(SETTINGS_OBJECT, key);
	}

	/** A due-day setting, 0 to 365, or the shipped default when unreadable. */
	private static Integer days(String key, Integer fallback) {
		Decimal stored = SettingsService.number(SETTINGS_OBJECT, key);
		return stored == null ? fallback : Math.min(Math.max(stored.intValue(), 0), 365);
	}

	/** Days from an invoice's date to its due date. */
	public static Integer invoiceDueDays() {
		return whole('Invoice_Due_Days__c');
	}

	/**
	 * Where a client lands after paying online. Filled with the org's My Domain address at
	 * install (`ProjectsPostInstall`), so the console shows it; read as that address if cleared.
	 */
	public static String invoiceReturnUrl() {
		String stored = SettingsService.text(SETTINGS_OBJECT, 'Invoice_Return_Url__c');
		return String.isBlank(stored) ? myDomain() : stored;
	}

	/** The org's My Domain address, the shipped Invoice payment return page. */
	public static String myDomain() {
		return Url.getOrgDomainUrl().toExternalForm();
	}

	private static Boolean part(String key) {
		return timeTracking() && SettingsService.flag(SETTINGS_OBJECT, key);
	}

	private static Integer whole(String key) {
		return SettingsService.number(SETTINGS_OBJECT, key).intValue();
	}
}
