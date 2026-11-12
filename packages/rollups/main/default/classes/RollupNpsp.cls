/**
 * NPSP Customizable Rollups in this org, read into the DLRS definition shape and never changed
 * (MIG-08, canonical model R-R16), so Import From NPSP and the same-field guard reuse the DLRS
 * code unchanged.
 *
 * NPSP keeps its rollups and filter rules in custom metadata types of its `npsp` namespace. They
 * are found through describe by names built at run time and read with dynamic SOQL in system mode
 * (configuration, as DLRS's is), so this class compiles and returns nothing without NPSP. Only
 * the fields the installed NPSP version has are read.
 *
 * A rollup BarnCRM cannot copy keeps its values and says why in `unsupported`, so the import
 * lists it as staying in NPSP and the guard still sees the field it fills.
 */
public with sharing class RollupNpsp implements RollupDlrs.Reader {
	private static final String PREFIX = 'npsp__';
	private static final String MERGE_SURVIVOR_FIELD = 'MasterRecordId';
	private static final String GIFT_OBJECT = 'Opportunity'; // detection-only: compared with the Detail Object name NPSP stores; nothing reads Opportunity
	private static final List<String> ROLLUP_FIELDS = new List<String>{
		'Active',
		'Description',
		'Filter_Group',
		'Integer',
		'Is_Deleted',
		'Operation',
		'Time_Bound_Operation_Type',
		'Use_Fiscal_Year'
	};
	private static final List<String> ROLLUP_RELATIONS = new List<String>{
		'Amount_Field',
		'Amount_Object',
		'Date_Field',
		'Date_Object',
		'Detail_Field',
		'Detail_Object',
		'Summary_Field',
		'Summary_Object'
	};
	private static final List<String> RULE_FIELDS = new List<String>{
		'Constant',
		'Filter_Group',
		'Is_Deleted',
		'Operator'
	};
	private static final List<String> RULE_RELATIONS = new List<String>{ 'Field', 'Object' };

	/** NPSP's operations, lower case, in DLRS's words, which the DLRS import maps. */
	private static final Map<String, String> OPERATION_BY_NPSP = new Map<String, String>{
		'sum' => 'Sum',
		'count' => 'Count',
		'average' => 'Avg',
		'largest' => 'Max',
		'smallest' => 'Min',
		'first' => 'First',
		'last' => 'Last'
	};
	/** The operations that read Detail Field, when it is set, rather than Amount Field. */
	private static final Set<String> PICKS = new Set<String>{ 'Max', 'Min', 'First', 'Last' };
	private static final Map<String, String> COMPARISON_BY_OPERATOR = new Map<String, String>{
		'equals' => '=',
		'not_equals' => '!=',
		'greater' => '>',
		'less' => '<',
		'greater_or_equal' => '>=',
		'less_or_equal' => '<='
	};
	private static final Map<String, String> LIST_BY_OPERATOR = new Map<String, String>{
		'in_list' => 'IN',
		'not_in_list' => 'NOT IN'
	};
	private static final Set<Schema.DisplayType> UNQUOTED = new Set<Schema.DisplayType>{
		Schema.DisplayType.BOOLEAN,
		Schema.DisplayType.CURRENCY,
		Schema.DisplayType.DATE,
		Schema.DisplayType.DATETIME,
		Schema.DisplayType.DOUBLE,
		Schema.DisplayType.INTEGER,
		Schema.DisplayType.LONG,
		Schema.DisplayType.PERCENT
	};

	/** Why a rollup stays in NPSP, in words. */
	private class UnsupportedException extends Exception {
	}

	public List<RollupDlrs.Definition> read() {
		return toDefinitions(
			readRows('Rollup__mdt', ROLLUP_FIELDS, ROLLUP_RELATIONS),
			readRows('Filter_Rule__mdt', RULE_FIELDS, RULE_RELATIONS)
		);
	}

	/**
	 * The rows of one NPSP type, keyed by field name without namespace or suffix; a related
	 * object or field is its API name. Empty without NPSP. The names are this class's constants,
	 * kept only when describe finds them, so nothing user supplied reaches the query, which has
	 * no values to bind.
	 */
	private static List<Map<String, Object>> readRows(
		String localType,
		List<String> plain,
		List<String> related
	) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		Schema.SObjectType type = NamespaceUtil.globalDescribe()
			.get((PREFIX + localType).toLowerCase());
		if (type == null) {
			return found;
		}
		Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
			.fields.getMap();
		List<String> selected = new List<String>{ 'DeveloperName', 'MasterLabel' };
		List<String> plainHere = new List<String>();
		List<String> relatedHere = new List<String>();
		for (String name : plain) {
			if (fields.containsKey((PREFIX + name + '__c').toLowerCase())) {
				selected.add(PREFIX + name + '__c');
				plainHere.add(name);
			}
		}
		for (String name : related) {
			if (fields.containsKey((PREFIX + name + '__c').toLowerCase())) {
				selected.add(PREFIX + name + '__r.QualifiedApiName');
				relatedHere.add(name);
			}
		}
		String query =
			'SELECT ' +
			String.join(selected, ', ') +
			' FROM ' +
			PREFIX +
			localType +
			' LIMIT 2000';
		for (
			SObject row : Database.queryWithBinds(
				query,
				new Map<String, Object>(),
				AccessLevel.SYSTEM_MODE
			)
		) {
			Map<String, Object> values = new Map<String, Object>{
				'DeveloperName' => row.get('DeveloperName'),
				'MasterLabel' => row.get('MasterLabel')
			};
			for (String name : plainHere) {
				values.put(name, row.get(PREFIX + name + '__c'));
			}
			for (String name : relatedHere) {
				SObject target = row.getSObject(PREFIX + name + '__r');
				values.put(name, target == null ? null : target.get('QualifiedApiName'));
			}
			found.add(values);
		}
		return found;
	}

	/** The rollups not deleted, each with its filter group's rules. Visible to tests. */
	@TestVisible
	private static List<RollupDlrs.Definition> toDefinitions(
		List<Map<String, Object>> rollups,
		List<Map<String, Object>> rules
	) {
		Map<String, List<Map<String, Object>>> rulesByGroup = new Map<String, List<Map<String, Object>>>();
		for (Map<String, Object> rule : rules) {
			String filterGroup = text(rule, 'Filter_Group');
			if (rule.get('Is_Deleted') != true && filterGroup != null) {
				if (!rulesByGroup.containsKey(filterGroup)) {
					rulesByGroup.put(filterGroup, new List<Map<String, Object>>());
				}
				rulesByGroup.get(filterGroup).add(rule);
			}
		}
		List<RollupDlrs.Definition> found = new List<RollupDlrs.Definition>();
		for (Map<String, Object> rollup : rollups) {
			if (rollup.get('Is_Deleted') == true) {
				continue;
			}
			RollupDlrs.Definition definition = new RollupDlrs.Definition();
			definition.key = text(rollup, 'DeveloperName');
			definition.label = text(rollup, 'MasterLabel');
			definition.source = RollupDlrs.SOURCE_NPSP;
			definition.active = rollup.get('Active') == true;
			definition.parentObject = text(rollup, 'Summary_Object');
			definition.aggregateResultField = text(rollup, 'Summary_Field');
			definition.childObject = text(rollup, 'Detail_Object');
			definition.description = text(rollup, 'Description');
			List<Map<String, Object>> groupRules = rulesByGroup.get(text(rollup, 'Filter_Group'));
			try {
				mapRollup(
					definition,
					rollup,
					groupRules == null ? new List<Map<String, Object>>() : groupRules
				);
			} catch (UnsupportedException refused) {
				definition.unsupported = refused.getMessage();
			}
			found.add(definition);
		}
		return found;
	}

	/** The operation, field, order, lookup and criteria, or why there is no copy. */
	private static void mapRollup(
		RollupDlrs.Definition definition,
		Map<String, Object> rollup,
		List<Map<String, Object>> rules
	) {
		String npspOperation = text(rollup, 'Operation');
		String operation = OPERATION_BY_NPSP.get(
			npspOperation == null ? '' : npspOperation.toLowerCase()
		);
		if (operation == null) {
			throw unsupported(
				BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOperation'),
				npspOperation
			);
		}
		String detail = definition.childObject;
		for (String side : new List<String>{ 'Amount_Object', 'Date_Object' }) {
			String other = text(rollup, side);
			if (other != null && !other.equalsIgnoreCase(detail)) {
				throw unsupported(
					BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOtherObject'),
					other
				);
			}
		}
		if (
			'Contact'.equalsIgnoreCase(definition.parentObject) &&
			GIFT_OBJECT.equalsIgnoreCase(detail)
		) {
			throw unsupported(BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonContact'), null);
		}
		if (rollup.get('Use_Fiscal_Year') == true) {
			throw unsupported(BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonFiscalYear'), null);
		}
		Schema.SObjectType detailType = SettingsService.typeByName(detail);
		definition.relationshipField = lookupTo(detailType, definition.parentObject);
		if (definition.relationshipField == null) {
			throw unsupported(BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonNoLookup'), detail);
		}
		definition.aggregateOperation = operation;
		String amountField = text(rollup, 'Amount_Field');
		String detailField = text(rollup, 'Detail_Field');
		if (operation != 'Count') {
			definition.fieldToAggregate = PICKS.contains(operation) && detailField != null
				? detailField
				: (amountField != null ? amountField : detailField);
		}
		String dateField = text(rollup, 'Date_Field');
		if ((operation == 'First' || operation == 'Last') && dateField != null) {
			definition.fieldToOrderBy = dateField + ' ASC NULLS LAST';
		}
		List<String> clauses = new List<String>();
		String bound = timeBound(rollup, dateField);
		if (bound != null) {
			clauses.add(bound);
		}
		for (Map<String, Object> rule : rules) {
			clauses.add(clause(rule, detail, detailType));
		}
		definition.relationshipCriteria = clauses.isEmpty() ? null : String.join(clauses, ' AND ');
	}

	/** All Time adds nothing; Years Ago 0 or 1 and Days Back n read Date Field. */
	private static String timeBound(Map<String, Object> rollup, String dateField) {
		String type = text(rollup, 'Time_Bound_Operation_Type');
		if (type == null || type.equalsIgnoreCase('All_Time')) {
			return null;
		}
		Object amount = rollup.get('Integer');
		Integer count = amount instanceof Decimal ? ((Decimal) amount).intValue() : 0;
		String literal;
		if (type.equalsIgnoreCase('Years_Ago') && count <= 1) {
			literal = count == 1 ? 'LAST_YEAR' : 'THIS_YEAR';
		} else if (type.equalsIgnoreCase('Days_Back') && count > 0) {
			literal = 'LAST_N_DAYS:' + count;
		}
		if (literal == null || dateField == null) {
			throw unsupported(
				BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonTimeBound'),
				type + ' ' + count
			);
		}
		return dateField + ' = ' + literal;
	}

	/** One filter rule as a DLRS criteria condition, on the counted records only. */
	private static String clause(
		Map<String, Object> rule,
		String detail,
		Schema.SObjectType detailType
	) {
		String ruleObject = text(rule, 'Object');
		if (ruleObject != null && !ruleObject.equalsIgnoreCase(detail)) {
			throw unsupported(
				BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOtherObject'),
				ruleObject
			);
		}
		String field = text(rule, 'Field');
		String npspOperator = text(rule, 'Operator');
		String operator = npspOperator == null ? '' : npspOperator.toLowerCase();
		Schema.SObjectField token = field == null ||
			detailType == null
			? null
			: detailType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.fields.getMap()
					.get(field.toLowerCase());
		if (token == null) {
			throw unsupported(
				BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOperator'),
				npspOperator
			);
		}
		Object constantValue = rule.get('Constant');
		String constant = constantValue == null ? '' : String.valueOf(constantValue);
		List<String> values = new List<String>();
		for (String value : constant.split(';')) {
			if (String.isNotBlank(value)) {
				values.add(value.trim());
			}
		}
		if (field.equalsIgnoreCase('RecordTypeId')) {
			values = recordTypeIds(detailType, values);
		}
		if (LIST_BY_OPERATOR.containsKey(operator) && !values.isEmpty()) {
			List<String> literals = new List<String>();
			for (String value : values) {
				literals.add(literal(token, value));
			}
			return field +
				' ' +
				LIST_BY_OPERATOR.get(operator) +
				' (' +
				String.join(literals, ', ') +
				')';
		}
		if (COMPARISON_BY_OPERATOR.containsKey(operator) && values.size() <= 1) {
			String value = values.isEmpty() ? null : values[0];
			return field + ' ' + COMPARISON_BY_OPERATOR.get(operator) + ' ' + literal(token, value);
		}
		if ((operator == 'starts_with' || operator == 'contains') && values.size() == 1) {
			String start = operator == 'contains' ? '%' : '';
			return field + ' LIKE \'' + start + String.escapeSingleQuotes(values[0]) + '%\'';
		}
		throw unsupported(BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonOperator'), npspOperator);
	}

	/** NPSP names record types by developer name or name; BarnCRM filters by Id. */
	private static List<String> recordTypeIds(Schema.SObjectType type, List<String> names) {
		Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
		Map<String, Schema.RecordTypeInfo> byDeveloperName = describe.getRecordTypeInfosByDeveloperName();
		Map<String, Schema.RecordTypeInfo> byName = describe.getRecordTypeInfosByName();
		List<String> ids = new List<String>();
		for (String name : names) {
			Schema.RecordTypeInfo info = byDeveloperName.containsKey(name)
				? byDeveloperName.get(name)
				: byName.get(name);
			if (info == null) {
				throw unsupported(
					BarnHelp.text('Rollups', 'Core_RollupNpsp_ReasonRecordType'),
					name
				);
			}
			ids.add(info.getRecordTypeId());
		}
		return ids;
	}

	/**
	 * The single lookup from the counted records to the summary object, standard first.
	 * `MasterRecordId` is not a parent: the platform fills it only on a record deleted by a
	 * merge, naming the survivor, so an Account or Contact rolling up into its own object is not
	 * refused for having two standard lookups.
	 */
	private static String lookupTo(Schema.SObjectType detailType, String summary) {
		Schema.SObjectType summaryType = SettingsService.typeByName(summary);
		if (detailType == null || summaryType == null) {
			return null;
		}
		List<String> standard = new List<String>();
		List<String> custom = new List<String>();
		for (
			Schema.SObjectField token : detailType.getDescribe(SObjectDescribeOptions.DEFERRED)
				.fields.getMap()
				.values()
		) {
			Schema.DescribeFieldResult field = token.getDescribe();
			if (
				field.getReferenceTo().contains(summaryType) &&
				field.getName() != MERGE_SURVIVOR_FIELD
			) {
				if (field.isCustom()) {
					custom.add(field.getName());
				} else {
					standard.add(field.getName());
				}
			}
		}
		List<String> chosen = standard.isEmpty() ? custom : standard;
		return chosen.size() == 1 ? chosen[0] : null;
	}

	private static String literal(Schema.SObjectField token, String value) {
		if (String.isBlank(value)) {
			return 'null';
		}
		return UNQUOTED.contains(token.getDescribe().getType())
			? value
			: '\'' + String.escapeSingleQuotes(value) + '\'';
	}

	private static UnsupportedException unsupported(String template, String value) {
		return new UnsupportedException(
			value == null ? template : String.format(template, new List<String>{ value })
		);
	}

	private static String text(Map<String, Object> values, String name) {
		Object value = values.get(name);
		return value == null || String.isBlank(String.valueOf(value))
			? null
			: String.valueOf(value).trim();
	}
}
