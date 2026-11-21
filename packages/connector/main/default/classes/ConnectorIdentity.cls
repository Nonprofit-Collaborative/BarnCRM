/**
 * Who a recipe runs as (canonical model R-CR2, R-CR4; design Section 3.10, D-215). BarnCRM
 * Automation and System recipes run as Salesforce's Automated Process user, which belongs to no
 * person and cannot be deactivated. Recipe Access picks the permission sets that user holds,
 * BarnCRM Admin and each installed module's admin set to start; saving assigns them, and the
 * BarnCRM Connections set (F12), from Apex. No BarnCRM record keeps the choice: it is read back
 * from the assignments. User and permission set Ids never come from the browser unchecked.
 */
public with sharing class ConnectorIdentity {
	/** Packaged sets never offered: Connector's own, and app or tab sets that grant no data. */
	private static final Set<String> NEVER = new Set<String>{
		ConnectorConnections.ADMIN_SET,
		'BarnCRM_Connector_Viewer',
		ConnectorConnections.ACCESS_SET
	};
	private static final Set<String> NOT_DEFAULT = new Set<String>{
		'BarnCRM_App_Admin_Console',
		'BarnCRM_App_Admin_Standard',
		'BarnCRM_Metadata_Admin'
	};

	/** Set by tests: the Automated Process user's Id (a test cannot assign to the real one). */
	@TestVisible
	private static Id automatedProcessOverride;

	/** One permission set Recipe Access offers. */
	public class Choice {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Boolean picked;
	}

	/** Recipe Access as the page shows it. */
	public class Access {
		/** False when the org has no Automated Process user BarnCRM can find. */
		@AuraEnabled
		public Boolean ready;
		/** True once Recipe Access was saved (the user holds a picked set). */
		@AuraEnabled
		public Boolean saved;
		@AuraEnabled
		public List<Choice> choices = new List<Choice>();
	}

	/** The Automated Process user, or null. */
	public static Id automatedProcessId() {
		if (automatedProcessOverride != null) {
			return automatedProcessOverride;
		}
		for (User row : [SELECT Id FROM User WHERE UserType = 'AutomatedProcess' WITH SYSTEM_MODE LIMIT 1]) {
			return row.Id;
		}
		return null;
	}

	/** The sets on offer, each ticked when the user holds it, or by default before a first save. */
	public static Access access() {
		Access result = new Access();
		Id identity = automatedProcessId();
		result.ready = identity != null;
		Set<Id> held = held(identity);
		List<PermissionSet> offered = offered();
		for (PermissionSet row : offered) {
			result.saved = result.saved == true || held.contains(row.Id);
		}
		result.saved = result.saved == true;
		String namespace = NamespaceUtil.namespacePrefix();
		for (PermissionSet row : offered) {
			Choice choice = new Choice();
			choice.id = row.Id;
			choice.label = row.Label;
			choice.name = row.Name;
			choice.picked = result.saved
				? held.contains(row.Id)
				: row.NamespacePrefix == namespace && isDefault(row.Name);
			result.choices.add(choice);
		}
		return result;
	}

	/** BarnCRM Admin and each module's admin set (named `<Module>_Admin`). */
	private static Boolean isDefault(String name) {
		return name == 'BarnCRM_Admin' ||
			(name.endsWith('_Admin') &&
			!NOT_DEFAULT.contains(name) &&
			!NEVER.contains(name));
	}

	/**
	 * Assigns the picked sets and BarnCRM Connections to the Automated Process user and removes
	 * the offered sets no longer picked; assignments it does not offer are left alone. Only a
	 * Connector admin holding BarnCRM Connector Admin and Manage Named Credentials or Customize
	 * Application may save it: it gives recipes the reach of the sets picked (F3).
	 */
	public static Access save(List<String> pickedIds) {
		ConnectorConnections.requireWriter();
		if (!ConnectorConnections.holdsAdminSet()) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NoManage'));
		}
		Id identity = automatedProcessId();
		if (identity == null) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Access_NotReady'));
		}
		Set<Id> wanted = new Set<Id>();
		Map<Id, PermissionSet> offered = new Map<Id, PermissionSet>(offered());
		for (String picked : pickedIds == null ? new List<String>() : pickedIds) {
			if (!ConnectorRecipeDocument.isId(picked) || !offered.containsKey(Id.valueOf(picked))) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Access_Unknown')
				);
			}
			wanted.add(Id.valueOf(picked));
		}
		Id connections = ConnectorConnections.ensureAccessSet();
		Set<Id> held = held(identity);
		List<PermissionSetAssignment> adds = new List<PermissionSetAssignment>();
		for (Id setId : wanted) {
			if (!held.contains(setId)) {
				adds.add(new PermissionSetAssignment(AssigneeId = identity, PermissionSetId = setId));
			}
		}
		if (!held.contains(connections)) {
			adds.add(new PermissionSetAssignment(AssigneeId = identity, PermissionSetId = connections));
		}
		Set<Id> dropped = new Set<Id>(offered.keySet());
		dropped.removeAll(wanted);
		List<PermissionSetAssignment> removals = [
			SELECT Id
			FROM PermissionSetAssignment
			WHERE AssigneeId = :identity AND PermissionSetId IN :dropped
			WITH SYSTEM_MODE
		];
		Database.insert(adds, AccessLevel.SYSTEM_MODE);
		Database.delete(removals, AccessLevel.SYSTEM_MODE);
		return access();
	}

	/** Whether the Automated Process user holds any offered set (Recipe Access was saved). */
	public static Boolean accessSaved() {
		Id identity = automatedProcessId();
		if (identity == null) {
			return false;
		}
		Set<Id> held = held(identity);
		held.retainAll(new Map<Id, PermissionSet>(offered()).keySet());
		return !held.isEmpty();
	}

	private static Set<Id> held(Id identity) {
		Set<Id> found = new Set<Id>();
		if (identity == null) {
			return found;
		}
		for (PermissionSetAssignment row : [
			SELECT PermissionSetId
			FROM PermissionSetAssignment
			WHERE AssigneeId = :identity
			WITH SYSTEM_MODE
		]) {
			found.add(row.PermissionSetId);
		}
		return found;
	}

	/** Custom permission sets with no license of their own, which any user can be given. */
	private static List<PermissionSet> offered() {
		List<PermissionSet> found = new List<PermissionSet>();
		for (PermissionSet row : [
			SELECT Id, Name, Label, NamespacePrefix
			FROM PermissionSet
			WHERE IsOwnedByProfile = FALSE AND IsCustom = TRUE AND LicenseId = NULL AND Type = 'Regular'
			WITH SYSTEM_MODE
			ORDER BY Label
			LIMIT 500
		]) {
			if (!NEVER.contains(row.Name)) {
				found.add(row);
			}
		}
		return found;
	}

	/**
	 * What a recipe identity (the Automated Process user for BarnCRM Automation, the integration
	 * user for Integration User) cannot do with a record map (R-CR2), in words,
	 * from the object and field permissions of the sets it holds; empty when it can.
	 */
	public static List<String> mapProblems(Id identity, String kind, String objectName, List<String> fieldNames) {
		List<String> found = new List<String>();
		Set<Id> sets = held(identity);
		Boolean creating = kind != 'update';
		Boolean editing = kind != 'create';
		Boolean canCreate = false;
		Boolean canEdit = false;
		for (ObjectPermissions row : [
			SELECT PermissionsCreate, PermissionsEdit
			FROM ObjectPermissions
			WHERE ParentId IN :sets AND SobjectType = :objectName
			WITH SYSTEM_MODE
		]) {
			canCreate |= row.PermissionsCreate;
			canEdit |= row.PermissionsEdit;
		}
		if ((creating && !canCreate) || (editing && !canEdit)) {
			found.add(BarnHelp.text('Connector', 'Connector_Publish_ObjectAccess', new List<Object>{ objectName }));
			return found;
		}
		Set<String> qualified = new Set<String>();
		for (String field : fieldNames) {
			qualified.add(objectName + '.' + field);
		}
		Set<String> editable = new Set<String>();
		for (FieldPermissions row : [
			SELECT Field
			FROM FieldPermissions
			WHERE ParentId IN :sets AND Field IN :qualified AND PermissionsEdit = TRUE
			WITH SYSTEM_MODE
		]) {
			editable.add(row.Field.toLowerCase());
		}
		Map<String, Schema.SObjectField> fieldMap = Schema.describeSObjects(new List<String>{ objectName })[0]
			.fields.getMap();
		for (String field : fieldNames) {
			Schema.SObjectField token = fieldMap.get(field.toLowerCase());
			// Required and system fields carry no field permission: their object access covers them.
			Boolean permissionable = token != null && token.getDescribe().isPermissionable();
			if (permissionable && !editable.contains((objectName + '.' + field).toLowerCase())) {
				found.add(
					BarnHelp.text(
						'Connector',
						'Connector_Publish_FieldAccess',
						new List<Object>{ objectName + '.' + field }
					)
				);
			}
		}
		return found;
	}
}
