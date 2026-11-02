/**
 * What the Eligibility Rules panel on a program calls (P-14, canonical model Section 29ZA, R-EN8):
 * reads the program's screening rules with its open enrollments' intake values for the preview,
 * saves the rules after checking them, and screens enrollments: sets Eligibility Status
 * (Eligible, Not Eligible or Review), Basis and Reason from the rules. Reads and writes in user
 * mode. The rules are evaluated by `EligibilityRules`; the preview evaluates them in the
 * framework-free `eligibilityEngine.js` (plan Section 9.9). Returns plain wrappers.
 */
public with sharing class EligibilityController {
    private static final String CONTEXT = 'Eligibility rules panel';
    /** The most enrollments the preview lists, and the most one Screen run changes. */
    public static final Integer MAX_SHOWN = 200;
    /** The Eligibility fields screening sets or that decide it, never offered to a rule. */
    private static final Set<String> OWN_FIELDS = new Set<String>{
        'eligibility_status__c',
        'eligibility_basis__c',
        'eligibility_date__c',
        'eligibility_reason__c'
    };
    private static final Set<Schema.DisplayType> RULE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.DATE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.LONG,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE
    };

    public class Field {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        /** string, number, date or boolean. */
        @AuraEnabled
        public String kind;
    }

    /** One open enrollment, with the intake values the rules read. */
    public class Person {
        @AuraEnabled
        public Id enrollmentId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Map<String, Object> values = new Map<String, Object>();
    }

    public class State {
        /** The rules as saved, JSON text; empty when none. */
        @AuraEnabled
        public String rules;
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public Boolean canScreen = false;
        @AuraEnabled
        public List<Field> fields = new List<Field>();
        /** The Eligibility Basis values, which a rule may set. */
        @AuraEnabled
        public List<String> bases = new List<String>();
        @AuraEnabled
        public List<Person> people = new List<Person>();
        @AuraEnabled
        public Boolean moreThanShown = false;
    }

    /** What one Screen run did. */
    public class Summary {
        @AuraEnabled
        public Integer eligible = 0;
        @AuraEnabled
        public Integer notEligible = 0;
        @AuraEnabled
        public Integer review = 0;
        /** Enrollments left alone: already Eligible or Not Eligible, or with no rules to apply. */
        @AuraEnabled
        public Integer skipped = 0;
        @AuraEnabled
        public Boolean noRules = false;
        @AuraEnabled
        public Boolean moreThanScreened = false;
    }

    @AuraEnabled
    public static State getState(Id programId) {
        try {
            State state = new State();
            Program__c program = programOf(programId);
            state.rules = program.Eligibility_Rules__c;
            state.canEdit = Schema.SObjectType.Program__c.fields.Eligibility_Rules__c.isUpdateable();
            state.canScreen =
                Schema.SObjectType.Enrollment__c.fields.Eligibility_Status__c.isUpdateable() &&
                Schema.SObjectType.Enrollment__c.fields.Eligibility_Reason__c.isUpdateable();
            Map<String, Field> fields = ruleFields();
            state.fields = fields.values();
            for (
                Schema.PicklistEntry entry : Enrollment__c.Eligibility_Basis__c.getDescribe()
                    .getPicklistValues()
            ) {
                if (entry.isActive()) {
                    state.bases.add(entry.getValue());
                }
            }
            List<Enrollment__c> open = openEnrollments(programId, null, MAX_SHOWN + 1);
            state.moreThanShown = open.size() > MAX_SHOWN;
            for (Integer i = 0; i < open.size() && i < MAX_SHOWN; i++) {
                Person person = new Person();
                person.enrollmentId = open[i].Id;
                person.name = personName(open[i]);
                person.status = open[i].Eligibility_Status__c;
                person.reason = open[i].Eligibility_Reason__c;
                person.values = valuesOf(open[i], fields);
                state.people.add(person);
            }
            return state;
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /** Saves the rules after checking them; blank clears them. Returns the problems, if any. */
    @AuraEnabled
    public static List<String> saveRules(Id programId, String rules) {
        try {
            String clean = String.isBlank(rules) ? null : rules.trim();
            List<String> problems = EligibilityRules.validate(clean, ruleFields().keySet());
            if (!problems.isEmpty()) {
                return problems;
            }
            Database.update(
                new Program__c(Id = programId, Eligibility_Rules__c = clean),
                AccessLevel.USER_MODE
            );
            return problems;
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /**
     * Screens the program's open enrollments, or just this one when `enrollmentId` is given, with
     * the saved rules. A bulk run leaves enrollments already Eligible or Not Eligible alone unless
     * `includeDecided`; a single one is always screened.
     */
    @AuraEnabled
    public static Summary screen(Id programId, Id enrollmentId, Boolean includeDecided) {
        try {
            Summary summary = new Summary();
            String rules = programOf(programId).Eligibility_Rules__c;
            if (String.isBlank(rules) || !EligibilityRules.validate(rules, null).isEmpty()) {
                summary.noRules = true;
                return summary;
            }
            Map<String, Field> fields = ruleFields();
            List<Enrollment__c> candidates = openEnrollments(
                programId,
                enrollmentId,
                MAX_SHOWN + 1
            );
            summary.moreThanScreened = candidates.size() > MAX_SHOWN;
            List<Enrollment__c> changes = new List<Enrollment__c>();
            Date today = Date.today();
            for (Integer i = 0; i < candidates.size() && i < MAX_SHOWN; i++) {
                Enrollment__c enrollment = candidates[i];
                Boolean decided =
                    enrollment.Eligibility_Status__c == EligibilityRules.ELIGIBLE ||
                    enrollment.Eligibility_Status__c == EligibilityRules.NOT_ELIGIBLE;
                if (decided && enrollmentId == null && includeDecided != true) {
                    summary.skipped++;
                    continue;
                }
                EligibilityRules.Result result = EligibilityRules.evaluate(
                    rules,
                    valuesOf(enrollment, fields)
                );
                if (result == null) {
                    summary.skipped++;
                    continue;
                }
                Enrollment__c change = new Enrollment__c(
                    Id = enrollment.Id,
                    Eligibility_Status__c = result.status,
                    Eligibility_Reason__c = result.reason.abbreviate(255)
                );
                if (!String.isBlank(result.basis)) {
                    change.Eligibility_Basis__c = result.basis;
                }
                if (result.status != enrollment.Eligibility_Status__c) {
                    change.Eligibility_Date__c = result.status == EligibilityRules.REVIEW
                        ? null
                        : today;
                }
                changes.add(change);
                if (result.status == EligibilityRules.ELIGIBLE) {
                    summary.eligible++;
                } else if (result.status == EligibilityRules.NOT_ELIGIBLE) {
                    summary.notEligible++;
                } else {
                    summary.review++;
                }
            }
            Database.update(changes, AccessLevel.USER_MODE);
            return summary;
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    private static Program__c programOf(Id programId) {
        List<Program__c> programs = [
            SELECT Id, Eligibility_Rules__c
            FROM Program__c
            WHERE Id = :programId
            WITH USER_MODE
            LIMIT 1
        ];
        if (programs.isEmpty()) {
            throw UserErrors.message(Label.Programs_Elig_ActionFailed);
        }
        return programs[0];
    }

    /** The enrollment fields a rule may read, by lower case API name: the org's own intake fields. */
    @TestVisible
    private static Map<String, Field> ruleFields() {
        Map<String, Field> fields = new Map<String, Field>();
        Map<String, Schema.SObjectField> all = Schema.SObjectType.Enrollment__c.fields.getMap();
        List<String> names = new List<String>(all.keySet());
        names.sort();
        for (String name : names) {
            Schema.DescribeFieldResult describe = all.get(name).getDescribe();
            if (
                !describe.isCustom() ||
                !describe.isAccessible() ||
                OWN_FIELDS.contains(name) ||
                !RULE_TYPES.contains(describe.getType())
            ) {
                continue;
            }
            Field field = new Field();
            field.apiName = describe.getName();
            field.label = describe.getLabel();
            field.kind = kindOf(describe.getType());
            fields.put(name, field);
        }
        return fields;
    }

    private static String kindOf(Schema.DisplayType type) {
        if (type == Schema.DisplayType.DATE) {
            return 'date';
        }
        if (type == Schema.DisplayType.BOOLEAN) {
            return 'boolean';
        }
        if (
            type == Schema.DisplayType.STRING ||
            type == Schema.DisplayType.PICKLIST ||
            type == Schema.DisplayType.EMAIL ||
            type == Schema.DisplayType.PHONE
        ) {
            return 'string';
        }
        return 'number';
    }

    private static List<Enrollment__c> openEnrollments(Id programId, Id enrollmentId, Integer max) {
        Set<String> names = new Set<String>{
            'Id',
            'Contact__r.Name',
            'Account__r.Name',
            'Eligibility_Status__c',
            'Eligibility_Reason__c'
        };
        for (Field field : ruleFields().values()) {
            names.add(field.apiName);
        }
        Set<String> open = EnrollmentService.OPEN_STAGES;
        String query =
            'SELECT ' +
            String.escapeSingleQuotes(String.join(new List<String>(names), ', ')) +
            ' FROM Enrollment__c WHERE ' +
            (enrollmentId == null
                ? 'Program__c = :programId AND Stage__c IN :open'
                : 'Id = :enrollmentId AND Program__c = :programId') +
            ' ORDER BY CreatedDate DESC LIMIT :max';
        return (List<Enrollment__c>) Database.queryWithBinds(
            query,
            new Map<String, Object>{
                'programId' => programId,
                'enrollmentId' => enrollmentId,
                'open' => open,
                'max' => max
            },
            AccessLevel.USER_MODE
        );
    }

    /** The intake values the rules read: text, number, Boolean, or a date as `yyyy-MM-dd`. */
    private static Map<String, Object> valuesOf(
        Enrollment__c enrollment,
        Map<String, Field> fields
    ) {
        Map<String, Object> values = new Map<String, Object>();
        for (Field field : fields.values()) {
            Object value = enrollment.get(field.apiName);
            values.put(
                field.apiName,
                value instanceof Date ? (Object) String.valueOf(value) : value
            );
        }
        return values;
    }

    /** A refusal is passed on in its own words; a failed save says why; anything else is logged. */
    private static AuraHandledException report(Exception failure) {
        if (failure instanceof AuraHandledException) {
            return (AuraHandledException) failure;
        }
        if (failure instanceof DmlException) {
            return UserErrors.message(((DmlException) failure).getDmlMessage(0));
        }
        ErrorLogger.log(failure, CONTEXT);
        return UserErrors.message(Label.Programs_Elig_ActionFailed);
    }

    private static String personName(Enrollment__c enrollment) {
        return enrollment.Contact__r != null
            ? enrollment.Contact__r.Name
            : enrollment.Account__r?.Name;
    }
}
