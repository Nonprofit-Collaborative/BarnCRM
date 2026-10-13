/**
 * Household names and greetings. Canonical model R-H4 to R-H9.
 *
 * The three compute methods are pure: give them the same people and the same pattern and
 * they give back the same words, with no query and no save. applyNaming is the only method
 * that touches the database.
 *
 * A pattern is a sentence with blanks in it. The blanks are {FirstName}, {LastName} and
 * {Salutation}. The {!Token} spelling is accepted as an alias so that a pattern copied
 * from a formula keeps working.
 */
@NamespaceAccessible
public with sharing class HouseholdNamingService {
    private static final String TOKEN_FIRST_NAME = '{FirstName}';
    private static final String TOKEN_LAST_NAME = '{LastName}';
    private static final String TOKEN_SALUTATION = '{Salutation}';
    private static final String DEFAULT_NAME_PATTERN = 'The {LastName} Family';
    private static final String DEFAULT_FORMAL_PATTERN = '{Salutation} {FirstName} {LastName}';
    private static final String DEFAULT_INFORMAL_PATTERN = '{FirstName}';

    private static Boolean applying = false;

    // ------------------------------------------------------------------ names

    @NamespaceAccessible
    public static String computeName(List<HouseholdService.Person> members, String pattern) {
        return computeName(members, pattern, includeDeceasedInName());
    }

    @NamespaceAccessible
    public static String computeName(
        List<HouseholdService.Person> members,
        String pattern,
        Boolean includeDeceased
    ) {
        List<HouseholdService.Person> eligible = new List<HouseholdService.Person>();
        for (HouseholdService.Person person : ordered(members)) {
            Boolean hidden = person.excludeFromName == true;
            Boolean gone = person.isDeceased == true && includeDeceased != true;
            if (!hidden && !gone) {
                eligible.add(person);
            }
        }
        if (eligible.isEmpty()) {
            return null;
        }
        String usable = String.isBlank(pattern) ? DEFAULT_NAME_PATTERN : pattern;
        List<String> surnames = distinctSurnames(eligible);
        if (surnames.size() > 1) {
            // Differing surnames read badly through a pattern, so they are listed instead:
            // "Garcia and Lee Household", "Garcia, Lee, and Smith Household".
            return joinNames(surnames) + ' ' + Label.Core_Households_NameSuffix;
        }
        String normalized = normalize(usable);
        Boolean perPerson =
            normalized.contains(TOKEN_FIRST_NAME) || normalized.contains(TOKEN_SALUTATION);
        if (!perPerson) {
            return substitute(usable, eligible[0]);
        }
        List<String> parts = new List<String>();
        for (HouseholdService.Person person : eligible) {
            String part = substitute(usable, person);
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return parts.isEmpty() ? null : joinNames(parts);
    }

    // ------------------------------------------------------------------ greetings

    @NamespaceAccessible
    public static String computeInformalGreeting(
        List<HouseholdService.Person> members,
        String pattern
    ) {
        String usable = String.isBlank(pattern) ? DEFAULT_INFORMAL_PATTERN : pattern;
        List<String> parts = new List<String>();
        for (HouseholdService.Person person : greetable(members, false)) {
            String part = substitute(usable, person);
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return parts.isEmpty() ? null : joinNames(parts);
    }

    @NamespaceAccessible
    public static String computeFormalGreeting(
        List<HouseholdService.Person> members,
        String pattern
    ) {
        return computeFormalGreeting(members, pattern, includeDeceasedInName());
    }

    @NamespaceAccessible
    public static String computeFormalGreeting(
        List<HouseholdService.Person> members,
        String pattern,
        Boolean includeDeceased
    ) {
        String usable = String.isBlank(pattern) ? DEFAULT_FORMAL_PATTERN : pattern;
        List<HouseholdService.Person> eligible = greetable(members, includeDeceased == true);
        if (eligible.isEmpty()) {
            return null;
        }
        String combined = combinedSalutation(eligible, usable);
        if (combined != null) {
            return combined;
        }
        List<String> parts = new List<String>();
        for (HouseholdService.Person person : eligible) {
            String part = substituteFormal(usable, person);
            if (String.isBlank(part)) {
                continue;
            }
            if (person.isDeceased == true) {
                part = Label.Core_Households_LatePrefix + ' ' + part;
            }
            parts.add(part);
        }
        return parts.isEmpty() ? null : joinNames(parts);
    }

    /**
     * "Mr. and Mrs. John Smith": two living people, one surname, both with a title, and a
     * pattern that asks for all three parts. Anything else is greeted person by person.
     */
    private static String combinedSalutation(
        List<HouseholdService.Person> eligible,
        String pattern
    ) {
        if (eligible.size() != 2) {
            return null;
        }
        HouseholdService.Person first = eligible[0];
        HouseholdService.Person second = eligible[1];
        if (first.isDeceased == true || second.isDeceased == true) {
            return null;
        }
        if (String.isBlank(first.salutation) || String.isBlank(second.salutation)) {
            return null;
        }
        if (String.isBlank(first.lastName) || !first.lastName.equals(second.lastName)) {
            return null;
        }
        String normalized = normalize(pattern);
        Boolean complete =
            normalized.contains(TOKEN_SALUTATION) &&
            normalized.contains(TOKEN_FIRST_NAME) &&
            normalized.contains(TOKEN_LAST_NAME);
        if (!complete) {
            return null;
        }
        String salutations =
            first.salutation +
            ' ' +
            Label.Core_Households_Conjunction +
            ' ' +
            second.salutation;
        // A formal greeting uses the name on the record, not the name a person prefers.
        return squeeze(salutations + ' ' + blankToEmpty(first.firstName) + ' ' + first.lastName);
    }

    // ------------------------------------------------------------------ saving

    /**
     * Recomputes and saves the name and both greetings for each household given, skipping
     * every household whose wording a person has taken over. Returns how many households
     * were changed. R-H8 and R-H14.
     *
     * Membership upkeep does not come through here: HouseholdService.afterMembershipChange
     * reads a household once and saves its count, primary and wording together, with the
     * same `Wording`. This is for the callers that change only the wording: the batch after
     * a pattern changes, and a household whose custom name box is cleared.
     */
    @NamespaceAccessible
    public static Integer applyNaming(Set<Id> householdIds) {
        return applyNaming(householdIds, null);
    }

    /**
     * The same, adding to `skippedNative` (when given) the households left alone because
     * they carry a native Nonprofit Cloud household group: mutual exclusion (product-plan
     * Section 11.2 item 9), BarnCRM never rewrites the wording of an Account somebody else's
     * household model owns.
     */
    @NamespaceAccessible
    public static Integer applyNaming(Set<Id> householdIds, Set<Id> skippedNative) {
        if (applying || householdIds == null || householdIds.isEmpty()) {
            return 0;
        }
        applying = true;
        Integer changed = 0;
        try {
            Set<Id> natives = HouseholdSelector.nativeHouseholdAccountsAmong(householdIds);
            if (skippedNative != null) {
                skippedNative.addAll(natives);
            }
            Set<Id> namable = new Set<Id>(householdIds);
            namable.removeAll(natives);
            Wording wording = new Wording();
            Map<Id, List<HouseholdService.Person>> membersByHousehold = HouseholdService.getMembers(
                namable
            );
            // R-H5 reads the primary from the mode's own source of truth: the membership rows
            // in junction mode (getMembers has already flagged it), the field in contact mode.
            Boolean primaryFromField = !HouseholdService.isJunctionMode();
            List<Account> updates = new List<Account>();
            for (Account household : HouseholdSelector.getHouseholdsByIds(namable)) {
                Account change = new Account(Id = household.Id);
                Id primaryId = primaryFromField ? household.Primary_Contact__c : null;
                List<HouseholdService.Person> members = membersByHousehold.get(household.Id);
                if (wording.apply(household, members, primaryId, change)) {
                    updates.add(change);
                }
            }
            if (!updates.isEmpty()) {
                // The name and the two greetings are computed by the package, so they are
                // saved by HouseholdWriter rather than with the saving user's own access.
                HouseholdWriter.updateHouseholds(updates);
                changed = updates.size();
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextNaming);
        } finally {
            applying = false;
        }
        return changed;
    }

    /**
     * The org's naming settings, read once for a pass over many households, and the one
     * place a household's saved wording is compared with what its members now call for.
     */
    @NamespaceAccessible
    public class Wording {
        private Id recordTypeId = HouseholdService.householdRecordTypeId();
        private Boolean includeDeceased = false;
        private String namePattern;
        private String formalPattern;
        private String informalPattern;

        @NamespaceAccessible
        public Wording() {
            BarnCRM_Settings__c settings = SettingsService.getSettings();
            if (settings != null) {
                includeDeceased = settings.Include_Deceased_In_Name__c == true;
                namePattern = settings.Household_Name_Pattern__c;
                formalPattern = settings.Formal_Greeting_Pattern__c;
                informalPattern = settings.Informal_Greeting_Pattern__c;
            }
        }

        /**
         * Puts the name and both greetings the members call for on `target`, when any of
         * them differs from what `household` holds, and says whether it did. A household
         * whose wording a person has taken over, or an account that is not a household, is
         * never changed. `primaryId` marks the primary member in contact mode, where the
         * household field holds it; in junction mode the members already carry the flag and
         * it is null.
         */
        @NamespaceAccessible
        public Boolean apply(
            Account household,
            List<HouseholdService.Person> members,
            Id primaryId,
            Account target
        ) {
            if (household.Custom_Name__c == true) {
                return false;
            }
            if (recordTypeId != null && household.RecordTypeId != recordTypeId) {
                return false;
            }
            if (members == null) {
                members = new List<HouseholdService.Person>();
            }
            markPrimary(members, primaryId);
            String name = computeName(members, namePattern, includeDeceased);
            if (String.isBlank(name)) {
                name = Label.Core_Households_NamePlaceholder;
            }
            String formal = computeFormalGreeting(members, formalPattern, includeDeceased);
            String informal = computeInformalGreeting(members, informalPattern);
            Boolean hasChanges =
                differs(household.Name, name) ||
                differs(household.Household_Formal_Greeting__c, formal) ||
                differs(household.Household_Informal_Greeting__c, informal);
            if (hasChanges) {
                target.Name = name;
                target.Household_Formal_Greeting__c = formal;
                target.Household_Informal_Greeting__c = informal;
            }
            return hasChanges;
        }
    }

    // ------------------------------------------------------------------ helpers

    private static void markPrimary(List<HouseholdService.Person> members, Id primaryId) {
        if (primaryId == null) {
            return;
        }
        for (HouseholdService.Person person : members) {
            if (person.id == primaryId) {
                person.isPrimary = true;
            }
        }
    }

    private static Boolean includeDeceasedInName() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && settings.Include_Deceased_In_Name__c == true;
    }

    private static List<HouseholdService.Person> greetable(
        List<HouseholdService.Person> members,
        Boolean includeDeceased
    ) {
        List<HouseholdService.Person> result = new List<HouseholdService.Person>();
        for (HouseholdService.Person person : ordered(members)) {
            if (person.excludeFromGreetings == true) {
                continue;
            }
            if (person.isDeceased == true && !includeDeceased) {
                continue;
            }
            result.add(person);
        }
        return result;
    }

    private static List<HouseholdService.Person> ordered(List<HouseholdService.Person> members) {
        List<HouseholdService.Person> result = new List<HouseholdService.Person>();
        if (members == null) {
            return result;
        }
        for (HouseholdService.Person person : members) {
            if (person != null) {
                result.add(person);
            }
        }
        result.sort();
        return result;
    }

    /**
     * Surnames in member order, each counted once. A hyphenated surname is one surname and
     * is never split. R-H6.
     */
    private static List<String> distinctSurnames(List<HouseholdService.Person> members) {
        List<String> result = new List<String>();
        Set<String> seen = new Set<String>();
        for (HouseholdService.Person person : members) {
            if (String.isBlank(person.lastName)) {
                continue;
            }
            // Two spellings of one surname are one surname, so "smith" and "Smith" never
            // produce "smith and Smith Household".
            String key = person.lastName.toLowerCase();
            if (seen.contains(key)) {
                continue;
            }
            seen.add(key);
            result.add(person.lastName);
        }
        return result;
    }

    private static String joinNames(List<String> parts) {
        if (parts.isEmpty()) {
            return null;
        }
        if (parts.size() == 1) {
            return parts[0];
        }
        String conjunction = Label.Core_Households_Conjunction;
        if (parts.size() == 2) {
            return parts[0] + ' ' + conjunction + ' ' + parts[1];
        }
        List<String> leading = new List<String>();
        for (Integer i = 0; i < parts.size() - 1; i++) {
            leading.add(parts[i]);
        }
        String separator = Label.Core_Households_ListSeparator + ' ';
        return String.join(leading, separator) +
            separator +
            conjunction +
            ' ' +
            parts[parts.size() - 1];
    }

    private static String substitute(String pattern, HouseholdService.Person person) {
        String result = normalize(pattern);
        result = result.replace(TOKEN_FIRST_NAME, blankToEmpty(displayFirstName(person)));
        result = result.replace(TOKEN_LAST_NAME, blankToEmpty(person.lastName));
        result = result.replace(TOKEN_SALUTATION, blankToEmpty(person.salutation));
        return squeeze(result);
    }

    /**
     * The same substitution, with the name on the record rather than the preferred name,
     * which is what a letter uses.
     */
    private static String substituteFormal(String pattern, HouseholdService.Person person) {
        HouseholdService.Person formal = person.copy();
        formal.preferredName = null;
        return substitute(pattern, formal);
    }

    private static String displayFirstName(HouseholdService.Person person) {
        return String.isNotBlank(person.preferredName) ? person.preferredName : person.firstName;
    }

    private static String normalize(String pattern) {
        return pattern == null ? '' : pattern.replace('{!', '{');
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static String squeeze(String value) {
        return value == null ? '' : value.replaceAll('\\s+', ' ').trim();
    }

    private static Boolean differs(String current, String proposed) {
        String left = current == null ? '' : current;
        String right = proposed == null ? '' : proposed;
        return !left.equals(right);
    }
}
