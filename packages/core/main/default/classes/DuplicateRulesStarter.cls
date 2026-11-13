/**
 * Duplicate Rules Starter (C-61, D-156, ADR "Duplicate Rules Starter and report subscriptions
 * through the org connection"): creates or repairs BarnCRM's recommended matching and duplicate
 * rules for people and households through the org connection (ADR-0148). Only rules named
 * `BarnCRM_...` are ever written; the org's own rules are listed and left as they are.
 */
public with sharing class DuplicateRulesStarter {
	public static final String LOG_CONTEXT = 'Duplicate Rules Starter';
	public static final String NONE = 'None';
	public static final String CREATE = 'Create';
	public static final String REPAIR = 'Repair';
	public static final String WAIT = 'Wait';
	public static final String MISSING = 'Missing';
	public static final String ACTIVE = 'Active';
	public static final String INACTIVE = 'Inactive';
	private static final Set<String> BUSY = new Set<String>{ 'Activating', 'Deactivating' };
	private static final Set<String> UNFINISHED = new Set<String>{
		'Holding',
		'Queued',
		'Preparing',
		'Processing'
	};
	private static final Integer MAX_TRIES = 15;

	/** Set only by tests: matching rule status by developer name, as a test cannot create one. */
	@TestVisible
	private static Map<String, String> matchStatusOverride;

	/** One recommended set: a matching rule and the duplicate rule that uses it. */
	@TestVisible
	private class Recommended {
		String key;
		String objectName;
		String matchName;
		String ruleName;
		String booleanFilter;
		/** Field and matching method, in order: the filter's numbers refer to these. */
		List<String> items;
		String recordType;

		Recommended(String key, String objectName, String booleanFilter, List<String> items) {
			this.key = key;
			this.objectName = objectName;
			this.matchName = 'BarnCRM_' + key + '_Match';
			this.ruleName = 'BarnCRM_' + key + '_Duplicates';
			this.booleanFilter = booleanFilter;
			this.items = items;
		}
	}

	@TestVisible
	private static List<Recommended> recommended() {
		Recommended people = new Recommended(
			'People',
			'Contact',
			'(1 AND 2 AND 3) OR (1 AND 2 AND 4 AND 5) OR (1 AND 2 AND 6)',
			new List<String>{
				'FirstName:FirstName',
				'LastName:LastName',
				'Email:Exact',
				'MailingStreet:Street',
				'MailingPostalCode:Zip',
				'Phone:Phone'
			}
		);
		// The household evidence of ADR-0168: street with city or postal code, phone, or name
		// with postal code; only Household accounts, so organizations are never compared.
		Recommended households = new Recommended(
			'Household',
			'Account',
			'(1 AND (2 OR 3)) OR 4 OR (5 AND 3)',
			new List<String>{
				'BillingStreet:Street',
				'BillingCity:City',
				'BillingPostalCode:Zip',
				'Phone:Phone',
				'Name:CompanyName'
			}
		);
		Schema.RecordTypeInfo household = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
			.get(HouseholdService.RECORD_TYPE_HOUSEHOLD);
		households.recordType = household == null ? null : household.getName();
		return new List<Recommended>{ people, households };
	}

	// ------------------------------------------------------------------ the view

	public class StarterView {
		@AuraEnabled
		public Boolean canUse = false;
		@AuraEnabled
		public Boolean connected = false;
		@AuraEnabled
		public Boolean running = false;
		@AuraEnabled
		public String lastResult;
		@AuraEnabled
		public Boolean lastResultFailed = false;
		@AuraEnabled
		public List<SetView> sets = new List<SetView>();
	}

	public class SetView {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String heading;
		@AuraEnabled
		public String action;
		@AuraEnabled
		public String matchState;
		@AuraEnabled
		public String ruleState;
		/** The recommended rule in words. */
		@AuraEnabled
		public String summary;
		/** What Set Up would do, one line per step; empty when nothing is needed. */
		@AuraEnabled
		public List<String> steps = new List<String>();
		/** The org's own duplicate rules on the object, each left unchanged. */
		@AuraEnabled
		public List<String> orgRules = new List<String>();
	}

	@AuraEnabled
	public static StarterView getView() {
		try {
			requireSettings();
			return view();
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'DuplicateRulesStarter.getView', true);
		}
	}

	/** Queues the create or repair of the chosen sets ('People', 'Household'). */
	@AuraEnabled
	public static StarterView start(List<String> keys) {
		try {
			requireConnection();
			if (running()) {
				throw new StarterException(BarnHelp.text('Core', 'Core_DuplicateStarter_Running'));
			}
			Set<String> chosen = new Set<String>(keys == null ? new List<String>() : keys);
			List<String> needed = new List<String>();
			for (SetView each : view().sets) {
				if (chosen.contains(each.key) && each.action != NONE && each.action != WAIT) {
					needed.add(each.key);
				}
			}
			if (needed.isEmpty()) {
				throw new StarterException(
					BarnHelp.text('Core', 'Core_DuplicateStarter_NothingToDo')
				);
			}
			AsyncStarter.queue(new StarterJob(needed, 0), 'DuplicateRulesStarter');
			return view();
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'DuplicateRulesStarter.start', true);
		}
	}

	public class StarterException extends Exception {
	}

	private static void requireSettings() {
		if (!FeatureManagement.checkPermission('Manage_BarnCRM_Settings')) {
			throw new StarterException(BarnHelp.text('Core', 'Core_DuplicateStarter_NoPermission'));
		}
	}

	private static void requireConnection() {
		ImportNewFieldService.Connection connection = ImportNewFieldService.connection();
		if (!connection.canCreate) {
			throw new StarterException(
				BarnHelp.text('Core', 'Core_AutomationInventory_NoConnectionPermission')
			);
		}
		if (!connection.connected) {
			throw new StarterException(
				BarnHelp.text('Core', 'Core_DuplicateStarter_ConnectionNeeded')
			);
		}
	}

	@TestVisible
	private static StarterView view() {
		StarterView result = new StarterView();
		ImportNewFieldService.Connection connection = ImportNewFieldService.connection();
		result.canUse = connection.canCreate;
		result.connected = connection.connected;
		result.running = running();
		Error_Log__c last = DuplicateSelector.latestScanResult(LOG_CONTEXT);
		if (last != null) {
			result.lastResult = last.Message__c;
			result.lastResultFailed = last.Severity__c != ErrorLogger.SEVERITY_INFO;
		}
		Map<String, String> matchStatus = matchStatuses();
		Map<String, List<DuplicateRule>> rulesByObject = new Map<String, List<DuplicateRule>>();
		for (
			DuplicateRule rule : DuplicateSelector.rulesFor(new Set<String>{ 'Contact', 'Account' })
		) {
			if (!rulesByObject.containsKey(rule.SobjectType)) {
				rulesByObject.put(rule.SobjectType, new List<DuplicateRule>());
			}
			rulesByObject.get(rule.SobjectType).add(rule);
		}
		for (Recommended each : recommended()) {
			List<DuplicateRule> rules = rulesByObject.get(each.objectName);
			result.sets.add(
				setView(
					each,
					matchStatus.get(each.matchName),
					rules == null ? new List<DuplicateRule>() : rules
				)
			);
		}
		return result;
	}

	/** One set's state, the action it needs, and the steps that action takes, in words. */
	@TestVisible
	private static SetView setView(
		Recommended each,
		String matchStatus,
		List<DuplicateRule> rules
	) {
		SetView result = new SetView();
		result.key = each.key;
		result.heading = heading(each.key);
		result.summary = summary(each.key);
		result.matchState = matchStatus == null
			? MISSING
			: (matchStatus == ACTIVE || BUSY.contains(matchStatus) ? matchStatus : INACTIVE);
		result.ruleState = MISSING;
		for (DuplicateRule rule : rules) {
			if (rule.DeveloperName == each.ruleName) {
				result.ruleState = rule.IsActive == true ? ACTIVE : INACTIVE;
			} else {
				List<Object> label = new List<Object>{ rule.MasterLabel };
				result.orgRules.add(
					rule.IsActive == true
						? BarnHelp.text('Core', 'Core_DuplicateStarter_OrgRuleActive', label)
						: BarnHelp.text('Core', 'Core_DuplicateStarter_OrgRuleInactive', label)
				);
			}
		}
		if (BUSY.contains(result.matchState)) {
			result.action = WAIT;
		} else if (result.matchState == ACTIVE && result.ruleState == ACTIVE) {
			result.action = NONE;
		} else if (result.matchState == MISSING && result.ruleState == MISSING) {
			result.action = CREATE;
		} else {
			result.action = REPAIR;
		}
		if (each.objectName == 'Account' && each.recordType == null && result.action != NONE) {
			// No Household record type to limit the rule to: never compare organizations.
			result.action = WAIT;
			result.steps.add(BarnHelp.text('Core', 'Core_DuplicateStarter_NoHouseholdType'));
			return result;
		}
		if (result.action == CREATE || result.action == REPAIR) {
			List<Object> match = new List<Object>{ each.matchName, each.objectName };
			List<Object> rule = new List<Object>{ each.ruleName, each.objectName };
			if (result.matchState == MISSING) {
				result.steps.add(
					BarnHelp.text('Core', 'Core_DuplicateStarter_StepCreateMatch', match)
				);
			} else if (result.matchState != ACTIVE) {
				result.steps.add(
					BarnHelp.text('Core', 'Core_DuplicateStarter_StepRepairMatch', match)
				);
			}
			if (result.ruleState == MISSING) {
				result.steps.add(
					BarnHelp.text('Core', 'Core_DuplicateStarter_StepCreateRule', rule)
				);
			} else if (result.ruleState != ACTIVE) {
				result.steps.add(
					BarnHelp.text('Core', 'Core_DuplicateStarter_StepRepairRule', rule)
				);
			}
		}
		return result;
	}

	private static String heading(String key) {
		return key == 'People'
			? BarnHelp.text('Core', 'Core_DuplicateStarter_HeadingPeople')
			: BarnHelp.text('Core', 'Core_DuplicateStarter_HeadingHousehold');
	}

	private static String summary(String key) {
		return key == 'People'
			? BarnHelp.text('Core', 'Core_DuplicateStarter_SummaryPeople')
			: BarnHelp.text('Core', 'Core_DuplicateStarter_SummaryHousehold');
	}

	/** Status of BarnCRM's matching rules by developer name; a missing rule has no entry. */
	private static Map<String, String> matchStatuses() {
		if (matchStatusOverride != null) {
			return matchStatusOverride;
		}
		Set<String> names = new Set<String>();
		for (Recommended each : recommended()) {
			names.add(each.matchName);
		}
		Map<String, String> result = new Map<String, String>();
		for (MatchingRule rule : [
			SELECT DeveloperName, RuleStatus
			FROM MatchingRule
			WHERE DeveloperName IN :names
			WITH USER_MODE
		]) {
			result.put(rule.DeveloperName, rule.RuleStatus);
		}
		return result;
	}

	private static Boolean running() {
		return [
				SELECT COUNT()
				FROM AsyncApexJob
				WHERE
					JobType = 'Queueable'
					AND ApexClass.Name = 'DuplicateRulesStarter'
					AND Status IN :UNFINISHED
				WITH SYSTEM_MODE
			] > 0;
	}

	// ------------------------------------------------------------------ the job

	/**
	 * Try 0 writes the matching rules that are missing or not active. A matching rule activates
	 * on its own time, so later tries, a minute apart, write each duplicate rule once its
	 * matching rule is active. The last try logs one entry in words.
	 */
	public with sharing class StarterJob implements Queueable, Database.AllowsCallouts {
		private final List<String> keys;
		private final Integer attempt;
		private final List<String> done;
		private final List<String> failed;

		public StarterJob(List<String> keys, Integer attempt) {
			this(keys, attempt, new List<String>(), new List<String>());
		}

		private StarterJob(
			List<String> keys,
			Integer attempt,
			List<String> done,
			List<String> failed
		) {
			this.keys = keys;
			this.attempt = attempt;
			this.done = done;
			this.failed = failed;
		}

		public void execute(QueueableContext context) {
			List<String> waiting;
			try {
				waiting = attempt == 0 ? writeMatches() : writeRules();
			} catch (Exception e) {
				failed.add(e.getMessage());
				waiting = new List<String>();
			}
			if (!waiting.isEmpty() && attempt < MAX_TRIES) {
				StarterJob next = new StarterJob(waiting, attempt + 1, done, failed);
				if (!Test.isRunningTest()) {
					System.enqueueJob(next, 1);
				}
				return;
			}
			for (String key : waiting) {
				failed.add(
					BarnHelp.text(
						'Core',
						'Core_DuplicateStarter_StillActivating',
						new List<Object>{ heading(key) }
					)
				);
			}
			finish();
		}

		/** Writes the matching rules that need it; returns every key still to finish. */
		private List<String> writeMatches() {
			Map<String, String> status = matchStatuses();
			List<Recommended> toWrite = new List<Recommended>();
			for (Recommended each : chosen()) {
				String current = status.get(each.matchName);
				if (current != ACTIVE && !BUSY.contains(current)) {
					toWrite.add(each);
				}
			}
			Set<String> refused = new Set<String>();
			if (!toWrite.isEmpty()) {
				List<String> bodies = new List<String>();
				for (Recommended each : toWrite) {
					bodies.add(matchXml(each));
				}
				refused = record(OrgMetadataApi.upsertMetadata('MatchingRule', bodies), toWrite);
			}
			List<String> waiting = new List<String>();
			for (String key : keys) {
				if (!refused.contains(key)) {
					waiting.add(key);
				}
			}
			return waiting;
		}

		/** Writes each duplicate rule whose matching rule is active; returns the keys still waiting. */
		private List<String> writeRules() {
			Map<String, String> status = matchStatuses();
			Map<String, Boolean> activeRule = new Map<String, Boolean>();
			Map<String, Integer> countByObject = new Map<String, Integer>{
				'Contact' => 0,
				'Account' => 0
			};
			for (DuplicateRule rule : DuplicateSelector.rulesFor(countByObject.keySet())) {
				activeRule.put(rule.DeveloperName, rule.IsActive == true);
				countByObject.put(rule.SobjectType, countByObject.get(rule.SobjectType) + 1);
			}
			List<Recommended> ready = new List<Recommended>();
			List<String> waiting = new List<String>();
			for (Recommended each : chosen()) {
				String current = status.get(each.matchName);
				if (current == ACTIVE) {
					if (activeRule.get(each.ruleName) == true) {
						done.add(heading(each.key));
					} else {
						ready.add(each);
					}
				} else if (current == null || BUSY.contains(current) || current == INACTIVE) {
					waiting.add(each.key);
				} else {
					failed.add(
						BarnHelp.text(
							'Core',
							'Core_DuplicateStarter_MatchFailed',
							new List<Object>{ each.matchName, current }
						)
					);
				}
			}
			if (!ready.isEmpty()) {
				List<String> bodies = new List<String>();
				for (Recommended each : ready) {
					// An existing rule keeps the last place; a new one goes after the org's rules.
					Integer count = countByObject.get(each.objectName);
					bodies.add(
						ruleXml(each, activeRule.containsKey(each.ruleName) ? count : count + 1)
					);
				}
				Set<String> refused = record(
					OrgMetadataApi.upsertMetadata('DuplicateRule', bodies),
					ready
				);
				for (Recommended each : ready) {
					if (!refused.contains(each.key)) {
						done.add(heading(each.key));
					}
				}
			}
			return waiting;
		}

		private List<Recommended> chosen() {
			Set<String> wanted = new Set<String>(keys);
			List<Recommended> result = new List<Recommended>();
			for (Recommended each : recommended()) {
				if (wanted.contains(each.key)) {
					result.add(each);
				}
			}
			return result;
		}

		/** Notes each refusal in words; returns the refused sets' keys. */
		private Set<String> record(List<OrgMetadataApi.Result> results, List<Recommended> sent) {
			Set<String> refused = new Set<String>();
			for (Integer i = 0; i < sent.size(); i++) {
				OrgMetadataApi.Result result = i < results.size() ? results[i] : null;
				if (result == null || !result.success) {
					refused.add(sent[i].key);
					failed.add(
						BarnHelp.text(
							'Core',
							'Core_DuplicateStarter_Refused',
							new List<Object>{
								heading(sent[i].key),
								result == null ? '' : String.valueOf(result.message)
							}
						)
					);
				}
			}
			return refused;
		}

		private void finish() {
			String message = BarnHelp.text(
				'Core',
				'Core_DuplicateStarter_Result',
				new List<Object>{ done.isEmpty() ? '-' : String.join(done, ', ') }
			);
			if (!failed.isEmpty()) {
				message += ' ' + String.join(failed, ' ');
			}
			ErrorLogger.logMessage(
				message,
				LOG_CONTEXT,
				failed.isEmpty() ? ErrorLogger.SEVERITY_INFO : ErrorLogger.SEVERITY_ERROR
			);
		}
	}

	// ------------------------------------------------------------------ metadata

	/** The MatchingRule's elements in the WSDL's order, activated on save. */
	@TestVisible
	private static String matchXml(Recommended each) {
		String items = '';
		for (String item : each.items) {
			items += OrgMetadataApi.wrap(
				'matchingRuleItems',
				OrgMetadataApi.element('blankValueBehavior', 'NullNotAllowed') +
					OrgMetadataApi.element('fieldName', item.substringBefore(':')) +
					OrgMetadataApi.element('matchingMethod', item.substringAfter(':'))
			);
		}
		return OrgMetadataApi.element('fullName', each.objectName + '.' + each.matchName) +
			OrgMetadataApi.element('booleanFilter', each.booleanFilter) +
			OrgMetadataApi.element('description', summary(each.key)) +
			OrgMetadataApi.element('label', each.matchName.replace('_', ' ')) +
			items +
			OrgMetadataApi.element('ruleStatus', ACTIVE);
	}

	/** The DuplicateRule's elements in the WSDL's order: allow the save, alert and report. */
	@TestVisible
	private static String ruleXml(Recommended each, Integer sortOrder) {
		String filter = '';
		if (each.recordType != null) {
			filter = OrgMetadataApi.wrap(
				'duplicateRuleFilter',
				OrgMetadataApi.wrap(
					'duplicateRuleFilterItems',
					OrgMetadataApi.element('field', 'RecordType') +
						OrgMetadataApi.element('operation', 'equals') +
						OrgMetadataApi.element('value', each.recordType) +
						OrgMetadataApi.element('sortOrder', 1) +
						OrgMetadataApi.element('table', each.objectName)
				)
			);
		}
		return OrgMetadataApi.element('fullName', each.objectName + '.' + each.ruleName) +
			OrgMetadataApi.element('actionOnInsert', 'Allow') +
			OrgMetadataApi.element('actionOnUpdate', 'Allow') +
			OrgMetadataApi.element(
				'alertText',
				BarnHelp.text('Core', 'Core_DuplicateStarter_AlertText')
			) +
			OrgMetadataApi.element('description', summary(each.key)) +
			filter +
			OrgMetadataApi.wrap(
				'duplicateRuleMatchRules',
				OrgMetadataApi.element('matchRuleSObjectType', each.objectName) +
				OrgMetadataApi.element('matchingRule', each.matchName)
			) +
			OrgMetadataApi.element('isActive', true) +
			OrgMetadataApi.element('masterLabel', each.ruleName.replace('_', ' ')) +
			OrgMetadataApi.element('operationsOnInsert', 'Alert') +
			OrgMetadataApi.element('operationsOnInsert', 'Report') +
			OrgMetadataApi.element('operationsOnUpdate', 'Alert') +
			OrgMetadataApi.element('operationsOnUpdate', 'Report') +
			OrgMetadataApi.element('securityOption', 'EnforceSharingRules') +
			OrgMetadataApi.element('sortOrder', sortOrder);
	}
}
