/**
 * A portal template (ADR-0185 `0185-portal-builder-off-platform-portal-api.md`, decision 3;
 * canonical model R-PB2): the JSON parsed and checked against this org's schema. The same shape
 * is checked in the client by `portal-client/src/template.js`; this class is the one the server
 * trusts. A template that fails any check is refused whole, never partly used.
 *
 * Shape (`schemaVersion` 1): `{ key, title, requiresModules: [..], pages: [{ key, title, kind:
 * person | related | catalog, object, personField, fields: [{ field, label, edit, required }],
 * where: [{ field, op, value }], orderBy, limit, actions: ["update", "create", { extension,
 * label }] }] }`.
 */
public with sharing class PortalTemplate {
	public static final Integer SCHEMA_VERSION = 1;
	public static final String KIND_PERSON = 'person';
	public static final String KIND_RELATED = 'related';
	public static final String KIND_CATALOG = 'catalog';
	private static final Integer MAX_PAGES = 20;
	private static final Integer MAX_FIELDS = 40;
	private static final Integer MAX_ROWS = 200;
	private static final Set<String> OPS = new Set<String>{
		'equals',
		'notEquals',
		'greaterOrEqual',
		'lessOrEqual',
		'isBlank',
		'isNotBlank'
	};
	/** Portal Builder's own objects, which no template may name. */
	private static final Set<String> OWN_OBJECTS = new Set<String>{
		'portal__c',
		'portal_access__c',
		'portal_session__c'
	};
	/** Field types a person may edit. Lookups, formulas and system fields never are. */
	private static final Set<Schema.DisplayType> EDITABLE_TYPES = new Set<Schema.DisplayType>{
		Schema.DisplayType.STRING,
		Schema.DisplayType.TEXTAREA,
		Schema.DisplayType.EMAIL,
		Schema.DisplayType.PHONE,
		Schema.DisplayType.URL,
		Schema.DisplayType.DATE,
		Schema.DisplayType.DATETIME,
		Schema.DisplayType.BOOLEAN,
		Schema.DisplayType.DOUBLE,
		Schema.DisplayType.INTEGER,
		Schema.DisplayType.PICKLIST,
		Schema.DisplayType.MULTIPICKLIST
	};

	/** Why a template cannot be used; the message names the page and field. */
	public class TemplateException extends Exception {
	}

	public String key;
	public String title;
	public List<String> requiresModules = new List<String>();
	public List<PageSpec> pages = new List<PageSpec>();

	public class PageSpec {
		public String key;
		public String title;
		public String kind;
		public Schema.SObjectType objectType;
		public String personField;
		/** True when the person is reached through one parent (`Parent__r.Contact__c`): read only. */
		public Boolean personViaParent = false;
		public List<FieldSpec> fields = new List<FieldSpec>();
		public List<Condition> conditions = new List<Condition>();
		public String orderBy;
		public Integer rowLimit = 50;
		public Boolean canUpdate = false;
		public Boolean canCreate = false;
		public Map<String, String> extensionLabels = new Map<String, String>();

		public FieldSpec field(String path) {
			for (FieldSpec spec : fields) {
				if (spec.path.equalsIgnoreCase(path)) {
					return spec;
				}
			}
			return null;
		}
	}

	public class FieldSpec {
		public String path;
		public String label;
		public Boolean edit = false;
		public Boolean required = false;
		/** The field itself, or for `Parent__r.Name` the parent's field. */
		public Schema.DescribeFieldResult describe;
	}

	public class Condition {
		public String field;
		public String op;
		public Object value;
	}

	/** Parses and checks a template, or throws TemplateException saying what is wrong. */
	public static PortalTemplate parse(String source) {
		if (String.isBlank(source)) {
			throw new TemplateException('The portal has no template');
		}
		Map<String, Object> root;
		try {
			root = (Map<String, Object>) JSON.deserializeUntyped(source);
		} catch (Exception notJson) {
			throw new TemplateException('The template is not valid JSON');
		}
		if (asInteger(root.get('schemaVersion')) != SCHEMA_VERSION) {
			throw new TemplateException('schemaVersion must be ' + SCHEMA_VERSION);
		}
		PortalTemplate template = new PortalTemplate();
		template.key = asText(root.get('key'));
		template.title = asText(root.get('title'));
		for (Object module : asList(root.get('requiresModules'))) {
			template.requiresModules.add(String.valueOf(module));
		}
		List<Object> pages = asList(root.get('pages'));
		if (pages.isEmpty() || pages.size() > MAX_PAGES) {
			throw new TemplateException('A template has 1 to ' + MAX_PAGES + ' pages');
		}
		Set<String> keys = new Set<String>();
		for (Object raw : pages) {
			PageSpec page = parsePage(asMap(raw, 'page'));
			if (!keys.add(page.key)) {
				throw new TemplateException('Two pages have the key ' + page.key);
			}
			template.pages.add(page);
		}
		return template;
	}

	/** The page with this key, or null. */
	public PageSpec page(String pageKey) {
		for (PageSpec candidate : pages) {
			if (candidate.key == pageKey) {
				return candidate;
			}
		}
		return null;
	}

	private static PageSpec parsePage(Map<String, Object> raw) {
		PageSpec page = new PageSpec();
		page.key = asText(raw.get('key'));
		page.title = asText(raw.get('title'));
		page.kind = asText(raw.get('kind'));
		if (String.isBlank(page.key) || !page.key.isAlphanumeric()) {
			throw new TemplateException('Each page needs a key of letters and numbers');
		}
		String at = 'Page ' + page.key + ': ';
		if (page.kind == KIND_PERSON) {
			page.objectType = Contact.SObjectType;
		} else if (page.kind == KIND_RELATED || page.kind == KIND_CATALOG) {
			page.objectType = customObject(asText(raw.get('object')), at);
		} else {
			throw new TemplateException(at + 'kind must be person, related or catalog');
		}
		Map<String, Schema.SObjectField> fieldMap = page.objectType.getDescribe().fields.getMap();
		if (page.kind == KIND_RELATED) {
			page.personField = asText(raw.get('personField'));
			page.personViaParent = page.personField != null && page.personField.contains('.');
			if (!isPersonLink(page.personField, fieldMap)) {
				throw new TemplateException(at + 'personField must be a lookup to Contact');
			}
		}
		List<Object> fields = asList(raw.get('fields'));
		if (fields.isEmpty() || fields.size() > MAX_FIELDS) {
			throw new TemplateException(at + 'list 1 to ' + MAX_FIELDS + ' fields');
		}
		for (Object rawField : fields) {
			page.fields.add(parseField(asMap(rawField, 'field'), page, fieldMap, at));
		}
		for (Object rawCondition : asList(raw.get('where'))) {
			page.conditions.add(parseCondition(asMap(rawCondition, 'where test'), fieldMap, at));
		}
		if (page.kind == KIND_CATALOG && page.conditions.isEmpty()) {
			throw new TemplateException(at + 'a catalog page needs at least one where test');
		}
		parseOrder(page, asText(raw.get('orderBy')), fieldMap, at);
		Integer rows = asInteger(raw.get('limit'));
		if (rows != null) {
			page.rowLimit = Math.max(1, Math.min(rows, MAX_ROWS));
		}
		parseActions(page, asList(raw.get('actions')), at);
		return page;
	}

	/** A lookup to Contact, or `Parent__r.Contact__c`: one parent hop to a lookup to Contact. */
	private static Boolean isPersonLink(String path, Map<String, Schema.SObjectField> fieldMap) {
		if (String.isBlank(path)) {
			return false;
		}
		if (!path.contains('.')) {
			Schema.SObjectField link = fieldMap.get(path.toLowerCase());
			return link != null &&
				link.getDescribe().getReferenceTo().contains(Contact.SObjectType);
		}
		String relationship = path.substringBefore('.');
		String parentField = path.substringAfter('.');
		if (parentField.contains('.')) {
			return false;
		}
		for (Schema.SObjectField field : fieldMap.values()) {
			Schema.DescribeFieldResult describe = field.getDescribe();
			if (
				describe.getRelationshipName() != null &&
				describe.getRelationshipName().equalsIgnoreCase(relationship) &&
				describe.getReferenceTo().size() == 1
			) {
				Schema.SObjectField target = describe.getReferenceTo()[0]
					.getDescribe()
					.fields.getMap()
					.get(parentField.toLowerCase());
				return target != null &&
					target.getDescribe().getReferenceTo().contains(Contact.SObjectType);
			}
		}
		return false;
	}

	private static Schema.SObjectType customObject(String name, String at) {
		Schema.SObjectType type = String.isBlank(name)
			? null
			: NamespaceUtil.globalDescribe().get(name.toLowerCase());
		if (
			type == null ||
			!type.getDescribe().isCustom() ||
			type.getDescribe().isCustomSetting() ||
			OWN_OBJECTS.contains(type.getDescribe().getLocalName().toLowerCase())
		) {
			throw new TemplateException(at + 'object must be a custom object of this org');
		}
		return type;
	}

	private static FieldSpec parseField(
		Map<String, Object> raw,
		PageSpec page,
		Map<String, Schema.SObjectField> fieldMap,
		String at
	) {
		FieldSpec spec = new FieldSpec();
		spec.path = asText(raw.get('field'));
		spec.edit = raw.get('edit') == true;
		spec.required = raw.get('required') == true;
		if (String.isBlank(spec.path)) {
			throw new TemplateException(at + 'each field needs a field name');
		}
		spec.describe = describePath(spec.path, fieldMap);
		if (spec.describe == null) {
			throw new TemplateException(at + spec.path + ' is not a field here');
		}
		spec.label = String.isBlank(asText(raw.get('label')))
			? spec.describe.getLabel()
			: asText(raw.get('label'));
		if (spec.edit) {
			Boolean editable =
				page.kind != KIND_CATALOG &&
				!page.personViaParent &&
				!spec.path.contains('.') &&
				spec.describe.isUpdateable() &&
				!spec.describe.isCalculated() &&
				EDITABLE_TYPES.contains(spec.describe.getType()) &&
				!spec.path.equalsIgnoreCase(page.personField);
			if (!editable) {
				throw new TemplateException(at + spec.path + ' cannot be edited in a portal');
			}
		}
		return spec;
	}

	/** A field, or one parent hop (`Parent__r.Name`, `Account.Name`) for reading. */
	private static Schema.DescribeFieldResult describePath(
		String path,
		Map<String, Schema.SObjectField> fieldMap
	) {
		if (!path.contains('.')) {
			Schema.SObjectField field = fieldMap.get(path.toLowerCase());
			return field == null ? null : field.getDescribe();
		}
		String relationship = path.substringBefore('.');
		String parentField = path.substringAfter('.');
		if (parentField.contains('.')) {
			return null;
		}
		for (Schema.SObjectField field : fieldMap.values()) {
			Schema.DescribeFieldResult describe = field.getDescribe();
			if (
				describe.getRelationshipName() != null &&
				describe.getRelationshipName().equalsIgnoreCase(relationship) &&
				describe.getReferenceTo().size() == 1
			) {
				Schema.SObjectField target = describe.getReferenceTo()[0]
					.getDescribe()
					.fields.getMap()
					.get(parentField.toLowerCase());
				return target == null ? null : target.getDescribe();
			}
		}
		return null;
	}

	private static Condition parseCondition(
		Map<String, Object> raw,
		Map<String, Schema.SObjectField> fieldMap,
		String at
	) {
		Condition condition = new Condition();
		condition.field = asText(raw.get('field'));
		condition.op = asText(raw.get('op'));
		condition.value = raw.get('value');
		if (condition.field == null || !fieldMap.containsKey(condition.field.toLowerCase())) {
			throw new TemplateException(at + 'a where test names no field of the object');
		}
		condition.field = fieldMap.get(condition.field.toLowerCase()).getDescribe().getName();
		if (!OPS.contains(condition.op)) {
			throw new TemplateException(at + 'where op ' + condition.op + ' is not known');
		}
		Object value = condition.value;
		Boolean plain =
			value == null ||
			value instanceof String ||
			value instanceof Boolean ||
			value instanceof Decimal ||
			value instanceof Integer ||
			value instanceof Long;
		if (!plain) {
			throw new TemplateException(
				at + 'a where value must be text, a number or true or false'
			);
		}
		return condition;
	}

	private static void parseOrder(
		PageSpec page,
		String orderBy,
		Map<String, Schema.SObjectField> fieldMap,
		String at
	) {
		if (String.isBlank(orderBy)) {
			return;
		}
		String field = orderBy.trim().substringBefore(' ');
		String direction = orderBy.trim().substringAfter(' ').trim().toUpperCase();
		if (
			!fieldMap.containsKey(field.toLowerCase()) ||
			!(direction == '' ||
			direction == 'ASC' ||
			direction == 'DESC')
		) {
			throw new TemplateException(at + 'orderBy must be a field, then ASC or DESC');
		}
		page.orderBy =
			fieldMap.get(field.toLowerCase()).getDescribe().getName() +
			(direction == '' ? '' : ' ' + direction);
	}

	private static void parseActions(PageSpec page, List<Object> actions, String at) {
		for (Object action : actions) {
			if (action == 'update' && page.kind != KIND_CATALOG && !page.personViaParent) {
				page.canUpdate = true;
			} else if (action == 'create' && page.kind == KIND_RELATED && !page.personViaParent) {
				page.canCreate = true;
			} else if (action instanceof Map<String, Object>) {
				Map<String, Object> extension = (Map<String, Object>) action;
				String name = asText(extension.get('extension'));
				if (name == null || !name.contains('.')) {
					throw new TemplateException(at + 'an extension action is named Module.Action');
				}
				String label = asText(extension.get('label'));
				page.extensionLabels.put(name, label == null ? name.substringAfter('.') : label);
			} else {
				throw new TemplateException(at + 'action ' + action + ' is not allowed here');
			}
		}
	}

	private static String asText(Object value) {
		return value == null ? null : String.valueOf(value).trim();
	}

	private static Integer asInteger(Object value) {
		if (value instanceof Integer) {
			return (Integer) value;
		}
		if (value instanceof Decimal) {
			return ((Decimal) value).intValue();
		}
		if (value instanceof Long) {
			return ((Long) value).intValue();
		}
		return null;
	}

	private static List<Object> asList(Object value) {
		return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
	}

	private static Map<String, Object> asMap(Object value, String what) {
		if (!(value instanceof Map<String, Object>)) {
			throw new TemplateException('Each ' + what + ' must be a JSON object');
		}
		return (Map<String, Object>) value;
	}
}
