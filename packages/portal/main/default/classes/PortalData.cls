/**
 * What a signed-in portal person sees and changes (ADR-0185
 * `0185-portal-builder-off-platform-portal-api.md`, decisions 3, 8 and 9; canonical model R-PB2,
 * R-PB3). Every read and write is the verified person's and only what their portal's template
 * allows: a related page is filtered by its person field, an update re-reads the record through
 * the same filter, a create always sets the person field, and only `edit` fields are written.
 *
 * Runs `without sharing` in system mode, because the integration user that calls it has no object
 * access of its own; these checks replace sharing (Without Sharing Register, Portal).
 */
public without sharing class PortalData {
	private static final String CONTEXT = 'PortalData';

	/** The portal's title, the person's first name, and its pages, for the client's menu. */
	public static Map<String, Object> describe(PortalAuth.Session session) {
		PortalTemplate template = templateOf(session.portal);
		List<Object> pages = new List<Object>();
		for (PortalTemplate.PageSpec page : template.pages) {
			pages.add(
				new Map<String, Object>{
					'key' => page.key,
					'title' => page.title,
					'kind' => page.kind,
					'canUpdate' => page.canUpdate,
					'canCreate' => page.canCreate,
					'actions' => extensionList(page)
				}
			);
		}
		// The first name came with the session (`PortalAuth.resolve`): no query of its own.
		return new Map<String, Object>{
			'title' => String.isBlank(template.title) ? session.portal.Name : template.title,
			'firstName' => session.access.Person__r.FirstName,
			'secondFactor' => new Map<String, Object>{
				'policy' => session.portal.Second_Factor__c,
				'enrolled' => session.access.Second_Factor_Enrolled__c == true
			},
			'pages' => pages
		};
	}

	/** One page: its fields, and the records it shows the person. */
	public static Map<String, Object> read(PortalAuth.Session session, String pageKey) {
		PortalTemplate.PageSpec page = pageOf(session, pageKey);
		List<Object> fields = new List<Object>();
		for (PortalTemplate.FieldSpec spec : page.fields) {
			fields.add(fieldInfo(spec));
		}
		List<Object> records = new List<Object>();
		for (SObject record : query(page, session.personId(), null)) {
			records.add(valuesOf(page, record));
		}
		return new Map<String, Object>{
			'key' => page.key,
			'title' => page.title,
			'kind' => page.kind,
			'canUpdate' => page.canUpdate,
			'canCreate' => page.canCreate,
			'search' => page.search,
			'actions' => extensionList(page),
			'fields' => fields,
			'records' => records
		};
	}

	/**
	 * Saves the person's changes to one record of a page, or creates one on a related page when
	 * no record is named. Returns the record's id.
	 */
	public static Id save(
		PortalAuth.Session session,
		String pageKey,
		String recordId,
		Map<String, Object> values
	) {
		PortalTemplate.PageSpec page = pageOf(session, pageKey);
		SObject target;
		if (String.isBlank(recordId)) {
			if (!page.canCreate) {
				throw new PortalAuth.RefusalException('not_allowed');
			}
			target = page.objectType.newSObject();
			target.put(page.personField, session.personId());
		} else {
			if (!page.canUpdate) {
				throw new PortalAuth.RefusalException('not_allowed');
			}
			target = ownRecord(page, session.personId(), recordId);
		}
		applyValues(
			page,
			target,
			values == null ? new Map<String, Object>() : values,
			target.Id == null
		);
		Database.SaveResult result = target.Id == null
			? Database.insert(target, false, AccessLevel.SYSTEM_MODE)
			: Database.update(target, false, AccessLevel.SYSTEM_MODE);
		if (!result.isSuccess()) {
			ErrorLogger.logMessage(
				result.getErrors()[0].getMessage(),
				CONTEXT + '.save',
				ErrorLogger.SEVERITY_WARNING
			);
			throw new PortalAuth.RefusalException('save_failed');
		}
		return result.getId();
	}

	/** Runs a module's action on one record of a page, through Core's seam. */
	public static String runAction(
		PortalAuth.Session session,
		String pageKey,
		String recordId,
		String actionName
	) {
		PortalTemplate.PageSpec page = pageOf(session, pageKey);
		if (!page.extensionLabels.containsKey(actionName)) {
			throw new PortalAuth.RefusalException('not_allowed');
		}
		SObject record = ownRecord(page, session.personId(), recordId);
		PortalActionExtension extension = PortalActionExtensions.forAction(actionName);
		if (extension == null) {
			throw new PortalAuth.RefusalException('not_allowed');
		}
		System.Savepoint before = Database.setSavepoint();
		try {
			return extension.run(actionName, session.personId(), record.Id);
		} catch (Exception refused) {
			Database.rollback(before);
			ErrorLogger.log(refused, CONTEXT + '.runAction', record.Id);
			throw new PortalAuth.RefusalException('action_failed');
		}
	}

	// ---- Template and pages ---------------------------------------------------------------

	/** The portal's template, checked now; a broken one is logged and refused whole. */
	public static PortalTemplate templateOf(Portal__c portal) {
		PortalTemplate template;
		try {
			template = PortalTemplate.parse(portal.Template__c);
		} catch (PortalTemplate.TemplateException broken) {
			ErrorLogger.logMessage(
				portal.Name + ': ' + broken.getMessage(),
				CONTEXT + '.templateOf',
				ErrorLogger.SEVERITY_WARNING
			);
			throw new PortalAuth.RefusalException('portal_unavailable');
		}
		// A module that is not installed has no objects, so its pages already failed the checks
		// above; one installed but turned off closes the portal here.
		Set<String> off = ModuleManagerService.turnedOff();
		for (String module : template.requiresModules) {
			if (off.contains(module.toLowerCase())) {
				throw new PortalAuth.RefusalException('portal_unavailable');
			}
		}
		return template;
	}

	private static PortalTemplate.PageSpec pageOf(PortalAuth.Session session, String pageKey) {
		PortalTemplate.PageSpec page = templateOf(session.portal).page(pageKey);
		if (page == null) {
			throw new PortalAuth.RefusalException('not_found');
		}
		return page;
	}

	private static List<Map<String, Object>> extensionList(PortalTemplate.PageSpec page) {
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (String name : page.extensionLabels.keySet()) {
			out.add(
				new Map<String, Object>{ 'name' => name, 'label' => page.extensionLabels.get(name) }
			);
		}
		return out;
	}

	// ---- Reading --------------------------------------------------------------------------

	/** The page's records for the person, optionally only one record. */
	private static List<SObject> query(PortalTemplate.PageSpec page, Id personId, Id onlyId) {
		Set<String> columns = new Set<String>{ 'Id' };
		for (PortalTemplate.FieldSpec spec : page.fields) {
			columns.add(spec.path);
		}
		Map<String, Object> binds = new Map<String, Object>{ 'personId' => personId };
		List<String> filters = new List<String>();
		if (page.kind == PortalTemplate.KIND_PERSON) {
			filters.add('Id = :personId');
		} else if (page.kind == PortalTemplate.KIND_RELATED) {
			filters.add(page.personField + ' = :personId');
		}
		Integer index = 0;
		for (PortalTemplate.Condition condition : page.conditions) {
			filters.add(conditionSoql(condition, 'v' + index, binds));
			index++;
		}
		if (onlyId != null) {
			binds.put('onlyId', onlyId);
			filters.add('Id = :onlyId');
		}
		String soql =
			'SELECT ' +
			String.join(new List<String>(columns), ', ') +
			' FROM ' +
			page.objectType.getDescribe().getName() +
			(filters.isEmpty() ? '' : ' WHERE ' + String.join(filters, ' AND ')) +
			(page.orderBy == null ? '' : ' ORDER BY ' + page.orderBy) +
			' LIMIT ' +
			page.rowLimit;
		return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
	}

	@TestVisible
	private static String conditionSoql(
		PortalTemplate.Condition condition,
		String name,
		Map<String, Object> binds
	) {
		if (condition.op == 'isBlank') {
			return condition.field + ' = null';
		}
		if (condition.op == 'isNotBlank') {
			return condition.field + ' != null';
		}
		// The value was typed for its field when the template was read; only the words are left.
		Object value = condition.value;
		Boolean isDate = condition.fieldType == Schema.DisplayType.DATE;
		if (PortalTemplate.TODAY.equals(value)) {
			value = isDate
				? (Object) Date.today()
				: (Object) Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
		} else if (PortalTemplate.NOW.equals(value)) {
			value = isDate ? (Object) Date.today() : (Object) Datetime.now();
		}
		binds.put(name, value);
		Map<String, String> operators = new Map<String, String>{
			'equals' => ' = :',
			'notEquals' => ' != :',
			'greaterOrEqual' => ' >= :',
			'lessOrEqual' => ' <= :'
		};
		return condition.field + operators.get(condition.op) + name;
	}

	/** The record if it is on this page for this person, or `not_found`. */
	private static SObject ownRecord(PortalTemplate.PageSpec page, Id personId, String recordId) {
		Id parsed;
		try {
			parsed = Id.valueOf(recordId);
		} catch (Exception notAnId) {
			throw new PortalAuth.RefusalException('not_found');
		}
		if (parsed.getSObjectType() != page.objectType) {
			throw new PortalAuth.RefusalException('not_found');
		}
		List<SObject> found = query(page, personId, parsed);
		if (found.isEmpty()) {
			throw new PortalAuth.RefusalException('not_found');
		}
		return found[0];
	}

	private static Map<String, Object> valuesOf(PortalTemplate.PageSpec page, SObject record) {
		Map<String, Object> values = new Map<String, Object>();
		for (PortalTemplate.FieldSpec spec : page.fields) {
			values.put(spec.path, valueAt(record, spec.path));
		}
		return new Map<String, Object>{ 'id' => record.Id, 'values' => values };
	}

	private static Object valueAt(SObject record, String path) {
		if (!path.contains('.')) {
			return record.get(path);
		}
		SObject parent = record.getSObject(path.substringBefore('.'));
		return parent == null ? null : parent.get(path.substringAfter('.'));
	}

	private static Map<String, Object> fieldInfo(PortalTemplate.FieldSpec spec) {
		Map<String, Object> info = new Map<String, Object>{
			'field' => spec.path,
			'label' => spec.label,
			'type' => String.valueOf(spec.describe.getType()).toLowerCase(),
			'edit' => spec.edit,
			'required' => spec.required
		};
		if (!spec.describe.getPicklistValues().isEmpty()) {
			List<Map<String, String>> options = new List<Map<String, String>>();
			for (Schema.PicklistEntry entry : spec.describe.getPicklistValues()) {
				if (entry.isActive()) {
					options.add(
						new Map<String, String>{
							'value' => entry.getValue(),
							'label' => entry.getLabel()
						}
					);
				}
			}
			info.put('options', options);
		}
		return info;
	}

	// ---- Writing --------------------------------------------------------------------------

	/** Puts the editable values on the record, coerced to each field's type; others refused. */
	private static void applyValues(
		PortalTemplate.PageSpec page,
		SObject target,
		Map<String, Object> values,
		Boolean creating
	) {
		for (String key : values.keySet()) {
			PortalTemplate.FieldSpec spec = page.field(key);
			if (spec == null || !spec.edit) {
				throw new PortalAuth.RefusalException('not_allowed');
			}
			target.put(spec.describe.getName(), coerce(spec.describe, values.get(key)));
		}
		for (PortalTemplate.FieldSpec spec : page.fields) {
			if (spec.edit && spec.required && (creating || values.containsKey(spec.path))) {
				Object value = target.get(spec.describe.getName());
				if (value == null || (value instanceof String && String.isBlank((String) value))) {
					throw new PortalAuth.RefusalException('required_missing');
				}
			}
		}
	}

	@TestVisible
	private static Object coerce(Schema.DescribeFieldResult field, Object raw) {
		if (raw == null || (raw instanceof String && String.isBlank((String) raw))) {
			return field.getType() == Schema.DisplayType.BOOLEAN ? (Object) false : null;
		}
		String text = String.valueOf(raw).trim();
		try {
			switch on field.getType() {
				when BOOLEAN {
					return raw == true || text == 'true';
				}
				when DATE {
					return Date.valueOf(text);
				}
				when DATETIME {
					return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
				}
				when DOUBLE {
					return Decimal.valueOf(text);
				}
				when INTEGER {
					// A whole-number field takes an Integer: a Decimal put on it fails the save.
					return Integer.valueOf(text);
				}
				when PICKLIST {
					return allowedOption(field, text);
				}
				when MULTIPICKLIST {
					List<String> chosen = new List<String>();
					for (String part : text.split(';')) {
						chosen.add(allowedOption(field, part.trim()));
					}
					return String.join(chosen, ';');
				}
				when else {
					if (text.length() > field.getLength() && field.getLength() > 0) {
						throw new PortalAuth.RefusalException('invalid_value');
					}
					return text;
				}
			}
		} catch (PortalAuth.RefusalException refusal) {
			throw refusal;
		} catch (Exception unreadable) {
			throw new PortalAuth.RefusalException('invalid_value');
		}
	}

	private static String allowedOption(Schema.DescribeFieldResult field, String value) {
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (entry.isActive() && entry.getValue() == value) {
				return value;
			}
		}
		throw new PortalAuth.RefusalException('invalid_value');
	}
}
