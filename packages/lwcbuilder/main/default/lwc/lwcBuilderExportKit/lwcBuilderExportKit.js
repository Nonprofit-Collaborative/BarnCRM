/**
 * What Export as LWC Source adds for Related List, Record List and Report Chart blocks (LB-07;
 * D-196; ADR-0203 amendment of 2026-11-12), as text, with no Salesforce dependency (plan 9.9).
 *
 * The exported bundle must not depend on BarnCRM, so it gets its own small Apex controller (a
 * report can only be run from Apex, and a list filter value needs the field's type, which only a
 * describe at run time knows), a test class for it, the list and chart helpers for its
 * JavaScript, and the chart styles. `CHART_HELPER` repeats `lwcBuilderModel.chartView` so the
 * exported chart draws what the built one draws; a Jest test keeps the two in step.
 */

/** Apex class names for a bundle's class name, within Apex's 40 characters. */
export function apexNames(className) {
  const base = String(className || 'BuiltComponent').slice(0, 26);
  return { controller: `${base}Controller`, test: `${base}ControllerTest` };
}

const apexMeta = [
  '<?xml version="1.0" encoding="UTF-8" ?>',
  '<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">',
  '    <apiVersion>67.0</apiVersion>',
  '    <status>Active</status>',
  '</ApexClass>',
  ''
].join('\n');

