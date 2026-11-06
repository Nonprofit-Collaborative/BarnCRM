/**
 * The automation inventory of the Automation tab (C-60, D-184, canonical model Section 29F,
 * "Automation tab inventory", rules R-OA1 to R-OA6): one list of every automation in the org, BarnCRM's and the org's own, with
 * whether the BarnCRM Automation Control setting (Pause All and Bypass) covers it.
 *
 * Read with user-mode SOQL only, the way the Data Dictionary inventory reads flows and triggers:
 * BarnCRM's switches (`Automation_Setting__c`), record-triggered, scheduled and platform event
 * flows and processes (`FlowDefinitionView`), and Apex triggers with their source
 * (`ApexTrigger`). Validation rules and workflow rules need the Tooling API and come from the
 * org connection's scan (`OrgAutomationScan`), when there is one.
 */
public with sharing class OrgAutomationInventory {
	/** The most flows, and the most triggers, read. */
	@TestVisible
	private static final Integer MAX_ROWS = 2000;
	/** The most triggers whose source is read, to keep the call inside the heap. */
	@TestVisible
	private static final Integer MAX_TRIGGERS = 500;

	public static final String KIND_BARN = 'BarnCRM';
	public static final String KIND_FLOW = 'Flow';
	public static final String KIND_PROCESS = 'ProcessBuilder';
	public static final String KIND_TRIGGER = 'ApexTrigger';
	public static final String KIND_VALIDATION = 'ValidationRule';
	public static final String KIND_WORKFLOW = 'WorkflowRule';

	public static final String OWNER_BARN = 'BarnCRM';
	public static final String OWNER_ORG = 'Org';

	public static final String COVERED_YES = 'Yes';
	public static final String COVERED_NO = 'No';
	public static final String COVERED_UNKNOWN = 'NotChecked';

	public static final String STATUS_ACTIVE = 'Active';
	public static final String STATUS_INACTIVE = 'Inactive';
	public static final String STATUS_ON = 'On';
	public static final String STATUS_OFF = 'Off';
	public static final String STATUS_ALWAYS = 'AlwaysRuns';

	/**
	 * BarnCRM's own flows, by API name: the inactive templates an admin copies (ADR-0090). With no
	 * namespace they cannot be told from the org's own any other way. A CI test keeps this list in
	 * step with the packages' flow folders.
	 */
	@TestVisible
	private static final Set<String> BARN_FLOWS = new Set<String>{
		'Template_Account_Address_Capture',
		'Template_Affiliation_Primary',
		'Template_Affiliation_Primary_Delete',
		'Template_Affiliation_Validation',
		'Template_Relationship_Reciprocal',
		'Template_Relationship_Reciprocal_Delete',
		'Template_Relationship_Validation',
		'Recalculate_Rollups_Template'
	};

	/**
	 * BarnCRM's triggers that are not routed through the dispatcher (R-A3): they record errors or
	 * settle BarnCRM's own work, so no pause or switch stops them. Kept in step by the CI test.
	 */
	@TestVisible
	private static final Set<String> BARN_EVENT_TRIGGERS = new Set<String>{
		'ErrorLogEventTrigger',
		'MergeSettlementReadyTrigger',
		'RollupQueueReadyTrigger',
		'RollupRecalcErrorTrigger'
	};

	/** What in a trigger's source shows it asks the BarnCRM Automation Control setting. */
	private static final Pattern CHECKS_CONTROL = Pattern.compile(
		'(?i)(TriggerDispatcher\\s*\\.\\s*run\\s*\\(|CheckAutomationAction|AutomationControl\\s*\\.|BarnCRM_Automation_Control__c)'
	);
	private static final Pattern DISPATCHED = Pattern.compile(
		'TriggerDispatcher\\s*\\.\\s*run\\s*\\('
	);

	/** A flow's trigger type, in words. */
	private static final Map<String, String> FLOW_TRIGGERS = new Map<String, String>{
		'RecordBeforeSave' => 'Before save',
		'RecordAfterSave' => 'After save',
		'RecordBeforeDelete' => 'Before delete',
		'Scheduled' => 'Scheduled',
		'PlatformEvent' => 'Platform event'
	};
	private static final Set<String> PROCESS_TYPES = new Set<String>{
		'Workflow',
		'InvocableProcess',
		'CustomEvent'
	};

	/** One automation. Plain values, so the page and a CSV read it as JSON. */
	public class Row {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String apiName;
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public String objectLabel;
		@AuraEnabled
		public String status;
		/** `BarnCRM`, `Org`, or a managed package's namespace. */
		@AuraEnabled
		public String owner;
		/** When it runs: the events of a trigger, the point in the save of a flow. */
		@AuraEnabled
		public String detail;
		@AuraEnabled
		public String covered;
		/** The Id the org connection changes it by: a flow definition's or a validation rule's. */
		@AuraEnabled
		public String recordId;
		/** True for an org's own active flow or validation rule (R-OA6). */
		@AuraEnabled
		public Boolean canDeactivate = false;
	}

	public class Result {
		@AuraEnabled
		public List<Row> rows = new List<Row>();
		/** The parts that could not be read: `Switches`, `Flows`, `Triggers`. */
		@AuraEnabled
		public List<String> unreadable = new List<String>();
		/** True when flows or triggers stopped at their cap. */
		@AuraEnabled
		public Boolean truncated = false;
		/** What a class name needs in front of it in this org's Apex (`ns.` or nothing). */
		@AuraEnabled
		public String classPrefix;
		/** What a field or setting name needs in front of it (`ns__` or nothing). */
		@AuraEnabled
		public String fieldPrefix;
	}

	/** Test hook: a part (`Switches`, `Flows`, `Triggers`) made to fail. */
	@TestVisible
	private static String failPart;

	private static Map<String, String> labelsByObject = new Map<String, String>();
	private static Map<String, String> namesByEntityId = new Map<String, String>();

	public static Result build() {
		Result result = new Result();
		result.fieldPrefix = NamespaceUtil.prefix();
		result.classPrefix = String.isBlank(result.fieldPrefix)
			? ''
			: result.fieldPrefix.removeEnd('__') + '.';
		try {
			fail('Switches');
			addSwitches(result);
		} catch (Exception unreadable) {
			result.unreadable.add('Switches');
		}
		List<SObject> flows = new List<SObject>();
		List<SObject> triggers = new List<SObject>();
		try {
			fail('Flows');
			// Every flow is read and the screen and called ones dropped here: FlowDefinitionView
			// takes few filters.
			List<SObject> read = Database.query(
				'SELECT DurableId, ApiName, Label, IsActive, ProcessType, TriggerType,' +
					' TriggerObjectOrEventId, NamespacePrefix FROM FlowDefinitionView' +
					' ORDER BY Label LIMIT ' +
					(MAX_ROWS + 1),
				AccessLevel.USER_MODE
			);
			result.truncated = read.size() > MAX_ROWS;
			for (Integer i = 0; i < Math.min(read.size(), MAX_ROWS); i++) {
				SObject flow = read[i];
				if (
					flow.get('TriggerType') != null ||
					PROCESS_TYPES.contains((String) flow.get('ProcessType'))
				) {
					flows.add(flow);
				}
			}
		} catch (Exception unreadable) {
			result.unreadable.add('Flows');
		}
		try {
			fail('Triggers');
			triggers = Database.query(
				'SELECT Name, Status, TableEnumOrId, NamespacePrefix, Body, UsageBeforeInsert,' +
					' UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate, UsageBeforeDelete,' +
					' UsageAfterDelete, UsageAfterUndelete FROM ApexTrigger ORDER BY Name LIMIT ' +
					(MAX_TRIGGERS + 1),
				AccessLevel.USER_MODE
			);
		} catch (Exception unreadable) {
			result.unreadable.add('Triggers');
		}
		result.truncated = result.truncated || triggers.size() > MAX_TRIGGERS;
		Set<String> entityIds = new Set<String>();
		for (SObject flow : flows) {
			entityIds.add((String) flow.get('TriggerObjectOrEventId'));
		}
		for (SObject each : triggers) {
			entityIds.add((String) each.get('TableEnumOrId'));
		}
		readEntityNames(entityIds);
		for (SObject flow : flows) {
			result.rows.add(flowRow(flow));
		}
		for (Integer i = 0; i < Math.min(triggers.size(), MAX_TRIGGERS); i++) {
			result.rows.add(triggerRow(triggers[i]));
		}
		return result;
	}

	/** BarnCRM's own automations, by their switches; an org's listed flow is shown as a flow. */
	private static void addSwitches(Result result) {
		for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForConsole()) {
			if (AutomationControlSettingService.isOwnFlow(setting)) {
				continue;
			}
			Row row = new Row();
			row.kind = KIND_BARN;
			row.name = setting.Name;
			row.apiName = setting.Automation_Name__c;
			row.key = KIND_BARN + '|' + row.apiName;
			row.objectName = setting.Object_Name__c;
			row.objectLabel = objectLabel(row.objectName);
			row.owner = OWNER_BARN;
			row.detail = setting.Description__c;
			if (setting.Always_Runs__c == true) {
				row.status = STATUS_ALWAYS;
				row.covered = COVERED_NO;
			} else {
				row.status = setting.Enabled__c == true ? STATUS_ON : STATUS_OFF;
				row.covered = COVERED_YES;
			}
			result.rows.add(row);
		}
	}

	@TestVisible
	private static Row flowRow(SObject flow) {
		Row row = new Row();
		String processType = (String) flow.get('ProcessType');
		row.kind = PROCESS_TYPES.contains(processType) ? KIND_PROCESS : KIND_FLOW;
		row.name = (String) flow.get('Label');
		row.apiName = (String) flow.get('ApiName');
		row.key = row.kind + '|' + row.apiName;
		row.recordId = (String) flow.get('DurableId');
		row.status = flow.get('IsActive') == true ? STATUS_ACTIVE : STATUS_INACTIVE;
		setObject(row, (String) flow.get('TriggerObjectOrEventId'));
		String triggerType = (String) flow.get('TriggerType');
		row.detail = FLOW_TRIGGERS.containsKey(triggerType)
			? FLOW_TRIGGERS.get(triggerType)
			: triggerType;
		row.owner = ownerOf((String) flow.get('NamespacePrefix'), BARN_FLOWS.contains(row.apiName));
		// BarnCRM's templates start with the Check BarnCRM Automation action; an org's own flow
		// is known to only once the org connection's scan has read what refers to the action.
		row.covered = row.owner == OWNER_BARN
			? COVERED_YES
			: (row.owner == OWNER_ORG ? COVERED_UNKNOWN : COVERED_NO);
		row.canDeactivate = row.owner == OWNER_ORG && row.status == STATUS_ACTIVE;
		return row;
	}

	@TestVisible
	private static Row triggerRow(SObject each) {
		Row row = new Row();
		row.kind = KIND_TRIGGER;
		row.name = (String) each.get('Name');
		row.apiName = row.name;
		row.key = KIND_TRIGGER + '|' + row.name;
		row.status = (String) each.get('Status');
		setObject(row, (String) each.get('TableEnumOrId'));
		String body = (String) each.get('Body');
		Boolean dispatched = body != null && DISPATCHED.matcher(body).find();
		row.owner = ownerOf(
			(String) each.get('NamespacePrefix'),
			dispatched || BARN_EVENT_TRIGGERS.contains(row.name)
		);
		row.covered = body != null && CHECKS_CONTROL.matcher(body).find()
			? COVERED_YES
			: COVERED_NO;
		if (BARN_EVENT_TRIGGERS.contains(row.name) && row.owner == OWNER_BARN) {
			row.covered = COVERED_NO;
		}
		List<String> events = new List<String>();
		for (
			String field : new List<String>{
				'UsageBeforeInsert',
				'UsageBeforeUpdate',
				'UsageBeforeDelete',
				'UsageAfterInsert',
				'UsageAfterUpdate',
				'UsageAfterDelete',
				'UsageAfterUndelete'
			}
		) {
			if (each.get(field) == true) {
				events.add(
					field.substringAfter('Usage')
						.replaceAll('([a-z])([A-Z])', '$1 $2')
						.toLowerCase()
				);
			}
		}
		row.detail = String.join(events, ', ');
		return row;
	}

	/** BarnCRM, the org, or the managed package whose namespace it carries. */
	public static String ownerOf(String namespace, Boolean barnByName) {
		String ours = NamespaceUtil.prefix().removeEnd('__');
		if (String.isNotBlank(namespace)) {
			return namespace == ours ? OWNER_BARN : namespace;
		}
		return barnByName ? OWNER_BARN : OWNER_ORG;
	}

	/** Sets the object's API name and label from a name, or a custom object's Id. */
	public static void setObject(Row row, String nameOrId) {
		row.objectName = namesByEntityId.containsKey(nameOrId)
			? namesByEntityId.get(nameOrId)
			: nameOrId;
		row.objectLabel = objectLabel(row.objectName);
	}

	/** Custom object Ids (as a flow or trigger names a custom object) to API names, one query. */
	public static void readEntityNames(Set<String> namesOrIds) {
		Set<String> ids = new Set<String>();
		for (String each : namesOrIds) {
			if (
				each != null &&
				each.startsWith('01I') &&
				(each.length() == 15 ||
				each.length() == 18)
			) {
				ids.add(each);
				ids.add(String.valueOf(Id.valueOf(each)));
			}
		}
		if (ids.isEmpty()) {
			return;
		}
		try {
			for (
				SObject entity : Database.queryWithBinds(
					'SELECT DurableId, QualifiedApiName FROM EntityDefinition WHERE DurableId IN :ids',
					new Map<String, Object>{ 'ids' => ids },
					AccessLevel.USER_MODE
				)
			) {
				String durable = (String) entity.get('DurableId');
				String name = (String) entity.get('QualifiedApiName');
				namesByEntityId.put(durable, name);
				namesByEntityId.put(durable.left(15), name);
			}
		} catch (Exception unreadable) {
			// The Id is shown in place of the name; nothing else depends on it.
			return;
		}
	}

	/** The object's label in this org, or the name as given when it is not an object here. */
	public static String objectLabel(String apiName) {
		if (String.isBlank(apiName)) {
			return apiName;
		}
		if (!labelsByObject.containsKey(apiName)) {
			Schema.SObjectType objectType = NamespaceUtil.globalDescribe()
				.get(apiName.toLowerCase());
			labelsByObject.put(
				apiName,
				objectType == null
					? apiName
					: objectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
			);
		}
		return labelsByObject.get(apiName);
	}

	private static void fail(String part) {
		if (part == failPart) {
			throw new QueryException('Made to fail by a test.');
		}
	}
}
