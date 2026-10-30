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
 *
 * The words BarnCRM adds to a stored name or greeting ("and", the list separator, "the late",
 * "Household", the placeholder name) are custom labels read in the org's default language,
 * not the language of whoever saved (owner decision, 2026-10-13): otherwise the same household
 * would be renamed into another language each time someone else saved it. See storedLabel.
 */
@NamespaceAccessible
public with sharing class HouseholdNamingService {
    /** The package namespace, or empty while it is deferred; derived, never hard-coded. */
    private static final String LABEL_NAMESPACE = HouseholdNamingService.class
            .getName()
            .contains('.')
        ? HouseholdNamingService.class.getName().substringBefore('.')
        : '';

    /**
     * Injected by the tests, which cannot add a translation: label values by language and
     * name ("de|Core_Households_Conjunction"). When set, a key it lacks reads as a missing
     * translation.
     */
    @TestVisible
    private static Map<String, String> translationsForTest;

    private static final String TOKEN_FIRST_NAME = '{FirstName}';
    private static final String TOKEN_LAST_NAME = '{LastName}';
    private static final String TOKEN_SALUTATION = '{Salutation}';
    private static final String DEFAULT_NAME_PATTERN = 'The {LastName} Family';
    private static final String DEFAULT_FORMAL_PATTERN = '{Salutation} {FirstName} {LastName}';
    private static final String DEFAULT_INFORMAL_PATTERN = '{FirstName}';

    /** Field lengths read from the describe, by field; see fieldLength. */
    private static final Map<String, Integer> FIELD_LENGTHS = new Map<String, Integer>();

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
            return fittedList(
                surnames,
                ' ' + storedLabel('Core_Households_NameSuffix', Label.Core_Households_NameSuffix),
                fieldLength(Account.Name)
            );
        }
        String normalized = normalize(usable);
        Boolean perPerson =
            normalized.contains(TOKEN_FIRST_NAME) || normalized.contains(TOKEN_SALUTATION);
        if (!perPerson) {
            return fitted(substitute(usable, eligible[0]), fieldLength(Account.Name));
        }
        List<String> parts = new List<String>();
        for (HouseholdService.Person person : eligible) {
            String part = substitute(usable, person);
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return fittedList(parts, '', fieldLength(Account.Name));
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
        return fittedList(parts, '', fieldLength(Account.Household_Informal_Greeting__c));
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
        Integer maxLength = fieldLength(Account.Household_Formal_Greeting__c);
        String combined = combinedSalutation(eligible, usable);
        if (combined != null) {
            return fitted(combined, maxLength);
        }
        List<String> parts = new List<String>();
        for (HouseholdService.Person person : eligible) {
            String part = substituteFormal(usable, person);
            if (String.isBlank(part)) {
                continue;
            }
            if (person.isDeceased == true) {
                // One label holding the whole phrase, so a translation can put the name first.
                part = storedLabel('Core_Households_LateName', Label.Core_Households_LateName)
                    .replace('{0}', part);
            }
            parts.add(part);
        }
        return fittedList(parts, '', maxLength);
    }

    /**
     * "Mr. and Mrs. John Smith": two living people, one surname, exactly one Mr. and one Mrs.
     * (named by the Mr.'s first name), and a pattern that asks for all three parts. Anything else is greeted person by person.
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
        // Only the traditional "Mr. and Mrs. John Smith" shares one first name: exactly one Mr.
        // and one Mrs. Two titles on one person's name ("Ms. and Ms. Rosa Hall", "Dr. and Mr.
        // Priya Nguyen") read wrongly, so every other pair is named person by person.
        HouseholdService.Person mr = null;
        HouseholdService.Person mrs = null;
        for (HouseholdService.Person person : eligible) {
            String title = person.salutation.trim().toLowerCase();
            if ((title == 'mr.' || title == 'mr') && mr == null) {
                mr = person;
            } else if ((title == 'mrs.' || title == 'mrs') && mrs == null) {
                mrs = person;
            }
        }
        if (mr == null || mrs == null) {
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
            mr.salutation +
            ' ' +
            storedLabel('Core_Households_Conjunction', Label.Core_Households_Conjunction) +
            ' ' +
            mrs.salutation;
        // A formal greeting uses the name on the record, not the name a person prefers.
        return squeeze(salutations + ' ' + blankToEmpty(mr.firstName) + ' ' + mr.lastName);
    }

    // ------------------------------------------------------------------ saving

    /**
     * Recomputes and saves the name and both greetings for each household given; a household
     * whose wording a person has taken over only has its blank greetings filled. Returns how
     * many households were changed. R-H8 and R-H14.
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
         * whose wording a person has taken over (Custom Name) keeps its name and every
         * greeting that has a value; only a blank greeting is filled (R-H8). An account that
         * is not a household is never changed. `primaryId` marks the primary member in
         * contact mode, where the household field holds it; in junction mode the members
         * already carry the flag and it is null.
         */
        @NamespaceAccessible
        public Boolean apply(
            Account household,
            List<HouseholdService.Person> members,
            Id primaryId,
            Account target
        ) {
            if (recordTypeId != null && household.RecordTypeId != recordTypeId) {
                return false;
            }
            if (household.Custom_Name__c == true) {
                return fillBlanks(household, members, primaryId, target);
            }
            if (members == null || members.isEmpty()) {
                // Nobody left to name it after: it keeps its last name and greetings, so a
                // household kept for the records credited to it still says which family it
                // was (R-H4). Erasure anonymizes one through its own path (R-ER3).
                return false;
            }
            markPrimary(members, primaryId);
            String name = computeName(members, namePattern, includeDeceased);
            if (String.isBlank(name)) {
                name = storedLabel(
                    'Core_Households_NamePlaceholder',
                    Label.Core_Households_NamePlaceholder
                );
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

        /**
         * Puts each greeting the members call for on `target` where `household` holds a
         * blank one, and says whether it did. The name and any greeting that has a value
         * are never touched, which is what upkeep does for a custom-named household (R-H8).
         */
        private Boolean fillBlanks(
            Account household,
            List<HouseholdService.Person> members,
            Id primaryId,
            Account target
        ) {
            if (members == null || members.isEmpty()) {
                return false;
            }
            markPrimary(members, primaryId);
            Boolean changed = false;
            if (String.isBlank(household.Household_Formal_Greeting__c)) {
                String formal = computeFormalGreeting(members, formalPattern, includeDeceased);
                if (String.isNotBlank(formal)) {
                    target.Household_Formal_Greeting__c = formal;
                    changed = true;
                }
            }
            if (String.isBlank(household.Household_Informal_Greeting__c)) {
                String informal = computeInformalGreeting(members, informalPattern);
                if (String.isNotBlank(informal)) {
                    target.Household_Informal_Greeting__c = informal;
                    changed = true;
                }
            }
            return changed;
        }
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Puts the two greetings the members call for on `target` where `household` holds a
     * blank one, whether or not it is custom named, and says whether it did. Upkeep does the
     * same for a custom-named household through Wording.apply (R-H8); the sample data load
     * calls this directly so a loaded household is greeted with Household Upkeep on or off.
     * A greeting already there is never replaced.
     */
    @NamespaceAccessible
    public static Boolean fillBlankGreetings(
        Account household,
        List<HouseholdService.Person> members,
        Id primaryId,
        Account target
    ) {
        return new Wording().fillBlanks(household, members, primaryId, target);
    }

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

    /**
     * A label that ends up in a stored name or greeting, in the org's default language. Falls
     * back to the label as the running user reads it when the org language cannot be read or
     * the platform cannot give the label in it.
     *
     * @param name the label's API name, without a namespace
     * @param fallback the same label read the ordinary way (Label.X)
     * @return the label's value
     */
    @NamespaceAccessible
    public static String storedLabel(String name, String fallback) {
        String language = OrgLanguageSelector.defaultLanguage();
        if (String.isBlank(language)) {
            return fallback;
        }
        try {
            if (translationsForTest != null) {
                String key = language + '|' + name;
                return translationsForTest.containsKey(key)
                    ? translationsForTest.get(key)
                    : fallback;
            }
            String value = System.Label.get(LABEL_NAMESPACE, name, language);
            return String.isBlank(value) ? fallback : value;
        } catch (Exception unavailable) {
            // Deliberate: a label the platform cannot give in the org language (for example an
            // unknown language key) is not worth failing a save over; the ordinary label is used.
            return fallback;
        }
    }

    private static String joinNames(List<String> parts) {
        if (parts.isEmpty()) {
            return null;
        }
        if (parts.size() == 1) {
            return parts[0];
        }
        String conjunction = storedLabel(
            'Core_Households_Conjunction',
            Label.Core_Households_Conjunction
        );
        if (parts.size() == 2) {
            return parts[0] + ' ' + conjunction + ' ' + parts[1];
        }
        List<String> leading = new List<String>();
        for (Integer i = 0; i < parts.size() - 1; i++) {
            leading.add(parts[i]);
        }
        String separator =
            storedLabel('Core_Households_ListSeparator', Label.Core_Households_ListSeparator) + ' ';
        return String.join(leading, separator) +
            separator +
            conjunction +
            ' ' +
            parts[parts.size() - 1];
    }

    /**
     * The parts read as a list and followed by `suffix`, in at most `maxLength` characters.
     * A list too long for its field keeps as many leading names as fit and counts the rest
     * ("Garcia, Lee and 28 others Household") rather than having the save refused. Null when
     * there are no parts.
     */
    private static String fittedList(List<String> parts, String suffix, Integer maxLength) {
        if (parts.isEmpty()) {
            return null;
        }
        String full = joinNames(parts) + suffix;
        if (full.length() <= maxLength) {
            return full;
        }
        String separator =
            storedLabel('Core_Households_ListSeparator', Label.Core_Households_ListSeparator) + ' ';
        String best = null;
        String leading = parts[0];
        for (Integer kept = 1; kept < parts.size(); kept++) {
            if (kept > 1) {
                leading += separator + parts[kept - 1];
            }
            String candidate = andOthers(leading, parts.size() - kept) + suffix;
            if (candidate.length() > maxLength) {
                // Each further name only lengthens it, so the last one that fitted is kept.
                break;
            }
            best = candidate;
        }
        return best != null ? best : fitted(full, maxLength);
    }

    private static String andOthers(String leading, Integer leftOut) {
        if (leftOut == 1) {
            return storedLabel(
                    'Core_Households_ListAndOneOther',
                    Label.Core_Households_ListAndOneOther
                )
                .replace('{0}', leading);
        }
        return storedLabel('Core_Households_ListAndOthers', Label.Core_Households_ListAndOthers)
            .replace('{1}', String.valueOf(leftOut))
            .replace('{0}', leading);
    }

    /**
     * The value cut back to the last whole word that fits in `maxLength`, for a single name or
     * greeting too long to shorten by counting people. Only a single word longer than the
     * field is cut inside the word.
     */
    private static String fitted(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        String cut = value.left(maxLength);
        if (value.substring(maxLength, maxLength + 1).isWhitespace()) {
            return cut.trim();
        }
        Integer lastSpace = cut.lastIndexOf(' ');
        return lastSpace > 0 ? cut.left(lastSpace).trim() : cut;
    }

    /** How many characters the field holds, read from the describe once per field. */
    private static Integer fieldLength(Schema.SObjectField field) {
        String key = String.valueOf(field);
        Integer length = FIELD_LENGTHS.get(key);
        if (length == null) {
            length = field.getDescribe().getLength();
            FIELD_LENGTHS.put(key, length);
        }
        return length;
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
