/**
 * Volunteers Home (vis-modules-19): the first tab of the BarnCRM Volunteers app.
 *
 * One round trip returns three figures, each opening its list: approved hours this month, hours
 * waiting for approval and upcoming open shifts that still need people. The names come from the
 * org's own metadata (object, picklist and list view labels) where one fits, so the page adds
 * one custom label. Each figure is read in user mode and capped; a figure the person cannot read
 * is left out, never shown as zero.
 */
public with sharing class VolunteersHomeController {
	/** The most rows a count reads; past it the page shows "2,000+". */
	@TestVisible
	private static final Integer COUNT_CAP = 2000;

	@TestVisible
	private static final String SHIFTS_LIST_VIEW = 'Shifts_Needing_Volunteers';

	/** One figure: a value over a label and a status word, and where clicking it goes. */
	public class Tile {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String badgeLabel;
		/** A word from the kit's status vocabulary (c/barnStatus), for the badge's tone. */
		@AuraEnabled
		public String badgeStatus;
		@AuraEnabled
		public Decimal value;
		/** True when a count reached COUNT_CAP and the real number is higher. */
		@AuraEnabled
		public Boolean capped = false;
		@AuraEnabled
		public String objectApiName;
		@AuraEnabled
		public String filterName;
		/** The app page tab the figure opens, when it opens one instead of a list view. */
		@AuraEnabled
		public String tabName;
		/** The ISO currency code of a money figure (V-12), or null for a count. */
		@AuraEnabled
		public String currencyCode;
	}

	@AuraEnabled
	public static List<Tile> getHome() {
		try {
			List<Tile> tiles = new List<Tile>();
			if (Schema.SObjectType.Volunteer_Hours__c.isAccessible()) {
				addHoursTiles(tiles);
			}
			if (Schema.SObjectType.Volunteer_Shift__c.isAccessible()) {
				addShiftsTile(tiles);
			}
			return tiles;
		} catch (Exception caught) {
			throw UserErrors.wrap(caught, 'Volunteers Home', true);
		}
	}

	/** The first-run panel (D-200 R4): whether it shows, and whether it offers a file import. */
	public class FirstRun {
		/** True when the person may create volunteer jobs and none exists yet. */
		@AuraEnabled
		public Boolean show = false;
		@AuraEnabled
		public Boolean canImport = false;
	}

	/**
	 * Whether Volunteers Home opens on its first-run panel: no volunteer job exists yet and the
	 * person may create one. A separate call, so getHome keeps its list of figures.
	 */
	@AuraEnabled
	public static FirstRun getFirstRun() {
		try {
			FirstRun result = new FirstRun();
			result.show =
				Schema.SObjectType.Volunteer_Job__c.isCreateable() &&
				[SELECT Id FROM Volunteer_Job__c WITH USER_MODE LIMIT 1]
				.isEmpty();
			result.canImport = result.show && Schema.SObjectType.Import_Batch__c.isCreateable();
			return result;
		} catch (Exception caught) {
			throw UserErrors.wrap(caught, 'Volunteers Home', true);
		}
	}

	private static void addHoursTiles(List<Tile> tiles) {
		String hoursObject = Schema.SObjectType.Volunteer_Hours__c.getName();
		Schema.DescribeFieldResult status = Schema.SObjectType.Volunteer_Hours__c.fields.Status__c;
		Tile month = new Tile();
		month.name = 'hoursThisMonth';
		month.label = Label.Volunteers_Home_HoursThisMonth;
		month.value = approvedHoursThisMonth();
		month.badgeLabel = picklistLabel(status, VolunteerHoursService.STATUS_APPROVED);
		month.badgeStatus = 'done';
		month.objectApiName = hoursObject;
		month.filterName = 'All_Volunteer_Hours';
		addIfRead(tiles, month);

		// V-12 (R-VP5): this month's hours times Hour Value, shown only; left out at 0.
		Decimal rate = VolunteerSettings.hourValue();
		if (month.value != null && rate > 0) {
			Tile worth = new Tile();
			worth.name = 'hoursValueThisMonth';
			worth.label = Label.Volunteers_Home_HoursValueThisMonth;
			worth.value = (month.value * rate).setScale(2);
			worth.currencyCode = UserInfo.getDefaultCurrency();
			worth.objectApiName = hoursObject;
			worth.filterName = 'All_Volunteer_Hours';
			tiles.add(worth);
		}

		Tile waiting = new Tile();
		waiting.name = 'hoursToApprove';
		waiting.label = Schema.SObjectType.Volunteer_Hours__c.getLabelPlural();
		setCount(waiting, countHoursToApprove());
		waiting.badgeLabel = picklistLabel(status, VolunteerHoursService.STATUS_SUBMITTED);
		waiting.badgeStatus = 'due';
		waiting.objectApiName = hoursObject;
		if (VolunteerHoursService.canManage()) {
			waiting.tabName = NamespaceUtil.qualify('Volunteer_Approve_Hours');
		} else {
			waiting.filterName = 'Hours_Awaiting_Approval';
		}
		addIfRead(tiles, waiting);
	}

	private static void addShiftsTile(List<Tile> tiles) {
		Tile shifts = new Tile();
		shifts.name = 'shiftsNeedingPeople';
		shifts.label = shiftsLabel();
		setCount(shifts, countShiftsNeedingPeople());
		shifts.badgeStatus = 'info';
		shifts.objectApiName = Schema.SObjectType.Volunteer_Shift__c.getName();
		shifts.filterName = SHIFTS_LIST_VIEW;
		addIfRead(tiles, shifts);
	}

	private static void setCount(Tile target, Integer counted) {
		if (counted != null) {
			target.capped = counted > COUNT_CAP;
			target.value = Math.min(counted, COUNT_CAP);
		}
	}

	private static void addIfRead(List<Tile> tiles, Tile candidate) {
		if (candidate.value != null) {
			tiles.add(candidate);
		}
	}

	private static Decimal approvedHoursThisMonth() {
		String approved = VolunteerHoursService.STATUS_APPROVED;
		try {
			AggregateResult[] totals = [
				SELECT SUM(Hours__c) total
				FROM Volunteer_Hours__c
				WHERE Status__c = :approved AND Date_Worked__c = THIS_MONTH
				WITH USER_MODE
			];
			Decimal total = totals.isEmpty() ? null : (Decimal) totals[0].get('total');
			return total == null ? 0 : total;
		} catch (QueryException unreadable) {
			return null;
		}
	}

	private static Integer countHoursToApprove() {
		String submitted = VolunteerHoursService.STATUS_SUBMITTED;
		Integer cap = COUNT_CAP + 1;
		try {
			return [
				SELECT COUNT()
				FROM Volunteer_Hours__c
				WHERE Status__c = :submitted
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	/** The same filter as the Shifts Needing Volunteers list view the figure opens. */
	private static Integer countShiftsNeedingPeople() {
		Integer cap = COUNT_CAP + 1;
		Datetime today = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
		try {
			return [
				SELECT COUNT()
				FROM Volunteer_Shift__c
				WHERE Status__c = 'Open' AND Start_Time__c >= :today AND Slots_Remaining__c > 0
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	private static String shiftsLabel() {
		String objectName = Schema.SObjectType.Volunteer_Shift__c.getName();
		List<ListView> views = [
			SELECT Name
			FROM ListView
			WHERE SobjectType = :objectName AND DeveloperName = :SHIFTS_LIST_VIEW
			WITH USER_MODE
			LIMIT 1
		];
		return views.isEmpty()
			? Schema.SObjectType.Volunteer_Shift__c.getLabelPlural()
			: views[0].Name;
	}

	@TestVisible
	private static String picklistLabel(Schema.DescribeFieldResult field, String value) {
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (entry.getValue() == value) {
				return entry.getLabel();
			}
		}
		return value;
	}
}
