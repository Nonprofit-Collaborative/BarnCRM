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
 * - FIRST and LAST read rows ordered by the order attribute and keep the best per record.
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13, ADR-0015, and RollupWriter): every
 * query here runs in system mode and without sharing, because a total must not depend on who
 * saved the gift. Nothing here is shown to a user; the values go straight to `RollupWriter`.
 */
public without sharing class RollupAggregator {
    /** At most this many references per query, so a grouped answer stays under 2,000 rows. */
    @TestVisible
    private static Integer keysPerQuery = 1000;

    /** One definition's running answer for one target record. */
    public class Tally {
        public Decimal total;
        public Integer counted = 0;
        public Object best;
        public Object bestOrder;

        /** The value to write: zero for a sum or count of nothing, blank otherwise. */
        public Object result(String aggregate) {
            switch on aggregate {
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
     * Calculates every planned definition for these target records.
     *
     * @param plan the planned pass
     * @param targetIds the target records to calculate
     */
    public static Answer calculate(RollupPlanner.Plan plan, Set<Id> targetIds) {
        Answer answer = new Answer();
        if (plan == null || targetIds == null || targetIds.isEmpty()) {
            return answer;
        }
        Map<String, Fanout> fanoutByToken = new Map<String, Fanout>();
        for (RollupPlanner.SourceQuery query : plan.queries) {
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
        }
        return answer;
    }

    /** Which target records each reference read off a source row counts towards. */
    private class Fanout {
        Set<Id> keys = new Set<Id>();
        Map<Id, Set<Id>> targetsByKey = new Map<Id, Set<Id>>();

        void add(Id key, Id targetId) {
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

    private static void run(RollupPlanner.SourceQuery query, Fanout fanout, Answer answer) {
        List<Id> keys = new List<Id>(fanout.keys);
        for (Integer start = 0; start < keys.size(); start += keysPerQuery) {
            Set<Id> slice = new Set<Id>();
            for (Integer i = start; i < Math.min(start + keysPerQuery, keys.size()); i++) {
                slice.add(keys[i]);
            }
            Map<String, Object> binds = new Map<String, Object>{ 'keys' => slice };
            if (query.kind == RollupPlanner.KIND_ORDERED) {
                foldRows(query, fanout, binds, answer);
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
        if (query.orderBy != null) {
            conditions.add(query.orderBy + ' != null');
        }
        return ' WHERE ' + String.join(conditions, ' AND ');
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
            whereFor(query) +
            ' GROUP BY ' +
            query.keyExpression;
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
            when 'COUNT' {
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
            when 'COUNT' {
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
        Set<String> columns = new Set<String>{ query.keyExpression, query.orderBy };
        Map<String, Boolean> isCurrencyByField = new Map<String, Boolean>();
        for (RollupPlanner.Measure measure : query.measures) {
            columns.add(measure.field);
            isCurrencyByField.put(
                measure.field,
                RollupCurrency.isMultiCurrency() &&
                RollupCurrency.isCurrencyPath(query.sourceObject, measure.field)
            );
        }
        Boolean readsCurrency = isCurrencyByField.values().contains(true);
        if (readsCurrency) {
            columns.add(RollupCurrency.ISO_FIELD);
        }
        String soql =
            'SELECT ' +
            String.join(new List<String>(columns), ', ') +
            ' FROM ' +
            query.sourceObject +
            whereFor(query) +
            ' ORDER BY ' +
            query.orderBy +
            (query.descending ? ' DESC' : ' ASC') +
            ', Id';
        for (SObject row : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            Set<Id> targets = fanout.targetsByKey.get((Id) valueAt(row, query.keyExpression));
            if (targets == null) {
                continue;
            }
            Object order = valueAt(row, query.orderBy);
            for (RollupPlanner.Measure measure : query.measures) {
                Object value = valueAt(row, measure.field);
                if (isCurrencyByField.get(measure.field) && value != null) {
                    value = RollupCurrency.toCorporate(
                        toDecimal(value),
                        (String) row.get(RollupCurrency.ISO_FIELD)
                    );
                }
                for (Id targetId : targets) {
                    Tally tally = tallyFor(answer, measure.definitionIndex, targetId);
                    Integer direction = query.descending ? 1 : -1;
                    if (
                        tally.bestOrder == null ||
                        compare(order, tally.bestOrder) * direction > 0
                    ) {
                        tally.best = value;
                        tally.bestOrder = order;
                    }
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
    @TestVisible
    private static Object valueAt(SObject row, String path) {
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

    /** Up to this many records of the target entity, in Id order. */
    public static Set<Id> allIds(Schema.SObjectType targetType, Integer maxRecords) {
        return new Map<Id, SObject>(
                Database.queryWithBinds(
                    'SELECT Id FROM ' +
                        String.valueOf(targetType) +
                        ' ORDER BY Id LIMIT :maxRecords',
                    new Map<String, Object>{ 'maxRecords' => maxRecords },
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
