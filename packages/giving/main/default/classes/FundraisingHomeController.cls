/**
 * Fundraising Home (people-giving-22): the first tab of the BarnCRM Fundraising app.
 *
 * One round trip returns the five "today" figures, whether the person may enter a gift, and the
 * Fundraising Setup tiles they may open. Every name on the page comes from the org's own
 * metadata (object and picklist labels, a list view's name, a tab's label), so a renamed object
 * or page shows its new name here and the page adds no custom labels for them.
 *
 * Each figure is counted in user mode and capped, so a large org pays for at most COUNT_CAP rows
 * per figure. A figure whose object the person cannot read is left out, never shown as zero.
 */
public with sharing class FundraisingHomeController {
	/** The most rows a figure counts; past it the page shows "2,000+". */
	@TestVisible
	private static final Integer COUNT_CAP = 2000;

	/** The asks figure is named by the list view it opens. */
	@TestVisible
	private static final String ASKS_LIST_VIEW = 'My_Asks_Due_This_Month';

	/** One figure: a count over a label and a status word, and where clicking it goes. */
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
		public Integer count;
		/** True when the count reached COUNT_CAP and the real number is higher. */
		@AuraEnabled
		public Boolean capped;
		/** The object the figure counts, for its icon and its list view. */
		@AuraEnabled
		public String objectApiName;
		/** The list view the figure opens, when it opens one. */
		@AuraEnabled
		public String filterName;
		/** The app page tab the figure opens, when it opens one instead of a list view. */
		@AuraEnabled
		public String tabName;
	}

	/** One Fundraising Setup tile: a setup page that left the app's menu. */
	public class SetupTile {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
	}

	/** The page, in one round trip. */
	public class HomeView {
		@AuraEnabled
		public List<Tile> tiles = new List<Tile>();
		@AuraEnabled
		public Boolean canEnterGift = false;
		@AuraEnabled
		public List<SetupTile> setupTiles = new List<SetupTile>();
	}

	@AuraEnabled
	public static HomeView getHome() {
		try {
			HomeView view = new HomeView();
			addTiles(view.tiles);
			view.canEnterGift = Schema.SObjectType.Gift__c.isCreateable();
			view.setupTiles = setupTiles();
			return view;
		} catch (Exception caught) {
			throw UserErrors.wrap(caught, 'Fundraising Home', true);
		}
	}

	private static void addTiles(List<Tile> tiles) {
		if (Schema.SObjectType.Gift__c.isAccessible()) {
			Tile thank = tile(
				'giftsToThank',
				Schema.SObjectType.Gift__c.getLabelPlural(),
				countGiftsToThank()
			);
			thank.badgeLabel = picklistLabel(
				Schema.SObjectType.Gift__c.fields.Acknowledgment_Status__c,
				AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE
			);
			thank.badgeStatus = 'due';
			thank.objectApiName = Schema.SObjectType.Gift__c.getName();
			thank.tabName = 'Acknowledgments';
			addIfCounted(tiles, thank);
		}
		if (Schema.SObjectType.Installment__c.isAccessible()) {
			Tile overdue = tile(
				'installmentsOverdue',
				Schema.SObjectType.Installment__c.getLabelPlural(),
				countOverdueInstallments()
			);
			overdue.badgeLabel = picklistLabel(
				Schema.SObjectType.Installment__c.fields.Status__c,
				'Overdue'
			);
			overdue.badgeStatus = 'overdue';
			overdue.objectApiName = Schema.SObjectType.Installment__c.getName();
			overdue.filterName = 'Overdue';
			addIfCounted(tiles, overdue);
		}
		if (Schema.SObjectType.Ask__c.isAccessible()) {
			Tile asks = tile('myAsksDue', asksLabel(), countMyAsksDueThisMonth());
			asks.objectApiName = Schema.SObjectType.Ask__c.getName();
			asks.filterName = ASKS_LIST_VIEW;
			addIfCounted(tiles, asks);
		}
		if (Schema.SObjectType.Gift_Batch__c.isAccessible()) {
			Tile batches = tile(
				'openBatches',
				Schema.SObjectType.Gift_Batch__c.getLabelPlural(),
				countOpenBatches()
			);
			batches.badgeLabel = picklistLabel(
				Schema.SObjectType.Gift_Batch__c.fields.Status__c,
				'Open'
			);
			batches.badgeStatus = 'info';
			batches.objectApiName = Schema.SObjectType.Gift_Batch__c.getName();
			batches.filterName = 'Open_Batches';
			addIfCounted(tiles, batches);
		}
		if (Schema.SObjectType.Stewardship_Plan__c.isAccessible()) {
			Tile plans = tile(
				'runningPlans',
				Schema.SObjectType.Stewardship_Plan__c.getLabelPlural(),
				countRunningPlans()
			);
			plans.badgeLabel = picklistLabel(
				Schema.SObjectType.Stewardship_Plan__c.fields.Status__c,
				'Running'
			);
			plans.badgeStatus = 'running';
			plans.objectApiName = Schema.SObjectType.Stewardship_Plan__c.getName();
			plans.filterName = 'Running_Plans';
			addIfCounted(tiles, plans);
		}
	}

	@TestVisible
	private static Tile tile(String name, String label, Integer counted) {
		Tile result = new Tile();
		result.name = name;
		result.label = label;
		if (counted != null) {
			result.capped = counted > COUNT_CAP;
			result.count = Math.min(counted, COUNT_CAP);
		}
		return result;
	}

	/** A figure whose count could not be read (a field the person cannot see) is left out. */
	private static void addIfCounted(List<Tile> tiles, Tile candidate) {
		if (candidate.count != null) {
			tiles.add(candidate);
		}
	}

	private static Integer limitPlusOne() {
		return COUNT_CAP + 1;
	}

	/**
	 * Received gifts waiting for a thank you. The same filter as
	 * AcknowledgmentSelector.queuedGifts, so this figure and the Acknowledgment Queue it opens
	 * count the same gifts.
	 */
	private static Integer countGiftsToThank() {
		String toAcknowledge = AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE;
		Integer cap = limitPlusOne();
		try {
			return [
				SELECT COUNT()
				FROM Gift__c
				WHERE
					Acknowledgment_Status__c = :toAcknowledge
					AND Status__c = 'Received'
					AND Amount__c > 0
					AND Id NOT IN (SELECT Gift__c FROM Acknowledgment__c WHERE Gift_Key__c != NULL)
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	private static Integer countOverdueInstallments() {
		Integer cap = limitPlusOne();
		try {
			return [
				SELECT COUNT()
				FROM Installment__c
				WHERE Status__c = 'Overdue'
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	/** The person's own open asks whose Target Date is this month, as the list view counts them. */
	private static Integer countMyAsksDueThisMonth() {
		Id me = UserInfo.getUserId();
		Integer cap = limitPlusOne();
		try {
			return [
				SELECT COUNT()
				FROM Ask__c
				WHERE OwnerId = :me AND Outcome__c = 'Open' AND Target_Date__c = THIS_MONTH
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	private static Integer countOpenBatches() {
		Integer cap = limitPlusOne();
		try {
			return [
				SELECT COUNT()
				FROM Gift_Batch__c
				WHERE Status__c = 'Open'
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	private static Integer countRunningPlans() {
		Integer cap = limitPlusOne();
		try {
			return [
				SELECT COUNT()
				FROM Stewardship_Plan__c
				WHERE Status__c = 'Running'
				WITH USER_MODE
				LIMIT :cap
			];
		} catch (QueryException unreadable) {
			return null;
		}
	}

	/** The asks list view's own name, so the figure and the list it opens read the same. */
	private static String asksLabel() {
		String objectName = Schema.SObjectType.Ask__c.getName();
		List<ListView> views = [
			SELECT Name
			FROM ListView
			WHERE SobjectType = :objectName AND DeveloperName = :ASKS_LIST_VIEW
			WITH USER_MODE
			LIMIT 1
		];
		return views.isEmpty() ? Schema.SObjectType.Ask__c.getLabelPlural() : views[0].Name;
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

	/**
	 * The setup pages that left the app's menu, each named by its own tab label. The Donor Level
	 * Ladder and Stewardship Plan Setup change org-wide setup, so they need Manage BarnCRM
	 * Settings; Pledge Reminders and Receipt Letters show to anyone who can read what they list,
	 * as their tabs do in the Giving permission sets.
	 */
	private static List<SetupTile> setupTiles() {
		Boolean canManage = BarnCRMPermissions.canManageSettings();
		List<String> names = new List<String>();
		if (canManage && Schema.SObjectType.Donor_Level__c.isAccessible()) {
			names.add('Donor_Levels');
		}
		if (canManage && Schema.SObjectType.Stewardship_Plan_Template__c.isAccessible()) {
			names.add('Stewardship_Plans');
		}
		if (Schema.SObjectType.Pledge_Reminder__c.isAccessible()) {
			names.add('Pledge_Reminders');
		}
		if (Schema.SObjectType.Receipt_Run__c.isAccessible()) {
			names.add('Receipts');
		}
		Map<String, String> labels = tabLabels(names);
		List<SetupTile> tiles = new List<SetupTile>();
		for (String name : names) {
			if (labels.containsKey(name)) {
				SetupTile setup = new SetupTile();
				setup.name = name;
				setup.label = labels.get(name);
				tiles.add(setup);
			}
		}
		return tiles;
	}

	private static Map<String, String> tabLabels(List<String> names) {
		Map<String, String> labels = new Map<String, String>();
		if (names.isEmpty()) {
			return labels;
		}
		for (TabDefinition tab : [
			SELECT Name, Label
			FROM TabDefinition
			WHERE Name IN :names
			WITH SYSTEM_MODE
		]) {
			labels.put(tab.Name, tab.Label);
		}
		return labels;
	}
}
