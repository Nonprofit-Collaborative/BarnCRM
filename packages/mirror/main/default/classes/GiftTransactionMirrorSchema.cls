/**
 * What the Gift Transaction mirror knows about this org's Nonprofit Cloud fundraising objects
 * (feature X-07, canonical model Section 29C1, R-GT1, R-GT5): whether the running person's
 * describe has Gift Transaction, whether its fields are the shape the mirror relies on, which of
 * them this person may read and write, and the same for the designation objects.
 *
 * Every object and field is a name held as a string and resolved through describe, never a
 * compile-time reference, so Mirror compiles and installs on an org without Nonprofit Cloud (plan
 * Section 4.2, ADR-0009, ADR-0013). The names are those of
 * `docs/architecture/reference/nonprofit-cloud-data-model.md` Sections 3.1 to 3.3, where their
 * types are inferred; so the types are checked here, and an org whose fields differ is treated as
 * one without the object: the mirror is unavailable and nothing queries it.
 *
 * All the names live in `names`, so tests can point the mirror at stand-in objects of the same
 * shape (`useStandIns`) and run its real queries and DML in an org without Nonprofit Cloud
 * (ADR-0157 decision 9). The describe is read once per transaction.
 */
public with sharing class GiftTransactionMirrorSchema {
	/** The object and field names the mirror uses. */
	public class Names {
		// detection-only: Nonprofit Cloud names, resolved through describe, never types
		public String transactionObject = 'GiftTransaction';
		/** The donor: a reference to Account (a person account or a business account). */
		public String donorField = 'DonorId';
		public String dateField = 'TransactionDate';
		public String amountField = 'OriginalAmount';
		/** Optional: the amount after refunds, written only when a Gift Transaction is created. */
		public String currentAmountField = 'CurrentAmount';
		public String statusField = 'Status';
		/** Optional: written only on creation, and only where it is not numbered. */
		public String nameField = 'Name';
		// detection-only: the designation junction and the designation, by name
		public String linkObject = 'GiftTransactionDesignation';
		public String linkTransactionField = 'GiftTransactionId';
		public String linkDesignationField = 'GiftDesignationId';
		public String linkAmountField = 'Amount';
		public String designationObject = 'GiftDesignation';
		/** Values a new Gift Transaction also gets: none for Nonprofit Cloud, set for stand-ins. */
		public Map<String, Object> createdAlso = new Map<String, Object>();
	}

	/** The names in use: Nonprofit Cloud's, or the stand-ins of `useStandIns`. */
	public static Names names {
		get {
			if (names == null) {
				names = new Names();
			}
			return names;
		}
		private set;
	}

	/** Test seam: the org as if it had no Gift Transactions, whatever it has. */
	@TestVisible
	private static Boolean absentForTest = false;

	/** Test seam: stand-in types, used instead of the global describe. */
	private static Map<String, Schema.SObjectType> standInTypes;

	private static Map<String, Described> described = new Map<String, Described>();
	private static Boolean shapeChecked = false;
	private static Boolean transactionShaped = false;
	private static Boolean designationShaped = false;

	/** One object's describe and field describes, read once. */
	private class Described {
		final Schema.SObjectType type;
		final Schema.DescribeSObjectResult result;
		final Map<String, Schema.SObjectField> fieldMap;
		final Map<String, Schema.DescribeFieldResult> fields = new Map<String, Schema.DescribeFieldResult>();

		Described(Schema.SObjectType type) {
			this.type = type;
			result = type.getDescribe(SObjectDescribeOptions.DEFERRED);
			fieldMap = result.fields.getMap();
		}

		Schema.DescribeFieldResult field(String name) {
			if (String.isBlank(name)) {
				return null;
			}
			String key = name.toLowerCase();
			if (!fields.containsKey(key)) {
				Schema.SObjectField token = fieldMap.get(key);
				fields.put(key, token == null ? null : token.getDescribe());
			}
			return fields.get(key);
		}
	}

	/**
	 * Points the mirror at objects every BarnCRM org with Giving has, in the shape of Nonprofit
	 * Cloud's: Gift for Gift Transaction, Gift Allocation for Gift Transaction Designation, Fund
	 * for Gift Designation. For tests only; the names come from the tokens, so they carry the
	 * package namespace once there is one.
	 */
	@TestVisible
	private static void useStandIns() {
		Names standIn = new Names();
		standIn.transactionObject = Gift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.getName();
		standIn.donorField = Gift__c.Donor_Account__c.getDescribe().getName();
		standIn.dateField = Gift__c.Gift_Date__c.getDescribe().getName();
		standIn.amountField = Gift__c.Amount__c.getDescribe().getName();
		standIn.currentAmountField = null;
		standIn.statusField = Gift__c.Status__c.getDescribe().getName();
		standIn.nameField = 'Name';
		standIn.linkObject = Gift_Allocation__c.SObjectType.getDescribe(
				SObjectDescribeOptions.DEFERRED
			)
			.getName();
		standIn.linkTransactionField = Gift_Allocation__c.Gift__c.getDescribe().getName();
		standIn.linkDesignationField = Gift_Allocation__c.Fund__c.getDescribe().getName();
		standIn.linkAmountField = Gift_Allocation__c.Amount__c.getDescribe().getName();
		standIn.designationObject = Fund__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.getName();
		standIn.createdAlso.put(Gift__c.Type__c.getDescribe().getName(), 'Cash');
		names = standIn;
		standInTypes = new Map<String, Schema.SObjectType>{
			standIn.transactionObject => Gift__c.SObjectType,
			standIn.linkObject => Gift_Allocation__c.SObjectType,
			standIn.designationObject => Fund__c.SObjectType
		};
		described.clear();
		shapeChecked = false;
	}

	// ------------------------------------------------------------------------ Gift Transaction

	/**
	 * The Gift Transaction object, or null where the running person's describe does not have it,
	 * or has it in a shape the mirror does not know.
	 */
	public static Schema.SObjectType objectType() {
		if (absentForTest == true) {
			return null;
		}
		checkShapes();
		return transactionShaped ? describedOf(names.transactionObject).type : null;
	}

	public static Boolean isAvailable() {
		return objectType() != null;
	}

	/** The object's API name as the org's describe gives it, or null when unavailable. */
	public static String objectName() {
		return isAvailable() ? describedOf(names.transactionObject).result.getName() : null;
	}

	/** The fields a later run compares and updates (R-GT4). */
	public static List<String> compared() {
		return new List<String>{ names.donorField, names.dateField, names.amountField };
	}

	/** What a Gift Transaction must let a run write for the copy to work. */
	public static List<String> requiredToCreate() {
		return new List<String>{
			names.donorField,
			names.dateField,
			names.amountField,
			names.statusField
		};
	}

	/** What the reconciliation reads from a Gift Transaction. */
	public static List<String> read() {
		return new List<String>{
			names.nameField,
			names.donorField,
			names.dateField,
			names.amountField,
			names.statusField
		};
	}

	/**
	 * The fields a new Gift Transaction is given (R-GT4) that exist, are of the type the mirror
	 * writes, and the running person may set: the required ones and the optional ones.
	 */
	public static Set<String> creatable() {
		List<String> candidates = requiredToCreate();
		for (String optional : new List<String>{ names.currentAmountField, names.nameField }) {
			if (hasOptional(optional)) {
				candidates.add(optional);
			}
		}
		candidates.addAll(names.createdAlso.keySet());
		return writable(candidates, true);
	}

	/** Whether the running person may read Gift Transactions and each of these fields. */
	public static Boolean canRead(List<String> fieldNames) {
		return isAvailable() && readable(names.transactionObject, fieldNames);
	}

	/** Whether the running person may create Gift Transactions with each of these fields. */
	public static Boolean canCreate(List<String> fieldNames) {
		return isAvailable() &&
			describedOf(names.transactionObject).result.isCreateable() &&
			writable(fieldNames, true).size() == new Set<String>(fieldNames).size();
	}

	/** Whether the running person may edit Gift Transactions and each of these fields. */
	public static Boolean canUpdate(List<String> fieldNames) {
		return isAvailable() &&
			describedOf(names.transactionObject).result.isUpdateable() &&
			writable(fieldNames, false).size() == new Set<String>(fieldNames).size();
	}

	/**
	 * The Gift Transaction fields among these that exist and the running person may write on a
	 * new record (`creating`) or an existing one. A numbered or calculated field never is.
	 */
	public static Set<String> writable(List<String> fieldNames, Boolean creating) {
		Set<String> found = new Set<String>();
		if (!isAvailable()) {
			return found;
		}
		Described gt = describedOf(names.transactionObject);
		for (String name : fieldNames) {
			Schema.DescribeFieldResult field = gt.field(name);
			if (field == null || field.isAutoNumber() || field.isCalculated()) {
				continue;
			}
			if (creating ? field.isCreateable() : field.isUpdateable()) {
				found.add(name);
			}
		}
		return found;
	}

	/** Whether this is an active value of the org's Gift Transaction Status list (R-GT2). */
	public static Boolean isActiveStatus(String value) {
		if (String.isBlank(value) || !isAvailable()) {
			return false;
		}
		for (
			Schema.PicklistEntry entry : describedOf(names.transactionObject)
				.field(names.statusField)
				.getPicklistValues()
		) {
			if (entry.isActive() && entry.getValue() == value) {
				return true;
			}
		}
		return false;
	}

	/** Whether the optional Gift Transaction field is there and of the type the mirror writes. */
	public static Boolean hasOptional(String name) {
		if (String.isBlank(name) || absentForTest == true) {
			return false;
		}
		Described gt = describedOf(names.transactionObject);
		Schema.DescribeFieldResult field = gt == null ? null : gt.field(name);
		if (field == null) {
			return false;
		}
		if (name == names.currentAmountField) {
			return isAmount(field);
		}
		return field.getType() == Schema.DisplayType.STRING;
	}

	// ------------------------------------------------------------------------- designations

	/**
	 * Whether a run may write designations (R-GT5): the designation objects are present in the
	 * shape the mirror relies on, and the running person may create the junction with its three
	 * fields.
	 */
	public static Boolean canWriteDesignations() {
		if (!isAvailable() || !designationShaped) {
			return false;
		}
		Described link = describedOf(names.linkObject);
		if (!link.result.isCreateable()) {
			return false;
		}
		for (String name : designationFields()) {
			if (!link.field(name).isCreateable()) {
				return false;
			}
		}
		return readable(names.linkObject, new List<String>{ names.linkTransactionField });
	}

	/** The Gift Designation object, or null where it is absent or not in the expected shape. */
	public static Schema.SObjectType designationType() {
		return isAvailable() && designationShaped
			? describedOf(names.designationObject).type
			: null;
	}

	/** The designation junction object, or null where it is absent or not in the expected shape. */
	public static Schema.SObjectType linkType() {
		return isAvailable() && designationShaped ? describedOf(names.linkObject).type : null;
	}

	public static String linkObjectName() {
		Schema.SObjectType link = linkType();
		return link == null ? null : link.getDescribe().getName();
	}

	private static List<String> designationFields() {
		return new List<String>{
			names.linkTransactionField,
			names.linkDesignationField,
			names.linkAmountField
		};
	}

	// ------------------------------------------------------------------------------- helpers

	/**
	 * An amount as a Decimal, whichever number type the org's field returns, so a comparison with
	 * a gift's amount is by value.
	 */
	public static Decimal decimalOf(Object value) {
		if (value == null) {
			return null;
		}
		if (value instanceof Decimal) {
			return (Decimal) value;
		}
		return Decimal.valueOf(String.valueOf(value));
	}

	/**
	 * R-GT1 and R-GT5: the fields the mirror cannot do without, with the types it relies on,
	 * checked once. The designation objects are checked only when Gift Transaction passes.
	 */
	private static void checkShapes() {
		if (shapeChecked) {
			return;
		}
		shapeChecked = true;
		Described gt = describedOf(names.transactionObject);
		transactionShaped = false;
		designationShaped = false;
		if (gt == null) {
			return;
		}
		Schema.DescribeFieldResult donor = gt.field(names.donorField);
		Schema.DescribeFieldResult status = gt.field(names.statusField);
		transactionShaped =
			refersTo(donor, Account.SObjectType) &&
			isType(gt.field(names.dateField), Schema.DisplayType.DATE) &&
			isAmount(gt.field(names.amountField)) &&
			isType(status, Schema.DisplayType.PICKLIST);
		Described link = describedOf(names.linkObject);
		Described designation = describedOf(names.designationObject);
		designationShaped =
			transactionShaped &&
			link != null &&
			designation != null &&
			refersTo(link.field(names.linkTransactionField), gt.type) &&
			refersTo(link.field(names.linkDesignationField), designation.type) &&
			isAmount(link.field(names.linkAmountField));
	}

	private static Boolean readable(String objectName, List<String> fieldNames) {
		Described found = describedOf(objectName);
		if (found == null || !found.result.isAccessible()) {
			return false;
		}
		for (String name : fieldNames) {
			Schema.DescribeFieldResult field = found.field(name);
			if (field == null || !field.isAccessible()) {
				return false;
			}
		}
		return true;
	}

	/** The object's describe, or null where the running person's describe does not have it. */
	private static Described describedOf(String objectName) {
		if (String.isBlank(objectName)) {
			return null;
		}
		if (!described.containsKey(objectName)) {
			Schema.SObjectType type = standInTypes != null
				? standInTypes.get(objectName)
				: NamespaceUtil.globalDescribe().get(objectName);
			described.put(objectName, type == null ? null : new Described(type));
		}
		return described.get(objectName);
	}

	private static Boolean refersTo(Schema.DescribeFieldResult field, Schema.SObjectType target) {
		return isType(field, Schema.DisplayType.REFERENCE) &&
			field.getReferenceTo().contains(target);
	}

	private static Boolean isType(Schema.DescribeFieldResult field, Schema.DisplayType type) {
		return field != null && field.getType() == type;
	}

	private static Boolean isAmount(Schema.DescribeFieldResult field) {
		return field != null &&
			(field.getType() == Schema.DisplayType.CURRENCY ||
			field.getType() == Schema.DisplayType.DOUBLE);
	}
}
