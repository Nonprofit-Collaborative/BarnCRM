/**
 * Advanced Reporting's one query service (ADR-0231 advanced reporting, canonical model 29AR).
 *
 * The browser sends a run request: a Find query document (canonical model R-SQ1) for the
 * records, plus the report's groupings, totals and related-record totals. Core's QueryCompiler
 * turns the document into SOQL from the running user's describe, binds every value and runs in
 * user mode (R-SQ2), so this class never takes SOQL text, an unchecked name or a value written
 * into a query. What it adds is checked the same way: every grouping, total and related path
 * resolves through QueryCompiler.resolve as the user, functions and date buckets come from fixed
 * lists, and every query runs with AccessLevel.USER_MODE. Each viewer therefore sees only the
 * records, objects and fields their own access allows.
 *
 * Large volumes: a grouped report is counted first and summarised in one aggregate query while
 * the records fit the request's query rows; past that the answer is `scan`, and the browser
 * reads the records in Id order (`page`, keyset paging) and totals them itself
 * (c/reportingModel). Rows, sorting, charts and layout are the browser's.
 */
public with sharing class ReportingQueryService {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		'ReportingQueryService',
		'Reporting',
		'Reporting_Error_Generic'
	);
	public static final Integer MAX_GROUPS = 2;
	public static final Integer MAX_MEASURES = 4;
	public static final Integer MAX_SUMMARIES = 3;
	public static final Integer MAX_PAGE = 5000;
	public static final Integer MAX_FIELDS = 20;
	public static final Integer GROUP_LIMIT = 2000;
	/** The most records one aggregate query totals before the browser reads them in pages. */
	@TestVisible
	private static Integer aggregateRecordLimit = 20000;
	private static final Set<String> FUNCTIONS = new Set<String>{
		'count',
		'sum',
		'avg',
		'min',
		'max',
		'countdistinct'
	};
	private static final Set<String> BUCKETS = new Set<String>{
		'day',
		'week',
		'month',
		'quarter',
		'year'
	};
	/** The standard objects a report may start from; every custom object the user reads too. */
	private static final Set<String> STANDARD_OBJECTS = new Set<String>{
		'Account',
		'Contact',
		'User'
	};
	private static final Set<Schema.DisplayType> NUMBERS = new Set<Schema.DisplayType>{
		Schema.DisplayType.CURRENCY,
		Schema.DisplayType.DOUBLE,
		Schema.DisplayType.INTEGER,
		Schema.DisplayType.LONG,
		Schema.DisplayType.PERCENT
	};
	private static final Set<Schema.DisplayType> DATES = new Set<Schema.DisplayType>{
		Schema.DisplayType.DATE,
		Schema.DisplayType.DATETIME
	};

	/** A refusal written for the person, shown as it is. */
	public class ReportingException extends Exception {
	}

	/** A run request, read and checked. */
	@TestVisible
	private class Request {
		String queryJson;
		String objectName;
		List<Map<String, Object>> groups = new List<Map<String, Object>>();
		List<Map<String, Object>> measures = new List<Map<String, Object>>();
		List<Map<String, Object>> summaries = new List<Map<String, Object>>();
		/** The export's columns once each, whatever their case, by lower-case path; never Id. */
		Map<String, String> fields = new Map<String, String>();
	}

	/** The objects a report may start from: the user's queryable custom objects, Account, Contact, User. */
	@AuraEnabled(cacheable=true)
	public static List<Map<String, String>> listObjects() {
		try {
			List<Map<String, String>> options = new List<Map<String, String>>();
			for (Schema.SObjectType type : NamespaceUtil.globalDescribe().values()) {
				Schema.DescribeSObjectResult described = type.getDescribe(
					SObjectDescribeOptions.DEFERRED
				);
				if (isReportable(described)) {
					options.add(
						new Map<String, String>{
							'value' => described.getName(),
							'label' => described.getLabel()
						}
					);
				}
			}
			return options;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** The kinds of related record of an object: a reportable child object and its lookup. */
	@AuraEnabled(cacheable=true)
	public static List<Map<String, String>> listChildren(String objectName) {
		try {
			List<Map<String, String>> options = new List<Map<String, String>>();
			for (Schema.ChildRelationship child : reportable(objectName).getChildRelationships()) {
				Schema.DescribeSObjectResult childObject = child.getChildSObject()
					.getDescribe(SObjectDescribeOptions.DEFERRED);
				Schema.DescribeFieldResult lookup = child.getField().getDescribe();
				if (
					isReportable(childObject) &&
					lookup.isAccessible() &&
					lookup.isFilterable() &&
					lookup.isGroupable()
				) {
					options.add(
						new Map<String, String>{
							'object' => childObject.getName(),
							'objectLabel' => childObject.getLabel(),
							'field' => lookup.getName(),
							'fieldLabel' => lookup.getLabel()
						}
					);
				}
			}
			return options;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * Runs a report as the user. Without totals: `rows`, the records in the document's order (at
	 * most its limit, 2,000), and `summaries` when related totals were asked for. With totals:
	 * `groups`, one entry per group (one entry in all when there is no grouping), or
	 * `scan: true` when more records match than one aggregate query may total.
	 */
	@AuraEnabled
	public static Map<String, Object> run(String requestJson) {
		try {
			Request request = read(requestJson);
			if (request.measures.isEmpty()) {
				QueryCompiler.Compiled compiled = QueryCompiler.compile(request.queryJson);
				List<SObject> rows = QueryCompiler.run(compiled);
				return new Map<String, Object>{
					'rows' => rows,
					'summaries' => summaries(request, rows)
				};
			}
			return grouped(request);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** True when the person has Salesforce's Export Reports permission, which export needs. */
	public static Boolean canExport() {
		for (UserPermissionAccess access : [
			SELECT PermissionsExportReport
			FROM UserPermissionAccess
			WITH USER_MODE
			LIMIT 1
		]) {
			return access.PermissionsExportReport;
		}
		return false;
	}

	/**
	 * One page of the report's records in Id order after `afterId`, each call within its own
	 * limits. An export (`forExport`) reads a list report's columns and related totals, at most
	 * 2,000 a call, and needs Export Reports. A scan reads only the fields the report's groupings
	 * and totals use, worked out here, at most 5,000 a call.
	 */
	@AuraEnabled
	public static Map<String, Object> page(
		String requestJson,
		String afterId,
		Integer pageSize,
		Boolean forExport
	) {
		try {
			Request request = read(requestJson);
			Boolean exporting = forExport == true;
			if (exporting != request.measures.isEmpty()) {
				throw invalid();
			}
			if (exporting && !canExport()) {
				throw new ReportingException(
					BarnHelp.text('Reporting', 'Reporting_Error_NoExport')
				);
			}
			List<String> fields = exporting ? request.fields.values() : scanFields(request);
			Integer most = exporting ? QueryCompiler.EXPORT_PAGE_SIZE : MAX_PAGE;
			Integer size = pageSize == null ? most : Math.max(1, Math.min(pageSize, most));
			QueryCompiler.Compiled compiled = QueryCompiler.compileSelection(
				request.queryJson,
				fields.isEmpty() ? new Set<String>{ 'Id' } : new Set<String>(fields),
				null
			);
			Map<String, Object> binds = new Map<String, Object>(compiled.binds);
			binds.put('reportPageSize', size);
			List<String> conditions = new List<String>();
			if (String.isNotBlank(afterId)) {
				binds.put('reportAfterId', Id.valueOf(afterId));
				conditions.add('Id > :reportAfterId');
			}
			List<String> selected = new List<String>{ 'Id' };
			selected.addAll(fields);
			List<SObject> rows = Database.queryWithBinds(
				'SELECT ' +
					String.join(selected, ', ') +
					withConditions(compiled.fromWhere, conditions) +
					' ORDER BY Id LIMIT :reportPageSize',
				binds,
				AccessLevel.USER_MODE
			);
			return new Map<String, Object>{
				'rows' => rows,
				'summaries' => exporting
					? summaries(request, rows)
					: new List<Map<String, Object>>(),
				'lastId' => rows.isEmpty() ? null : rows[rows.size() - 1].Id,
				'done' => rows.size() < size
			};
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/**
	 * The fields a scan reads, each grouping and total checked as `run` checks it: the grouping
	 * fields with their record names, and the totalled fields. Money is not totalled from pages
	 * when the org has more than one currency, since each record holds its own currency.
	 */
	private static List<String> scanFields(Request request) {
		Map<String, String> fields = new Map<String, String>();
		for (Map<String, Object> groupSpec : request.groups) {
			String path = (String) groupSpec.get('field');
			Schema.DescribeFieldResult field = QueryCompiler.resolve(request.objectName, path);
			bucketed(field, path, (String) groupSpec.get('bucket'));
			addField(fields, path);
			addField(fields, labelPath(request.objectName, field, path));
		}
		Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();
		for (Map<String, Object> spec : request.measures) {
			measure(request.objectName, spec);
			String fn = String.valueOf(spec.get('fn')).toLowerCase();
			if (fn == 'count') {
				continue;
			}
			String path = (String) spec.get('path');
			if (
				multiCurrency &&
				fn != 'countdistinct' &&
				QueryCompiler.resolve(request.objectName, path).getType() ==
				Schema.DisplayType.CURRENCY
			) {
				throw refusal(BarnHelp.text('Reporting', 'Reporting_Error_ScanCurrency'), path);
			}
			addField(fields, path);
		}
		return fields.values();
	}

	/** Adds a field path once, whatever its case; Id is always read, so never added. */
	private static void addField(Map<String, String> fields, String path) {
		if (path != null && path.toLowerCase() != 'id') {
			fields.put(path.toLowerCase(), path);
		}
	}

	private static Map<String, Object> grouped(Request request) {
		QueryCompiler.Compiled compiled = QueryCompiler.compileSelection(
			request.queryJson,
			new Set<String>{ 'Id' },
			null
		);
		if (!fits(compiled.fromWhere, compiled.binds)) {
			return new Map<String, Object>{ 'scan' => true };
		}
		List<String> selected = new List<String>();
		List<String> grouping = new List<String>();
		List<Integer> widths = new List<Integer>();
		List<Boolean> labelled = new List<Boolean>();
		for (Integer g = 0; g < request.groups.size(); g++) {
			Map<String, Object> groupSpec = request.groups[g];
			String path = (String) groupSpec.get('field');
			Schema.DescribeFieldResult field = QueryCompiler.resolve(request.objectName, path);
			List<String> expressions = bucketed(field, path, (String) groupSpec.get('bucket'));
			String label = labelPath(request.objectName, field, path);
			widths.add(expressions.size());
			labelled.add(label != null);
			if (label != null) {
				expressions.add(label);
			}
			for (Integer e = 0; e < expressions.size(); e++) {
				selected.add(expressions[e] + ' g' + g + '_' + e);
				grouping.add(expressions[e]);
			}
		}
		for (Integer m = 0; m < request.measures.size(); m++) {
			selected.add(measure(request.objectName, request.measures[m]) + ' m' + m);
		}
		Map<String, Object> binds = new Map<String, Object>(compiled.binds);
		// A total with no grouping returns one row, and SOQL refuses LIMIT on it.
		String tail = '';
		if (!grouping.isEmpty()) {
			binds.put('reportGroupLimit', GROUP_LIMIT + 1);
			tail = ' GROUP BY ' + String.join(grouping, ', ') + ' LIMIT :reportGroupLimit';
		}
		List<Map<String, Object>> groups = new List<Map<String, Object>>();
		for (
			SObject row : Database.queryWithBinds(
				'SELECT ' + String.join(selected, ', ') + compiled.fromWhere + tail,
				binds,
				AccessLevel.USER_MODE
			)
		) {
			List<Object> keys = new List<Object>();
			List<Object> labels = new List<Object>();
			for (Integer g = 0; g < widths.size(); g++) {
				List<Object> parts = new List<Object>();
				for (Integer e = 0; e < widths[g]; e++) {
					parts.add(row.get('g' + g + '_' + e));
				}
				keys.add(parts);
				labels.add(labelled[g] ? row.get('g' + g + '_' + widths[g]) : null);
			}
			List<Object> values = new List<Object>();
			for (Integer m = 0; m < request.measures.size(); m++) {
				values.add(row.get('m' + m));
			}
			groups.add(
				new Map<String, Object>{ 'keys' => keys, 'labels' => labels, 'values' => values }
			);
		}
		Boolean more = groups.size() > GROUP_LIMIT;
		if (more) {
			groups.remove(GROUP_LIMIT);
		}
		return new Map<String, Object>{ 'groups' => groups, 'more' => more };
	}

	/**
	 * Related totals (each `{object, field, fn, path, filter}`): per record shown, the count or
	 * total of its child records that match the entry's own filter, keyed by the record's Id.
	 */
	private static List<Map<String, Object>> summaries(Request request, List<SObject> rows) {
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		if (request.summaries.isEmpty() || rows.isEmpty()) {
			return out;
		}
		Set<Id> parentIds = new Map<Id, SObject>(rows).keySet();
		for (Map<String, Object> entry : request.summaries) {
			String childObject = reportable((String) entry.get('object')).getName();
			String lookupName = (String) entry.get('field');
			Schema.DescribeFieldResult lookup = QueryCompiler.resolve(childObject, lookupName);
			if (
				lookupName.contains('.') ||
				!lookup.isFilterable() ||
				!lookup.isGroupable() ||
				lookup.getReferenceTo().isEmpty() ||
				lookup.getReferenceTo()[0].getDescribe().getName() != request.objectName
			) {
				throw refusal(BarnHelp.text('Reporting', 'Reporting_Error_Related'), lookupName);
			}
			QueryCompiler.Compiled compiled = QueryCompiler.compileSelection(
				JSON.serialize(
					new Map<String, Object>{
						'version' => 1,
						'object' => childObject,
						'fields' => new List<Object>{ lookupName },
						'filter' => entry.get('filter')
					}
				),
				new Set<String>{ lookupName },
				null
			);
			Map<String, Object> binds = new Map<String, Object>(compiled.binds);
			binds.put('reportParentIds', parentIds);
			String fromWhere = withConditions(
				compiled.fromWhere,
				new List<String>{ lookupName + ' IN :reportParentIds' }
			);
			if (!fits(fromWhere, binds)) {
				throw new ReportingException(
					BarnHelp.text('Reporting', 'Reporting_Error_TooManyRelated')
				);
			}
			Map<String, Object> values = new Map<String, Object>();
			for (
				SObject row : Database.queryWithBinds(
					'SELECT ' +
						lookupName +
						' k, ' +
						measure(childObject, entry) +
						' v' +
						fromWhere +
						' GROUP BY ' +
						lookupName,
					binds,
					AccessLevel.USER_MODE
				)
			) {
				values.put(String.valueOf(row.get('k')), row.get('v'));
			}
			out.add(values);
		}
		return out;
	}

	/**
	 * True when the records fit one aggregate query: counted first, at most the configured limit
	 * and half the query rows the request has left (the count and the total each read them).
	 */
	private static Boolean fits(String fromWhere, Map<String, Object> compiledBinds) {
		Integer room = (Limits.getLimitQueryRows() - Limits.getQueryRows()) / 2 - 1;
		Integer cap = Math.min(aggregateRecordLimit, room);
		Map<String, Object> binds = new Map<String, Object>(compiledBinds);
		binds.put('reportCountLimit', cap + 1);
		return Database.countQueryWithBinds(
				'SELECT COUNT()' + fromWhere + ' LIMIT :reportCountLimit',
				binds,
				AccessLevel.USER_MODE
			) <= cap;
	}

	/** One total as SOQL: the function from the fixed list, the field checked as the user. */
	private static String measure(String objectName, Map<String, Object> spec) {
		String fn = String.valueOf(spec.get('fn')).toLowerCase();
		if (!FUNCTIONS.contains(fn)) {
			throw refusal(
				BarnHelp.text('Reporting', 'Reporting_Error_Function'),
				fn.abbreviate(40)
			);
		}
		if (fn == 'count') {
			return 'COUNT(Id)';
		}
		String path = (String) spec.get('path');
		Schema.DescribeFieldResult field = QueryCompiler.resolve(objectName, path);
		Schema.DisplayType type = field.getType();
		Boolean allowed = fn == 'countdistinct'
			? field.isGroupable()
			: field.isAggregatable() &&
			  (NUMBERS.contains(type) || ((fn == 'min' || fn == 'max') && DATES.contains(type)));
		if (!allowed) {
			throw refusal(BarnHelp.text('Reporting', 'Reporting_Error_Measure'), path);
		}
		return (fn == 'countdistinct' ? 'COUNT_DISTINCT' : fn.toUpperCase()) + '(' + path + ')';
	}

	/** The GROUP BY expressions of one grouping: a date in its bucket, anything else as it is. */
	private static List<String> bucketed(
		Schema.DescribeFieldResult field,
		String path,
		String bucket
	) {
		Schema.DisplayType type = field.getType();
		String key = String.isBlank(bucket) ? 'day' : bucket.toLowerCase();
		Boolean isDate = DATES.contains(type);
		// A date and time field is never groupable as it is, but its date functions are.
		Boolean groupable =
			field.isGroupable() || (type == Schema.DisplayType.DATETIME && field.isFilterable());
		if (
			!groupable ||
			(isDate && !BUCKETS.contains(key)) ||
			(!isDate && String.isNotBlank(bucket))
		) {
			throw refusal(BarnHelp.text('Reporting', 'Reporting_Error_Group'), path);
		}
		if (!isDate) {
			return new List<String>{ path };
		}
		String local = type == Schema.DisplayType.DATETIME ? 'convertTimezone(' + path + ')' : path;
		if (key == 'day') {
			return new List<String>{
				type == Schema.DisplayType.DATETIME ? 'DAY_ONLY(' + local + ')' : path
			};
		}
		List<String> parts = new List<String>{ 'CALENDAR_YEAR(' + local + ')' };
		if (key == 'week') {
			parts.add('WEEK_IN_YEAR(' + local + ')');
		} else if (key == 'month') {
			parts.add('CALENDAR_MONTH(' + local + ')');
		} else if (key == 'quarter') {
			parts.add('CALENDAR_QUARTER(' + local + ')');
		}
		return parts;
	}

	/**
	 * For a grouping by a lookup, the path to its record's Name, so a group shows a name rather
	 * than an Id. The path is checked as the user like any other; null (the group shows its Id)
	 * when it does not resolve, or its Name is not readable or cannot be grouped.
	 */
	private static String labelPath(
		String objectName,
		Schema.DescribeFieldResult field,
		String path
	) {
		if (
			field.getType() != Schema.DisplayType.REFERENCE ||
			field.getRelationshipName() == null ||
			field.getReferenceTo().size() != 1
		) {
			return null;
		}
		String prefix = path.contains('.') ? path.substringBeforeLast('.') + '.' : '';
		String label = prefix + field.getRelationshipName() + '.Name';
		try {
			Schema.DescribeFieldResult name = QueryCompiler.resolve(objectName, label);
			return name.isAccessible() && name.isGroupable() ? label : null;
		} catch (Exception unresolved) {
			return null;
		}
	}

	/** Reads a request, checks its shape and limits, and refuses an object not offered. */
	@TestVisible
	private static Request read(String requestJson) {
		Map<String, Object> raw;
		try {
			raw = (Map<String, Object>) JSON.deserializeUntyped(requestJson);
		} catch (Exception unreadable) {
			throw invalid();
		}
		if (raw == null || !(raw.get('query') instanceof Map<String, Object>)) {
			throw invalid();
		}
		Request request = new Request();
		Map<String, Object> query = (Map<String, Object>) raw.get('query');
		request.objectName = reportable((String) query.get('object')).getName();
		for (Map<String, Object> related : maps(query.get('related'), 2)) {
			reportable((String) related.get('object'));
		}
		request.queryJson = JSON.serialize(query);
		request.groups = maps(raw.get('groups'), MAX_GROUPS);
		request.measures = maps(raw.get('measures'), MAX_MEASURES);
		request.summaries = maps(raw.get('summaries'), MAX_SUMMARIES);
		if (!request.groups.isEmpty() && request.measures.isEmpty()) {
			throw invalid();
		}
		for (Object field : entries(raw.get('fields'), MAX_FIELDS)) {
			addField(request.fields, String.valueOf(field));
		}
		return request;
	}

	private static List<Object> entries(Object raw, Integer most) {
		if (raw == null) {
			return new List<Object>();
		}
		if (!(raw instanceof List<Object>) || ((List<Object>) raw).size() > most) {
			throw invalid();
		}
		return (List<Object>) raw;
	}

	private static List<Map<String, Object>> maps(Object raw, Integer most) {
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (Object entry : entries(raw, most)) {
			if (!(entry instanceof Map<String, Object>)) {
				throw invalid();
			}
			out.add((Map<String, Object>) entry);
		}
		return out;
	}

	/** The describe of an object a report may read, or a refusal naming it. */
	private static Schema.DescribeSObjectResult reportable(String objectName) {
		Schema.DescribeSObjectResult described = String.isBlank(objectName)
			? null
			: NamespaceUtil.describe(objectName);
		if (described == null || !isReportable(described)) {
			throw refusal(
				BarnHelp.text('Reporting', 'Reporting_Error_Object'),
				String.valueOf(objectName).abbreviate(80)
			);
		}
		return described;
	}

	private static Boolean isReportable(Schema.DescribeSObjectResult described) {
		String name = described.getName();
		return described.isQueryable() &&
			described.isAccessible() &&
			!described.isCustomSetting() &&
			(STANDARD_OBJECTS.contains(name) || (described.isCustom() && name.endsWith('__c')));
	}

	/** FROM and WHERE with more conditions joined by AND. */
	private static String withConditions(String fromWhere, List<String> conditions) {
		if (conditions.isEmpty()) {
			return fromWhere;
		}
		return fromWhere +
			(fromWhere.contains(' WHERE ') ? ' AND ' : ' WHERE ') +
			String.join(conditions, ' AND ');
	}

	private static ReportingException refusal(String text, String detail) {
		return new ReportingException(String.format(text, new List<Object>{ detail }));
	}

	private static ReportingException invalid() {
		return new ReportingException(BarnHelp.text('Reporting', 'Reporting_Error_Definition'));
	}
}