/** The controller: list rows and report charts, every read in user mode. */
export function apexController(name, bundle) {
  return `/**
 * Exported from the BarnCRM LWC Builder for the ${bundle} component: its list and chart reads.
 * Yours to change, deploy and maintain; it does not depend on BarnCRM. Every read runs as the
 * user (user mode), so object, field and record access apply.
 */
public with sharing class ${name} {
    private static final Pattern API_NAME = Pattern.compile('[A-Za-z][A-Za-z0-9_]{0,79}');

    /**
     * A list block's rows. requestJson: {object, fields, parentField, recordId, filterField,
     * filterOperator, filterValue, orderBy, direction, rowLimit}. Returns {columns: [{fieldName,
     * label, type, isName}], rows}; a field the user cannot read is left out.
     */
    @AuraEnabled
    public static Map<String, Object> records(String requestJson) {
        Map<String, Object> request = (Map<String, Object>) JSON.deserializeUntyped(requestJson);
        String objectName = text(request.get('object'));
        Schema.SObjectType type = API_NAME.matcher(objectName).matches()
            ? Schema.getGlobalDescribe().get(objectName)
            : null;
        if (type == null) {
            throw new AuraHandledException('There is no object called ' + objectName + '.');
        }
        Map<String, Schema.SObjectField> fields = type.getDescribe().fields.getMap();
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        Set<String> selected = new Set<String>{ 'Id' };
        for (Object item : (List<Object>) request.get('fields')) {
            Schema.DescribeFieldResult field = describe(fields, text(item));
            if (field.isAccessible() && selected.add(field.getName())) {
                columns.add(new Map<String, Object>{
                    'fieldName' => field.getName(),
                    'label' => field.getLabel(),
                    'type' => String.valueOf(field.getType()).toLowerCase(),
                    'isName' => field.isNameField()
                });
            }
        }
        String recordId = text(request.get('recordId'));
        Map<String, Object> binds = new Map<String, Object>{
            'recordId' => String.isBlank(recordId) ? null : recordId
        };
        List<String> conditions = new List<String>();
        if (String.isNotBlank(text(request.get('parentField')))) {
            conditions.add(describe(fields, text(request.get('parentField'))).getName() + ' = :recordId');
        }
        if (String.isNotBlank(text(request.get('filterField')))) {
            Schema.DescribeFieldResult filter = describe(fields, text(request.get('filterField')));
            binds.put('filterValue', typed(filter, text(request.get('filterValue'))));
            String operator = text(request.get('filterOperator')) == 'notEquals' ? ' != ' : ' = ';
            conditions.add(filter.getName() + operator + ':filterValue');
        }
        String query = 'SELECT ' + String.join(new List<String>(selected), ', ') + ' FROM ' + type;
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        if (String.isNotBlank(text(request.get('orderBy')))) {
            String direction = text(request.get('direction')) == 'desc' ? ' DESC' : ' ASC';
            query += ' ORDER BY ' + describe(fields, text(request.get('orderBy'))).getName() + direction + ' NULLS LAST';
        }
        Integer rowLimit = request.get('rowLimit') == null ? 10 : Integer.valueOf(request.get('rowLimit'));
        query += ' LIMIT ' + Math.max(1, Math.min(200, rowLimit));
        return new Map<String, Object>{
            'columns' => columns,
            'rows' => Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)
        };
    }

    /**
     * A chart block's data: a summary or matrix report run once as the user, with up to two
     * groupings and three summaries. Returns {title, measures, series, groups: [{label, cells}]},
     * cells holding one list per series of {value, label} per measure.
     */
    @AuraEnabled
    public static Map<String, Object> chart(String reportName) {
        List<SObject> found = Database.queryWithBinds(
            'SELECT Id, Name FROM Report WHERE DeveloperName = :reportName LIMIT 1',
            new Map<String, Object>{ 'reportName' => reportName },
            AccessLevel.USER_MODE
        );
        if (found.isEmpty()) {
            throw new AuraHandledException('There is no report ' + reportName + ' you can open.');
        }
        Reports.ReportResults results = Reports.ReportManager.runReport(found[0].Id, false);
        Reports.ReportMetadata metadata = results.getReportMetadata();
        List<Reports.GroupingValue> groups = results.getGroupingsDown().getGroupings();
        if (groups == null || groups.isEmpty() || metadata.getAggregates().isEmpty()) {
            throw new AuraHandledException(String.valueOf(found[0].get('Name')) + ' cannot be charted.');
        }
        List<String> measures = new List<String>();
        for (String aggregate : metadata.getAggregates()) {
            if (measures.size() < 3) {
                measures.add(results.getReportExtendedMetadata().getAggregateColumnInfo().get(aggregate).getLabel());
            }
        }
        Map<String, Reports.ReportFact> facts = results.getFactMap();
        List<String> series = new List<String>();
        List<Reports.GroupingValue> across = metadata.getReportFormat() == Reports.ReportFormat.MATRIX
            ? results.getGroupingsAcross().getGroupings()
            : null;
        Map<String, List<Object>> cellsByKey = new Map<String, List<Object>>();
        for (String key : facts.keySet()) {
            cellsByKey.put(key, cell(facts.get(key), measures.size()));
        }
        List<Map<String, Object>> rows = walk(plain(groups), plain(across), cellsByKey, series);
        return new Map<String, Object>{
            'title' => found[0].get('Name'),
            'measures' => measures,
            'series' => series,
            'groups' => rows
        };
    }

    /** Report groupings as plain maps {key, label, children}, one level of children. */
    private static List<Map<String, Object>> plain(List<Reports.GroupingValue> values) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Reports.GroupingValue value : values == null ? new List<Reports.GroupingValue>() : values) {
            result.add(new Map<String, Object>{
                'key' => value.getKey(),
                'label' => value.getLabel(),
                'children' => value.getGroupings() == null
                    ? new List<Map<String, Object>>()
                    : plainLeaves(value.getGroupings())
            });
        }
        return result;
    }

    private static List<Map<String, Object>> plainLeaves(List<Reports.GroupingValue> values) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Reports.GroupingValue value : values) {
            result.add(new Map<String, Object>{ 'key' => value.getKey(), 'label' => value.getLabel() });
        }
        return result;
    }

    /**
     * The rows of a chart from plain inputs: groupings down and across as {key, label, children},
     * and each fact's cells by fact key. A matrix's columns are the series; a second grouping's
     * values are the series otherwise (up to 12, added to series as met); up to 200 rows.
     */
    @TestVisible
    private static List<Map<String, Object>> walk(
        List<Map<String, Object>> groups,
        List<Map<String, Object>> across,
        Map<String, List<Object>> cellsByKey,
        List<String> series
    ) {
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        for (Map<String, Object> column : across == null ? new List<Map<String, Object>>() : across) {
            if (columns.size() < 12) {
                columns.add(column);
                series.add((String) column.get('label'));
            }
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Map<String, Object> grouping : groups) {
            if (rows.size() == 200) {
                break;
            }
            List<Object> cells = new List<Object>();
            List<Map<String, Object>> children = (List<Map<String, Object>>) grouping.get('children');
            if (!columns.isEmpty()) {
                for (Map<String, Object> column : columns) {
                    cells.add(found(cellsByKey, grouping.get('key') + '!' + column.get('key')));
                }
            } else if (children != null && !children.isEmpty()) {
                for (Map<String, Object> child : children) {
                    Integer lane = series.indexOf((String) child.get('label'));
                    if (lane < 0 && series.size() < 12) {
                        series.add((String) child.get('label'));
                        lane = series.size() - 1;
                    }
                    while (lane >= 0 && cells.size() <= lane) {
                        cells.add(null);
                    }
                    if (lane >= 0) {
                        cells[lane] = found(cellsByKey, child.get('key') + '!T');
                    }
                }
            } else {
                cells.add(found(cellsByKey, grouping.get('key') + '!T'));
            }
            rows.add(new Map<String, Object>{ 'label' => grouping.get('label'), 'cells' => cells });
        }
        return rows;
    }

    private static List<Object> found(Map<String, List<Object>> cellsByKey, Object key) {
        List<Object> cells = cellsByKey.get(String.valueOf(key));
        return cells == null ? new List<Object>() : cells;
    }

    @TestVisible
    private static List<Object> cell(Reports.ReportFact fact, Integer measures) {
        List<Object> values = new List<Object>();
        List<Reports.SummaryValue> summaries = fact == null
            ? new List<Reports.SummaryValue>()
            : fact.getAggregates();
        for (Integer m = 0; m < measures && m < summaries.size(); m++) {
            values.add(new Map<String, Object>{
                'value' => summaries[m].getValue(),
                'label' => summaries[m].getLabel()
            });
        }
        return values;
    }

    private static Schema.DescribeFieldResult describe(Map<String, Schema.SObjectField> fields, String name) {
        Schema.SObjectField field = API_NAME.matcher(name).matches() ? fields.get(name.toLowerCase()) : null;
        if (field == null) {
            throw new AuraHandledException(name + ' is not a field on this object.');
        }
        return field.getDescribe();
    }

    /** The filter value as the field's type, so the bind compares like with like. */
    @TestVisible
    private static Object typed(Schema.DescribeFieldResult field, String value) {
        if (String.isBlank(value)) {
            return null;
        }
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
    }

    private static String text(Object value) {
        return value == null ? '' : String.valueOf(value).trim();
    }
}
`;
}

