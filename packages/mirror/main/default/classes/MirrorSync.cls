/**
 * What Mirror's copies to standard objects share: Campaign sync (X-02, ADR-0056) and the
 * Opportunity mirror (X-01, canonical model Section 29C). Kept in one place so the two copies
 * compare values, check limits and read typed identifiers the same way.
 *
 * - `same`: equality as a person means it.
 * - `hasHeadroom`: whether a copy made inside someone else's save still fits the transaction.
 * - `idOf`: a typed identifier, checked against the object it must belong to.
 * - `Warnings`: refusals grouped by the platform's message, written in one statement, so a rule
 *   that refuses every record of a large save costs a handful of Error Log entries (R-OM6).
 */
public with sharing class MirrorSync {
    /** Left over for the other automation running in the same transaction. */
    public static final Integer SAFETY_MARGIN = 10;
    /** How many record names a grouped Warning spells out before it says "and N more". */
    public static final Integer NAMES_SHOWN = 10;
    /**
     * How many distinct messages are kept; further ones are counted together. A platform message
     * can carry a record identifier, which would otherwise make every refusal its own Warning.
     */
    public static final Integer MESSAGES_KEPT = 50;

    /** Test seams standing in for `Limits`, to show what a nearly spent transaction does. */
    @TestVisible
    private static Integer simulatedQueriesUsed;
    @TestVisible
    private static Integer simulatedDmlStatementsUsed;
    @TestVisible
    private static Integer simulatedCpuTimeUsed;

    /**
     * Equality as a person means it: text compared with case (Apex's own == ignores it, so a
     * rename from "spring appeal" to "Spring appeal" would never be copied), amounts by value and
     * not by scale, so 100 and 100.00 are the same.
     */
    public static Boolean same(Object left, Object right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        if (left instanceof String && right instanceof String) {
            return ((String) left).equals((String) right);
        }
        if (left instanceof Decimal && right instanceof Decimal) {
            return ((Decimal) left - (Decimal) right) == 0;
        }
        return left == right;
    }

    /**
     * Whether this transaction still has room for this many queries, DML statements and rows, with
     * a margin for the other automation in the same transaction.
     */
    public static Boolean hasHeadroom(Integer queries, Integer statements, Integer rows) {
        Integer queriesUsed = simulatedQueriesUsed != null
            ? simulatedQueriesUsed
            : Limits.getQueries();
        Integer statementsUsed = simulatedDmlStatementsUsed != null
            ? simulatedDmlStatementsUsed
            : Limits.getDmlStatements();
        Integer rowsLeft = Limits.getLimitDmlRows() - Limits.getDmlRows();
        return Limits.getLimitQueries() - queriesUsed >=
            queries + SAFETY_MARGIN &&
            Limits.getLimitDmlStatements() - statementsUsed >=
            statements + SAFETY_MARGIN &&
            rowsLeft >= rows + SAFETY_MARGIN;
    }

    /**
     * The same, and at least this share of the transaction's CPU time still unspent. A write to a
     * standard object runs the org's own automation on it, which can be heavy (NPSP's rollups on
     * Opportunity), so a copy started with little CPU left would fail the whole save.
     */
    public static Boolean hasHeadroom(
        Integer queries,
        Integer statements,
        Integer rows,
        Decimal cpuShareLeft
    ) {
        Integer cpuUsed = simulatedCpuTimeUsed != null ? simulatedCpuTimeUsed : Limits.getCpuTime();
        Integer cpuLimit = Limits.getLimitCpuTime();
        return hasHeadroom(queries, statements, rows) &&
            (cpuLimit - cpuUsed) >= cpuLimit * cpuShareLeft;
    }

    /**
     * The same, and at least this share of the transaction's queries and DML statements still
     * unspent as well. A fixed margin cannot cover automation whose cost is not known in advance:
     * NPSP's Opportunity triggers can spend twenty queries or more per chunk inside the same save,
     * and a limit reached there cannot be caught, so the save being copied from would fail.
     */
    public static Boolean hasHeadroom(
        Integer queries,
        Integer statements,
        Integer rows,
        Decimal cpuShareLeft,
        Decimal limitShareLeft
    ) {
        Integer queriesUsed = simulatedQueriesUsed != null
            ? simulatedQueriesUsed
            : Limits.getQueries();
        Integer statementsUsed = simulatedDmlStatementsUsed != null
            ? simulatedDmlStatementsUsed
            : Limits.getDmlStatements();
        Integer queryLimit = Limits.getLimitQueries();
        Integer statementLimit = Limits.getLimitDmlStatements();
        return hasHeadroom(queries, statements, rows, cpuShareLeft) &&
            queryLimit - queriesUsed >=
            queryLimit * limitShareLeft + queries &&
            statementLimit - statementsUsed >=
            statementLimit * limitShareLeft + statements;
    }

    /**
     * The typed text as an identifier of the expected object, in its 18 character form, or null
     * when it is blank, not an identifier, or another object's.
     */
    public static Id idOf(String typed, Schema.SObjectType expected) {
        if (String.isBlank(typed) || expected == null) {
            return null;
        }
        Id parsed;
        try {
            parsed = Id.valueOf(typed.trim());
        } catch (Exception notAnId) {
            return null;
        }
        return parsed.getSObjectType() == expected ? parsed : null;
    }

    /**
     * Refusals grouped by message, written together. One Warning per distinct message: a message
     * that concerns one record names it, and one that concerns many gives the count and the first
     * few names.
     */
    public class Warnings {
        private final List<String> order = new List<String>();
        private final Map<String, List<String>> namesByMessage = new Map<String, List<String>>();
        private final Map<String, Integer> countByMessage = new Map<String, Integer>();
        private final Map<String, Id> firstRecordByMessage = new Map<String, Id>();

        /** Records one refusal of the named record. */
        public void add(String message, String recordName, Id recordId) {
            String key = keyFor(String.isBlank(message) ? '' : message);
            if (!countByMessage.containsKey(key)) {
                order.add(key);
                namesByMessage.put(key, new List<String>());
                countByMessage.put(key, 0);
                firstRecordByMessage.put(key, recordId);
            }
            countByMessage.put(key, countByMessage.get(key) + 1);
            List<String> names = namesByMessage.get(key);
            if (names.size() < NAMES_SHOWN && String.isNotBlank(recordName)) {
                names.add(recordName);
            }
        }

        /** Takes in another call's refusals, for a run that reports once when it ends. */
        public void addAll(Warnings other) {
            if (other == null) {
                return;
            }
            for (String theirs : other.order) {
                String key = keyFor(theirs);
                if (!countByMessage.containsKey(key)) {
                    order.add(key);
                    namesByMessage.put(key, new List<String>());
                    countByMessage.put(key, 0);
                    firstRecordByMessage.put(key, other.firstRecordByMessage.get(theirs));
                }
                countByMessage.put(key, countByMessage.get(key) + other.countByMessage.get(theirs));
                List<String> names = namesByMessage.get(key);
                for (String name : other.namesByMessage.get(theirs)) {
                    if (names.size() < NAMES_SHOWN) {
                        names.add(name);
                    }
                }
            }
        }

        /** The message itself, or the shared one once as many distinct messages are kept. */
        private String keyFor(String message) {
            if (countByMessage.containsKey(message) || order.size() < MESSAGES_KEPT - 1) {
                return message;
            }
            return Label.Mirror_Sync_OtherMessages;
        }

        /** How many records were refused, across every message. */
        public Integer count() {
            Integer total = 0;
            for (Integer each : countByMessage.values()) {
                total += each;
            }
            return total;
        }

        public Boolean isEmpty() {
            return order.isEmpty();
        }

        /**
         * Writes one Warning per message, all in one statement, and empties the list.
         *
         * @param context the Error Log context
         * @param oneTemplate the wording for one record: {0} its name, {1} the message
         * @param manyTemplate the wording for several: {0} the count, {1} the names, {2} the message
         */
        public void write(String context, String oneTemplate, String manyTemplate) {
            if (order.isEmpty()) {
                return;
            }
            List<String> messages = new List<String>();
            List<Id> recordIds = new List<Id>();
            for (String key : order) {
                Integer howMany = countByMessage.get(key);
                List<String> names = namesByMessage.get(key);
                if (howMany == 1) {
                    messages.add(
                        String.format(
                            oneTemplate,
                            new List<Object>{ names.isEmpty() ? '' : names[0], key }
                        )
                    );
                } else {
                    String listed = String.join(names, ', ');
                    if (howMany > names.size()) {
                        listed = String.format(
                            Label.Mirror_Sync_AndMore,
                            new List<Object>{ listed, howMany - names.size() }
                        );
                    }
                    messages.add(
                        String.format(manyTemplate, new List<Object>{ howMany, listed, key })
                    );
                }
                recordIds.add(firstRecordByMessage.get(key));
            }
            order.clear();
            namesByMessage.clear();
            countByMessage.clear();
            firstRecordByMessage.clear();
            ErrorLogger.logMessages(messages, recordIds, context, ErrorLogger.SEVERITY_WARNING);
        }
    }
}
