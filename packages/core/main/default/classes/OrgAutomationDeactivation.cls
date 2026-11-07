/**
 * Deactivate Org Flows and Validation Rules, and Restore (canonical model Section 10A, R-AS4 to
 * R-AS8, ADR-0174, D-184). Queued jobs, each its own transaction, through the org connection:
 *
 * 1. Snapshot: reads every chosen item's current state from the Tooling API and saves it before
 *    anything changes; an item that is not the org's own, or not active, is left Unchanged.
 * 2. Apply: deactivates the saved items a few per job, chained, saving each result.
 * 3. Restore: puts back exactly the snapshot for each item that changed.
 *
 * Every callout in a job comes before its one save, as Apex requires.
 */
public with sharing class OrgAutomationDeactivation implements Queueable, Database.AllowsCallouts {
	public static final String KIND = 'Deactivation';
	public static final String MODE_SNAPSHOT = 'Snapshot';
	public static final String MODE_APPLY = 'Apply';
	public static final String MODE_RESTORE = 'Restore';

	public static final String RESULT_PENDING = 'Pending';
	public static final String RESULT_CHANGED = 'Changed';
	public static final String RESULT_UNCHANGED = 'Unchanged';
	public static final String RESULT_FAILED = 'Failed';

	public static final String KIND_FLOW = 'Flow';
	public static final String KIND_VALIDATION = 'ValidationRule';

	/** The most items one run takes, so the snapshot fits its field. */
	public static final Integer MAX_ITEMS = 200;
	/** Items changed per job: two callouts each at most, inside the callout time limit. */
	@TestVisible
	private static final Integer ITEMS_PER_JOB = 20;
	private static final String LOG_CONTEXT = 'Deactivate org automation';

	/** One flow or validation rule: what it was, and what happened to it. */
	public class Item {
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public String recordId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public Boolean wasActive;
		/** A flow's active version number before; null for a rule. */
		@AuraEnabled
		public Integer activeVersion;
		@AuraEnabled
		public String result;
		@AuraEnabled
		public String message;
		@AuraEnabled
		public String restoreResult;
		@AuraEnabled
		public String restoreMessage;
	}

	public class DeactivationException extends Exception {
	}

	private final Id snapshotId;
	private final String mode;

	public OrgAutomationDeactivation(Id snapshotId, String mode) {
		this.snapshotId = snapshotId;
		this.mode = mode;
	}

	// -------------------------------------------------------------------------- starting

	/** Saves a Running snapshot of the chosen items and queues the snapshot job. */
	public static Id start(List<Item> chosen) {
		if (chosen == null || chosen.isEmpty() || chosen.size() > MAX_ITEMS) {
			throw new DeactivationException(
				BarnHelp.text('Core', 'Core_AutomationDeactivate_ChooseItems')
			);
		}
		refuseWhileRunning();
		List<Item> items = new List<Item>();
		for (Item each : chosen) {
			Item item = new Item();
			// A process builder is a flow.
			item.kind = each.kind == OrgAutomationInventory.KIND_PROCESS ? KIND_FLOW : each.kind;
			item.recordId = each.recordId;
			item.name = each.name;
			item.objectName = each.objectName;
			if (!isValidItem(item)) {
				throw new DeactivationException(
					BarnHelp.text('Core', 'Core_AutomationDeactivate_ChooseItems')
				);
			}
			items.add(item);
		}
		Automation_Snapshot__c snapshot = new Automation_Snapshot__c(
			Kind__c = KIND,
			Status__c = OrgAutomationScan.STATUS_RUNNING,
			Items__c = JSON.serialize(items)
		);
		insert as user snapshot;
		System.enqueueJob(new OrgAutomationDeactivation(snapshot.Id, MODE_SNAPSHOT));
		return snapshot.Id;
	}

	/** Marks the snapshot Restoring and queues the restore job. */
	public static Id restore(Id snapshotId) {
		refuseWhileRunning();
		Automation_Snapshot__c snapshot = load(snapshotId);
		if (
			snapshot == null ||
			snapshot.Kind__c != KIND ||
			(snapshot.Status__c != 'Done' &&
			snapshot.Status__c != 'Partial')
		) {
			throw new DeactivationException(
				BarnHelp.text('Core', 'Core_AutomationDeactivate_CannotRestore')
			);
		}
		snapshot.Status__c = 'Restoring';
		update as user snapshot;
		System.enqueueJob(new OrgAutomationDeactivation(snapshot.Id, MODE_RESTORE));
		return snapshot.Id;
	}

	/** A flow definition (300) or validation rule (03d) Id of the kind named. */
	private static Boolean isValidItem(Item item) {
		String prefix = item.kind == KIND_FLOW
			? '300'
			: (item.kind == KIND_VALIDATION ? '03d' : null);
		return prefix != null &&
			item.recordId != null &&
			Pattern.matches('[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?', item.recordId) &&
			item.recordId.startsWith(prefix);
	}

	private static void refuseWhileRunning() {
		Integer running = [
			SELECT COUNT()
			FROM Automation_Snapshot__c
			WHERE Kind__c = :KIND AND Status__c IN ('Running', 'Restoring')
			WITH USER_MODE
		];
		if (running > 0) {
			throw new DeactivationException(
				BarnHelp.text('Core', 'Core_AutomationDeactivate_AlreadyRunning')
			);
		}
	}

	// -------------------------------------------------------------------------- the jobs

	public void execute(QueueableContext context) {
		Automation_Snapshot__c snapshot = load(snapshotId);
		List<Item> items = (List<Item>) JSON.deserialize(snapshot.Items__c, List<Item>.class);
		try {
			if (mode == MODE_SNAPSHOT) {
				readStates(items);
			} else {
				change(items, mode == MODE_RESTORE);
			}
		} catch (Exception e) {
			// A refused connection fails every item still waiting, in words.
			String reason = String.format(
				BarnHelp.text('Core', 'Core_AutomationDeactivate_ConnectionFailed'),
				new List<Object>{ e.getMessage() }
			);
			failWaiting(items, mode == MODE_RESTORE, reason);
			ErrorLogger.logWithMessage(e, LOG_CONTEXT, reason);
		}
		snapshot.Items__c = JSON.serialize(items);
		Boolean more = hasWaiting(items, mode == MODE_RESTORE);
		if (!more) {
			snapshot.Status__c = finalStatus(items, mode == MODE_RESTORE);
			if (mode == MODE_RESTORE) {
				snapshot.Restored_At__c = System.now();
			}
		}
		update as user snapshot;
		// A test cannot chain a queued job: it runs each job itself.
		if (more && !Test.isRunningTest()) {
			System.enqueueJob(
				new OrgAutomationDeactivation(
					snapshotId,
					mode == MODE_RESTORE ? MODE_RESTORE : MODE_APPLY
				)
			);
		}
	}

	/** Snapshot: each item's current state from the Tooling API; only the org's own active ones wait. */
	@TestVisible
	private static void readStates(List<Item> items) {
		Set<String> flowIds = new Set<String>();
		Set<String> ruleIds = new Set<String>();
		for (Item item : items) {
			(item.kind == KIND_FLOW ? flowIds : ruleIds).add(item.recordId);
		}
		Map<String, Map<String, Object>> found = new Map<String, Map<String, Object>>();
		if (!flowIds.isEmpty()) {
			for (
				Object each : OrgToolingApi.query(
					'SELECT Id, DeveloperName, NamespacePrefix, ActiveVersion.VersionNumber' +
						' FROM FlowDefinition WHERE Id IN (' +
						OrgToolingApi.quoted(flowIds) +
						')'
				)
			) {
				Map<String, Object> row = (Map<String, Object>) each;
				found.put(((String) row.get('Id')).left(15), row);
			}
		}
		if (!ruleIds.isEmpty()) {
			for (
				Object each : OrgToolingApi.query(
					'SELECT Id, ValidationName, Active, NamespacePrefix FROM ValidationRule' +
						' WHERE Id IN (' +
						OrgToolingApi.quoted(ruleIds) +
						')'
				)
			) {
				Map<String, Object> row = (Map<String, Object>) each;
				found.put(((String) row.get('Id')).left(15), row);
			}
		}
		for (Item item : items) {
			Map<String, Object> row = found.get(item.recordId.left(15));
			String refusal = refusal(item, row);
			if (refusal != null) {
				item.result = RESULT_UNCHANGED;
				item.message = refusal;
				continue;
			}
			item.wasActive = true;
			item.result = RESULT_PENDING;
		}
	}

	/** Why an item is left alone, or null when it is the org's own and active. */
	@TestVisible
	private static String refusal(Item item, Map<String, Object> row) {
		if (row == null) {
			return BarnHelp.text('Core', 'Core_AutomationDeactivate_NotFound');
		}
		Boolean barnFlow =
			item.kind == KIND_FLOW &&
			OrgAutomationInventory.BARN_FLOWS.contains((String) row.get('DeveloperName'));
		if (String.isNotBlank((String) row.get('NamespacePrefix')) || barnFlow) {
			return BarnHelp.text('Core', 'Core_AutomationDeactivate_NotOwn');
		}
		if (item.kind == KIND_FLOW) {
			Map<String, Object> active = (Map<String, Object>) row.get('ActiveVersion');
			if (active == null || active.get('VersionNumber') == null) {
				return BarnHelp.text('Core', 'Core_AutomationDeactivate_AlreadyInactive');
			}
			item.activeVersion = Integer.valueOf(active.get('VersionNumber'));
		} else if (row.get('Active') != true) {
			return BarnHelp.text('Core', 'Core_AutomationDeactivate_AlreadyInactive');
		}
		return null;
	}

	/** Apply or restore: the next ITEMS_PER_JOB waiting items, each result saved. */
	@TestVisible
	private static void change(List<Item> items, Boolean restoring) {
		Integer done = 0;
		for (Item item : items) {
			if (done >= ITEMS_PER_JOB) {
				break;
			}
			if (!isWaiting(item, restoring)) {
				continue;
			}
			done++;
			try {
				if (item.kind == KIND_FLOW) {
					OrgToolingApi.updateMetadata(
						'FlowDefinition',
						item.recordId,
						new Map<String, Object>{
							'activeVersionNumber' => restoring ? item.activeVersion : 0
						}
					);
				} else {
					Map<String, Object> metadata = (Map<String, Object>) OrgToolingApi.read(
							'ValidationRule',
							item.recordId
						)
						.get('Metadata');
					metadata.put('active', restoring ? item.wasActive == true : false);
					OrgToolingApi.updateMetadata('ValidationRule', item.recordId, metadata);
				}
				setResult(item, restoring, RESULT_CHANGED, null);
			} catch (Exception e) {
				setResult(item, restoring, RESULT_FAILED, e.getMessage());
			}
		}
	}

	private static Boolean isWaiting(Item item, Boolean restoring) {
		return restoring
			? item.result == RESULT_CHANGED && item.restoreResult == null
			: item.result == RESULT_PENDING;
	}

	private static Boolean hasWaiting(List<Item> items, Boolean restoring) {
		for (Item item : items) {
			if (isWaiting(item, restoring)) {
				return true;
			}
		}
		return false;
	}

	private static void setResult(Item item, Boolean restoring, String result, String message) {
		if (restoring) {
			item.restoreResult = result;
			item.restoreMessage = message;
		} else {
			item.result = result;
			item.message = message;
		}
	}

	private static void failWaiting(List<Item> items, Boolean restoring, String reason) {
		for (Item item : items) {
			if (isWaiting(item, restoring) || (!restoring && item.result == null)) {
				setResult(item, restoring, RESULT_FAILED, reason);
			}
		}
	}

	/**
	 * Done when every item that could change did, Partial when some did, Failed when none did.
	 * A restore ends Restored, whatever each item's result (each is shown).
	 */
	@TestVisible
	private static String finalStatus(List<Item> items, Boolean restoring) {
		if (restoring) {
			return 'Restored';
		}
		Integer changed = 0;
		Integer failed = 0;
		for (Item item : items) {
			if (item.result == RESULT_CHANGED) {
				changed++;
			} else if (item.result == RESULT_FAILED) {
				failed++;
			}
		}
		if (failed == 0 && changed > 0) {
			return 'Done';
		}
		return changed > 0 ? 'Partial' : OrgAutomationScan.STATUS_FAILED;
	}

	// -------------------------------------------------------------------------- reading

	private static Automation_Snapshot__c load(Id snapshotId) {
		List<Automation_Snapshot__c> found = [
			SELECT Id, Kind__c, Status__c, Items__c
			FROM Automation_Snapshot__c
			WHERE Id = :snapshotId
			WITH USER_MODE
			LIMIT 1
		];
		return found.isEmpty() ? null : found[0];
	}

	/** The newest deactivation snapshots, for the page. */
	public static List<OrgAutomationInventory.Snapshot> recent() {
		List<OrgAutomationInventory.Snapshot> recent = new List<OrgAutomationInventory.Snapshot>();
		for (Automation_Snapshot__c each : [
			SELECT Id, Name, Status__c, Items__c, Restored_At__c, CreatedDate, CreatedBy.Name
			FROM Automation_Snapshot__c
			WHERE Kind__c = :KIND
			WITH USER_MODE
			ORDER BY CreatedDate DESC
			LIMIT 20
		]) {
			OrgAutomationInventory.Snapshot snapshot = new OrgAutomationInventory.Snapshot();
			snapshot.id = each.Id;
			snapshot.name = each.Name;
			snapshot.status = each.Status__c;
			snapshot.createdAt = each.CreatedDate;
			snapshot.createdBy = each.CreatedBy?.Name;
			snapshot.restoredAt = each.Restored_At__c;
			if (String.isNotBlank(each.Items__c)) {
				snapshot.items = (List<Item>) JSON.deserialize(each.Items__c, List<Item>.class);
			}
			recent.add(snapshot);
		}
		return recent;
	}
}