/** A test for the controller, on Account, which every org has. */
export function apexTest(name, controller) {
  return `@IsTest
private class ${name} {
    @IsTest
    static void listsAndCharts() {
        insert new Account(Name = 'Exported Component Test');
        Map<String, Object> result = ${controller}.records(JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'fields' => new List<String>{ 'Name' },
            'filterField' => 'Name',
            'filterOperator' => 'equals',
            'filterValue' => 'Exported Component Test',
            'orderBy' => 'Name',
            'direction' => 'desc',
            'rowLimit' => 5
        }));
        Assert.areEqual(1, ((List<SObject>) result.get('rows')).size(), 'The filtered row');
        Assert.areEqual(1, ((List<Object>) result.get('columns')).size(), 'Name');
        try {
            ${controller}.chart('No_Such_Report_Anywhere');
            Assert.fail('A report that is not there');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Says so');
        }
        Assert.areEqual(0, ${controller}.cell(null, 3).size(), 'An empty cell');
    }

    @IsTest
    static void listFollowsAParentAndNotEquals() {
        Account parent = new Account(Name = 'Exported Parent');
        insert parent;
        insert new List<Account>{
            new Account(Name = 'Exported Child A', ParentId = parent.Id),
            new Account(Name = 'Exported Child B', ParentId = parent.Id)
        };
        Map<String, Object> result = ${controller}.records(JSON.serialize(new Map<String, Object>{
            'object' => 'Account',
            'fields' => new List<String>{ 'Name', 'ParentId' },
            'parentField' => 'ParentId',
            'recordId' => parent.Id,
            'filterField' => 'Name',
            'filterOperator' => 'notEquals',
            'filterValue' => 'Exported Child A'
        }));
        Assert.areEqual(1, ((List<SObject>) result.get('rows')).size(), 'Only the other child');
    }

    @IsTest
    static void aFilterValueTakesTheFieldsType() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
        Assert.isNull(${controller}.typed(fields.get('name').getDescribe(), ' '), 'Blank is null');
        Assert.areEqual('Acme', ${controller}.typed(fields.get('name').getDescribe(), 'Acme'), 'Text');
        Assert.areEqual(true, ${controller}.typed(fields.get('isdeleted').getDescribe(), 'true'), 'Boolean');
        Assert.areEqual(12.5, ${controller}.typed(fields.get('annualrevenue').getDescribe(), '12.5'), 'Currency');
        Assert.areEqual(40, ${controller}.typed(fields.get('numberofemployees').getDescribe(), '40'), 'Integer');
        Assert.areEqual(
            Date.newInstance(2026, 1, 31),
            ${controller}.typed(Schema.SObjectType.Contact.fields.getMap().get('birthdate').getDescribe(), '2026-01-31'),
            'Date'
        );
    }

    private static Map<String, Object> group(String key, String label, List<Map<String, Object>> children) {
        return new Map<String, Object>{ 'key' => key, 'label' => label, 'children' => children };
    }

    private static List<Object> one(Object value) {
        return new List<Object>{ new Map<String, Object>{ 'value' => value, 'label' => String.valueOf(value) } };
    }

    @IsTest
    static void aSummaryReportHasOneCellPerGroup() {
        List<String> series = new List<String>();
        List<Map<String, Object>> rows = ${controller}.walk(
            new List<Map<String, Object>>{
                group('0', 'Alpha', new List<Map<String, Object>>()),
                group('1', 'Beta', null)
            },
            null,
            new Map<String, List<Object>>{ '0!T' => one(5) },
            series
        );
        Assert.areEqual(2, rows.size(), 'A row per group');
        Assert.areEqual(1, ((List<Object>) rows[0].get('cells')).size(), 'One cell');
        Assert.areEqual(0, ((List<Object>) ((List<Object>) rows[1].get('cells'))[0]).size(), 'No fact, empty cell');
        Assert.isTrue(series.isEmpty(), 'No series');
    }

    @IsTest
    static void twoGroupingsMakeTheSecondTheSeries() {
        List<String> series = new List<String>();
        List<Map<String, Object>> rows = ${controller}.walk(
            new List<Map<String, Object>>{
                group('0', 'Alpha', new List<Map<String, Object>>{
                    new Map<String, Object>{ 'key' => '0_0', 'label' => 'Open' },
                    new Map<String, Object>{ 'key' => '0_1', 'label' => 'Closed' }
                }),
                group('1', 'Beta', new List<Map<String, Object>>{
                    new Map<String, Object>{ 'key' => '1_1', 'label' => 'Closed' }
                })
            },
            null,
            new Map<String, List<Object>>{ '0_0!T' => one(1), '0_1!T' => one(2), '1_1!T' => one(3) },
            series
        );
        Assert.areEqual(new List<String>{ 'Open', 'Closed' }, series, 'Series in the order met');
        List<Object> beta = (List<Object>) rows[1].get('cells');
        Assert.areEqual(2, beta.size(), 'A gap is filled');
        Assert.isNull(beta[0], 'Beta has no Open');
        Assert.isNotNull(beta[1], 'Beta has Closed');
    }

    @IsTest
    static void aMatrixUsesItsColumnsAsTheSeriesAndCapsThem() {
        List<Map<String, Object>> across = new List<Map<String, Object>>();
        Map<String, List<Object>> cells = new Map<String, List<Object>>();
        for (Integer i = 0; i < 14; i++) {
            across.add(new Map<String, Object>{ 'key' => String.valueOf(i), 'label' => 'C' + i });
            cells.put('0!' + i, one(i));
        }
        List<String> series = new List<String>();
        List<Map<String, Object>> rows = ${controller}.walk(
            new List<Map<String, Object>>{ group('0', 'Alpha', null) },
            across,
            cells,
            series
        );
        Assert.areEqual(12, series.size(), 'At most twelve series');
        Assert.areEqual(12, ((List<Object>) rows[0].get('cells')).size(), 'A cell per column');
    }

    @IsTest
    static void aChartHasAtMostTwoHundredRows() {
        List<Map<String, Object>> groups = new List<Map<String, Object>>();
        for (Integer i = 0; i < 205; i++) {
            groups.add(group(String.valueOf(i), 'G' + i, null));
        }
        Assert.areEqual(200, ${controller}.walk(groups, null, new Map<String, List<Object>>(), new List<String>()).size(), 'Capped');
    }
}
`;
}

