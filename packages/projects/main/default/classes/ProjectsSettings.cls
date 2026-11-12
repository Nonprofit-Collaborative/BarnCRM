/**
 * The Project Management settings as the module's code reads them (canonical model 29PM7),
 * through Core's `SettingsService`, which serves an org that never saved them the record its
 * first save would store (ADR-0035). A blank or out of range number reads as its default.
 */
public with sharing class ProjectsSettings {
	public static final String SETTINGS_OBJECT = 'Projects_Settings__c';

	/** Whether Log Time, budgets, utilization and the billable export show. Ships on. */
	public static Boolean timeTracking() {
		Object stored = read('Time_Tracking_Enabled__c');
		return stored == null ? true : Boolean.valueOf(String.valueOf(stored));
	}

	/** Days past due before an open task puts its project At Risk. */
	public static Integer atRiskDays() {
		return number('At_Risk_Days__c', 7, 365);
	}

	/** The share of Budget Hours that, once used, puts a project At Risk. */
	public static Integer budgetWarningPercent() {
		return number('Budget_Warning_Percent__c', 90, 100);
	}

	/** One person's working hours in a week. */
	public static Integer weeklyCapacity() {
		return number('Weekly_Capacity_Hours__c', 40, 168);
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

	/** Days from an invoice's date to its due date. */
	public static Integer invoiceDueDays() {
		return number('Invoice_Due_Days__c', 30, 365);
	}

	/**
	 * Where a client lands after paying online. Filled with the org's My Domain address at
	 * install (`ProjectsPostInstall`), so the console shows it; read as that address if cleared.
	 */
	public static String invoiceReturnUrl() {
		Object stored = read('Invoice_Return_Url__c');
		return stored == null || String.isBlank(String.valueOf(stored))
			? myDomain()
			: String.valueOf(stored).trim();
	}

	/** The org's My Domain address, the shipped Invoice payment return page. */
	public static String myDomain() {
		return Url.getOrgDomainUrl().toExternalForm();
	}

	private static Boolean part(String key) {
		Object stored = read(key);
		return timeTracking() && stored != null && Boolean.valueOf(String.valueOf(stored));
	}

	private static Integer number(String key, Integer shipped, Integer max) {
		Object stored = read(key);
		Integer value;
		try {
			value = stored == null ? null : Decimal.valueOf(String.valueOf(stored)).intValue();
		} catch (TypeException unreadable) {
			value = null;
		}
		return value == null || value < 1 || value > max ? shipped : value;
	}

	/** A setting that cannot be read is treated as never saved: the shipped value applies. */
	private static Object read(String key) {
		try {
			return SettingsService.getValue(SETTINGS_OBJECT, key);
		} catch (SettingsService.SettingsException unreadable) {
			return null;
		}
	}
}
