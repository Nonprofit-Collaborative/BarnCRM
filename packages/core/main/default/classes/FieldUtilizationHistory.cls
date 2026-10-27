/**
 * The Snapshot History list on the Field Utilization tab (canonical model Section 29F): one
 * entry per saved count, newest first, read in user mode.
 *
 * A saved count is the set of rows sharing one Taken At. SOQL cannot group by a DateTime, so the
 * selector groups by the hour and the person, and this class splits any group that holds more
 * than one save (two saves in one hour is ordinary: save, change a field, count, save again).
 */
public with sharing class FieldUtilizationHistory {
    /** The most saves the list returns for one object. */
    public static final Integer MAX_RUNS = 50;

    /** One saved count. */
    public class Run {
        public Datetime takenAt;
        public Id savedById;
        public Integer rowCount = 0;
        public Integer fieldCount = 0;
        public Decimal filled = 0;
        public Decimal total = 0;
        public Set<String> fieldNames = new Set<String>();

        /** Filled values as a percentage of the records looked at, across every row of the save. */
        public Decimal averagePercent() {
            return total > 0 ? (filled * 100).divide(total, 1) : null;
        }
    }

    /** The newest saves for the object, newest first, at most MAX_RUNS. */
    public static List<Run> latest(String objectName) {
        List<Run> runs = new List<Run>();
        for (AggregateResult bucket : FieldUtilizationSelector.groupsByHour(objectName, MAX_RUNS)) {
            Datetime firstAt = (Datetime) bucket.get('firstAt');
            Datetime lastAt = (Datetime) bucket.get('lastAt');
            Id savedBy = (Id) bucket.get('CreatedById');
            if (firstAt == lastAt) {
                Run run = new Run();
                run.takenAt = firstAt;
                run.savedById = savedBy;
                run.rowCount = (Integer) bucket.get('n');
                run.fieldCount = (Integer) bucket.get('fieldCount');
                run.filled = toDecimal(bucket.get('filled'));
                run.total = toDecimal(bucket.get('total'));
                runs.add(run);
            } else {
                runs.addAll(split(objectName, savedBy, firstAt, lastAt));
            }
        }
        runs.sort(new NewestFirst());
        while (runs.size() > MAX_RUNS) {
            runs.remove(runs.size() - 1);
        }
        return runs;
    }

    /** The people's names, by user Id, for a list of saves. */
    public static Map<Id, String> namesOf(List<Run> runs) {
        Set<Id> ids = new Set<Id>();
        for (Run run : runs) {
            ids.add(run.savedById);
        }
        return ids.isEmpty() ? new Map<Id, String>() : FieldUtilizationSelector.userNames(ids);
    }

    /** One person's saves between two times, told apart by Taken At. */
    private static List<Run> split(
        String objectName,
        Id savedBy,
        Datetime firstAt,
        Datetime lastAt
    ) {
        Map<Datetime, Run> byTakenAt = new Map<Datetime, Run>();
        for (
            Field_Utilization_Snapshot__c row : FieldUtilizationSelector.rowsBetween(
                objectName,
                savedBy,
                firstAt,
                lastAt
            )
        ) {
            Run run = byTakenAt.get(row.Taken_At__c);
            if (run == null) {
                run = new Run();
                run.takenAt = row.Taken_At__c;
                run.savedById = savedBy;
                byTakenAt.put(row.Taken_At__c, run);
            }
            run.rowCount++;
            run.fieldNames.add(row.Field_Name__c);
            run.fieldCount = run.fieldNames.size();
            run.filled += row.Filled_Count__c == null ? 0 : row.Filled_Count__c;
            run.total += row.Record_Count__c == null ? 0 : row.Record_Count__c;
        }
        return byTakenAt.values();
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? 0 : Decimal.valueOf(String.valueOf(value));
    }

    private class NewestFirst implements System.Comparator<Run> {
        public Integer compare(Run left, Run right) {
            if (left.takenAt == right.takenAt) {
                return 0;
            }
            return left.takenAt > right.takenAt ? -1 : 1;
        }
    }
}