/** Each Apex file of the export, with its metadata. */
export function apexFiles(className, bundle) {
  const names = apexNames(className);
  return [
    { name: `${names.controller}.cls`, content: apexController(names.controller, bundle) },
    { name: `${names.controller}.cls-meta.xml`, content: apexMeta },
    { name: `${names.test}.cls`, content: apexTest(names.test, names.controller) },
    { name: `${names.test}.cls-meta.xml`, content: apexMeta }
  ];
}

/** The list helpers for the exported JavaScript: datatable columns and rows from records(). */
export const LIST_HELPER = `// lightning-datatable column types for the field types the controller reports.
const COLUMN_TYPES = {
    currency: 'currency',
    percent: 'percent',
    double: 'number',
    integer: 'number',
    long: 'number',
    date: 'date-local',
    datetime: 'date',
    boolean: 'boolean',
    email: 'email',
    phone: 'phone',
    url: 'url'
};

function listView(result) {
    return {
        columns: (result.columns || []).map((column) =>
            column.isName
                ? { label: column.label, fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: column.fieldName } } }
                : { label: column.label, fieldName: column.fieldName, type: COLUMN_TYPES[column.type] || 'text' }
        ),
        rows: (result.rows || []).map((row) => ({ ...row, recordUrl: '/' + row.Id })),
        error: ''
    };
}
`;

