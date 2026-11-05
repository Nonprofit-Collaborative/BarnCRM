/**
 * What the Automation page manages beyond the switches and the timed pause (ADR-0165 dispatcher
 * errors and Automation Control, decisions 2.6 to 2.8; canonical model R-A8):
 *
 * - the BarnCRM Automation Control rows: the org default, always shown (both boxes off until
 *   saved) and never deleted, and each profile and user row, added, saved per box and removed;
 * - an org's own flows, listed as switch rows named `Flow:` plus the API name, which the Check
 *   BarnCRM Automation action reads; listing or removing never changes the flow;
 * - Catch Up Now.
 *
 * Every write requires Manage BarnCRM Settings and is logged as a setting change. The setting
 * rows are read and written in system mode: a custom setting takes no object or field permission
 * a BarnCRM Admin could hold, so `AutomationSettingsWriter` (ADR-0021) writes them after the
 * check here, and only with an owner checked to be this org, a Profile or a User.
 */
public with sharing class AutomationControlSettingService {
	public static final String FLOW_PREFIX = 'Flow:';
	public static final String LEVEL_ORGANIZATION = 'Organization';
	public static final String LEVEL_PROFILE = 'Profile';
	public static final String LEVEL_USER = 'User';

	private static final Integer MAX_ROWS = 1000;
	private static final Pattern FLOW_API_NAME = Pattern.compile('[A-Za-z][A-Za-z0-9_]{0,79}');

	/** One Automation Control row as the page shows it; sorts by name. */
	public class ControlRow implements Comparable {
		@AuraEnabled
		public String ownerId;
		/** The profile's or user's name; null for the org default, which the page names. */
		@AuraEnabled
		public String ownerName;
		/** Organization, Profile or User. */
		@AuraEnabled
		public String level;
		@AuraEnabled
		public Boolean pauseAll;
		@AuraEnabled
		public Boolean bypass;

		public Integer compareTo(Object other) {
			String mine = ownerName == null ? '' : ownerName.toLowerCase();
			String theirs = ((ControlRow) other).ownerName;
			return mine.compareTo(theirs == null ? '' : theirs.toLowerCase());
		}
	}

	/** One choice in a picker: a profile, or a flow not yet listed. */
	public class Option {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;

		Option(String value, String label) {
			this.value = value;
			this.label = label;
		}
	}

	// ------------------------------------------------------------- Automation Control rows

	/** The org default first, with its values or both off, then profiles, then users, by name. */
	public static List<ControlRow> rows() {
		Id orgId = UserInfo.getOrganizationId();
		ControlRow orgRow = row(orgId, null, LEVEL_ORGANIZATION, false, false);
		List<ControlRow> profiles = new List<ControlRow>();
		List<ControlRow> users = new List<ControlRow>();
		// System mode: a custom setting is configuration with no object permission to grant,
		// and the page must show every row to whoever may read it (R-A8).
		List<BarnCRM_Automation_Control__c> stored = [
			SELECT SetupOwnerId, Pause_All__c, Bypass__c
			FROM BarnCRM_Automation_Control__c
			WITH SYSTEM_MODE
			LIMIT :MAX_ROWS
		];
		Set<Id> owners = new Set<Id>();
		for (BarnCRM_Automation_Control__c control : stored) {
			owners.add(control.SetupOwnerId);
		}
		// The polymorphic SetupOwner does not carry a profile's name, so names are read here.
		Map<Id, String> names = new Map<Id, String>();
		for (Profile profile : [SELECT Id, Name FROM Profile WHERE Id IN :owners WITH USER_MODE]) {
			names.put(profile.Id, profile.Name);
		}
		for (User person : [SELECT Id, Name FROM User WHERE Id IN :owners WITH USER_MODE]) {
			names.put(person.Id, person.Name);
		}
		for (BarnCRM_Automation_Control__c control : stored) {
			String level = levelOf(control.SetupOwnerId);
			ControlRow shown = row(
				control.SetupOwnerId,
				level == LEVEL_ORGANIZATION
					? null
					: names.containsKey(control.SetupOwnerId)
							? names.get(control.SetupOwnerId)
							: String.valueOf(control.SetupOwnerId),
				level,
				control.Pause_All__c,
				control.Bypass__c
			);
			if (level == LEVEL_ORGANIZATION) {
				orgRow = shown;
			} else if (level == LEVEL_PROFILE) {
				profiles.add(shown);
			} else {
				users.add(shown);
			}
		}
		profiles.sort();
		users.sort();
		List<ControlRow> result = new List<ControlRow>{ orgRow };
		result.addAll(profiles);
		result.addAll(users);
		return result;
	}

	/** Saves both boxes for the org default, a profile or a user. Saving the same writes nothing. */
	public static void save(String ownerId, Boolean pauseAll, Boolean bypass) {
		requirePermission();
		Id owner = checkedOwner(ownerId);
		BarnCRM_Automation_Control__c stored = stored(owner);
		Boolean targetPause = pauseAll == true;
		Boolean targetBypass = bypass == true;
		if (
			stored != null &&
			stored.Pause_All__c == targetPause &&
			stored.Bypass__c == targetBypass
		) {
			return;
		}
		BarnCRM_Automation_Control__c changed = stored == null
			? new BarnCRM_Automation_Control__c(SetupOwnerId = owner)
			: new BarnCRM_Automation_Control__c(Id = stored.Id);
		changed.Pause_All__c = targetPause;
		changed.Bypass__c = targetBypass;
		AutomationSettingsWriter.saveControl(changed);
		SettingsService.logChange(logName(owner), describe(stored), describe(changed));
	}

	/** Adds a profile or user row with Bypass on, the usual reason to add one; one already there stays. */
	public static void add(String ownerId) {
		requirePermission();
		Id owner = checkedOwner(ownerId);
		if (owner == UserInfo.getOrganizationId() || stored(owner) != null) {
			return;
		}
		save(owner, false, true);
	}

	/** Deletes a profile or user row, so it follows the org default again. */
	public static void remove(String ownerId) {
		requirePermission();
		Id owner = checkedOwner(ownerId);
		if (owner == UserInfo.getOrganizationId()) {
			throw new AutomationControl.AutomationControlException(
				BarnHelp.text('Core', 'Core_AutomationControl_OrgRowStays')
			);
		}
		BarnCRM_Automation_Control__c stored = stored(owner);
		if (stored == null) {
			return;
		}
		AutomationSettingsWriter.deleteControl(stored.Id);
		SettingsService.logChange(logName(owner), describe(stored), null);
	}

	/** True when the org default has Pause All on. */
	public static Boolean pausedForEveryone() {
		return AutomationControl.isPausedForEveryone();
	}

	/** The profiles to add a row for, by name. */
	public static List<Option> profileOptions() {
		List<Option> options = new List<Option>();
		for (Profile profile : [
			SELECT Id, Name
			FROM Profile
			WITH USER_MODE
			ORDER BY Name
			LIMIT :MAX_ROWS
		]) {
			options.add(new Option(profile.Id, profile.Name));
		}
		return options;
	}

	// ------------------------------------------------------------------------ own flows

	/** True when the switch row is an org's own listed flow, which the page may remove. */
	public static Boolean isOwnFlow(Automation_Setting__c setting) {
		return setting != null &&
			setting.Automation_Name__c != null &&
			setting.Automation_Name__c.startsWith(FLOW_PREFIX) &&
			setting.Is_Package_Default__c != true &&
			setting.Always_Runs__c != true;
	}

	/**
	 * The org's own active flows not yet listed, by label (`listedNames` lower case). A flow
	 * list that cannot be read leaves the picker empty rather than failing the page.
	 */
	public static List<Option> flowOptions(Set<String> listedNames) {
		List<Option> options = new List<Option>();
		try {
			List<SObject> flows = Database.query(
				'SELECT ApiName, Label FROM FlowDefinitionView' +
					' WHERE IsActive = true AND NamespacePrefix = null' +
					' ORDER BY Label LIMIT ' +
					MAX_ROWS,
				AccessLevel.USER_MODE
			);
			for (SObject flow : flows) {
				String apiName = (String) flow.get('ApiName');
				if (!listedNames.contains((FLOW_PREFIX + apiName).toLowerCase())) {
					options.add(
						new Option(apiName, (String) flow.get('Label') + ' (' + apiName + ')')
					);
				}
			}
		} catch (Exception unreadable) {
			// Not logged: the page is read by a cacheable call, which may not write. An org whose
			// flows cannot be read simply has nothing to pick.
			options.clear();
		}
		return options;
	}

	/** Lists one of the org's own flows with a switch, on; listing it again changes nothing. */
	public static void addFlow(String apiName) {
		requirePermission();
		String name = apiName == null ? '' : apiName.trim();
		List<SObject> found = new List<SObject>();
		if (FLOW_API_NAME.matcher(name).matches()) {
			found = Database.queryWithBinds(
				'SELECT ApiName, Label, TriggerObjectOrEventLabel FROM FlowDefinitionView' +
				' WHERE ApiName = :apiName AND NamespacePrefix = null LIMIT 1',
				new Map<String, Object>{ 'apiName' => name },
				AccessLevel.USER_MODE
			);
		}
		if (found.isEmpty()) {
			throw new AutomationControl.AutomationControlException(
				BarnHelp.text('Core', 'Core_AutomationControl_FlowNotFound')
			);
		}
		String automationName = FLOW_PREFIX + (String) found[0].get('ApiName');
		if (!AutomationSettingSelector.selectByNames(new Set<String>{ automationName }).isEmpty()) {
			return;
		}
		AutomationControl.ensureSwitch(
			automationName,
			(String) found[0].get('Label'),
			(String) found[0].get('TriggerObjectOrEventLabel'),
			BarnHelp.text(
				'Core',
				'Core_AutomationControl_OwnFlowDescription',
				new List<Object>{ automationName }
			)
		);
		SettingsService.logChange('Automation: ' + automationName, null, 'Listed');
	}

	/** Takes one of the org's own flows off the list; BarnCRM's own rows cannot be removed. */
	public static void removeFlow(String automationName) {
		requirePermission();
		List<Automation_Setting__c> matches = String.isBlank(automationName)
			? new List<Automation_Setting__c>()
			: AutomationSettingSelector.selectByNames(new Set<String>{ automationName.trim() });
		if (matches.isEmpty() || !isOwnFlow(matches[0])) {
			throw new AutomationControl.AutomationControlException(
				BarnHelp.text('Core', 'Core_AutomationControl_NotOwnFlow')
			);
		}
		AutomationSettingsWriter.deleteSwitch(matches[0].Id);
		AutomationControl.clearCache();
		SettingsService.logChange('Automation: ' + matches[0].Automation_Name__c, 'Listed', null);
	}

	// ------------------------------------------------------------------------ catch up

	/** Queues the household catch-up, the household names recompute and the waiting rollups. */
	public static void catchUpNow() {
		requirePermission();
		AutomationControl.catchUp(true);
		SettingsService.logChange('Automation: Catch Up Now', null, 'Started');
	}

	// ---------------------------------------------------------------------------- helpers

	private static void requirePermission() {
		if (!AutomationControl.canManage()) {
			throw new AutomationControl.AutomationControlException(
				Label.Core_Automation_NoPermission
			);
		}
	}

	/** This org, or a Profile or User that exists; anything else is refused with a message. */
	private static Id checkedOwner(String ownerId) {
		Id owner;
		try {
			owner = String.isBlank(ownerId) ? null : Id.valueOf(ownerId.trim());
		} catch (Exception notAnId) {
			owner = null;
		}
		if (owner == UserInfo.getOrganizationId()) {
			return owner;
		}
		Boolean exists = false;
		if (owner != null && owner.getSObjectType() == Profile.SObjectType) {
			exists = ![SELECT Id FROM Profile WHERE Id = :owner WITH USER_MODE LIMIT 1].isEmpty();
		} else if (owner != null && owner.getSObjectType() == User.SObjectType) {
			exists = ![SELECT Id FROM User WHERE Id = :owner WITH USER_MODE LIMIT 1].isEmpty();
		}
		if (!exists) {
			throw new AutomationControl.AutomationControlException(
				BarnHelp.text('Core', 'Core_AutomationControl_OwnerNotFound')
			);
		}
		return owner;
	}

	/** The row stored for exactly this owner, or null; costs no query. */
	private static BarnCRM_Automation_Control__c stored(Id owner) {
		BarnCRM_Automation_Control__c found = owner == UserInfo.getOrganizationId()
			? BarnCRM_Automation_Control__c.getOrgDefaults()
			: BarnCRM_Automation_Control__c.getValues(owner);
		return found == null || found.Id == null ? null : found;
	}

	private static String levelOf(Id owner) {
		Schema.SObjectType kind = owner.getSObjectType();
		if (kind == Profile.SObjectType) {
			return LEVEL_PROFILE;
		}
		return kind == User.SObjectType ? LEVEL_USER : LEVEL_ORGANIZATION;
	}

	private static ControlRow row(
		Id owner,
		String name,
		String level,
		Boolean pauseAll,
		Boolean bypass
	) {
		ControlRow shown = new ControlRow();
		shown.ownerId = owner;
		shown.ownerName = name;
		shown.level = level;
		shown.pauseAll = pauseAll == true;
		shown.bypass = bypass == true;
		return shown;
	}

	/** "Automation Control: Profile Integration", as the change list shows it. */
	private static String logName(Id owner) {
		String level = levelOf(owner);
		String name = String.valueOf(owner);
		if (level == LEVEL_PROFILE) {
			name = [SELECT Name FROM Profile WHERE Id = :owner WITH USER_MODE LIMIT 1].Name;
		} else if (level == LEVEL_USER) {
			name = [SELECT Name FROM User WHERE Id = :owner WITH USER_MODE LIMIT 1].Name;
		} else {
			name = 'Whole Organization';
		}
		return 'Automation Control: ' + level + ' ' + name;
	}

	private static String describe(BarnCRM_Automation_Control__c row) {
		if (row == null) {
			return null;
		}
		return 'Pause All ' + (row.Pause_All__c == true) + ', Bypass ' + (row.Bypass__c == true);
	}
}
