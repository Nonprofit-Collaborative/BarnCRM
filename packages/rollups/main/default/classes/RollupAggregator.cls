/**
 * The calculator of BarnCRM's own rollup engine: runs a `RollupPlanner.Plan` for a set of target
 * records and answers each definition's value for each of them (rollup proposal, Part 2 section 4,
 * "Aggregate SOQL").
 *
 * Recompute, never add and subtract (D3): every value is aggregated again from all the source rows
 * that reach the record, so running twice, or in any order, gives the same answer (R-R9).
 *
 * - A plain path is one aggregate query grouped by the reference, `WHERE key IN :keys`.
 * - Alternatives `A | B` are one query each, the later ones limited to rows where every earlier
 *   reference is blank, and their partial results are merged (R-R1).
 * - A household token is aggregated by person and folded into households in Apex, with the people
 *   and their households answered by `HouseholdService` only, so contact mode and junction mode
 *   give the same answer. AVG is carried as a sum and a count so the fold stays exact.
 * - FIRST and LAST read rows ordered by the order attribute and keep the best per record, a tie
 *   going to the lower record Id.
 * - ANY and NONE are a grouped count, read as "more than none" and "none".
 * - COUNT_DISTINCT and the text lists collect every matching row's value per record and order
 *   them when the answer is read, so they stay exact across alternatives and household members.
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13, ADR-0015, and RollupWriter): every
 * query here runs in system mode and without sharing, because a total must not depend on who
 * saved the gift. Nothing here is shown to a user; the values go straight to `RollupWriter`.
 */