/** The chart helper for the exported JavaScript, the same layout as lwcBuilderModel.chartView. */
export const CHART_HELPER = `// Lays out chart() data as bars and a table: up to three measures, each on its own scale;
// 'stacked' splits each bar by the second grouping, otherwise each series has its own bar.
function chartView(data, display) {
    const measures = (data.measures || []).slice(0, 3);
    const series = data.series || [];
    const groups = data.groups || [];
    const lanes = series.length ? series : [''];
    const stacked = display === 'stacked' && series.length > 0;
    const cellOf = (group, lane, m) => ((group.cells || [])[lane] || [])[m];
    const size = (cell) => Math.abs(Number(cell && cell.value) || 0);
    const shown = (cell) => {
        if (!cell || cell.value === null || cell.value === undefined) return '';
        return cell.label === null || cell.label === undefined ? String(cell.value) : cell.label;
    };
    const total = (group, m) => lanes.reduce((sum, name, lane) => sum + size(cellOf(group, lane, m)), 0);
    const largest = (group, m) => {
        if (stacked) return total(group, m);
        return Math.max(...lanes.map((name, lane) => size(cellOf(group, lane, m))));
    };
    const max = measures.map((label, m) => Math.max(0, ...groups.map((group) => largest(group, m))));
    const width = (value, m) => 'width: ' + (max[m] > 0 ? Math.round((value / max[m]) * 100) : 0) + '%';
    const tone = (lane) => (series.length ? 'segment tone' + (lane % 5) : 'segment');
    const segment = (key, group, lane, m) => ({ key, css: tone(lane), style: width(size(cellOf(group, lane, m)), m) });
    return {
        title: data.title || '',
        caption: measures.length === 1 ? (data.title || '') + ': ' + measures[0] : data.title || '',
        showMeasureNames: measures.length > 1,
        legend: series.map((label, lane) => ({ key: 's' + lane, label, swatch: 'swatch tone' + (lane % 5) })),
        groups: groups.map((group, g) => ({
            key: 'g' + g,
            label: group.label,
            measures: measures.map((label, m) => ({
                key: 'g' + g + 'm' + m,
                label,
                tracks: stacked
                    ? [{
                        key: 'g' + g + 'm' + m + 't',
                        label: '',
                        value: total(group, m).toLocaleString(),
                        segments: series.map((name, lane) => segment('g' + g + 'm' + m + 's' + lane, group, lane, m))
                    }]
                    : lanes.map((name, lane) => ({
                        key: 'g' + g + 'm' + m + 'l' + lane,
                        label: name,
                        value: shown(cellOf(group, lane, m)),
                        segments: [segment('g' + g + 'm' + m + 'l' + lane + 's', group, lane, m)]
                    }))
            }))
        })),
        table: {
            headers: lanes.flatMap((name, lane) =>
                measures.map((label, m) => ({ key: 'h' + lane + 'm' + m, label: [name, label].filter(Boolean).join(': ') }))
            ),
            rows: groups.map((group, g) => ({
                key: 'r' + g,
                label: group.label,
                cells: lanes.flatMap((name, lane) =>
                    measures.map((label, m) => ({ key: 'r' + g + 'l' + lane + 'm' + m, value: shown(cellOf(group, lane, m)) }))
                )
            }))
        }
    };
}
`;

