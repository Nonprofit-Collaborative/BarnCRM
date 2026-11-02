/**
 * Donor scoring (feature G-19, canonical model Section 25T): recency, frequency and monetary
 * scores and a segment on every donor, from rollups the engine has already written.
 *
 * Like donor levels (ADR-0028) this class does no aggregation: it reads `Last_Gift_Date__c`,
 * `Recent_Gift_Count__c` and `Recent_Giving__c` from the same record, mutates the record in
 * memory and never saves it. The trigger handler calls it in a before context, so the scores are
 * right in the same save as the rollup that changed them, and the nightly donor level pass calls
 * it and saves, because days since the last gift move with no record saved.
 */
public with sharing class DonorScoreService {
    @TestVisible
    private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
    @TestVisible
    private static final String KEY_RECENCY = 'Donor_Score_Recency_Days__c';
    @TestVisible
    private static final String KEY_FREQUENCY = 'Donor_Score_Frequency_Gifts__c';
    @TestVisible
    private static final String KEY_MONETARY = 'Donor_Score_Monetary_Amount__c';
    private static final String SWITCH_PREFIX = 'Donor_Score_Assignment_';

    private static final List<String> OUTPUTS = new List<String>{
        'RFM_Recency_Score__c',
        'RFM_Frequency_Score__c',
        'RFM_Monetary_Score__c',
        'RFM_Score__c',
        'RFM_Segment__c'
    };

    private static Map<String, Map<String, String>> cachedFieldNames = new Map<String, Map<String, String>>();

    /** Today, replaceable in a test. */
    @TestVisible
    private static Date todayOverride;

    /** The cutoffs the organization set, or the defaults. */
    public class Cutoffs {
        public List<Decimal> recency;
        public List<Decimal> frequency;
        public List<Decimal> monetary;
    }

    public static Cutoffs cutoffs() {
        Cutoffs found = new Cutoffs();
        found.recency = DonorScoreMath.cutoffs(
            text(KEY_RECENCY),
            DonorScoreMath.DEFAULT_RECENCY_DAYS,
            true
        );
        found.frequency = DonorScoreMath.cutoffs(
            text(KEY_FREQUENCY),
            DonorScoreMath.DEFAULT_FREQUENCY_GIFTS,
            false
        );
        found.monetary = DonorScoreMath.cutoffs(
            text(KEY_MONETARY),
            DonorScoreMath.DEFAULT_MONETARY_AMOUNTS,
            false
        );
        return found;
    }

    /**
     * Scores one record in memory. Returns true when any of the five values changed, which is the
     * only case anything is written. A donor with no gift has every value cleared.
     */
    public static Boolean score(SObject record, Cutoffs cutoffs) {
        if (record == null) {
            return false;
        }
        Map<String, String> names = fieldNames(record.getSObjectType());
        if (!names.containsKey('Last_Gift_Date__c') || !names.containsKey('RFM_Segment__c')) {
            // The object does not carry giving totals or scores, so there is nothing to score.
            return false;
        }
        Date lastGift = (Date) record.get(names.get('Last_Gift_Date__c'));
        Map<String, Object> wanted = new Map<String, Object>();
        if (lastGift == null) {
            for (String output : OUTPUTS) {
                wanted.put(output, null);
            }
        } else {
            Date today = todayOverride == null ? Date.today() : todayOverride;
            Integer days = Math.max(lastGift.daysBetween(today), 0);
            Integer recency = DonorScoreMath.recencyScore(days, cutoffs.recency);
            Integer frequency = DonorScoreMath.highScore(
                (Decimal) record.get(names.get('Recent_Gift_Count__c')),
                cutoffs.frequency
            );
            Integer monetary = DonorScoreMath.highScore(
                (Decimal) record.get(names.get('Recent_Giving__c')),
                cutoffs.monetary
            );
            wanted.put('RFM_Recency_Score__c', recency);
            wanted.put('RFM_Frequency_Score__c', frequency);
            wanted.put('RFM_Monetary_Score__c', monetary);
            wanted.put('RFM_Score__c', recency + frequency + monetary);
            wanted.put('RFM_Segment__c', DonorScoreMath.segment(recency, frequency, monetary));
        }
        Boolean changed = false;
        for (String output : OUTPUTS) {
            String apiName = names.get(output);
            Object held = record.get(apiName);
            Object next = wanted.get(output);
            if (next instanceof Integer) {
                next = Decimal.valueOf((Integer) next);
            }
            if (held != next) {
                record.put(apiName, next);
                changed = true;
            }
        }
        return changed;
    }

    /**
     * Scores every record in the list and returns the ones that changed. Does nothing when the
     * object's Automation switch is off (the Automation page), so the nightly pass and the save
     * path agree.
     */
    public static List<SObject> scoreAll(List<SObject> records) {
        List<SObject> changed = new List<SObject>();
        if (records == null || records.isEmpty()) {
            return changed;
        }
        String objectName = String.valueOf(records[0].getSObjectType());
        if (!AutomationControl.isEnabled(SWITCH_PREFIX + objectName)) {
            return changed;
        }
        Cutoffs cutoffs = cutoffs();
        for (SObject record : records) {
            if (score(record, cutoffs)) {
                changed.add(record);
            }
        }
        return changed;
    }

    private static String text(String key) {
        Object value = SettingsService.getValue(SETTINGS_OBJECT, key);
        return value == null ? null : String.valueOf(value);
    }

    /** The real API name of each field this class touches, namespace or not. */
    private static Map<String, String> fieldNames(Schema.SObjectType type) {
        String key = String.valueOf(type);
        if (cachedFieldNames.containsKey(key)) {
            return cachedFieldNames.get(key);
        }
        Map<String, String> byLocalName = new Map<String, String>();
        for (
            Schema.SObjectField token : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult field = token.getDescribe();
            byLocalName.put(field.getLocalName(), field.getName());
        }
        cachedFieldNames.put(key, byLocalName);
        return byLocalName;
    }
}
