/**
 * The LWC Builder's Apex (LB-01 to LB-05; ADR-0203 `0203-lwc-builder-module.md`): the builder's
 * list and save, and what the packaged renderer reads for a built component and its blocks.
 *
 * Every read and write is the running user's (user mode, with sharing), so a built component
 * never shows more than its viewer could open (R-LB2). The definition document's shape is the
 * `lwcBuilderModel` module's to check; this class only refuses what is not a definition at all.
 * List queries name only fields the schema holds, bind the filter value and stop at Rows per
 * List.
 */
public with sharing class LwcBuilderController {
	private static final String CONTEXT = 'LwcBuilderController';
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
			CONTEXT,
			'LwcBuilder',
			'LwcBuilder_Error_Generic'
		)
		.showingDml();
	@TestVisible
	private static final String SETTINGS_OBJECT = 'LWC_Builder_Settings__c';
	@TestVisible
	private static final Integer SCHEMA_VERSION = 1;
	private static final Integer MAX_COLUMNS = 6;
	private static final Integer MAX_ROWS = 200;
	private static final Integer MAX_MEASURES = 3;
	private static final Integer MAX_SERIES = 12;
	private static final Integer MAX_DEFINITION = 131072;
	private static final Pattern API_NAME = Pattern.compile('[A-Za-z][A-Za-z0-9_.]{0,79}');

	/** A refusal written for the person, shown as it is. */
	public class LwcBuilderException extends Exception {
	}

	/** The builder's page: every built component, active or not, and the settings. */
	@AuraEnabled
	public static Map<String, Object> getStudio() {
		try {
			List<Map<String, Object>> rows = new List<Map<String, Object>>();
			for (Built_Component__c row : [
				SELECT
					Id,
					Name,
					Key__c,
					Description__c,
					Object_Name__c,
					Active__c,
					Version__c,
					Definition__c
				FROM Built_Component__c
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				rows.add(shape(row));
			}
			return new Map<String, Object>{
				'components' => rows,
				'sourceExport' => flag('Source_Export__c'),
				'rowsPerList' => rowsPerList(),
				'canEdit' => Schema.SObjectType.Built_Component__c.isUpdateable()
			};
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * Saves a component from the builder: `{id, name, key, description, objectName, active,
	 * definition}`, the definition a JSON object. Raises the version by one and returns the row.
	 */
	@AuraEnabled
	public static Map<String, Object> saveComponent(String componentJson) {
		try {
			Map<String, Object> input = asMap(parse(componentJson));
			String name = text(input.get('name'));
			String key = text(input.get('key'));
			String objectName = text(input.get('objectName'));
			if (String.isBlank(name)) {
				throw refusal(BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_NameNeeded'));
			}
			if (!isKey(key) || key.contains('.')) {
				throw refusal(BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Key'));
			}
			if (String.isNotBlank(objectName) && NamespaceUtil.objectType(objectName) == null) {
				throw refusal(
					BarnHelp.text(
						'LwcBuilder',
						'LwcBuilder_Error_Object',
						new List<Object>{ objectName }
					)
				);
			}
			String body = JSON.serialize(checkedDefinition(input.get('definition')));
			if (body.length() > MAX_DEFINITION) {
				throw refusal(BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_TooLarge'));
			}
			Id recordId = String.isBlank(text(input.get('id')))
				? null
				: Id.valueOf(text(input.get('id')));
			Decimal version = 0;
			if (recordId != null) {
				for (Built_Component__c existing : [
					SELECT Version__c
					FROM Built_Component__c
					WHERE Id = :recordId
					WITH USER_MODE
				]) {
					version = existing.Version__c == null ? 0 : existing.Version__c;
				}
			}
			Built_Component__c row = new Built_Component__c(
				Id = recordId,
				Name = name.left(80),
				Key__c = key,
				Description__c = text(input.get('description')).left(255),
				Object_Name__c = objectName,
				Active__c = input.get('active') != false,
				Version__c = version + 1,
				Definition__c = body
			);
			try {
				upsert as user row;
			} catch (DmlException e) {
				if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
					throw refusal(
						BarnHelp.text(
							'LwcBuilder',
							'LwcBuilder_Error_KeyUsed',
							new List<Object>{ key }
						)
					);
				}
				throw e;
			}
			return shape(row);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * What the renderer shows for a key: `enabled` false when Show Built Components is off,
	 * `found` false when the component is missing, inactive or not readable by this user.
	 */
	@AuraEnabled
	public static Map<String, Object> loadComponent(String componentKey) {
		try {
			Map<String, Object> result = new Map<String, Object>{
				'enabled' => flag('Components_Enabled__c'),
				'found' => false
			};
			if (result.get('enabled') == false || !isKey(componentKey)) {
				return result;
			}
			for (Built_Component__c row : [
				SELECT
					Id,
					Name,
					Key__c,
					Description__c,
					Object_Name__c,
					Active__c,
					Version__c,
					Definition__c
				FROM Built_Component__c
				WHERE Key__c = :componentKey AND Active__c = TRUE
				WITH USER_MODE
				LIMIT 1
			]) {
				result.putAll(shape(row));
				result.put('found', true);
			}
			return result;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Whether the running user holds each named custom permission (LB-05). Unknown is false. */
	@AuraEnabled
	public static Map<String, Boolean> checkPermissions(List<String> names) {
		Map<String, Boolean> held = new Map<String, Boolean>();
		for (String name : names == null ? new List<String>() : names) {
			if (held.size() >= 50 || !isKey(name)) {
				continue;
			}
			try {
				held.put(name, FeatureManagement.checkPermission(name));
			} catch (Exception unknown) {
				held.put(name, false);
			}
		}
		return held;
	}

	/**
	 * Rows for a Related List or Record List block (LB-03). `requestJson`: `{object, fields,
	 * parentField, recordId, filterField, filterOperator, filterValue, orderBy, direction}`.
	 * Returns `{columns: [{fieldName, label, type, isName}], rows}`; a field the user cannot read
	 * is left out, as Lightning Data Service leaves it out.
	 */
	@AuraEnabled
	public static Map<String, Object> loadRecords(String requestJson) {
		try {
			Map<String, Object> request = asMap(parse(requestJson));
			String objectName = text(request.get('object'));
			Schema.SObjectType type = isKey(objectName)
				? NamespaceUtil.objectType(objectName)
				: null;
			if (type == null) {
				throw refusal(
					BarnHelp.text(
						'LwcBuilder',
						'LwcBuilder_Error_Object',
						new List<Object>{ objectName }
					)
				);
			}
			Map<String, Schema.SObjectField> fields = type.getDescribe(
					SObjectDescribeOptions.DEFERRED
				)
				.fields.getMap();
			List<Object> asked = request.get('fields') instanceof List<Object>
				? (List<Object>) request.get('fields')
				: new List<Object>();
			List<Map<String, Object>> columns = new List<Map<String, Object>>();
			Set<String> selected = new Set<String>{ 'Id' };
			for (Object item : asked) {
				Schema.DescribeFieldResult field = describe(fields, text(item), objectName);
				if (
					columns.size() < MAX_COLUMNS &&
					field.isAccessible() &&
					selected.add(field.getName())
				) {
					columns.add(
						new Map<String, Object>{
							'fieldName' => field.getName(),
							'label' => field.getLabel(),
							'type' => String.valueOf(field.getType()).toLowerCase(),
							'isName' => field.isNameField()
						}
					);
				}
			}
			Map<String, Object> binds = new Map<String, Object>();
			List<String> conditions = new List<String>();
			String parentField = text(request.get('parentField'));
			if (String.isNotBlank(parentField)) {
				String parentId = text(request.get('recordId'));
				binds.put('parentId', String.isBlank(parentId) ? null : parentId);
				conditions.add(
					describe(fields, parentField, objectName).getName() + ' = :parentId'
				);
			}
			String filterField = text(request.get('filterField'));
			if (String.isNotBlank(filterField)) {
				Schema.DescribeFieldResult filter = describe(fields, filterField, objectName);
				binds.put('filterValue', typed(filter, text(request.get('filterValue'))));
				String operator = text(request.get('filterOperator')) == 'notEquals'
					? ' != '
					: ' = ';
				conditions.add(filter.getName() + operator + ':filterValue');
			}
			String query =
				'SELECT ' +
				String.join(new List<String>(selected), ', ') +
				' FROM ' +
				String.valueOf(type);
			if (!conditions.isEmpty()) {
				query += ' WHERE ' + String.join(conditions, ' AND ');
			}
			String orderBy = text(request.get('orderBy'));
			if (String.isNotBlank(orderBy)) {
				Schema.DescribeFieldResult sortField = describe(fields, orderBy, objectName);
				if (sortField.isSortable()) {
					String direction = text(request.get('direction')) == 'desc' ? ' DESC' : ' ASC';
					query += ' ORDER BY ' + sortField.getName() + direction + ' NULLS LAST';
				}
			}
			query += ' LIMIT ' + rowsPerList();
			return new Map<String, Object>{
				'columns' => columns,
				'rows' => Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)
			};
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * A Report Chart block (LB-03, LB-07; D-196): a standard summary or matrix report, by its API
	 * name, run once as the user. Up to two groupings (a summary report's first two row
	 * groupings, or a matrix report's first row and first column grouping) and its first three
	 * summaries. Returns `{title, measures, series, groups: [{label, cells}]}`: `cells` holds one
	 * list per series (one list with a single grouping) of `{value, label}` per measure. At most
	 * 200 groups and 12 series; `lwcBuilderModel.chartView` lays them out.
	 */
	@AuraEnabled
	public static Map<String, Object> loadChart(String reportName) {
		try {
			// Report is queried by string, as Org Optimizer does: no compile-time reference.
			List<SObject> found = isKey(reportName)
				? Database.queryWithBinds(
						'SELECT Id, Name FROM Report WHERE DeveloperName = :reportName LIMIT 1',
						new Map<String, Object>{ 'reportName' => reportName },
						AccessLevel.USER_MODE
				  )
				: new List<SObject>();
			if (found.isEmpty()) {
				throw refusal(
					BarnHelp.text(
						'LwcBuilder',
						'LwcBuilder_Chart_NoReport',
						new List<Object>{ reportName }
					)
				);
			}
			String title = (String) found[0].get('Name');
			Reports.ReportResults results = Reports.ReportManager.runReport(found[0].Id, false);
			Reports.ReportMetadata metadata = results.getReportMetadata();
			List<Reports.GroupingValue> groups = results.getGroupingsDown().getGroupings();
			if (
				metadata.getReportFormat() == Reports.ReportFormat.TABULAR ||
				groups == null ||
				groups.isEmpty() ||
				metadata.getAggregates().isEmpty()
			) {
				throw refusal(
					BarnHelp.text(
						'LwcBuilder',
						'LwcBuilder_Chart_NotChartable',
						new List<Object>{ title }
					)
				);
			}
			List<String> measures = new List<String>();
			for (String aggregate : metadata.getAggregates()) {
				if (measures.size() < MAX_MEASURES) {
					measures.add(
						results.getReportExtendedMetadata()
							.getAggregateColumnInfo()
							.get(aggregate)
							.getLabel()
					);
				}
			}
			// The second grouping: a matrix report's first column grouping, or a summary
			// report's second row grouping. Series are named in the order they first appear.
			Map<String, Reports.ReportFact> facts = results.getFactMap();
			List<String> series = new List<String>();
			List<Reports.GroupingValue> across = metadata.getReportFormat() ==
				Reports.ReportFormat.MATRIX
				? results.getGroupingsAcross().getGroupings()
				: null;
			Map<String, List<Object>> cellsByKey = new Map<String, List<Object>>();
			for (String key : facts.keySet()) {
				cellsByKey.put(key, cell(facts.get(key), measures.size()));
			}
			List<Map<String, Object>> rows = chartRows(
				plainGroupings(groups),
				plainGroupings(across),
				cellsByKey,
				series
			);
			return new Map<String, Object>{
				'title' => title,
				'measures' => measures,
				'series' => series,
				'groups' => rows
			};
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Report groupings as plain maps `{key, label, children}`, with one level of children. */
	private static List<Map<String, Object>> plainGroupings(List<Reports.GroupingValue> values) {
		List<Map<String, Object>> result = new List<Map<String, Object>>();
		for (
			Reports.GroupingValue value : values == null
				? new List<Reports.GroupingValue>()
				: values
		) {
			List<Map<String, Object>> children = new List<Map<String, Object>>();
			for (
				Reports.GroupingValue child : value.getGroupings() == null
					? new List<Reports.GroupingValue>()
					: value.getGroupings()
			) {
				children.add(
					new Map<String, Object>{ 'key' => child.getKey(), 'label' => child.getLabel() }
				);
			}
			result.add(
				new Map<String, Object>{
					'key' => value.getKey(),
					'label' => value.getLabel(),
					'children' => children
				}
			);
		}
		return result;
	}

	/**
	 * The chart's rows from plain inputs: the groupings down and across as `{key, label,
	 * children}` and each fact's cells by fact key. A matrix's columns are the series (up to 12);
	 * otherwise a second grouping's values are, added to `series` as they are first met. At most
	 * 200 rows. A fact with no cells gives an empty cell.
	 */
	@TestVisible
	private static List<Map<String, Object>> chartRows(
		List<Map<String, Object>> groups,
		List<Map<String, Object>> across,
		Map<String, List<Object>> cellsByKey,
		List<String> series
	) {
		List<Map<String, Object>> columns = new List<Map<String, Object>>();
		for (
			Map<String, Object> column : across == null ? new List<Map<String, Object>>() : across
		) {
			if (columns.size() < MAX_SERIES) {
				columns.add(column);
				series.add((String) column.get('label'));
			}
		}
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		for (Map<String, Object> grouping : groups) {
			if (rows.size() == MAX_ROWS) {
				break;
			}
			List<Object> cells = new List<Object>();
			List<Map<String, Object>> children = (List<Map<String, Object>>) grouping.get(
				'children'
			);
			if (!columns.isEmpty()) {
				for (Map<String, Object> column : columns) {
					cells.add(cellFor(cellsByKey, grouping.get('key') + '!' + column.get('key')));
				}
			} else if (children != null && !children.isEmpty()) {
				for (Map<String, Object> child : children) {
					Integer lane = series.indexOf((String) child.get('label'));
					if (lane < 0 && series.size() < MAX_SERIES) {
						series.add((String) child.get('label'));
						lane = series.size() - 1;
					}
					while (lane >= 0 && cells.size() <= lane) {
						cells.add(null);
					}
					if (lane >= 0) {
						cells[lane] = cellFor(cellsByKey, child.get('key') + '!T');
					}
				}
			} else {
				cells.add(cellFor(cellsByKey, grouping.get('key') + '!T'));
			}
			rows.add(new Map<String, Object>{ 'label' => grouping.get('label'), 'cells' => cells });
		}
		return rows;
	}

	private static List<Object> cellFor(Map<String, List<Object>> cellsByKey, Object key) {
		List<Object> cells = cellsByKey.get(String.valueOf(key));
		return cells == null ? new List<Object>() : cells;
	}

	/** One report cell as `[{value, label}]`, one per measure; an empty cell is an empty list. */
	@TestVisible
	private static List<Object> cell(Reports.ReportFact fact, Integer measures) {
		List<Object> values = new List<Object>();
		List<Reports.SummaryValue> summaries = fact == null
			? new List<Reports.SummaryValue>()
			: fact.getAggregates();
		for (Integer m = 0; m < measures && m < summaries.size(); m++) {
			values.add(
				new Map<String, Object>{
					'value' => summaries[m].getValue(),
					'label' => summaries[m].getLabel()
				}
			);
		}
		return values;
	}

	/** Rows per List, 1 to 200; blank or unreadable is 10. */
	@TestVisible
	private static Integer rowsPerList() {
		return SettingsService.number(SETTINGS_OBJECT, 'Rows_Per_List__c').intValue();
	}

	/** A checkbox setting; both ship on, so blank or unreadable is on. */
	private static Boolean flag(String key) {
		try {
			Object stored = SettingsService.getValue(SETTINGS_OBJECT, key);
			return stored == null || Boolean.valueOf(String.valueOf(stored));
		} catch (Exception unreadable) {
			return true;
		}
	}

	/** The definition as a map, refused unless it is a schema version 1 document with sections. */
	private static Map<String, Object> checkedDefinition(Object definition) {
		Object parsed = definition instanceof String ? parse((String) definition) : definition;
		Map<String, Object> document = asMap(parsed);
		if (
			document.get('schemaVersion') != SCHEMA_VERSION ||
			!(document.get('sections') instanceof List<Object>)
		) {
			throw refusal(BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Definition'));
		}
		return document;
	}

	private static Schema.DescribeFieldResult describe(
		Map<String, Schema.SObjectField> fields,
		String name,
		String objectName
	) {
		Schema.SObjectField field = isKey(name) ? fields.get(name.toLowerCase()) : null;
		if (field == null) {
			throw refusal(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Error_Field',
					new List<Object>{ name, objectName }
				)
			);
		}
		return field.getDescribe();
	}

	/** The filter value as the field's type, so the bind compares like with like. */
	private static Object typed(Schema.DescribeFieldResult field, String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			switch on field.getType() {
				when BOOLEAN {
					return Boolean.valueOf(value);
				}
				when DOUBLE, CURRENCY, PERCENT, INTEGER, LONG {
					return Decimal.valueOf(value);
				}
				when DATE {
					return Date.valueOf(value);
				}
				when else {
					return value;
				}
			}
		} catch (TypeException e) {
			throw refusal(
				BarnHelp.text(
					'LwcBuilder',
					'LwcBuilder_Error_FilterValue',
					new List<Object>{ value, field.getLabel() }
				)
			);
		}
	}

	private static Map<String, Object> shape(Built_Component__c row) {
		return new Map<String, Object>{
			'id' => row.Id,
			'name' => row.Name,
			'key' => row.Key__c,
			'description' => row.Description__c,
			'objectName' => row.Object_Name__c,
			'active' => row.Active__c,
			'version' => row.Version__c,
			'definition' => row.Definition__c
		};
	}

	private static Object parse(String body) {
		try {
			return String.isBlank(body) ? null : JSON.deserializeUntyped(body);
		} catch (JSONException e) {
			throw refusal(BarnHelp.text('LwcBuilder', 'LwcBuilder_Error_Definition'));
		}
	}

	private static Map<String, Object> asMap(Object value) {
		return value instanceof Map<String, Object>
			? (Map<String, Object>) value
			: new Map<String, Object>();
	}

	private static String text(Object value) {
		return value == null ? '' : String.valueOf(value).trim();
	}

	/** A key, an API name or a quick action name: a letter, then letters, digits, _ and dots. */
	private static Boolean isKey(String value) {
		return String.isNotBlank(value) && API_NAME.matcher(value).matches();
	}

	private static LwcBuilderException refusal(String message) {
		return new LwcBuilderException(message);
	}
}
