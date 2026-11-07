/**
 * The scan of the Automation tab (canonical model Section 10A, R-AS2 and R-AS3, ADR-NEXT): a
 * queued job reads through the org connection what user-mode SOQL cannot, the validation rules,
 * the workflow rules and what refers to Check BarnCRM Automation or the BarnCRM Automation
 * Control fields, and saves it as the one Scan snapshot the inventory adds to its rows.
 */
public with sharing class OrgAutomationScan implements Queueable, Database.AllowsCallouts {
	public static final String KIND_SCAN = 'Scan';
	public static final String STATUS_RUNNING = 'Running';
	public static final String STATUS_DONE = 'Done';
	public static final String STATUS_FAILED = 'Failed';
	private static final String LOG_CONTEXT = 'Automation inventory scan';
	@TestVisible
	private static final Integer MAX_ITEMS_LENGTH = 130000;

	/** What a scan read. Plain values, saved as JSON. */
	public class Found {
		public List<Rule> rules = new List<Rule>();
		/** Ids and names of the flows, triggers and rules that check the setting. */
		public Set<String> covered = new Set<String>();
		public Boolean truncated = false;
	}

	/** One validation or workflow rule. */
	public class Rule {
		public String kind;
		public String recordId;
		public String name;
		public String objectName;
		public Boolean active;
		public String namespace;
	}

	private final Id snapshotId;

	public OrgAutomationScan(Id snapshotId) {
		this.snapshotId = snapshotId;
	}

	/** Saves a Running scan and queues the job; returns the snapshot's Id. */
	public static Id start() {
		Automation_Snapshot__c snapshot = new Automation_Snapshot__c(
			Kind__c = KIND_SCAN,
			Status__c = STATUS_RUNNING
		);
		insert as user snapshot;
		System.enqueueJob(new OrgAutomationScan(snapshot.Id));
		return snapshot.Id;
	}

	public void execute(QueueableContext context) {
		Automation_Snapshot__c snapshot = new Automation_Snapshot__c(Id = snapshotId);
		try {
			Found found = read();
			String items = JSON.serialize(found);
			// Long Text Area holds 131,072 characters: rules past that are left out, and said so.
			while (items.length() > MAX_ITEMS_LENGTH && !found.rules.isEmpty()) {
				found.rules.remove(found.rules.size() - 1);
				found.truncated = true;
				items = JSON.serialize(found);
			}
			snapshot.Items__c = items;
			snapshot.Status__c = STATUS_DONE;
		} catch (Exception e) {
			snapshot.Status__c = STATUS_FAILED;
			snapshot.Message__c = String.format(
				BarnHelp.text('Core', 'Core_AutomationInventory_ScanFailed'),
				new List<Object>{ e.getMessage() }
			);
			ErrorLogger.logWithMessage(e, LOG_CONTEXT, snapshot.Message__c);
		}
		update as user snapshot;
		if (snapshot.Status__c == STATUS_DONE) {
			delete as user [
				SELECT Id
				FROM Automation_Snapshot__c
				WHERE Kind__c = :KIND_SCAN AND Id != :snapshotId
				WITH USER_MODE
				LIMIT 50
			];
		}
	}

	/** Every callout first, then the one SOQL query that names custom objects. */
	@TestVisible
	private static Found read() {
		Found found = new Found();
		Set<String> referenced = referencedIds();
		// The setting's fields: a formula or flow that reads `$Setup` refers to them.
		for (
			Object each : OrgToolingApi.query(
				'SELECT Id FROM CustomField WHERE TableEnumOrId IN (' + quoted(referenced) + ')'
			)
		) {
			referenced.add((String) ((Map<String, Object>) each).get('Id'));
		}
		List<Object> rules = OrgToolingApi.query(
			'SELECT Id, ValidationName, Active, NamespacePrefix, EntityDefinitionId' +
			' FROM ValidationRule LIMIT 2000'
		);
		List<Object> workflows = OrgToolingApi.query(
			'SELECT Id, Name, TableEnumOrId, NamespacePrefix FROM WorkflowRule LIMIT 2000'
		);
		List<Object> refs = OrgToolingApi.query(
			'SELECT MetadataComponentId, MetadataComponentName, RefMetadataComponentId' +
				' FROM MetadataComponentDependency WHERE RefMetadataComponentId IN (' +
				quoted(referenced) +
				') LIMIT 2000'
		);
		found.truncated = rules.size() >= 2000 || workflows.size() >= 2000 || refs.size() >= 2000;
		Set<String> objects = new Set<String>();
		for (Object each : rules) {
			Map<String, Object> row = (Map<String, Object>) each;
			Rule rule = new Rule();
			rule.kind = OrgAutomationInventory.KIND_VALIDATION;
			rule.recordId = (String) row.get('Id');
			rule.name = (String) row.get('ValidationName');
			rule.objectName = (String) row.get('EntityDefinitionId');
			rule.active = row.get('Active') == true;
			rule.namespace = (String) row.get('NamespacePrefix');
			objects.add(rule.objectName);
			found.rules.add(rule);
		}
		for (Object each : workflows) {
			Map<String, Object> row = (Map<String, Object>) each;
			Rule rule = new Rule();
			rule.kind = OrgAutomationInventory.KIND_WORKFLOW;
			rule.recordId = (String) row.get('Id');
			rule.name = (String) row.get('Name');
			rule.objectName = (String) row.get('TableEnumOrId');
			rule.namespace = (String) row.get('NamespacePrefix');
			objects.add(rule.objectName);
			found.rules.add(rule);
		}
		for (Object each : refs) {
			Map<String, Object> row = (Map<String, Object>) each;
			found.covered.add((String) row.get('MetadataComponentId'));
			found.covered.add((String) row.get('MetadataComponentName'));
		}
		OrgAutomationInventory.readEntityNames(objects);
		for (Rule rule : found.rules) {
			OrgAutomationInventory.Row named = new OrgAutomationInventory.Row();
			OrgAutomationInventory.setObject(named, rule.objectName);
			rule.objectName = named.objectName;
		}
		return found;
	}

	/**
	 * What an automation that checks the setting refers to: the Check BarnCRM Automation and
	 * AutomationControl classes, and the setting's object (its fields are added by `read`).
	 */
	@TestVisible
	private static Set<String> referencedIds() {
		Set<String> ids = new Set<String>();
		String ns = NamespaceUtil.prefix().removeEnd('__');
		for (ApexClass each : [
			SELECT Id
			FROM ApexClass
			WHERE
				Name IN ('CheckAutomationAction', 'AutomationControl')
				AND NamespacePrefix = :(String.isBlank(ns) ? null : ns)
			WITH SYSTEM_MODE
		]) {
			ids.add(each.Id);
		}
		String setting = BarnCRM_Automation_Control__c.SObjectType.getDescribe(
				SObjectDescribeOptions.DEFERRED
			)
			.getName();
		for (
			SObject entity : Database.queryWithBinds(
				'SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = :setting',
				new Map<String, Object>{ 'setting' => setting },
				AccessLevel.SYSTEM_MODE
			)
		) {
			String durable = String.valueOf(Id.valueOf((String) entity.get('DurableId')));
			ids.add(durable);
			ids.add(durable.left(15));
		}
		return ids;
	}

	private static String quoted(Set<String> values) {
		List<String> parts = new List<String>();
		for (String value : values) {
			parts.add('\'' + String.escapeSingleQuotes(value) + '\'');
		}
		return parts.isEmpty() ? '\'\'' : String.join(parts, ',');
	}

	/** The newest finished scan, or null. */
	public static Automation_Snapshot__c latest() {
		List<Automation_Snapshot__c> scans = [
			SELECT Id, Status__c, Items__c, Message__c, CreatedDate
			FROM Automation_Snapshot__c
			WHERE Kind__c = :KIND_SCAN
			WITH USER_MODE
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		return scans.isEmpty() ? null : scans[0];
	}
}
