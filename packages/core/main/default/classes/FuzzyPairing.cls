/**
 * Pairs people by similar names, household aware, for the duplicate scan (C-51, canonical model
 * R-DP7, ADR-NEXT advanced duplicate management).
 *
 * The org's duplicate rules match names by their own methods and know nothing of households.
 * Here, the people who share a last name or an email with someone in the scan's chunk are
 * scored on their full names by the shared scorer (`FuzzyMatch`). A name alone is never enough:
 * two people are proposed when their names score at or above the Fuzzy Name Match setting and
 * they also share an email or a phone number, or are in different households and share a
 * mailing postal code. In one household an address is shared by design and similar names are
 * usually family (Daniel and Danielle), so there two people with nothing else in common are
 * proposed only when their names are the same once normalized. Two people whose birthdates are
 * both filled in and differ are never paired.
 *
 * Everything is read in user mode, and only the fields this person can read are used.
 */
public with sharing class FuzzyPairing {
    @TestVisible
    private static final Integer DEFAULT_THRESHOLD = 90;
    private static final Integer MIN_THRESHOLD = 80;
    private static final Integer MAX_THRESHOLD = 100;
    /** The most people one chunk compares against, so a common surname cannot exhaust a chunk. */
    @TestVisible
    private static Integer maxCandidates = 2000;
    private static final String CONTEXT = 'Duplicate scan: pairing similar names';
    private static final List<String> FIELDS = new List<String>{
        'FirstName',
        'LastName',
        'Email',
        'Phone',
        'Birthdate',
        'AccountId',
        'MailingPostalCode'
    };

    /** The Fuzzy Name Match setting in percent: blank reads as 90, out of range as the end. */
    public static Integer thresholdPercent() {
        Decimal configured = SettingsService.getSettings().Fuzzy_Match_Threshold__c;
        if (configured == null) {
            return DEFAULT_THRESHOLD;
        }
        return Math.max(MIN_THRESHOLD, Math.min(MAX_THRESHOLD, configured.intValue()));
    }

    /**
     * The pairs similar names find among these records; nothing unless they are people. Each
     * pair carries a reason and no rule; DuplicateService.pairsToRecord folds repeats. A read
     * that fails is logged and counted as the scan counts a failed source.
     */
    public static List<DuplicateService.Pair> pairsFor(List<Id> recordIds) {
        List<DuplicateService.Pair> result = new List<DuplicateService.Pair>();
        if (
            recordIds == null ||
            recordIds.isEmpty() ||
            recordIds[0].getSObjectType() != Contact.SObjectType
        ) {
            return result;
        }
        try {
            List<String> readable = readableFields();
            if (!readable.contains('LastName')) {
                return result;
            }
            String head = 'SELECT Id, ' + String.join(readable, ', ') + ' FROM Contact WHERE ';
            List<Contact> chunk = Database.queryWithBinds(
                head + 'Id IN :ids',
                new Map<String, Object>{ 'ids' => recordIds },
                AccessLevel.USER_MODE
            );
            Set<String> lastNames = new Set<String>();
            Set<String> emails = new Set<String>();
            for (Contact person : chunk) {
                lastNames.add(person.LastName);
                String email = (String) value(person, 'Email');
                if (String.isNotBlank(email)) {
                    emails.add(email);
                }
            }
            String filter = emails.isEmpty()
                ? 'LastName IN :lastNames'
                : '(LastName IN :lastNames OR Email IN :emails)';
            List<Contact> candidates = Database.queryWithBinds(
                head + filter + ' LIMIT ' + maxCandidates,
                new Map<String, Object>{ 'lastNames' => lastNames, 'emails' => emails },
                AccessLevel.USER_MODE
            );
            if (candidates.size() >= maxCandidates) {
                ErrorLogger.logMessage(
                    String.format(
                        Label.Core_DuplicateManagement_CandidateCap,
                        new List<Object>{ maxCandidates }
                    ),
                    CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            Double threshold = thresholdPercent();
            result.addAll(pairsAmong(chunk, candidates, threshold / 100));
        } catch (Exception caught) {
            DuplicateService.failureCount++;
            ErrorLogger.log(caught, CONTEXT);
        }
        return result;
    }

    private static List<DuplicateService.Pair> pairsAmong(
        List<Contact> chunk,
        List<Contact> candidates,
        Double threshold
    ) {
        List<DuplicateService.Pair> result = new List<DuplicateService.Pair>();
        Set<String> seen = new Set<String>();
        for (Contact person : chunk) {
            for (Contact other : candidates) {
                String key = DuplicateService.pairKey(person.Id, other.Id);
                if (person.Id == other.Id || seen.contains(key)) {
                    continue;
                }
                String reason = reasonFor(person, other, threshold);
                if (reason != null) {
                    seen.add(key);
                    DuplicateService.Pair pair = new DuplicateService.Pair(
                        person.Id,
                        other.Id,
                        null
                    );
                    pair.reason = reason;
                    result.add(pair);
                }
            }
        }
        return result;
    }

    /** Why the two are proposed, or null when they are not (R-DP7). */
    @TestVisible
    private static String reasonFor(Contact first, Contact second, Double threshold) {
        Date firstBorn = (Date) value(first, 'Birthdate');
        Date secondBorn = (Date) value(second, 'Birthdate');
        if (firstBorn != null && secondBorn != null && firstBorn != secondBorn) {
            return null;
        }
        Double similarity = FuzzyMatch.score(fullName(first), fullName(second));
        if (similarity < threshold) {
            return null;
        }
        Id household = (Id) value(first, 'AccountId');
        Boolean sameHousehold = household != null && household == (Id) value(second, 'AccountId');
        String shared = sharedValue(first, second, sameHousehold);
        if (shared == null) {
            return sameHousehold && similarity == 1
                ? Label.Core_DuplicateManagement_ReasonSameHousehold
                : null;
        }
        return String.format(
            Label.Core_DuplicateManagement_ReasonSimilarNames,
            new List<Object>{ String.valueOf(Math.floor(similarity * 100).intValue()), shared }
        );
    }

    /** The first value the two share, named for the reason, or null. */
    private static String sharedValue(Contact first, Contact second, Boolean sameHousehold) {
        if (
            same(
                MatchSourceService.email((String) value(first, 'Email')),
                MatchSourceService.email((String) value(second, 'Email'))
            )
        ) {
            return Label.Core_DuplicateManagement_SharedEmail;
        }
        if (
            same(
                MatchSourceService.phone((String) value(first, 'Phone')),
                MatchSourceService.phone((String) value(second, 'Phone'))
            )
        ) {
            return Label.Core_DuplicateManagement_SharedPhone;
        }
        Boolean samePostal = same(
            MatchSourceService.postalCode((String) value(first, 'MailingPostalCode')),
            MatchSourceService.postalCode((String) value(second, 'MailingPostalCode'))
        );
        return !sameHousehold && samePostal
            ? Label.Core_DuplicateManagement_SharedPostalCode
            : null;
    }

    private static Boolean same(String first, String second) {
        return first != null && first.equals(second);
    }

    private static String fullName(Contact person) {
        String firstName = (String) value(person, 'FirstName');
        return (firstName == null ? '' : firstName + ' ') + person.LastName;
    }

    /** A field's value when it was read; a field this person cannot read was not. */
    private static Object value(Contact person, String fieldName) {
        return person.getPopulatedFieldsAsMap().get(fieldName);
    }

    private static List<String> readableFields() {
        List<String> readable = new List<String>();
        Map<String, Schema.SObjectField> byName = Schema.SObjectType.Contact.fields.getMap();
        for (String name : FIELDS) {
            Schema.SObjectField field = byName.get(name);
            if (field != null && field.getDescribe().isAccessible()) {
                readable.add(name);
            }
        }
        return readable;
    }
}
