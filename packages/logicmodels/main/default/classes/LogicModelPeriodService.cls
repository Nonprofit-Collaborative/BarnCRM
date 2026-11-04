/**
 * A logic model's shared reporting periods (canonical model R-LM4; v1.0 modules-23): the list
 * kept on the model as JSON (plan 9.9), and copying its periods onto indicators so they line up
 * in the Logic Model Report (R-IN7).
 *
 * The list is a template, not a link: copying creates ordinary Indicator Period rows (name and
 * dates, no target or result), skipping an indicator that already has a period with the same
 * dates (R-IP2). Every read and write runs in user mode.
 *
 * Stored shape: `{"version": 1, "periods": [{"name": "2026 Q1", "startDate": "2026-01-01",
 * "endDate": "2026-03-31"}]}`.
 */
public with sharing class LogicModelPeriodService {
    private static final Integer VERSION = 1;
    private static final Integer MAX_PERIODS = 60;
    private static final Integer MAX_NAME = 80;

    /** One shared period. */
    public class Period {
        public String name;
        public Date startDate;
        public Date endDate;

        public String key() {
            return String.valueOf(startDate) + '|' + String.valueOf(endDate);
        }

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'name' => name,
                'startDate' => String.valueOf(startDate),
                'endDate' => String.valueOf(endDate)
            };
        }
    }

    // ------------------------------------------------------------------------------- reading

    /**
     * The stored periods as plain JSON for the builder, in start date order; empty when there
     * are none or the text cannot be read.
     *
     * @param stored the model's Periods__c
     * @return name, startDate and endDate (ISO dates) per period
     */
    public static List<Map<String, Object>> periodsOf(String stored) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Period period : parse(stored)) {
            rows.add(period.toMap());
        }
        return rows;
    }

    @TestVisible
    private static List<Period> parse(String stored) {
        List<Period> periods = new List<Period>();
        if (String.isBlank(stored)) {
            return periods;
        }
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(stored);
            for (Object item : (List<Object>) raw.get('periods')) {
                periods.add(periodFrom((Map<String, Object>) item));
            }
        } catch (Exception unreadable) {
            return new List<Period>();
        }
        return periods;
    }

    private static Period periodFrom(Map<String, Object> fields) {
        Period period = new Period();
        period.name = fields.get('name') == null ? null : String.valueOf(fields.get('name')).trim();
        period.startDate = dateOf(fields.get('startDate'));
        period.endDate = dateOf(fields.get('endDate'));
        return period;
    }

    private static Date dateOf(Object value) {
        return value == null || String.isBlank(String.valueOf(value))
            ? null
            : Date.valueOf(String.valueOf(value));
    }

    private static List<Period> periodsOfModel(Id modelId) {
        List<Logic_Model__c> models = [
            SELECT Periods__c
            FROM Logic_Model__c
            WHERE Id = :modelId
            WITH USER_MODE
        ];
        if (models.isEmpty()) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Builder_NotFound);
        }
        return parse(models[0].Periods__c);
    }

    // ------------------------------------------------------------------------------- saving

    /**
     * Replaces the model's list of periods, checked: a name of at most 80 characters, both
     * dates, an end not before the start, no two with the same dates, at most 60.
     *
     * @param modelId the logic model
     * @param rows the periods, each name, startDate and endDate
     */
    public static void save(Id modelId, List<Object> rows) {
        List<Period> periods = new List<Period>();
        Set<String> keys = new Set<String>();
        for (Object row : rows == null ? new List<Object>() : rows) {
            Period period;
            try {
                period = periodFrom((Map<String, Object>) row);
            } catch (Exception unreadable) {
                throw new LogicModelService.BuilderException(
                    BarnHelp.text('LogicModels', 'LogicModels_Periods_Invalid')
                );
            }
            if (
                String.isBlank(period.name) ||
                period.name.length() > MAX_NAME ||
                period.startDate == null ||
                period.endDate == null
            ) {
                throw new LogicModelService.BuilderException(
                    BarnHelp.text('LogicModels', 'LogicModels_Periods_Invalid')
                );
            }
            if (period.endDate < period.startDate) {
                throw new LogicModelService.BuilderException(
                    BarnHelp.text(
                        'LogicModels',
                        'LogicModels_Periods_EndBeforeStart',
                        new List<Object>{ period.name }
                    )
                );
            }
            if (!keys.add(period.key())) {
                throw new LogicModelService.BuilderException(
                    BarnHelp.text(
                        'LogicModels',
                        'LogicModels_Periods_SameDates',
                        new List<Object>{ period.name }
                    )
                );
            }
            periods.add(period);
        }
        if (periods.size() > MAX_PERIODS) {
            throw new LogicModelService.BuilderException(
                BarnHelp.text(
                    'LogicModels',
                    'LogicModels_Periods_TooMany',
                    new List<Object>{ MAX_PERIODS }
                )
            );
        }
        List<Map<String, Object>> stored = new List<Map<String, Object>>();
        for (Period period : sortedByStart(periods)) {
            stored.add(period.toMap());
        }
        update as user new Logic_Model__c(
            Id = modelId,
            Periods__c = periods.isEmpty()
                ? null
                : JSON.serialize(new Map<String, Object>{ 'version' => VERSION, 'periods' => stored })
        );
    }

    private static List<Period> sortedByStart(List<Period> periods) {
        Map<String, Period> byKey = new Map<String, Period>();
        List<String> keys = new List<String>();
        for (Period period : periods) {
            String key = period.key() + '|' + period.name;
            byKey.put(key, period);
            keys.add(key);
        }
        keys.sort();
        List<Period> sorted = new List<Period>();
        for (String key : keys) {
            sorted.add(byKey.get(key));
        }
        return sorted;
    }

    // ------------------------------------------------------------------------------ copying

    /**
     * Add Period to Every Indicator: the model period with these dates, created on every
     * indicator of the model that has no period with the same dates.
     *
     * @param modelId the logic model
     * @param startDate the model period's start (ISO date)
     * @param endDate the model period's end (ISO date)
     * @return how many indicators got the period
     */
    public static Integer addToEvery(Id modelId, String startDate, String endDate) {
        Period wanted = null;
        for (Period period : periodsOfModel(modelId)) {
            if (
                String.valueOf(period.startDate) == startDate &&
                String.valueOf(period.endDate) == endDate
            ) {
                wanted = period;
            }
        }
        if (wanted == null) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Builder_NotFound);
        }
        List<Indicator__c> indicators = [
            SELECT Id, (SELECT Start_Date__c, End_Date__c FROM Periods__r)
            FROM Indicator__c
            WHERE Element__r.Logic_Model__c = :modelId
            WITH USER_MODE
        ];
        return copy(indicators, new List<Period>{ wanted });
    }

    /**
     * Use the Model's Periods: every model period the indicator lacks, created on it.
     *
     * @param modelId the logic model
     * @param indicatorId the indicator, of that model
     * @return how many periods were added
     */
    public static Integer useForIndicator(Id modelId, Id indicatorId) {
        List<Indicator__c> indicators = [
            SELECT Id, (SELECT Start_Date__c, End_Date__c FROM Periods__r)
            FROM Indicator__c
            WHERE Id = :indicatorId AND Element__r.Logic_Model__c = :modelId
            WITH USER_MODE
        ];
        if (indicators.isEmpty()) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Builder_NotFound);
        }
        return copy(indicators, periodsOfModel(modelId));
    }

    private static Integer copy(List<Indicator__c> indicators, List<Period> periods) {
        List<Indicator_Period__c> created = new List<Indicator_Period__c>();
        for (Indicator__c indicator : indicators) {
            Set<String> taken = new Set<String>();
            for (Indicator_Period__c existing : indicator.Periods__r) {
                taken.add(
                    String.valueOf(existing.Start_Date__c) +
                        '|' +
                        String.valueOf(existing.End_Date__c)
                );
            }
            for (Period period : periods) {
                if (taken.contains(period.key())) {
                    continue;
                }
                created.add(
                    new Indicator_Period__c(
                        Indicator__c = indicator.Id,
                        Name = period.name,
                        Start_Date__c = period.startDate,
                        End_Date__c = period.endDate
                    )
                );
            }
        }
        if (!created.isEmpty()) {
            insert as user created;
        }
        return created.size();
    }
}