public without sharing class RollupAggregator {
    /** At most this many references per query, so a grouped answer stays under 2,000 rows. */
    @TestVisible
    private static Integer keysPerQuery = 1000;

    /** One value collected for COUNT_DISTINCT or a text list, with what orders it. */
    public class Listed implements Comparable {
        /** The order attribute's value, or the value in lower case when the list has no order. */
        public Object order;
        public String recordId;
        public String value;
        /** The value as read, for a row limited SUM, AVG, MIN or MAX (ADR-0136). */
        public Object raw;
        /** True when the list is ordered descending (`Order_Direction__c`). */
        public Boolean descending = false;

        public Listed(Object order, String recordId, String value) {
            this.order = order;
            this.recordId = recordId;
            this.value = value;
        }

        /**
         * By order in its direction, a blank order last either way, then by record Id, so every
         * run lists the same way.
         */
        public Integer compareTo(Object other) {
            Listed that = (Listed) other;
            if (this.order == null || that.order == null) {
                if (this.order != null) {
                    return -1;
                }
                if (that.order != null) {
                    return 1;
                }
            } else {
                Integer byOrder = compare(this.order, that.order);
                if (byOrder != 0) {
                    return this.descending ? -byOrder : byOrder;
                }
            }
            return this.recordId.compareTo(that.recordId);
        }
    }

    /** One definition's running answer for one target record. */
    public class Tally {
        public Decimal total;
        public Integer counted = 0;
        public Object best;
        public Object bestOrder;
        public String bestId;
        public List<Listed> listed = new List<Listed>();
        /**
         * Where each value sits in `listed`, for COUNT_DISTINCT and TEXT_LIST_DISTINCT, which
         * keep one entry per value: the first in list order, the one the answer would show. A
         * large parent's answer is then as large as its distinct values, not its rows (R-RQ6).
         */
        public Map<String, Integer> indexByValue = new Map<String, Integer>();
        /** Only the first this many entries count (ADR-0136); null for every entry. */
        public Integer rowLimit;

        /** Lists a value; a distinct aggregate keeps only the earliest entry for each value. */
        public void add(Listed entry, Boolean distinct) {
            if (distinct) {
                Integer at = this.indexByValue.get(entry.value);
                if (at != null) {
                    if (entry.compareTo(this.listed[at]) < 0) {
                        this.listed[at] = entry;
                    }
                    return;
                }
                this.indexByValue.put(entry.value, this.listed.size());
            }
            this.listed.add(entry);
            // A limited answer keeps only its first entries, so a large parent's tally stays as
            // small as its limit. An entry dropped here ranks behind as many better ones, so it
            // could never be among the first: the answer stays exact.
            if (this.rowLimit != null && this.listed.size() > 2 * this.rowLimit) {
                keepFirst();
            }
        }

        /** Sorts the entries and keeps the first `rowLimit`, each distinct value's place kept. */
        private void keepFirst() {
            this.listed.sort();
            while (this.listed.size() > this.rowLimit) {
                this.listed.remove(this.listed.size() - 1);
            }
            if (!this.indexByValue.isEmpty()) {
                this.indexByValue.clear();
                for (Integer i = 0; i < this.listed.size(); i++) {
                    this.indexByValue.put(this.listed[i].value, i);
                }
            }
        }

        /** A row limited SUM, AVG, MIN or MAX, folded from the first entries only. */
        private void foldFirst(String aggregate) {
            keepFirst();
            this.total = null;
            this.counted = 0;
            this.best = null;
            for (Listed entry : this.listed) {
                if (aggregate == 'SUM' || aggregate == 'AVG') {
                    this.total = (this.total == null ? 0 : this.total) + toDecimal(entry.raw);
                    this.counted++;
                } else if (
                    this.best == null ||
                    compare(entry.raw, this.best) * (aggregate == 'MIN' ? -1 : 1) > 0
                ) {
                    this.best = entry.raw;
                }
            }
        }

        /**
         * The value to write, a text list joined by this separator (canonical model R-R15):
         * ordered, each value once for TEXT_LIST_DISTINCT, blank when nothing was listed, and
         * no more than the row limit's values.
         */
        public Object result(String aggregate, String separator) {
            if (this.rowLimit != null && !aggregate.startsWith('TEXT_LIST')) {
                foldFirst(aggregate);
            }
            switch on aggregate {
                when 'TEXT_LIST', 'TEXT_LIST_DISTINCT' {
                    if (this.listed.isEmpty()) {
                        return null;
                    }
                    this.listed.sort();
                    List<String> values = new List<String>();
                    Set<String> seen = new Set<String>();
                    for (Listed entry : this.listed) {
                        if (this.rowLimit != null && values.size() == this.rowLimit) {
                            break;
                        }
                        if (seen.add(entry.value) || aggregate == 'TEXT_LIST') {
                            values.add(entry.value);
                        }
                    }
                    return String.join(values, separator);
                }
                when 'COUNT_DISTINCT' {
                    Set<String> distinct = new Set<String>();
                    for (Listed entry : this.listed) {
                        distinct.add(entry.value);
                    }
                    return Decimal.valueOf(distinct.size());
                }
                when 'ANY' {
                    return this.counted > 0;
                }
                when 'NONE' {
                    return this.counted == 0;
                }
                when 'SUM' {
                    return this.total == null ? 0 : this.total;
                }
                when 'COUNT' {
                    return Decimal.valueOf(this.counted);
                }
                when 'AVG' {
                    return this.counted == 0 ||
                        this.total == null
                        ? null
                        : this.total.divide(this.counted, 8, System.RoundingMode.HALF_UP);
                }
                when else {
                    return this.best;
                }
            }
        }
    }

    /** Values by definition index, then by target record, for the records that had source rows. */
    public class Answer {
        public Map<Integer, Map<Id, Tally>> tallies = new Map<Integer, Map<Id, Tally>>();
        /** Definitions whose query failed, by index, so they are left out of the write. */
        public Set<Integer> failed = new Set<Integer>();
    }

    /**
     * Calculates every planned definition for these target records. With a row ceiling set
     * (`limitQueryRows`), stops with `RowCeilingException` rather than start a query that would
     * take the transaction past it.
     *
     * @param plan the planned pass
     * @param targetIds the target records to calculate
     */
    public static Answer calculate(RollupPlanner.Plan plan, Set<Id> targetIds) {
        // One calculation only: the write that follows may set off triggers that calculate
        // totals of their own, and those must not be held to the queue's ceiling.
        Integer ceiling = rowCeiling;
        rowCeiling = null;
        Answer answer = new Answer();
        if (plan == null || targetIds == null || targetIds.isEmpty()) {
            return answer;
        }
        Map<String, Fanout> fanoutByToken = new Map<String, Fanout>();
        Integer largestQuery = 0;
        for (RollupPlanner.SourceQuery query : plan.queries) {
            if (passesCeiling(Limits.getQueryRows(), largestQuery, ceiling)) {
                throw new RowCeilingException(
                    'The next rollup query would pass the query row ceiling of ' + ceiling
                );
            }
            Integer rowsBefore = Limits.getQueryRows();
            try {
                String tokenKey = String.valueOf(query.token);
                if (!fanoutByToken.containsKey(tokenKey)) {
                    fanoutByToken.put(tokenKey, fanoutFor(query.token, targetIds));
                }
                run(query, fanoutByToken.get(tokenKey), answer);
            } catch (Exception failedQuery) {
                for (RollupPlanner.Measure measure : query.measures) {
                    answer.failed.add(measure.definitionIndex);
                    ErrorLogger.log(
                        failedQuery,
                        'RollupAggregator.calculate',
                        plan.definitions[measure.definitionIndex].Id
                    );
                }
            }
            largestQuery = Math.max(largestQuery, Limits.getQueryRows() - rowsBefore);
        }
        return answer;
    }

    /**
     * The query rows a transaction may have read before the next calculation starts a further
     * query, or null for no ceiling (the default: the instant path and previews). The Rollup
     * Queue and the full run set it for each of their own recalculations (R-RQ6); a calculation
     * takes it and leaves none behind.
     */
    private static Integer rowCeiling;

    /**
     * Sets, or clears with null, the ceiling the next `calculate` checks before each query after
     * its first.
     *
     * @param ceiling the query rows the transaction may have read before a further query
     */
    public static void limitQueryRows(Integer ceiling) {
        rowCeiling = ceiling;
    }

    /**
     * Thrown by `calculate` instead of starting a query that would take the transaction past its
     * row ceiling. Nothing has been written; the caller sends the records to the large parent
     * route (`RollupLargeParentBatch`).
     */
    public class RowCeilingException extends Exception {
    }

    /**
     * Whether a further query would pass the ceiling: the rows read so far plus the most one
     * earlier query of this calculation read, as the next is taken to read as many. A plan's
     * queries mostly read the same source rows under different filters: a fund's COUNT and its
     * SUMs each read its allocations. The first query is never stopped (nothing is measured
     * yet), so a record whose queries are small is never stopped at all.
     *
     * @param read the query rows the transaction has read
     * @param largestQuery the most rows one earlier query of this calculation read
     * @param ceiling the ceiling, or null for none
     */
    @TestVisible
    private static Boolean passesCeiling(Integer read, Integer largestQuery, Integer ceiling) {
        return ceiling != null && largestQuery > 0 && read + largestQuery > ceiling;
    }

    /** Which target records each reference read off a source row counts towards. */
    private class Fanout {
        public Set<Id> keys = new Set<Id>();
        public Map<Id, Set<Id>> targetsByKey = new Map<Id, Set<Id>>();

        public void add(Id key, Id targetId) {
            this.keys.add(key);
            if (!this.targetsByKey.containsKey(key)) {
                this.targetsByKey.put(key, new Set<Id>());
            }
            this.targetsByKey.get(key).add(targetId);
        }
    }

    /**
     * A plain path reaches the target itself. `{Household}` reaches the household each
     * member's person is in now; `{HouseholdMembers}` reaches every member of that household.
     * The candidates are the members of every household the targets belong to, which holds
     * every person whose source rows can reach one of them.
     */
    private static Fanout fanoutFor(String token, Set<Id> targetIds) {
        Fanout result = new Fanout();
        if (token == null) {
            for (Id targetId : targetIds) {
                result.add(targetId, targetId);
            }
            return result;
        }
        Set<Id> households = new Set<Id>(targetIds);
        if (token == RollupPath.TOKEN_HOUSEHOLD_MEMBERS) {
            households = new Set<Id>(HouseholdService.householdIdsForPeople(targetIds));
            households.addAll(HouseholdService.getHouseholdIdsFor(targetIds).values());
            households.remove(null);
        }
        Map<Id, Set<Id>> membersByHousehold = HouseholdService.getMemberPersonIds(households);
        Set<Id> people = new Set<Id>();
        for (Set<Id> members : membersByHousehold.values()) {
            people.addAll(members);
        }
        Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(people);
        for (Id personId : people) {
            Id householdId = householdByPerson.get(personId);
            if (householdId == null) {
                continue;
            }
            if (token == RollupPath.TOKEN_HOUSEHOLD) {
                if (targetIds.contains(householdId)) {
                    result.add(personId, householdId);
                }
                continue;
            }
            Set<Id> members = membersByHousehold.get(householdId);
            for (Id memberId : members == null ? new Set<Id>() : members) {
                if (targetIds.contains(memberId)) {
                    result.add(personId, memberId);
                }
            }
        }
        return result;
    }

    /**
     * One source query of a plan for these target records, over these source rows only, folded
     * into `answer` (ADR-0116, `RollupLargeParentBatch`). Partial answers merge exactly, as the
     * alternatives of a path already do (R-R1), so a record whose source rows are more than one
     * transaction may read is calculated chunk by chunk. A query that fails leaves its
     * definitions out of the write, as in `calculate`.
     *
     * @param plan the planned pass
     * @param queryIndex the query of the plan to run
     * @param targetIds the target records to calculate
     * @param rowIds the source rows of this chunk
     * @param answer the answer so far, added to
     */
    public static void calculateRows(
        RollupPlanner.Plan plan,
        Integer queryIndex,
        Set<Id> targetIds,
        Set<Id> rowIds,
        Answer answer
    ) {
        RollupPlanner.SourceQuery query = plan.queries[queryIndex];
        if (query.includeDeleted && answer.failed.contains(query.measures[0].definitionIndex)) {
            return; // refused and logged on its first chunk
        }
        try {
            // A query locator cannot read ALL ROWS, so the chunks would miss the deleted rows:
            // the definition is left out of the write rather than written without them (R-R15).
            if (query.includeDeleted) {
                throw new RollupPlanner.RollupPlanException(
                    System.Label.Core_Rollups_ErrorDeletedLargeParent
                );
            }
            run(query, fanoutFor(query.token, targetIds), answer, rowIds);
        } catch (Exception failedQuery) {
            for (RollupPlanner.Measure measure : query.measures) {
                answer.failed.add(measure.definitionIndex);
                ErrorLogger.log(
                    failedQuery,
                    'RollupAggregator.calculateRows',
                    plan.definitions[measure.definitionIndex].Id
                );
            }
        }
    }

    /**
     * The source rows one query of a plan reads for these target records, for a batch to read in
     * chunks: only their Ids, so reading them costs no aggregate.
     */
    public static Database.QueryLocator sourceRows(
        RollupPlanner.Plan plan,
        Integer queryIndex,
        Set<Id> targetIds
    ) {
        RollupPlanner.SourceQuery query = plan.queries[queryIndex];
        return Database.getQueryLocatorWithBinds(
            'SELECT Id FROM ' + query.sourceObject + whereFor(query),
            new Map<String, Object>{ 'keys' => fanoutFor(query.token, targetIds).keys },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void run(RollupPlanner.SourceQuery query, Fanout fanout, Answer answer) {
        run(query, fanout, answer, null);
    }

    private static void run(
        RollupPlanner.SourceQuery query,
        Fanout fanout,
        Answer answer,
        Set<Id> rowIds
    ) {
        List<Id> keys = new List<Id>(fanout.keys);
        for (Integer start = 0; start < keys.size(); start += keysPerQuery) {
            Set<Id> slice = new Set<Id>();
            for (Integer i = start; i < Math.min(start + keysPerQuery, keys.size()); i++) {
                slice.add(keys[i]);
            }
            Map<String, Object> binds = new Map<String, Object>{ 'keys' => slice };
            if (rowIds != null) {
                binds.put('rows', rowIds);
            }
            if (query.kind == RollupPlanner.KIND_ORDERED) {
                foldRows(query, fanout, binds, answer);
            } else if (query.kind == RollupPlanner.KIND_LISTED) {
                foldListed(query, fanout, binds, answer);
            } else {
                foldGroups(query, fanout, binds, answer);
            }
        }
    }

    @TestVisible
    private static String whereFor(RollupPlanner.SourceQuery query) {
        List<String> conditions = new List<String>{ query.keyExpression + ' IN :keys' };
        for (String earlier : query.earlierKeys) {
            conditions.add(earlier + ' = null');
        }
        if (String.isNotBlank(query.whereClause)) {
            conditions.add('(' + query.whereClause + ')');
        }
        if (query.kind == RollupPlanner.KIND_ORDERED) {
            conditions.add(query.orderBy + ' != null');
        }
        return ' WHERE ' + String.join(conditions, ' AND ');
    }

    /** As above, limited to one chunk's source rows when the binds hold them. */
    private static String whereFor(RollupPlanner.SourceQuery query, Map<String, Object> binds) {
        return whereFor(query) + (binds.containsKey('rows') ? ' AND Id IN :rows' : '');
    }

    /**
     * What ends a query of a definition that includes deleted records: Recycle Bin rows and
     * archived activities are read only with ALL ROWS (ADR-0136).
     */
    @TestVisible
    private static String allRows(RollupPlanner.SourceQuery query) {
        return query.includeDeleted ? ' ALL ROWS' : '';
    }

    /** One grouped query for every grouped measure, each distinct expression selected once. */
    private static void foldGroups(
        RollupPlanner.SourceQuery query,
        Fanout fanout,
        Map<String, Object> binds,
        Answer answer
    ) {
        Map<String, String> aliasByExpression = new Map<String, String>();
        for (RollupPlanner.Measure measure : query.measures) {
            for (String expression : expressionsFor(measure)) {
                if (!aliasByExpression.containsKey(expression)) {
                    aliasByExpression.put(expression, 'a' + aliasByExpression.size());
                }
            }
        }
        List<String> columns = new List<String>{ query.keyExpression + ' k' };
        for (String expression : aliasByExpression.keySet()) {
            columns.add(expression + ' ' + aliasByExpression.get(expression));
        }
        String soql =
            'SELECT ' +
            String.join(columns, ', ') +
            ' FROM ' +
            query.sourceObject +
            whereFor(query, binds) +
            ' GROUP BY ' +
            query.keyExpression +
            allRows(query);
        for (
            AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
                soql,
                binds,
                AccessLevel.SYSTEM_MODE
            )
        ) {
            Set<Id> targets = fanout.targetsByKey.get((Id) row.get('k'));
            if (targets == null) {
                continue;
            }
            for (RollupPlanner.Measure measure : query.measures) {
                List<String> expressions = expressionsFor(measure);
                Object first = row.get(aliasByExpression.get(expressions[0]));
                Object second = expressions.size() > 1
                    ? row.get(aliasByExpression.get(expressions[1]))
                    : null;
                for (Id targetId : targets) {
                    foldGroup(
                        tallyFor(answer, measure.definitionIndex, targetId),
                        measure,
                        first,
                        second
                    );
                }
            }
        }
    }

    /** What a measure selects: AVG is a sum and a count, so partial answers merge exactly. */
    private static List<String> expressionsFor(RollupPlanner.Measure measure) {
        switch on measure.aggregate {
            when 'COUNT', 'ANY', 'NONE' {
                return new List<String>{ 'COUNT(Id)' };
            }
            when 'AVG' {
                return new List<String>{
                    'SUM(' +
                    measure.field +
                    ')',
                    'COUNT(' +
                    measure.field +
                    ')'
                };
            }
            when else {
                return new List<String>{ measure.aggregate + '(' + measure.field + ')' };
            }
        }
    }

    private static void foldGroup(
        Tally tally,
        RollupPlanner.Measure measure,
        Object first,
        Object second
    ) {
        switch on measure.aggregate {
            when 'SUM' {
                if (first != null) {
                    tally.total = (tally.total == null ? 0 : tally.total) + toDecimal(first);
                }
            }
            when 'COUNT', 'ANY', 'NONE' {
                tally.counted += first == null ? 0 : Integer.valueOf(first);
            }
            when 'AVG' {
                if (first != null) {
                    tally.total = (tally.total == null ? 0 : tally.total) + toDecimal(first);
                    tally.counted += second == null ? 0 : Integer.valueOf(second);
                }
            }
            when 'MIN' {
                if (first != null && (tally.best == null || compare(first, tally.best) < 0)) {
                    tally.best = first;
                }
            }
            when 'MAX' {
                if (first != null && (tally.best == null || compare(first, tally.best) > 0)) {
                    tally.best = first;
                }
            }
        }
    }

    /**
     * FIRST and LAST: the rows in order, keeping the best per target record. In a multi-currency
     * org a currency value is read in its row's own currency, so it is brought to the corporate
     * currency here, the unit grouped answers already arrive in (`RollupCurrency`).
     */
    private static void foldRows(
        RollupPlanner.SourceQuery query,
        Fanout fanout,
        Map<String, Object> binds,
        Answer answer
    ) {
        Set<String> columns = new Set<String>{ 'Id', query.keyExpression, query.orderBy };
        Map<String, Boolean> isCurrencyByField = currencyColumns(query, columns);
        String soql =
            'SELECT ' +
            String.join(new List<String>(columns), ', ') +
            ' FROM ' +
            query.sourceObject +
            whereFor(query, binds) +
            ' ORDER BY ' +
            query.orderBy +
            (query.descending ? ' DESC' : ' ASC') +
            ', Id' +
            allRows(query);
        for (SObject row : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            Set<Id> targets = fanout.targetsByKey.get((Id) valueAt(row, query.keyExpression));
            if (targets == null) {
                continue;
            }
            Object order = valueAt(row, query.orderBy);
            String rowId = String.valueOf(row.Id);
            for (RollupPlanner.Measure measure : query.measures) {
                Object value = asRead(row, measure, isCurrencyByField, valueAt(row, measure.field));
                for (Id targetId : targets) {
                    Tally tally = tallyFor(answer, measure.definitionIndex, targetId);
                    Integer direction = query.descending ? 1 : -1;
                    Integer better = tally.bestOrder == null
                        ? 1
                        : compare(order, tally.bestOrder) * direction;
                    // A tie goes to the lower record Id, whichever path alternative read it first.
                    if (better > 0 || (better == 0 && rowId.compareTo(tally.bestId) < 0)) {
                        tally.best = value;
                        tally.bestOrder = order;
                        tally.bestId = rowId;
                    }
                }
            }
        }
    }

    /**
     * Which measured attributes are money in a multi-currency org, the currency column added to
     * `columns` when any is, so a row's value can be brought to the corporate currency.
     */
    private static Map<String, Boolean> currencyColumns(
        RollupPlanner.SourceQuery query,
        Set<String> columns
    ) {
        Map<String, Boolean> isCurrencyByField = new Map<String, Boolean>();
        for (RollupPlanner.Measure measure : query.measures) {
            columns.add(measure.field);
            isCurrencyByField.put(
                measure.field,
                RollupCurrency.isMultiCurrency() &&
                RollupCurrency.isCurrencyPath(query.sourceObject, measure.field)
            );
        }
        if (isCurrencyByField.values().contains(true)) {
            columns.add(RollupCurrency.ISO_FIELD);
        }
        return isCurrencyByField;
    }

    /**
     * A row's value in the corporate currency, the unit grouped answers arrive in. A value
     * copied into text is copied as entered (R-R15), never converted.
     */
    private static Object asRead(
        SObject row,
        RollupPlanner.Measure measure,
        Map<String, Boolean> isCurrencyByField,
        Object value
    ) {
        if (!measure.asText && isCurrencyByField.get(measure.field) && value != null) {
            return RollupCurrency.toCorporate(
                toDecimal(value),
                (String) row.get(RollupCurrency.ISO_FIELD)
            );
        }
        return value;
    }

    /**
     * A value as text, written plainly (canonical model R-R15): a number without grouping or a
     * currency symbol, a date as `2026-03-01`, a datetime in UTC as `2026-03-01 14:05`, a checkbox
     * as `true` or `false`. UTC, not the running user's time zone, so an instant run and the
     * nightly run write the same text.
     */
    public static String toText(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).toPlainString();
        }
        if (value instanceof Date) {
            return String.valueOf((Date) value);
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd HH:mm');
        }
        return String.valueOf(value);
    }

    /**
     * COUNT_DISTINCT and the text lists: every matching row's value, blanks left out, collected
     * per target record and ordered when the answer is read (`Tally.result`). Rows are read
     * rather than grouped because a distinct count or a list cannot be merged from partial
     * grouped answers, and a long text attribute can be neither grouped nor ordered in a query.
     */
    private static void foldListed(
        RollupPlanner.SourceQuery query,
        Fanout fanout,
        Map<String, Object> binds,
        Answer answer
    ) {
        Set<String> columns = new Set<String>{ 'Id', query.keyExpression };
        if (query.orderBy != null) {
            columns.add(query.orderBy);
        }
        Map<String, Boolean> isCurrencyByField = currencyColumns(query, columns);
        String soql =
            'SELECT ' +
            String.join(new List<String>(columns), ', ') +
            ' FROM ' +
            query.sourceObject +
            whereFor(query, binds) +
            ' ORDER BY Id' +
            allRows(query);
        for (SObject row : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            Set<Id> targets = fanout.targetsByKey.get((Id) valueAt(row, query.keyExpression));
            if (targets == null) {
                continue;
            }
            String rowId = String.valueOf(row.Id);
            for (RollupPlanner.Measure measure : query.measures) {
                Object read = valueAt(row, measure.field);
                String value = toText(read);
                if (String.isBlank(value)) {
                    continue;
                }
                Object order = query.orderBy == null
                    ? value.toLowerCase()
                    : valueAt(row, query.orderBy);
                Boolean distinct =
                    measure.aggregate == 'COUNT_DISTINCT' ||
                    measure.aggregate == 'TEXT_LIST_DISTINCT';
                Listed entry = new Listed(order, rowId, value);
                entry.raw = asRead(row, measure, isCurrencyByField, read);
                entry.descending = query.descending;
                for (Id targetId : targets) {
                    Tally tally = tallyFor(answer, measure.definitionIndex, targetId);
                    tally.rowLimit = measure.rowLimit;
                    tally.add(entry, distinct);
                }
            }
        }
    }

    private static Tally tallyFor(Answer answer, Integer definitionIndex, Id targetId) {
        if (!answer.tallies.containsKey(definitionIndex)) {
            answer.tallies.put(definitionIndex, new Map<Id, Tally>());
        }
        Map<Id, Tally> byTarget = answer.tallies.get(definitionIndex);
        if (!byTarget.containsKey(targetId)) {
            byTarget.put(targetId, new Tally());
        }
        return byTarget.get(targetId);
    }

    /** A value read through a dotted path such as `Gift__r.Gift_Date__c`. */
    public static Object valueAt(SObject row, String path) {
        List<String> parts = path.split('\\.');
        SObject current = row;
        for (Integer i = 0; i < parts.size() - 1 && current != null; i++) {
            current = current.getSObject(parts[i]);
        }
        return current == null ? null : current.get(parts[parts.size() - 1]);
    }

    /** Orders two values of the same type: numbers, dates, datetimes, or text. */
    @TestVisible
    private static Integer compare(Object left, Object right) {
        if (left instanceof Date) {
            Date a = (Date) left;
            Date b = (Date) right;
            return a == b ? 0 : (a < b ? -1 : 1);
        }
        if (left instanceof Datetime) {
            Datetime a = (Datetime) left;
            Datetime b = (Datetime) right;
            return a == b ? 0 : (a < b ? -1 : 1);
        }
        if (left instanceof String) {
            return ((String) left).compareTo((String) right);
        }
        Decimal a = toDecimal(left);
        Decimal b = toDecimal(right);
        return a == b ? 0 : (a < b ? -1 : 1);
    }

    /** A number of any Apex numeric type, as a Decimal. */
    public static Decimal toDecimal(Object value) {
        if (value == null || value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        return Decimal.valueOf((Double) value);
    }

    /** The records of the target entity among these that pass a target filter (R-R8). */
    public static Set<Id> passing(
        Schema.SObjectType targetType,
        String targetFilter,
        Set<Id> targetIds
    ) {
        String soql =
            'SELECT Id FROM ' +
            String.valueOf(targetType) +
            ' WHERE Id IN :targetIds AND (' +
            targetFilter +
            ')';
        return new Map<Id, SObject>(
                Database.queryWithBinds(
                    soql,
                    new Map<String, Object>{ 'targetIds' => targetIds },
                    AccessLevel.SYSTEM_MODE
                )
            )
            .keySet();
    }

    /** The target records as they are stored now, with the attributes the pass may write. */
    public static Map<Id, SObject> stored(
        Schema.SObjectType targetType,
        Set<String> fieldNames,
        Set<Id> targetIds
    ) {
        Set<String> columns = new Set<String>{ 'Id' };
        columns.addAll(fieldNames);
        String soql =
            'SELECT ' +
            String.join(new List<String>(columns), ', ') +
            ' FROM ' +
            String.valueOf(targetType) +
            ' WHERE Id IN :targetIds';
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'targetIds' => targetIds },
                AccessLevel.SYSTEM_MODE
            )
        );
    }
}