/** The chart styles: SLDS 2 styling hooks with fallbacks, five series tones. */
export const CHART_CSS = `.lane {
    padding-right: var(--slds-g-spacing-2, 0.5rem);
}

.lane:empty {
    display: none;
}

.track {
    display: flex;
    height: var(--slds-g-sizing-5, 0.75rem);
    background: var(--slds-g-color-surface-container-2, #f3f3f3);
    border-radius: var(--slds-g-radius-border-2, 0.25rem);
    overflow: hidden;
}

.segment {
    background: var(--slds-g-color-accent-1, #0176d3);
}

.swatch {
    display: inline-block;
    width: var(--slds-g-sizing-5, 0.75rem);
    height: var(--slds-g-sizing-5, 0.75rem);
    margin-right: var(--slds-g-spacing-1, 0.25rem);
    vertical-align: middle;
}

.tone0 {
    background: var(--slds-g-color-palette-blue-40, #0b5cab);
}

.tone1 {
    background: var(--slds-g-color-palette-teal-40, #056764);
}

.tone2 {
    background: var(--slds-g-color-palette-violet-40, #5a1ba9);
}

.tone3 {
    background: var(--slds-g-color-palette-green-40, #2e844a);
}

.tone4 {
    background: var(--slds-g-color-palette-orange-40, #8c4b02);
}
`;
