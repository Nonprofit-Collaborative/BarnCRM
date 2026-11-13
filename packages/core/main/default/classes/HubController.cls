/**
 * The BarnCRM home page's Apex surface: how far setup has got, whether automation is
 * paused, and how many errors nobody has looked at.
 *
 * The steps themselves belong to the Setup Assistant, which loads them itself, so the home
 * page asks only for the two counters it uses to decide whether the assistant is still the
 * main panel.
 *
 * Everything except the checklist is optional: automation control and the Error Log belong
 * to other features, so each call is wrapped and a failure costs the page a number, not the
 * page.
 */
public with sharing class HubController {
	private static final String ERROR_CONTEXT = 'BarnCRM home';
	/** A quick link target that opens an object's new record form (`Enrollment__c.new`). */
	private static final String NEW_RECORD = '.new';

	/**
	 * The tile counts this many new errors and then says "more", so a flooded Error Log costs
	 * the home page at most this many query rows plus one. A test lowers it.
	 */
	@TestVisible
	private static Integer errorCountCap = 999;

	public class HomeModel {
		@AuraEnabled
		public Boolean canEdit;
		@AuraEnabled
		public Boolean automationPaused;
		@AuraEnabled
		public Integer newErrorCount;
		/** True when there are more new errors than `newErrorCount`, the most the tile counts. */
		@AuraEnabled
		public Boolean newErrorCountCapped;
		/**
		 * Problems the install and its upgrades logged that nobody has looked at, capped like
		 * the error count; null for someone who cannot read the Error Log.
		 */
		@AuraEnabled
		public Integer installProblemCount;
		@AuraEnabled
		public Integer stepsCompleted;
		@AuraEnabled
		public Integer stepsTotal;
		/** True when the Rollup Builder module is installed; the rollups tile shows only then. */
		@AuraEnabled
		public Boolean rollupsInstalled;
		@AuraEnabled
		public Datetime rollupsLastCalculated;
		@AuraEnabled
		public Boolean rollupsStale;
		@AuraEnabled
		public Datetime seasonalAddressLastRun;
		@AuraEnabled
		public String seasonalAddressLastRunSummary;
		@AuraEnabled
		public Boolean seasonalAddressScheduled;
		@AuraEnabled
		public Boolean seasonalAddressStale;
		@AuraEnabled
		public List<RecurringSource> recurringSources;
		/** True when this person may create a household, so New household is shown. */
		@AuraEnabled
		public Boolean canCreateHousehold;
		/** True when this person may create a contact, so New Person is shown. */
		@AuraEnabled
		public Boolean canCreatePerson;
		/** True when this person may run an import, so Quick Links offers Import a File. */
		@AuraEnabled
		public Boolean canImport;
		/**
		 * The links installed and turned-on modules add to Quick Links, from their catalog rows
		 * (`Quick_Links__c`, D-200 R7), never from module code, so Core depends on no module.
		 */
		@AuraEnabled
		public List<QuickLink> quickLinks;
	}

	/** One module quick link: a tab, or an object's new record form, with its words. */
	public class QuickLink {
		/** The tab API name as written in the catalog; the page qualifies it. */
		@AuraEnabled
		public String tab;
		/** The object whose new record form the link opens, qualified for this org. */
		@AuraEnabled
		public String objectApiName;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String line;
	}

	/** One file that arrives regularly, and when it was last imported (R-IT6). */
	public class RecurringSource {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String sourceName;
		@AuraEnabled
		public String templateName;
		@AuraEnabled
		public Date lastImportDate;
	}

	@AuraEnabled(cacheable=true)
	public static HomeModel getHomeModel() {
		try {
			return buildModel();
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
			throw UserErrors.message(BarnHelp.text('Core', 'Core_HubHome_LoadErrorMessage'));
		}
	}

	/**
	 * New household: creates an empty household and answers its Id, for the page to open.
	 * Staff are never given the Household record type (ADR-0141), so the standard
	 * New form cannot create one; the household is created by HouseholdWriter, which checks
	 * the person's access to accounts first.
	 */
	@AuraEnabled
	public static Id createHousehold() {
		try {
			return HouseholdService.createEmptyHousehold();
		} catch (HouseholdException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
			throw UserErrors.message(
				String.format(
					BarnHelp.text('Core', 'Core_HubHomeActions_NewHouseholdFailed'),
					new List<Object>{ e.getMessage() }
				)
			);
		}
	}

	private static HomeModel buildModel() {
		HomeModel model = new HomeModel();
		model.canCreateHousehold = HouseholdWriter.canCreateHouseholds();
		model.canCreatePerson = Schema.SObjectType.Contact.isCreateable();
		model.canImport =
			ModuleDetectionService.isImportPresent() &&
			Schema.SObjectType.Import_Batch__c.isCreateable();
		model.quickLinks = readQuickLinks();
		model.canEdit = BarnCRMPermissions.canManageSettings();
		model.automationPaused = readAutomationPaused();
		model.recurringSources = readRecurringSources();
		if (model.canEdit) {
			List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
			model.stepsTotal = steps.size();
			model.stepsCompleted = SetupAssistantService.countCompleted(steps);
			readErrorCounts(model);
			readRollupFreshness(model);
			readSeasonalAddressRun(model);
		} else {
			// The checklist and the administrator tiles are hidden from staff (the page's
			// visibility rules, barncrm-app.md), so their numbers are not worked out (ADMIN-10).
			model.stepsTotal = 0;
			model.stepsCompleted = 0;
			model.newErrorCount = 0;
			model.newErrorCountCapped = false;
			model.rollupsInstalled = false;
			model.rollupsStale = false;
			model.seasonalAddressScheduled = false;
			model.seasonalAddressStale = false;
		}
		return model;
	}

	/**
	 * Each installed, turned-on module's quick links, in catalog order. An entry is
	 * `Target:Label:Line`; a target ending `.new` opens that object's new record form and is
	 * offered only to someone who can create the object. A failure costs the page its module
	 * links, never the page.
	 */
	@TestVisible
	private static List<QuickLink> readQuickLinks() {
		List<QuickLink> links = new List<QuickLink>();
		try {
			Set<String> off = ModuleManagerService.turnedOff();
			for (BarnCRM_Module__mdt row : ModuleDetectionService.installedCatalog()) {
				if (off.contains(row.DeveloperName.toLowerCase())) {
					continue;
				}
				for (
					String entry : (row.Quick_Links__c == null ? '' : row.Quick_Links__c).split(';')
				) {
					QuickLink link = quickLink(entry);
					if (link != null) {
						links.add(link);
					}
				}
			}
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
		}
		return links;
	}

	/** Stands in for the tabs the running user can see, by name as written or qualified. */
	@TestVisible
	private static Set<String> visibleTabsOverride;

	/** The tabs the running user can see, lower case, read once per transaction. */
	private static Set<String> visibleTabs;

	/**
	 * Whether the running user can see the tab: it is in one of the apps Salesforce describes
	 * for them (Schema.describeTabs), under its name as written or with this org's prefix.
	 */
	private static Boolean canSeeTab(String tab) {
		if (visibleTabs == null) {
			visibleTabs = new Set<String>();
			if (visibleTabsOverride != null) {
				for (String name : visibleTabsOverride) {
					visibleTabs.add(name.toLowerCase());
				}
			} else {
				for (Schema.DescribeTabSetResult app : Schema.describeTabs()) {
					for (Schema.DescribeTabResult described : app.getTabs()) {
						if (described.getName() != null) {
							visibleTabs.add(described.getName().toLowerCase());
						}
					}
				}
			}
		}
		return visibleTabs.contains(tab.toLowerCase()) ||
			visibleTabs.contains(NamespaceUtil.qualify(tab).toLowerCase());
	}

	/**
	 * One catalog entry as a link, or null when it is blank, its object cannot be created, or
	 * its tab is one the running user cannot see.
	 */
	@TestVisible
	private static QuickLink quickLink(String entry) {
		List<String> parts = entry.split(':', 3);
		if (String.isBlank(entry) || parts.size() < 2 || String.isBlank(parts[0])) {
			return null;
		}
		QuickLink link = new QuickLink();
		String target = parts[0].trim();
		link.label = parts[1].trim();
		link.line = parts.size() > 2 ? parts[2].trim() : null;
		if (target.endsWith(NEW_RECORD)) {
			Schema.DescribeSObjectResult described = NamespaceUtil.describe(
				target.removeEnd(NEW_RECORD)
			);
			if (described == null || !described.isCreateable()) {
				return null;
			}
			link.objectApiName = described.getName();
		} else {
			if (!canSeeTab(target)) {
				return null;
			}
			link.tab = target;
		}
		return link;
	}

	private static Boolean readAutomationPaused() {
		try {
			return AutomationControl.isPaused();
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
			return false;
		}
	}

	/**
	 * "Rollups last completed", and whether the nightly run is overdue (plan Section 4.10).
	 * Optional like the rest: an org where the rollup engine cannot answer loses a tile, not the
	 * page. Without the Rollup Builder module there is no tile (ADR-0125).
	 */
	private static void readRollupFreshness(HomeModel model) {
		model.rollupsInstalled = false;
		model.rollupsStale = false;
		try {
			RollupEngineExtension engine = RollupEngineExtensions.find();
			if (engine == null) {
				return;
			}
			model.rollupsInstalled = true;
			failIfTestSaysSo(PART_ROLLUPS);
			model.rollupsLastCalculated = engine.lastCalculated();
			model.rollupsStale = engine.isStale();
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
			model.rollupsStale = false;
		}
	}

	/**
	 * "Seasonal addresses last swapped", and whether the nightly job has missed its window
	 * (C-18, R-AD8). A nightly job whose last run nobody can see is a job nobody trusts, so this
	 * belongs on the page an administrator opens every morning rather than only on the settings
	 * page they open twice a year.
	 *
	 * Optional like the rest: an org that cannot answer loses a tile, not the page.
	 */
	private static void readSeasonalAddressRun(HomeModel model) {
		try {
			failIfTestSaysSo(PART_SEASONAL);
			model.seasonalAddressLastRun = SeasonalAddressService.lastRun();
			model.seasonalAddressLastRunSummary = SeasonalAddressService.lastRunSummary();
			model.seasonalAddressScheduled = SeasonalAddressScheduler.isScheduled();
			model.seasonalAddressStale = SeasonalAddressService.isStale(
				model.seasonalAddressScheduled
			);
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
			model.seasonalAddressScheduled = false;
			model.seasonalAddressStale = false;
		}
	}

	/**
	 * The files that arrive regularly and when each was last imported, oldest first, so the
	 * one nobody has loaded this month is at the top (R-IT6). Optional like the rest: a user
	 * who cannot read import templates loses the list, not the page.
	 */
	private static List<RecurringSource> readRecurringSources() {
		List<RecurringSource> result = new List<RecurringSource>();
		if (!Schema.SObjectType.Import_Template__c.isAccessible()) {
			return result;
		}
		try {
			for (Import_Template__c template : ImportTemplateService.recurringSources()) {
				RecurringSource source = new RecurringSource();
				source.id = template.Id;
				source.sourceName = template.Source_Name__c;
				source.templateName = template.Name;
				source.lastImportDate = template.Last_Import_Date__c;
				result.add(source);
			}
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
		}
		return result;
	}

	/**
	 * The new error count and the install problem count, both capped (ADMIN-8). The Error Log
	 * ships in Core, so the static, user mode count in ErrorLogCountSelector is enough: it
	 * answers zero for someone who cannot read the log.
	 */
	private static void readErrorCounts(HomeModel model) {
		try {
			Integer newErrors = ErrorLogCountSelector.countNewUpTo(errorCountCap);
			model.newErrorCountCapped = newErrors > errorCountCap;
			model.newErrorCount = Math.min(newErrors, errorCountCap);
			Integer installProblems = CorePostInstall.countInstallProblemsUpTo(errorCountCap);
			model.installProblemCount = installProblems == null
				? null
				: Math.min(installProblems, errorCountCap);
		} catch (Exception e) {
			ErrorLogger.log(e, ERROR_CONTEXT);
			model.newErrorCount = 0;
			model.newErrorCountCapped = false;
		}
	}

	/** Parts of the page a test can make fail, to see the page degrade instead (ADMIN-13). */
	@TestVisible
	private static final String PART_ROLLUPS = 'rollups';
	@TestVisible
	private static final String PART_SEASONAL = 'seasonal';
	@TestVisible
	private static Set<String> failingPartsForTest = new Set<String>();

	private static void failIfTestSaysSo(String part) {
		if (Test.isRunningTest() && failingPartsForTest.contains(part)) {
			throw new HubPartException('A test made this part fail: ' + part);
		}
	}

	private class HubPartException extends Exception {
	}
}
