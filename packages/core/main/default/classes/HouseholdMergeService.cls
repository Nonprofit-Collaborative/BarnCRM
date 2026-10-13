/**
 * Combining two households into one, and moving people out of a household into another.
 *
 * A merge is done with the platform's own account merge, so that everything hanging off
 * the household that goes away follows it to the survivor without this class knowing what
 * any of it is: activities, files, notes, and every lookup any other package points at a
 * household with. That is why a merge here is a merge and not a copy.
 *
 * The membership itself is moved first, through HouseholdService, so that neither the
 * merge nor the split has to know how this org says a person belongs to a household.
 *
 * Canonical model Section 5, rule R-H13.
 */
@NamespaceAccessible
public with sharing class HouseholdMergeService {
    @NamespaceAccessible
    public static final String KEEP_SURVIVOR = 'Survivor';
    @NamespaceAccessible
    public static final String KEEP_VICTIM = 'Victim';

    // The two handlers that keep household membership tidy. Named here because a merge
    // deliberately stands them down while it moves people (see mergeHouseholds).
    private static final String CONTACT_HANDLER = 'ContactTriggerHandler';
    private static final String MEMBER_HANDLER = 'HouseholdMemberTriggerHandler';

    /**
     * The fields a merge offers a choice about, in the order the comparison shows them.
     * Every one of them is a field a person typed or a person cares about; the computed
     * member count is not among them because it is recalculated afterwards either way.
     */
    private static final List<String> COMPARED_FIELDS = new List<String>{
        'Name',
        'Custom_Name__c',
        'Household_Formal_Greeting__c',
        'Household_Informal_Greeting__c',
        'Primary_Contact__c',
        'Anniversary__c',
        'BillingStreet',
        'BillingCity',
        'BillingState',
        'BillingPostalCode',
        'BillingCountry'
    };

    /**
     * One field, as the side by side comparison presents it.
     */
    @NamespaceAccessible
    public class FieldChoice {
        @AuraEnabled
        public String fieldName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String survivorValue;
        @AuraEnabled
        public String victimValue;
        @AuraEnabled
        public Boolean inConflict;
    }

    /**
     * One person who will be in the household after the merge, and which of the two
     * households they are in now.
     */
    @NamespaceAccessible
    public class MemberChoice {
        @AuraEnabled
        public Id personId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public Boolean isPrimary;
        @AuraEnabled
        public Boolean isDeceased;
        @AuraEnabled
        public Boolean fromSurvivor;
    }

    /**
     * Everything the screen needs to let a person decide, and nothing it does not.
     */
    @NamespaceAccessible
    public class MergePreview {
        @AuraEnabled
        public Id survivorId;
        @AuraEnabled
        public String survivorName;
        @AuraEnabled
        public Id victimId;
        @AuraEnabled
        public String victimName;
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<FieldChoice> fields = new List<FieldChoice>();
        @AuraEnabled
        public List<MemberChoice> members = new List<MemberChoice>();
    }

    /**
     * The survivor of a merge, and whether its name is now held as a custom one that the
     * naming automation will leave alone. The screen tells the person about the second
     * part; nothing else here needs it.
     */
    @NamespaceAccessible
    public class MergeResult {
        @AuraEnabled
        public Id survivorId;
        @AuraEnabled
        public Boolean customNameKept;
    }

    /**
     * Which household each contested field is taken from. A field left out is taken from
     * the survivor, which is what the screen preselects.
     */
    @NamespaceAccessible
    public class MergeChoices {
        @AuraEnabled
        public Map<String, String> keepFrom = new Map<String, String>();

        /**
         * Built from what the screen sent, which may be nothing at all when the person
         * accepted every value the surviving household already had.
         */
        @NamespaceAccessible
        public MergeChoices(Map<String, String> keepFrom) {
            this.keepFrom = keepFrom == null ? new Map<String, String>() : keepFrom;
        }
    }

    // ------------------------------------------------------------------ preview

    /**
     * The two households side by side: every compared field with both values and whether
     * they disagree, and the people who will be in the household afterwards.
     */
    @NamespaceAccessible
    public static MergePreview preview(Id survivorId, Id victimId) {
        Map<Id, Account> households = loadPair(survivorId, victimId);
        Account survivor = households.get(survivorId);
        Account victim = households.get(victimId);

        MergePreview result = new MergePreview();
        result.survivorId = survivorId;
        result.survivorName = survivor.Name;
        result.victimId = victimId;
        result.victimName = victim.Name;
        result.canEdit =
            HouseholdSelector.getEditableIds(new Set<Id>{ survivorId, victimId }).size() == 2;

        Map<String, Schema.SObjectField> describe = Schema.SObjectType.Account.fields.getMap();
        for (String fieldName : comparedFields()) {
            Schema.SObjectField token = describe.get(fieldName);
            if (token == null || !token.getDescribe().isAccessible()) {
                continue;
            }
            FieldChoice choice = new FieldChoice();
            choice.fieldName = fieldName;
            choice.label = token.getDescribe().getLabel();
            choice.survivorValue = display(survivor, fieldName);
            choice.victimValue = display(victim, fieldName);
            choice.inConflict = differs(choice.survivorValue, choice.victimValue);
            result.fields.add(choice);
        }

        // The preview is shown to somebody, so the members are read with that person's own
        // access (ADR-0021): a deceased flag, a preferred name or a role they cannot read
        // on the record itself does not reach them through the comparison either.
        Map<Id, List<HouseholdService.Person>> membersByHousehold = HouseholdService.getMembersAsUser(
            new Set<Id>{ survivorId, victimId }
        );
        addMembers(result, membersByHousehold.get(survivorId), true);
        addMembers(result, membersByHousehold.get(victimId), false);
        return result;
    }

    private static void addMembers(
        MergePreview result,
        List<HouseholdService.Person> people,
        Boolean fromSurvivor
    ) {
        if (people == null) {
            return;
        }
        Set<Id> alreadyListed = new Set<Id>();
        for (MemberChoice listed : result.members) {
            alreadyListed.add(listed.personId);
        }
        for (HouseholdService.Person person : people) {
            if (person.id != null && alreadyListed.contains(person.id)) {
                continue;
            }
            MemberChoice row = new MemberChoice();
            row.personId = person.id;
            row.name = fullName(person);
            row.role = person.role;
            row.source = person.sourceObject;
            row.isPrimary = person.isPrimary == true;
            row.isDeceased = person.isDeceased == true;
            row.fromSurvivor = fromSurvivor;
            result.members.add(row);
        }
    }

    // ------------------------------------------------------------------ merge

    /**
     * Combines the two households. The people move first, then the chosen values are
     * written to the survivor, then the platform merges the accounts so that everything
     * else follows, and finally both the member count and the wording are settled.
     *
     * A merge is not reversible and it is not logged by this class: the platform records
     * an account merge in the survivor's own history, which is the audit trail a person
     * can actually read. Only a failure is logged: the platform's refusal of the merge
     * here, with its own wording, and anything unexpected by the caller.
     */
    @NamespaceAccessible
    public static MergeResult mergeHouseholds(Id survivorId, Id victimId, MergeChoices choices) {
        Map<Id, Account> households = loadPair(survivorId, victimId);
        Account survivor = households.get(survivorId);
        Account victim = households.get(victimId);
        if (HouseholdSelector.getEditableIds(new Set<Id>{ survivorId, victimId }).size() != 2) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorNoEditAccess);
        }

        Set<Id> movedPeople = HouseholdService.getMemberPersonIds(new Set<Id>{ victimId })
            .get(victimId);
        if (movedPeople != null && !movedPeople.isEmpty()) {
            // The move empties the household that is about to go away, and the upkeep the
            // membership handlers run would tidy an empty household away where the org asks
            // for that. That would delete the very record the platform merge is about to
            // fold into the survivor, and everything hanging off it, activities, files,
            // notes and giving history, would go with it instead of following the merge.
            // So the handlers are stood down for the move only, and this method settles the
            // survivor up itself once the merge has happened.
            withoutMembershipUpkeep(movedPeople, survivorId);
        }

        Boolean keepsCustomName = applyChoices(survivor, victim, choices);
        String chosenName = chosenOtherName(victim, choices);

        // The platform's own merge, so that activities, files, notes, and every lookup
        // another package points at this household follow the record that goes away.
        Database.MergeResult merged = Database.merge(
            new Account(Id = survivorId),
            victimId,
            false,
            AccessLevel.USER_MODE
        );
        if (!merged.isSuccess()) {
            // The people have already moved. Throwing here rolls the whole transaction
            // back, so a merge that cannot finish leaves both households as they were
            // rather than emptying one and keeping it.
            // The platform's own wording is for the administrator reading the Error Log,
            // which survives the rollback; the person at the screen gets the plain message.
            List<String> reasons = new List<String>();
            for (Database.Error problem : merged.getErrors()) {
                reasons.add(problem.getMessage());
            }
            ErrorLogger.logMessage(
                Label.Core_HouseholdMerge_ErrorMergeFailed + ' ' + String.join(reasons, ' '),
                Label.Core_HouseholdMerge_ErrorContext,
                ErrorLogger.SEVERITY_ERROR,
                survivorId
            );
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorMergeFailed);
        }

        Set<Id> survivorOnly = new Set<Id>{ survivorId };
        Boolean customNameKept = keepsCustomName;
        if (keepsCustomName) {
            HouseholdService.recalculateMemberCounts(survivorOnly);
            // The primary member may have arrived with the move; the field follows it (R-M3).
            HouseholdService.settlePrimaryContacts(survivorOnly);
        } else {
            // The household a merge has just folded the other one into is never tidied
            // away by the merge's own settle-up. Tidying away an empty household is what
            // happens when the last person leaves one (R-H12); the survivor of a merge is
            // the record the merge exists to keep, and everything the other household
            // carried has just been moved onto it. Two households that were both empty
            // would otherwise merge into nothing at all.
            HouseholdService.afterMembershipChange(survivorOnly, false);
            customNameKept = keepChosenName(survivorId, chosenName);
        }
        MergeResult result = new MergeResult();
        result.survivorId = survivorId;
        // The screen offers this back so a person is told when the name they chose has
        // stopped following the naming automation, instead of finding out later by
        // wondering why the household never renames itself.
        result.customNameKept = customNameKept;
        return result;
    }

    /**
     * The other household's name, when the person chose to keep it, on the same terms
     * applyChoices wrote it: the field is theirs to update and the value is not empty.
     */
    private static String chosenOtherName(Account victim, MergeChoices choices) {
        Boolean chosen =
            choices != null &&
            choices.keepFrom != null &&
            KEEP_VICTIM.equalsIgnoreCase(choices.keepFrom.get('Name'));
        if (!chosen || String.isBlank(victim.Name)) {
            return null;
        }
        return Schema.SObjectType.Account.fields.Name.isUpdateable() ? victim.Name : null;
    }

    /**
     * Makes the name the person chose stick when the settle-up has just written a
     * different one over it.
     *
     * The screen offers the other household's name as a choice. On a household whose
     * wording is not custom, the settle-up above recomputes the name from everyone now in
     * it and would throw that choice away, so a choice the screen offers has to be
     * honored rather than quietly discarded. Where the recomputed name is the very name
     * the person chose there is nothing to do, and the household stays one that naming
     * keeps up to date. Where it differs, the person has chosen wording that naming would
     * not produce, which is what a custom name is (R-H8), so the household is marked as
     * one, exactly as if they had typed that name in by hand. Written with their own
     * access, like every other choice on this screen: a person who may not take over a
     * household's wording is not given that power by a merge.
     *
     * Answers whether the household is now one whose name is held as a custom one, so the
     * caller can pass that on to the screen.
     */
    private static Boolean keepChosenName(Id survivorId, String chosenName) {
        if (chosenName == null) {
            return false;
        }
        if (!Schema.SObjectType.Account.fields.Custom_Name__c.isUpdateable()) {
            return false;
        }
        List<Account> settled = HouseholdSelector.getHouseholdsByIds(new Set<Id>{ survivorId });
        if (settled.isEmpty() || settled[0].Name == chosenName) {
            return false;
        }
        Database.update(
            new List<Account>{
                new Account(Id = survivorId, Name = chosenName, Custom_Name__c = true)
            },
            AccessLevel.USER_MODE
        );
        return true;
    }

    /**
     * Writes the values the person chose onto the survivor, and answers whether the
     * household is now one whose wording a person has taken over, in which case nothing
     * afterwards is allowed to rewrite it.
     */
    private static Boolean applyChoices(Account survivor, Account victim, MergeChoices choices) {
        Map<String, String> keepFrom = choices == null ||
            choices.keepFrom == null
            ? new Map<String, String>()
            : choices.keepFrom;
        Account changes = new Account(Id = survivor.Id);
        Boolean anyChange = false;
        Map<String, Schema.SObjectField> describe = Schema.SObjectType.Account.fields.getMap();
        for (String fieldName : comparedFields()) {
            Schema.SObjectField token = describe.get(fieldName);
            if (token == null || !token.getDescribe().isUpdateable()) {
                continue;
            }
            if (!KEEP_VICTIM.equalsIgnoreCase(keepFrom.get(fieldName))) {
                continue;
            }
            Object value = victim.get(fieldName);
            if (value == null && fieldName == 'Name') {
                continue;
            }
            changes.put(fieldName, value);
            anyChange = true;
        }
        if (anyChange) {
            Database.update(new List<Account>{ changes }, AccessLevel.USER_MODE);
        }
        Object custom = KEEP_VICTIM.equalsIgnoreCase(keepFrom.get('Custom_Name__c'))
            ? victim.get('Custom_Name__c')
            : survivor.get('Custom_Name__c');
        return custom == true;
    }

    // ------------------------------------------------------------------ split

    /**
     * Moves people out of one household into another. With no destination given, a new
     * household is created and named from the people moving into it. Both households are
     * settled afterwards, and the one they left goes away when it is empty and the org
     * asked for that.
     *
     * Answers with the household the people now belong to, so that the screen can send
     * the person there.
     */
    @NamespaceAccessible
    public static Id split(Id householdId, Set<Id> personIds, Id targetHouseholdId) {
        if (householdId == null || personIds == null || personIds.isEmpty()) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorSplitNoMembers);
        }
        List<Account> sources = HouseholdSelector.getHouseholdsByIds(new Set<Id>{ householdId });
        if (
            sources.isEmpty() || sources[0].RecordTypeId != HouseholdService.householdRecordTypeId()
        ) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorNotHousehold);
        }
        if (targetHouseholdId == householdId) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorSplitSameHousehold);
        }
        // Both ends of the move are edited, so edit access is needed on both. Checking only
        // the household people leave would let somebody push people into a household they
        // cannot see the inside of.
        Set<Id> bothEnds = new Set<Id>{ householdId };
        if (targetHouseholdId != null) {
            bothEnds.add(targetHouseholdId);
        }
        if (HouseholdSelector.getEditableIds(bothEnds).size() != bothEnds.size()) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorNoEditAccess);
        }

        List<HouseholdService.Person> moving = new List<HouseholdService.Person>();
        List<HouseholdService.Person> members = HouseholdService.getMembers(
                new Set<Id>{ householdId }
            )
            .get(householdId);
        if (members != null) {
            for (HouseholdService.Person person : members) {
                if (personIds.contains(person.id)) {
                    moving.add(person);
                }
            }
        }
        if (moving.isEmpty()) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorSplitNotMembers);
        }

        Id destination = targetHouseholdId;
        if (destination == null) {
            destination = HouseholdService.createHouseholdFor(moving);
        }

        Set<Id> affected = HouseholdService.moveMembers(personIds, destination);
        affected.add(householdId);
        // One settle-up for the whole split, however many people moved: counts, names and
        // greetings on both households, and the household left empty tidied away when the
        // org asks for that.
        HouseholdService.afterMembershipChange(affected);
        return destination;
    }

    // ------------------------------------------------------------------ helpers

    /**
     * The fields a merge offers a choice about in this org. In junction mode Primary Contact
     * mirrors the member marked primary and is written only by HouseholdService (R-M3), so it
     * is not a choice: the membership rows decide it and the field follows.
     */
    private static List<String> comparedFields() {
        List<String> result = new List<String>(COMPARED_FIELDS);
        if (HouseholdService.isJunctionMode()) {
            result.remove(result.indexOf('Primary_Contact__c'));
        }
        return result;
    }

    /**
     * Moves people with the membership handlers stood down, so that nothing is recounted,
     * renamed, or tidied away in the middle of a merge. The bypass is per transaction and
     * is always cleared, including when the move throws.
     */
    private static void withoutMembershipUpkeep(Set<Id> personIds, Id survivorId) {
        AutomationControl.bypass(CONTACT_HANDLER);
        AutomationControl.bypass(MEMBER_HANDLER);
        try {
            HouseholdService.moveMembers(personIds, survivorId);
        } finally {
            AutomationControl.clearBypass(CONTACT_HANDLER);
            AutomationControl.clearBypass(MEMBER_HANDLER);
        }
    }

    /**
     * Both households, checked to be two different households and not organizations,
     * before anything is moved or written.
     */
    private static Map<Id, Account> loadPair(Id survivorId, Id victimId) {
        if (survivorId == null || victimId == null) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorMissingInput);
        }
        if (survivorId == victimId) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorSameRecord);
        }
        Map<Id, Account> result = new Map<Id, Account>();
        for (
            Account household : HouseholdSelector.getHouseholdsForMerge(
                new Set<Id>{ survivorId, victimId }
            )
        ) {
            result.put(household.Id, household);
        }
        if (result.size() != 2) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorNotFound);
        }
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        for (Account household : result.values()) {
            if (recordTypeId == null || household.RecordTypeId != recordTypeId) {
                throw new HouseholdException(Label.Core_HouseholdMerge_ErrorNotHousehold);
            }
        }
        // A household that is also a Nonprofit Cloud household is not BarnCRM's to merge: the
        // merge deletes one Account, and its native household group would go with it (ADR-0036).
        if (!HouseholdSelector.accountsWithNativeHouseholdGroups(result.keySet()).isEmpty()) {
            throw new HouseholdException(Label.Core_HouseholdMerge_ErrorNativeHousehold);
        }
        return result;
    }

    /**
     * A field's value as the comparison shows it: the person's name rather than the id
     * behind a lookup, and an empty string rather than nothing, so that two blank fields
     * read as agreeing.
     */
    private static String display(Account household, String fieldName) {
        if (fieldName == 'Primary_Contact__c') {
            return household.Primary_Contact__r == null ? '' : household.Primary_Contact__r.Name;
        }
        Object value = household.get(fieldName);
        return value == null ? '' : String.valueOf(value);
    }

    private static Boolean differs(String left, String right) {
        String a = left == null ? '' : left.trim();
        String b = right == null ? '' : right.trim();
        return a != b;
    }

    private static String fullName(HouseholdService.Person person) {
        String first = String.isNotBlank(person.preferredName)
            ? person.preferredName
            : person.firstName;
        String full =
            (first == null ? '' : first) +
            ' ' +
            (person.lastName == null ? '' : person.lastName);
        return full.trim();
    }
}
