/**
 * Household membership, in both membership modes, behind one entry point.
 *
 * Feature code never asks how membership is stored. In contact mode a person's household
 * is the account their contact record points at. In junction mode a Household Member row
 * joins a person to a household, and the person may be stored as a contact or, in orgs
 * that store people as accounts, as an account.
 *
 * Canonical model Section 5 (R-H1 to R-H12) and Section 6 (R-M1 to R-M5).
 */
@NamespaceAccessible
public with sharing class HouseholdService {
    @NamespaceAccessible
    public static final String MODE_JUNCTION = 'Junction';
    @NamespaceAccessible
    public static final String SOURCE_CONTACT = 'Contact';
    @NamespaceAccessible
    public static final String SOURCE_ACCOUNT = 'Account';
    @NamespaceAccessible
    public static final String RECORD_TYPE_HOUSEHOLD = 'Household';
    @NamespaceAccessible
    public static final String ROLE_HEAD = 'Head';

    /**
     * Set only by tests, so that the person account branches are exercised deterministically
     * on org shapes that do not have them. Production code always reads the detector.
     */
    @TestVisible
    private static Boolean personAccountOverride;

    /**
     * One guard for both automatic creation paths (ADR-0037). Creating a household is an
     * Account insert, which fires the Account trigger, and the membership row that follows
     * fires the Household Member trigger, so either path can arrive back here inside its own
     * write. It is set for the whole of one creation pass and read at both entry points.
     */
    private static Boolean creatingAutomaticHouseholds = false;
    private static Boolean automaticCreationSuspended = false;

    /**
     * Answers already worked out in this transaction, so that a caller asking about the
     * same people twice does not query twice. Cleared whenever membership changes here.
     */
    private static final Map<Id, Id> HOUSEHOLD_ID_BY_PERSON = new Map<Id, Id>();
    private static Boolean upkeepRunning = false;

    /**
     * Set while settling the households a person delete (not a merge) left, so that a
     * household left empty is stamped `Emptied_By_Deletion__c` for the nightly tidy-up
     * (R-H12a, ADR-0120).
     */
    private static Boolean settlingAfterPeopleDeleted = false;

    /**
     * Households already reported in this transaction as kept for their native dependents.
     * A single move settles up twice, once from the trigger on the person's save and once
     * from the caller, and the administrator is told about a kept household once.
     */
    private static final Set<Id> REPORTED_KEPT_HOUSEHOLDS = new Set<Id>();

    /**
     * Set while this service writes Primary Contact itself, so that the guard against a hand
     * edit in junction mode (refuseHandSetPrimaryContacts) lets the package's own write through.
     */
    private static Boolean writingPrimaryContacts = false;

    /**
     * Households ensureHouseholds created before insert in contact mode, waiting for the id
     * of the person they were made for, so that person can be named their Primary Contact
     * after insert (R-H2 in contact mode, PEOPLE-27).
     */
    private static final Set<Id> HOUSEHOLDS_AWAITING_PRIMARY = new Set<Id>();

    /** The trigger handlers stood down by `moveMembersWithoutUpkeep`. */
    private static final String CONTACT_HANDLER = 'ContactTriggerHandler';
    private static final String MEMBER_HANDLER = 'HouseholdMemberTriggerHandler';

    /**
     * One member of a household, whichever object the person is stored on.
     */
    @NamespaceAccessible
    public class Person implements Comparable {
        @NamespaceAccessible
        public Id id;
        @NamespaceAccessible
        public String firstName;
        @NamespaceAccessible
        public String lastName;
        @NamespaceAccessible
        public String preferredName;
        @NamespaceAccessible
        public String salutation;
        @NamespaceAccessible
        public String role;
        @NamespaceAccessible
        public String sourceObject;
        @NamespaceAccessible
        public Boolean isDeceased = false;
        @NamespaceAccessible
        public Boolean isPrimary = false;
        @NamespaceAccessible
        public Boolean excludeFromName = false;
        @NamespaceAccessible
        public Boolean excludeFromGreetings = false;
        @NamespaceAccessible
        public Datetime createdDate;

        @NamespaceAccessible
        public Person() {
            this.sourceObject = SOURCE_CONTACT;
        }

        @NamespaceAccessible
        public Person(Contact source) {
            this.id = source.Id;
            this.firstName = source.FirstName;
            this.lastName = source.LastName;
            this.preferredName = source.Preferred_Name__c;
            this.salutation = source.Salutation;
            this.role = source.Household_Role__c;
            this.isDeceased = source.Deceased__c == true;
            this.excludeFromName = source.Exclude_From_Household_Name__c == true;
            this.excludeFromGreetings = source.Exclude_From_Greetings__c == true;
            this.createdDate = source.CreatedDate;
            this.sourceObject = SOURCE_CONTACT;
        }

        /**
         * A person built from whatever values the record actually carries. Used on the
         * display path, where a field the running user cannot read has been stripped out
         * and naming it would throw, so every value is read from the record's own
         * populated values and a missing one simply stays empty.
         */
        @NamespaceAccessible
        public Person(SObject record, String source) {
            Map<String, Object> values = record.getPopulatedFieldsAsMap();
            this.id = record.Id;
            this.sourceObject = source;
            this.firstName = textValue(values, 'FirstName');
            this.lastName = textValue(values, 'LastName');
            this.preferredName = textValue(values, 'Preferred_Name__c');
            this.salutation = textValue(values, 'Salutation');
            this.role = textValue(values, 'Household_Role__c');
            this.isDeceased = flagValue(values, 'Deceased__c');
            this.excludeFromName = flagValue(values, 'Exclude_From_Household_Name__c');
            this.excludeFromGreetings = flagValue(values, 'Exclude_From_Greetings__c');
            this.createdDate = values.get('CreatedDate') instanceof Datetime
                ? (Datetime) values.get('CreatedDate')
                : null;
        }

        /** The name a screen shows: the preferred name, or else the first name, and the surname. */
        @NamespaceAccessible
        public String fullName() {
            String first = String.isNotBlank(preferredName) ? preferredName : firstName;
            return ((first == null ? '' : first) + ' ' + (lastName == null ? '' : lastName)).trim();
        }

        @NamespaceAccessible
        public Person copy() {
            Person result = new Person();
            result.id = this.id;
            result.firstName = this.firstName;
            result.lastName = this.lastName;
            result.preferredName = this.preferredName;
            result.salutation = this.salutation;
            result.role = this.role;
            result.sourceObject = this.sourceObject;
            result.isDeceased = this.isDeceased;
            result.isPrimary = this.isPrimary;
            result.excludeFromName = this.excludeFromName;
            result.excludeFromGreetings = this.excludeFromGreetings;
            result.createdDate = this.createdDate;
            return result;
        }

        /**
         * Head first, then spouse or partner, then child, then other, then anyone with no
         * role. Within a role the primary member leads, then the earliest created member,
         * then first name, so that a household's name never changes without a reason.
         */
        @NamespaceAccessible
        public Integer compareTo(Object other) {
            Person that = (Person) other;
            Integer result = rank(this.role) - rank(that.role);
            if (result != 0) {
                return result;
            }
            result = flag(that.isPrimary) - flag(this.isPrimary);
            if (result != 0) {
                return result;
            }
            if (
                this.createdDate != null &&
                that.createdDate != null &&
                this.createdDate != that.createdDate
            ) {
                return this.createdDate < that.createdDate ? -1 : 1;
            }
            result = compareText(this.firstName, that.firstName);
            if (result != 0) {
                return result;
            }
            String leftId = this.id == null ? '' : String.valueOf(this.id);
            String rightId = that.id == null ? '' : String.valueOf(that.id);
            return compareText(leftId, rightId);
        }

        private Integer rank(String value) {
            if (value == ROLE_HEAD) {
                return 0;
            }
            if (value == 'Spouse or Partner') {
                return 1;
            }
            if (value == 'Child') {
                return 2;
            }
            if (value == 'Other') {
                return 3;
            }
            return 4;
        }

        private Integer flag(Boolean value) {
            return value == true ? 1 : 0;
        }

        private Integer compareText(String left, String right) {
            String a = left == null ? '' : left;
            String b = right == null ? '' : right;
            return a.compareTo(b);
        }
    }

    /**
     * True when this org stores people as accounts. The detection itself lives in
     * OrgShapeDetector so that only one class knows how the org is shaped.
     */
    @NamespaceAccessible
    public static Boolean isPersonAccountOrg() {
        if (personAccountOverride != null) {
            return personAccountOverride;
        }
        // One facet, not the whole shape: this is asked on Account saves (PEOPLE-36).
        return OrgShapeDetector.hasPersonAccounts();
    }

    @NamespaceAccessible
    public static Boolean isJunctionMode() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null &&
            MODE_JUNCTION.equalsIgnoreCase(settings.Household_Membership_Mode__c);
    }

    @NamespaceAccessible
    public static Id householdRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_HOUSEHOLD);
        return info == null ? null : info.getRecordTypeId();
    }

    @NamespaceAccessible
    public static List<Person> toPersons(List<Contact> contacts) {
        List<Person> result = new List<Person>();
        if (contacts == null) {
            return result;
        }
        for (Contact record : contacts) {
            result.add(new Person(record));
        }
        return result;
    }

    /**
     * The current members of each household, keyed by household id. Every requested id is
     * present in the map, with an empty list where the household has no members.
     */
    @NamespaceAccessible
    public static Map<Id, List<Person>> getMembers(Set<Id> householdIds) {
        return getMembers(householdIds, false);
    }

    /**
     * The same members, read with the running user's own access, for a screen. Object
     * access is checked and any field the user cannot read is left empty rather than
     * shown (ADR-0021).
     */
    @NamespaceAccessible
    public static Map<Id, List<Person>> getMembersAsUser(Set<Id> householdIds) {
        return getMembers(householdIds, true);
    }

    private static Map<Id, List<Person>> getMembers(Set<Id> householdIds, Boolean asUser) {
        Map<Id, List<Person>> result = new Map<Id, List<Person>>();
        if (householdIds == null || householdIds.isEmpty()) {
            return result;
        }
        for (Id householdId : householdIds) {
            result.put(householdId, new List<Person>());
        }
        if (isJunctionMode()) {
            addJunctionMembers(householdIds, result, asUser);
        } else if (asUser) {
            for (
                Contact record : HouseholdSelector.getContactsByHouseholdIdsForDisplay(householdIds)
            ) {
                Id householdId = idValue(record.getPopulatedFieldsAsMap(), 'AccountId');
                List<Person> bucket = householdId == null ? null : result.get(householdId);
                if (bucket != null) {
                    bucket.add(new Person(record, SOURCE_CONTACT));
                }
            }
        } else {
            for (Contact record : HouseholdSelector.getContactsByHouseholdIds(householdIds)) {
                List<Person> bucket = result.get(record.AccountId);
                if (bucket != null) {
                    bucket.add(new Person(record));
                }
            }
        }
        return result;
    }

    private static void addJunctionMembers(
        Set<Id> householdIds,
        Map<Id, List<Person>> result,
        Boolean asUser
    ) {
        List<Household_Member__c> memberships = asUser
            ? HouseholdSelector.getMembershipsForDisplay(householdIds)
            : HouseholdSelector.getMemberships(householdIds);
        Set<Id> contactIds = new Set<Id>();
        Set<Id> personRecordIds = new Set<Id>();
        for (Household_Member__c membership : memberships) {
            // Read from the values the row actually carries: on the display path a field
            // the user cannot read has been stripped, and naming it would throw.
            Map<String, Object> values = membership.getPopulatedFieldsAsMap();
            Id contactId = idValue(values, 'Contact__c');
            Id personRecordId = idValue(values, 'Account__c');
            if (contactId != null) {
                contactIds.add(contactId);
            } else if (personRecordId != null) {
                personRecordIds.add(personRecordId);
            }
        }
        Map<Id, Person> peopleById = new Map<Id, Person>();
        if (asUser) {
            for (Contact record : HouseholdSelector.getContactsByIdsForDisplay(contactIds)) {
                peopleById.put(record.Id, new Person(record, SOURCE_CONTACT));
            }
        } else {
            for (Contact record : HouseholdSelector.getContactsByIds(contactIds)) {
                peopleById.put(record.Id, new Person(record));
            }
        }
        // Everybody the rows named and this org can read through: in an org that does not
        // store people as accounts, an account named by a membership row is not a person
        // and is not looked for at all.
        Set<Id> lookedFor = new Set<Id>(contactIds);
        if (!personRecordIds.isEmpty() && isPersonAccountOrg()) {
            lookedFor.addAll(personRecordIds);
            List<Person> people = asUser
                ? PersonRecordSelector.getPersonsForDisplay(personRecordIds)
                : PersonRecordSelector.getPersons(personRecordIds);
            for (Person person : people) {
                peopleById.put(person.id, person);
            }
        }
        for (Household_Member__c membership : memberships) {
            Map<String, Object> values = membership.getPopulatedFieldsAsMap();
            Id contactId = idValue(values, 'Contact__c');
            Id personId = contactId != null ? contactId : idValue(values, 'Account__c');
            Id householdId = idValue(values, 'Household__c');
            Person source = peopleById.get(personId);
            List<Person> bucket = householdId == null ? null : result.get(householdId);
            if (bucket == null) {
                continue;
            }
            if (source == null) {
                if (asUser || !lookedFor.contains(personId)) {
                    // A screen shows the people this user can read and nothing standing in
                    // for the ones they cannot, and a row naming nobody the org stores
                    // people on names no member at all.
                    continue;
                }
                source = unresolvedMember(
                    personId,
                    contactId != null ? SOURCE_CONTACT : SOURCE_ACCOUNT
                );
            }
            Person member = source.copy();
            String role = textValue(values, 'Role__c');
            if (String.isNotBlank(role)) {
                member.role = role;
            }
            member.isPrimary = flagValue(values, 'Is_Primary__c');
            bucket.add(member);
        }
    }

    /**
     * A member whose own record the upkeep read did not return, kept as a member anyway.
     *
     * That read runs in system mode (ADR-0021), so field level access is not why the record
     * is missing: either it has been deleted while the membership row still names it, or
     * sharing withholds it from the running user. Dropping the member would recount the
     * household smaller than it is, could rename it, could have it deleted as empty, and in
     * a merge would leave the member behind on the household the merge deletes. So the
     * member is counted. There is no name to put in the household name or the greetings,
     * and the naming service would read a blank surname as a real one, so the placeholder
     * is kept out of both: the wording a household ends up with is the wording it has
     * today, and only the count and the moves change.
     */
    private static Person unresolvedMember(Id personId, String source) {
        Person result = new Person();
        result.id = personId;
        result.sourceObject = source;
        result.excludeFromName = true;
        result.excludeFromGreetings = true;
        return result;
    }

    /**
     * The household each of these people belongs to, for callers in other packages that
     * hold a person id and need the household to credit or to roll up to (ADR-0017).
     *
     * The set may mix people stored as contacts and people stored as accounts. Every id
     * asked about is in the answer: a person with no household, or one whose account is
     * not a household, is answered with null, so that "asked and there is none" is never
     * confused with "not asked".
     */
    @NamespaceAccessible
    public static Map<Id, Id> getHouseholdIdsFor(Set<Id> personIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (personIds == null || personIds.isEmpty()) {
            return result;
        }
        Set<Id> unresolved = new Set<Id>();
        for (Id personId : personIds) {
            if (personId == null) {
                continue;
            }
            if (HOUSEHOLD_ID_BY_PERSON.containsKey(personId)) {
                result.put(personId, HOUSEHOLD_ID_BY_PERSON.get(personId));
            } else {
                unresolved.add(personId);
                result.put(personId, null);
            }
        }
        if (unresolved.isEmpty()) {
            return result;
        }
        if (isJunctionMode()) {
            resolveThroughJunction(unresolved, result);
        } else {
            resolveThroughContacts(unresolved, result);
        }
        for (Id personId : unresolved) {
            HOUSEHOLD_ID_BY_PERSON.put(personId, result.get(personId));
        }
        return result;
    }

    /**
     * Every household these people currently belong to, all of them rather than only the
     * one they are primary in.
     *
     * `getHouseholdIdsFor` answers "which household is this person's", which is the right
     * question when crediting a gift. This answers "which households does a change to this
     * person show up in", which is the right question when settling up after that person
     * has been renamed, deleted or restored: somebody in two households is named in two
     * household names, and both have to be rewritten.
     *
     * Junction mode only. In contact mode a person's household is the account their
     * contact record points at, and the contact trigger reads it from the record itself.
     */
    @NamespaceAccessible
    public static Set<Id> householdIdsForPeople(Set<Id> personIds) {
        Set<Id> result = new Set<Id>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return result;
        }
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (
                personId != null &&
                personIds.contains(personId) &&
                membership.Household__c != null
            ) {
                result.add(membership.Household__c);
            }
        }
        return result;
    }

    /**
     * Every household each of these people currently belongs to, by person: in junction mode
     * each household they hold a current membership of, in contact mode the one household
     * their record points at. Every person asked about is in the answer, with an empty set when
     * they belong to none. For a screen that asks which household a change is for (R-AD9).
     */
    @NamespaceAccessible
    public static Map<Id, Set<Id>> currentHouseholdIdsByPerson(Set<Id> personIds) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        if (personIds == null || personIds.isEmpty()) {
            return result;
        }
        for (Id personId : personIds) {
            result.put(personId, new Set<Id>());
        }
        if (isJunctionMode()) {
            for (
                Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(
                    personIds
                )
            ) {
                Id personId = personOf(membership);
                if (result.containsKey(personId) && membership.Household__c != null) {
                    result.get(personId).add(membership.Household__c);
                }
            }
            return result;
        }
        Map<Id, Id> householdByPerson = getHouseholdIdsFor(personIds);
        for (Id personId : householdByPerson.keySet()) {
            Id householdId = householdByPerson.get(personId);
            if (householdId != null && result.containsKey(personId)) {
                result.get(personId).add(householdId);
            }
        }
        return result;
    }

    /** Who joined or left which households in one save, for `membershipChangeOf`. */
    @NamespaceAccessible
    public class MembershipChange {
        /** The households on both sides of the change. */
        @NamespaceAccessible
        public Set<Id> householdIds = new Set<Id>();
        /** The people who joined or left. */
        @NamespaceAccessible
        public Set<Id> personIds = new Set<Id>();
    }

    /**
     * The households on both sides of a save of these people or membership rows, for the rollup
     * engine: a total reached through a household token moves when somebody joins or leaves
     * (canonical model R-R11). In contact mode the change is a contact added, moved to another
     * account, deleted or restored; in junction mode it is a membership row added, changed,
     * removed or restored. Records of the kind the mode in use does not read answer nothing.
     *
     * Any answer already given in this transaction about who belongs where is forgotten when
     * something changed, so the totals that follow read the new households.
     *
     * @param records the saved records, or the deleted ones as they were
     * @param oldRecords the same records before an update, or null for any other save
     */
    @NamespaceAccessible
    public static MembershipChange membershipChangeOf(
        List<SObject> records,
        Map<Id, SObject> oldRecords
    ) {
        MembershipChange change = new MembershipChange();
        if (records == null || records.isEmpty()) {
            return change;
        }
        Schema.SObjectType changedType = records[0].getSObjectType();
        Boolean junction = isJunctionMode();
        if (changedType == Contact.SObjectType && !junction) {
            for (Contact person : (List<Contact>) records) {
                Contact before = oldRecords == null ? null : (Contact) oldRecords.get(person.Id);
                if (before != null && before.AccountId == person.AccountId) {
                    continue;
                }
                addIfSet(change.householdIds, person.AccountId);
                addIfSet(change.householdIds, before?.AccountId);
                addIfSet(change.personIds, person.Id);
            }
        } else if (changedType == Household_Member__c.SObjectType && junction) {
            for (Household_Member__c row : (List<Household_Member__c>) records) {
                Household_Member__c before = oldRecords == null
                    ? null
                    : (Household_Member__c) oldRecords.get(row.Id);
                if (before != null && !membershipMoved(row, before)) {
                    continue;
                }
                for (Household_Member__c version : new List<Household_Member__c>{ row, before }) {
                    if (version != null) {
                        addIfSet(change.householdIds, version.Household__c);
                        addIfSet(change.personIds, personOf(version));
                    }
                }
            }
        }
        if (!change.householdIds.isEmpty()) {
            HOUSEHOLD_ID_BY_PERSON.clear();
        }
        return change;
    }

    private static Boolean membershipMoved(Household_Member__c row, Household_Member__c before) {
        return row.Household__c != before.Household__c ||
            row.Contact__c != before.Contact__c ||
            row.Account__c != before.Account__c ||
            row.Start_Date__c != before.Start_Date__c ||
            row.End_Date__c != before.End_Date__c;
    }

    private static void addIfSet(Set<Id> ids, Id value) {
        if (value != null) {
            ids.add(value);
        }
    }

    /**
     * The people who currently belong to each household given, by household id. The
     * counterpart of getHouseholdIdsFor, for callers rolling values up to a household.
     */
    @NamespaceAccessible
    public static Map<Id, Set<Id>> getMemberPersonIds(Set<Id> householdIds) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        if (householdIds == null || householdIds.isEmpty()) {
            return result;
        }
        Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
        for (Id householdId : householdIds) {
            Set<Id> personIds = new Set<Id>();
            List<Person> members = membersByHousehold.get(householdId);
            if (members != null) {
                for (Person person : members) {
                    if (person.id != null) {
                        personIds.add(person.id);
                    }
                }
            }
            result.put(householdId, personIds);
        }
        return result;
    }

    /**
     * Every membership row these people have, current or ended, as it stands. Read before a
     * person is deleted so that, when the deletion turns out to be a merge, their memberships
     * can be handed to the person they were merged into (`moveMembershipsToSurvivors`).
     * Empty outside junction mode.
     */
    @NamespaceAccessible
    public static List<Household_Member__c> membershipsFor(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return new List<Household_Member__c>();
        }
        return HouseholdSelector.getAllMembershipsForPeople(personIds);
    }

    /**
     * Gives the survivor of a people merge the memberships the merged-away person had, and
     * answers with the households that has changed.
     *
     * The platform's merge moves every record that looks up to the person it deletes onto
     * the survivor. It cannot move these: they were taken out in `before delete`, which the
     * platform runs before it knows the delete is a merge, so that an ordinary delete can
     * recount the household and an undelete can put them back. Without this the survivor
     * would not be in the households the other record was in, and a household whose only
     * member was the merged-away record would be left with nobody.
     *
     * Only a current row counts as already being a member: where the survivor is a current
     * member of the household, the merged-away row is not copied, and otherwise it is, even
     * when the survivor has an ended row there. An ended row is copied as history unless the
     * survivor already has a row in that household.
     *
     * Primary is per household (R-M3, ADR-0044). Where the merged-away person was the
     * household's primary member and the household has no other current primary, the
     * survivor takes it: the copied row carries the flag, or the survivor's own current row
     * is promoted. So a merge never leaves a household without the primary it had, and its
     * Primary Contact keeps mirroring somebody.
     *
     * The rows are written all or none: a membership that cannot be written fails the merge
     * rather than being lost.
     *
     * @param removed the rows `membershipsFor` read before the delete
     * @param survivorByMerged the survivor of each merged-away person
     */
    @NamespaceAccessible
    public static Set<Id> moveMembershipsToSurvivors(
        List<Household_Member__c> removed,
        Map<Id, Id> survivorByMerged
    ) {
        Set<Id> affected = new Set<Id>();
        if (
            removed == null ||
            removed.isEmpty() ||
            survivorByMerged == null ||
            survivorByMerged.isEmpty()
        ) {
            return affected;
        }
        Set<Id> survivors = new Set<Id>(survivorByMerged.values());
        Map<String, Household_Member__c> currentRowBySurvivorHousehold = new Map<String, Household_Member__c>();
        Set<String> anyRowBySurvivorHousehold = new Set<String>();
        for (
            Household_Member__c existing : HouseholdSelector.getAllMembershipsForPeople(survivors)
        ) {
            Id personId = personOf(existing);
            if (!survivors.contains(personId) || existing.Household__c == null) {
                continue;
            }
            String key = survivorHouseholdKey(personId, existing.Household__c);
            anyRowBySurvivorHousehold.add(key);
            if (isCurrentMembership(existing) && !currentRowBySurvivorHousehold.containsKey(key)) {
                currentRowBySurvivorHousehold.put(key, existing);
            }
        }
        Set<Id> touched = new Set<Id>();
        for (Household_Member__c row : removed) {
            if (row.Household__c != null) {
                touched.add(row.Household__c);
            }
        }
        Set<Id> householdsWithPrimary = new Set<Id>();
        for (Household_Member__c member : HouseholdSelector.getMemberships(touched)) {
            if (member.Is_Primary__c == true) {
                householdsWithPrimary.add(member.Household__c);
            }
        }
        // Current rows first, so that an ended row never stands in the way of a current one.
        List<Household_Member__c> ordered = new List<Household_Member__c>();
        List<Household_Member__c> endedRows = new List<Household_Member__c>();
        for (Household_Member__c row : removed) {
            if (isCurrentMembership(row)) {
                ordered.add(row);
            } else {
                endedRows.add(row);
            }
        }
        ordered.addAll(endedRows);

        List<Household_Member__c> created = new List<Household_Member__c>();
        Map<Id, Household_Member__c> promoted = new Map<Id, Household_Member__c>();
        for (Household_Member__c row : ordered) {
            Id survivorId = survivorByMerged.get(personOf(row));
            if (survivorId == null || row.Household__c == null) {
                continue;
            }
            Id householdId = row.Household__c;
            String key = survivorHouseholdKey(survivorId, householdId);
            Boolean current = isCurrentMembership(row);
            Boolean takesPrimary =
                current &&
                row.Is_Primary__c == true &&
                !householdsWithPrimary.contains(householdId);
            if (current && currentRowBySurvivorHousehold.containsKey(key)) {
                if (takesPrimary) {
                    Id survivorRowId = currentRowBySurvivorHousehold.get(key).Id;
                    promoted.put(
                        survivorRowId,
                        new Household_Member__c(Id = survivorRowId, Is_Primary__c = true)
                    );
                    householdsWithPrimary.add(householdId);
                    affected.add(householdId);
                }
                continue;
            }
            if (!current && anyRowBySurvivorHousehold.contains(key)) {
                continue;
            }
            Household_Member__c copy = new Household_Member__c(
                Household__c = householdId,
                Role__c = row.Role__c,
                Start_Date__c = row.Start_Date__c,
                End_Date__c = row.End_Date__c,
                Is_Primary__c = takesPrimary
            );
            if (survivorId.getSObjectType() == Contact.SObjectType) {
                copy.Contact__c = survivorId;
            } else {
                copy.Account__c = survivorId;
            }
            created.add(copy);
            anyRowBySurvivorHousehold.add(key);
            if (current) {
                currentRowBySurvivorHousehold.put(key, copy);
            }
            if (takesPrimary) {
                householdsWithPrimary.add(householdId);
            }
            affected.add(householdId);
        }
        HouseholdWriter.saveMergedMemberships(created, promoted.values());
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * Collapses a person's duplicate current memberships in a household to one row, for the
     * households a Salesforce merge of two households has just folded together. The merge
     * moves both households' rows onto the survivor, so a person who was in both is in the
     * survivor twice and would be counted twice.
     *
     * The row kept is the one the household choice rule would pick (R-M3, `comesFirst`):
     * primary first, then the earlier start date, then the older row. It takes Is Primary
     * if any duplicate had it. The others are removed in system mode (upkeep, ADR-0021).
     * Junction mode only; ended rows are history and are left alone. Answers the number of
     * rows removed.
     */
    @NamespaceAccessible
    public static Integer collapseDuplicateMemberships(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty() || !isJunctionMode()) {
            return 0;
        }
        Map<String, List<Household_Member__c>> rowsByPersonHousehold = new Map<String, List<Household_Member__c>>();
        for (Household_Member__c row : HouseholdSelector.getMemberships(householdIds)) {
            Id personId = personOf(row);
            if (personId == null || row.Household__c == null) {
                continue;
            }
            String key = survivorHouseholdKey(personId, row.Household__c);
            if (!rowsByPersonHousehold.containsKey(key)) {
                rowsByPersonHousehold.put(key, new List<Household_Member__c>());
            }
            rowsByPersonHousehold.get(key).add(row);
        }
        List<Household_Member__c> redundant = new List<Household_Member__c>();
        List<Household_Member__c> promoted = new List<Household_Member__c>();
        for (List<Household_Member__c> rows : rowsByPersonHousehold.values()) {
            if (rows.size() < 2) {
                continue;
            }
            Household_Member__c kept;
            Boolean anyPrimary = false;
            for (Household_Member__c row : rows) {
                anyPrimary = anyPrimary || row.Is_Primary__c == true;
                if (comesFirst(row, kept)) {
                    kept = row;
                }
            }
            for (Household_Member__c row : rows) {
                if (row.Id != kept.Id) {
                    redundant.add(row);
                }
            }
            if (anyPrimary && kept.Is_Primary__c != true) {
                promoted.add(new Household_Member__c(Id = kept.Id, Is_Primary__c = true));
            }
        }
        HouseholdWriter.collapseMemberships(promoted, redundant);
        if (!redundant.isEmpty()) {
            HOUSEHOLD_ID_BY_PERSON.clear();
        }
        return redundant.size();
    }

    /** The person a membership row is for, whichever object they are stored on. */
    public static Id personOf(Household_Member__c row) {
        return row.Contact__c != null ? row.Contact__c : row.Account__c;
    }

    private static String survivorHouseholdKey(Id personId, Id householdId) {
        return String.valueOf(personId) + '|' + String.valueOf(householdId);
    }

    /** Current as the membership selectors count it: no end date, or one after today. */
    private static Boolean isCurrentMembership(Household_Member__c row) {
        return row.End_Date__c == null || row.End_Date__c > Date.today();
    }

    /**
     * Takes the membership rows that join these people to their households out of the way,
     * for the one caller that needs it: the person records themselves are being deleted.
     *
     * Called from a `before delete` context, while the rows still say whose membership
     * they are. Two things follow from that, and neither works from `after delete`. The
     * households the deletion affects can still be read off the rows, and they are what
     * this returns. And the rows go into the recycle bin still naming the person, so that
     * restoring the person can put the membership back (`restoreMembershipsFor`).
     *
     * Ended memberships go too. A membership that has ended is history of a person, and
     * once that person is gone it is history of nobody: left behind, the platform empties
     * its person lookup and the row says nothing at all (R-M4).
     */
    @NamespaceAccessible
    public static Set<Id> removeMembershipsFor(Set<Id> personIds) {
        Set<Id> affected = new Set<Id>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return affected;
        }
        List<Household_Member__c> removing = new List<Household_Member__c>();
        for (
            Household_Member__c membership : HouseholdSelector.getAllMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (membership.Household__c != null) {
                affected.add(membership.Household__c);
            }
            removing.add(new Household_Member__c(Id = membership.Id));
        }
        HouseholdWriter.deleteMemberships(removing);
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * Ends every current membership these people have, today, and takes away the primary flag:
     * what erasing a person does to their households (canonical model R-ER3). A membership that
     * starts in the future starts and ends today. Saved with the user's own access, so the
     * membership trigger recounts, renames and tidies the households as on any ended
     * membership. Answers the rows ended; empty outside junction mode.
     */
    @NamespaceAccessible
    public static List<Household_Member__c> endMembershipsFor(Set<Id> personIds) {
        List<Household_Member__c> ending = new List<Household_Member__c>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return ending;
        }
        Date today = Date.today();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Household_Member__c ended = new Household_Member__c(
                Id = membership.Id,
                End_Date__c = today,
                Is_Primary__c = false
            );
            if (membership.Start_Date__c != null && membership.Start_Date__c > today) {
                ended.Start_Date__c = today;
            }
            ending.add(ended);
        }
        if (!ending.isEmpty()) {
            Database.update(ending, true, AccessLevel.USER_MODE);
        }
        HOUSEHOLD_ID_BY_PERSON.clear();
        return ending;
    }

    /**
     * Puts back the membership rows that were removed when these people were deleted, and
     * answers with the households that has changed.
     *
     * The platform cannot do this for us. A lookup that was emptied because the record it
     * pointed at was deleted is not restored when that record comes back, so a membership
     * row left to the platform would come out of the deletion naming nobody and stay that
     * way. Removing the row first, while it still names the person, is what makes the
     * restore possible at all.
     */
    @NamespaceAccessible
    public static Set<Id> restoreMembershipsFor(Set<Id> personIds) {
        Set<Id> affected = new Set<Id>();
        if (personIds == null || personIds.isEmpty() || !isJunctionMode()) {
            return affected;
        }
        List<Household_Member__c> restoring = new List<Household_Member__c>();
        for (
            Household_Member__c membership : HouseholdSelector.getDeletedMembershipsForPeople(
                personIds
            )
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (membership.Household__c != null) {
                affected.add(membership.Household__c);
            }
            restoring.add(new Household_Member__c(Id = membership.Id));
        }
        HouseholdWriter.undeleteMemberships(restoring);
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * Everything a household needs once its membership has changed: the member count, the
     * name and the two greetings, and the tidying away of a household that has been left
     * with nobody in it.
     *
     * This is the one place that upkeep is spelled out. The trigger handlers call it, and
     * so may another package that has changed membership itself (ADR-0017). The guard stops
     * the saves it makes from coming back round through another trigger and starting again.
     */
    @NamespaceAccessible
    public static void afterMembershipChange(Set<Id> householdIds) {
        afterMembershipChange(householdIds, true);
    }

    /**
     * The settle-up after people (not a merge) were deleted: never tidies a household away
     * (R-H12), and stamps each household left empty with the day, so the nightly tidy-up can
     * move it to the Recycle Bin once its former members can no longer be restored (R-H12a,
     * ADR-0120).
     */
    @NamespaceAccessible
    public static void afterPeopleDeleted(Set<Id> householdIds) {
        settlingAfterPeopleDeleted = true;
        try {
            afterMembershipChange(householdIds, false);
        } finally {
            settlingAfterPeopleDeleted = false;
        }
    }

    /**
     * The same, saying whether a household left with nobody in it may be tidied away. It
     * may not on a path where people are still being added to a household that has only
     * just been created.
     */
    @NamespaceAccessible
    public static void afterMembershipChange(Set<Id> householdIds, Boolean mayTidyAway) {
        if (upkeepRunning || householdIds == null || householdIds.isEmpty()) {
            return;
        }
        upkeepRunning = true;
        try {
            // Who belongs to what has just changed, so any answer already given is stale.
            HOUSEHOLD_ID_BY_PERSON.clear();
            // One read of the households and one of their members for the whole pass
            // (PEOPLE-34): the primary, the count and the wording are worked out from them in
            // memory and saved in one write, and the tidy-up reads the same members.
            List<Account> households = HouseholdSelector.getHouseholdsByIds(householdIds);
            Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
            settleHouseholds(households, membersByHousehold);
            if (mayTidyAway == true) {
                deleteEmptyHouseholds(households, membersByHousehold);
            }
        } finally {
            upkeepRunning = false;
        }
    }

    /**
     * The primary, the member count, the name and the greetings of each household, from one
     * read of the households and their members, saved in one write.
     *
     * Each part keeps the rule it has on its own: the primary is settled on a household only
     * (settlePrimaryContacts), the count on every account given when the org has no household
     * record type (recalculateMemberCounts), and the wording skips a custom name and a
     * household that carries a native Nonprofit Cloud household group (mutual exclusion,
     * product-plan Section 11.2 item 9). The wording reads the primary as it now stands.
     * Working out the wording is logged and skipped if it fails, as applyNaming does, and a
     * household whose new wording is refused on save still gets its count and primary.
     */
    private static void settleHouseholds(
        List<Account> households,
        Map<Id, List<Person>> membersByHousehold
    ) {
        if (households.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        Map<Id, Id> primaryByHousehold = recordTypeId == null
            ? new Map<Id, Id>()
            : settledPrimaries(households, membersByHousehold, recordTypeId);
        Map<Id, Account> worded = wordingOf(households, membersByHousehold, primaryByHousehold);
        List<Account> updates = new List<Account>();
        Map<Id, Account> bookkeepingById = new Map<Id, Account>();
        for (Account household : households) {
            Account change = new Account(Id = household.Id);
            Boolean bookkept = false;
            List<Person> members = membersByHousehold.get(household.Id);
            Decimal count = members == null ? 0 : members.size();
            Boolean counted = recordTypeId == null || household.RecordTypeId == recordTypeId;
            if (counted && household.Member_Count__c != count) {
                change.Member_Count__c = count;
                bookkept = true;
            }
            Date emptiedOn = emptiedByDeletion(household, count, recordTypeId);
            if (household.Emptied_By_Deletion__c != emptiedOn) {
                change.Emptied_By_Deletion__c = emptiedOn;
                bookkept = true;
            }
            Id primaryId = primaryByHousehold.get(household.Id);
            if (
                primaryByHousehold.containsKey(household.Id) &&
                household.Primary_Contact__c != primaryId
            ) {
                change.Primary_Contact__c = primaryId;
                bookkept = true;
            }
            if (bookkept) {
                bookkeepingById.put(household.Id, change.clone(true, true));
            }
            Account renamed = worded.get(household.Id);
            if (renamed != null) {
                change.Name = renamed.Name;
                change.Household_Formal_Greeting__c = renamed.Household_Formal_Greeting__c;
                change.Household_Informal_Greeting__c = renamed.Household_Informal_Greeting__c;
            }
            if (bookkept || renamed != null) {
                updates.add(change);
            }
        }
        Set<Id> refused = writeSettledHouseholds(updates);
        // A household whose wording was refused, by a duplicate rule on the name for example,
        // still gets the count and primary it would have had with the wording saved apart.
        List<Account> retries = new List<Account>();
        for (Id householdId : refused) {
            if (worded.containsKey(householdId) && bookkeepingById.containsKey(householdId)) {
                retries.add(bookkeepingById.get(householdId));
            }
        }
        writeSettledHouseholds(retries);
    }

    /**
     * The day a household was emptied by deleting people (R-H12a): stamped when a person
     * delete leaves a household with no members, kept while it stays empty, and cleared as
     * soon as anyone belongs to it again, so a later move that empties it is not mistaken for
     * a delete.
     */
    private static Date emptiedByDeletion(Account household, Decimal count, Id recordTypeId) {
        if (count > 0) {
            return null;
        }
        Boolean isHousehold = recordTypeId != null && household.RecordTypeId == recordTypeId;
        if (household.Emptied_By_Deletion__c == null && settlingAfterPeopleDeleted && isHousehold) {
            return Date.today();
        }
        return household.Emptied_By_Deletion__c;
    }

    /**
     * The Primary Contact each household should hold, keyed by household id, for households
     * only: an organization shares the field (R-O3), where it names the person the
     * organization deals with, and household upkeep never touches it.
     *
     * Junction mode: the field names the current member marked Is Primary. A member stored as
     * a contact is named as that contact; a member stored as a person account is named as the
     * contact the platform keeps behind that account, which a Contact lookup accepts. More
     * than one primary, which only a data load can produce, mirrors the first in member order.
     *
     * Contact mode: the field is the mark itself, set by a person, and is kept unless the
     * person it names has left.
     *
     * Either way nothing is promoted when there is no primary (R-H10): the canonical model says
     * the next member is proposed, not silently assigned, so a split that moves the primary
     * out leaves the household with no primary rather than one naming somebody who has left.
     */
    private static Map<Id, Id> settledPrimaries(
        List<Account> households,
        Map<Id, List<Person>> membersByHousehold,
        Id recordTypeId
    ) {
        Map<Id, Id> result = new Map<Id, Id>();
        Boolean junction = isJunctionMode();
        Set<Id> primariesStoredAsAccounts = new Set<Id>();
        for (Account household : households) {
            if (household.RecordTypeId != recordTypeId) {
                continue;
            }
            List<Person> members = membersByHousehold.get(household.Id);
            Id primaryId = junction
                ? firstPrimaryId(members)
                : memberOrNull(household.Primary_Contact__c, members);
            result.put(household.Id, primaryId);
            if (primaryId != null && primaryId.getSObjectType() == Account.SObjectType) {
                primariesStoredAsAccounts.add(primaryId);
            }
        }
        if (primariesStoredAsAccounts.isEmpty()) {
            return result;
        }
        // One read for every household in the pass, and none when no primary is an account.
        Map<Id, Id> personContactByAccount = PersonRecordSelector.getPersonContactIds(
            primariesStoredAsAccounts
        );
        for (Id householdId : result.keySet()) {
            Id primaryId = result.get(householdId);
            if (primaryId != null && primariesStoredAsAccounts.contains(primaryId)) {
                result.put(householdId, personContactByAccount.get(primaryId));
            }
        }
        return result;
    }

    /** The person given when they are among the members, otherwise null. */
    private static Id memberOrNull(Id personId, List<Person> members) {
        if (personId == null || members == null) {
            return null;
        }
        for (Person member : members) {
            if (member.id == personId) {
                return personId;
            }
        }
        return null;
    }

    /**
     * The name and greetings each household now calls for, keyed by household id, holding
     * only the households whose wording changes. Logged and empty on a failure, as
     * applyNaming is, so the count and primary are still saved.
     */
    private static Map<Id, Account> wordingOf(
        List<Account> households,
        Map<Id, List<Person>> membersByHousehold,
        Map<Id, Id> primaryByHousehold
    ) {
        Map<Id, Account> result = new Map<Id, Account>();
        try {
            Set<Id> natives = HouseholdSelector.nativeHouseholdAccountsAmong(
                new Map<Id, Account>(households).keySet()
            );
            HouseholdNamingService.Wording wording = new HouseholdNamingService.Wording();
            // R-H5 reads the primary from the mode's own source of truth: the membership rows
            // in junction mode (getMembers has already flagged it), the settled field in
            // contact mode.
            Boolean primaryFromField = !isJunctionMode();
            for (Account household : households) {
                if (natives.contains(household.Id)) {
                    continue;
                }
                Id primaryId = null;
                if (primaryFromField) {
                    primaryId = primaryByHousehold.containsKey(household.Id)
                        ? primaryByHousehold.get(household.Id)
                        : household.Primary_Contact__c;
                }
                List<Person> members = membersByHousehold.get(household.Id);
                Account change = new Account(Id = household.Id);
                if (wording.apply(household, members, primaryId, change)) {
                    result.put(household.Id, change);
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextNaming);
            result.clear();
        }
        return result;
    }

    /**
     * Saves the settled households as package upkeep (ADR-0021), marked as the package's own
     * Primary Contact write so the junction mode guard lets it through, and answers the ids
     * the save refused (HouseholdWriter logs each refusal).
     */
    private static Set<Id> writeSettledHouseholds(List<Account> updates) {
        if (updates.isEmpty()) {
            return new Set<Id>();
        }
        writingPrimaryContacts = true;
        try {
            return HouseholdWriter.updateHouseholdsReportingRefusals(updates);
        } finally {
            writingPrimaryContacts = false;
        }
    }

    private static void resolveThroughContacts(Set<Id> personIds, Map<Id, Id> result) {
        Set<Id> contactIds = idsOfType(personIds, Contact.SObjectType);
        if (contactIds.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        for (Contact record : HouseholdSelector.getContactsWithHouseholds(contactIds)) {
            Boolean isHousehold =
                record.AccountId != null &&
                recordTypeId != null &&
                record.Account.RecordTypeId == recordTypeId;
            result.put(record.Id, isHousehold ? record.AccountId : null);
        }
    }

    /**
     * A person's household (R-M3, PEOPLE-12): the one they are the primary member of, and
     * when they are the primary member of none, the one they joined earliest (a membership
     * with no start date counts as earliest, then the oldest row). A person with a current
     * membership is never answered with null. Where they are the primary member of more than
     * one, the earliest of those wins, so the answer is the same every time.
     */
    private static void resolveThroughJunction(Set<Id> personIds, Map<Id, Id> result) {
        Map<Id, List<Household_Member__c>> byPerson = new Map<Id, List<Household_Member__c>>();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (!byPerson.containsKey(personId)) {
                byPerson.put(personId, new List<Household_Member__c>());
            }
            byPerson.get(personId).add(membership);
        }
        for (Id personId : byPerson.keySet()) {
            Household_Member__c chosen;
            for (Household_Member__c membership : byPerson.get(personId)) {
                if (comesFirst(membership, chosen)) {
                    chosen = membership;
                }
            }
            result.put(personId, chosen.Household__c);
        }
    }

    /**
     * Whether `candidate` is a better answer for a person's household than `held`: primary
     * before not, then earlier start (no start date first), then the row read first, which
     * the selector orders oldest first.
     */
    private static Boolean comesFirst(Household_Member__c candidate, Household_Member__c held) {
        if (held == null) {
            return true;
        }
        Boolean candidatePrimary = candidate.Is_Primary__c == true;
        Boolean heldPrimary = held.Is_Primary__c == true;
        if (candidatePrimary != heldPrimary) {
            return candidatePrimary;
        }
        if (candidate.Start_Date__c == held.Start_Date__c) {
            return false;
        }
        if (candidate.Start_Date__c == null) {
            return true;
        }
        return held.Start_Date__c != null && candidate.Start_Date__c < held.Start_Date__c;
    }

    /**
     * Values read from a record's own populated values, so that a field the running user
     * cannot read, which has been stripped out before the record got here, reads as empty
     * instead of throwing.
     */
    private static String textValue(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean flagValue(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value instanceof Boolean ? (Boolean) value : false;
    }

    private static Id idValue(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value instanceof Id ? (Id) value : null;
    }

    private static Set<Id> idsOfType(Set<Id> ids, Schema.SObjectType wanted) {
        Set<Id> result = new Set<Id>();
        for (Id value : ids) {
            if (value.getSObjectType() == wanted) {
                result.add(value);
            }
        }
        return result;
    }

    /**
     * Set while package code is inserting people it is going to join to households itself,
     * so that automatic creation does not give each of them one of their own first (the
     * sample data loader is the caller this exists for). It suspends the automatic path
     * only: everything a person does by hand is unaffected, and the flag lasts for one
     * transaction.
     */
    @NamespaceAccessible
    public static void suspendAutomaticCreation() {
        automaticCreationSuspended = true;
    }

    @NamespaceAccessible
    public static void resumeAutomaticCreation() {
        automaticCreationSuspended = false;
    }

    /**
     * Whether the org asks for a household to be made for a new person who has none. One
     * setting answers it for both membership modes and for both objects a person can be
     * stored on (R-H1, R-H2, ADR-0037). Public for the household catch-up batch.
     */
    public static Boolean automaticCreationEnabled() {
        if (automaticCreationSuspended) {
            return false;
        }
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && settings.Auto_Create_Households__c == true;
    }

    /**
     * Turns automatic household creation on, which is what the Health Check fix for
     * "no new person is getting a household" does. The setting is saved the way every
     * setting is saved, so the change is cached, invalidated and audited like any other.
     */
    @NamespaceAccessible
    public static void enableAutomaticHouseholds() {
        SettingsService.saveValues(new Map<String, Object>{ 'Auto_Create_Households__c' => true });
    }

    /**
     * In contact mode a person's account is their household, so pointing someone who is in a
     * household at an organization instead (from the standard edit page or a data load)
     * takes them out of it, usually by mistake: an affiliation is how a person is connected
     * to an organization. That one change is refused, with a message saying what to do
     * (R-C1a). Everything else is left alone: a person already at an organization or at no
     * account may be pointed anywhere, a move between households is untouched, a native
     * Nonprofit Cloud household counts as a household, and in junction mode the account is
     * an employer, so nothing is checked. Runs before update.
     */
    public static void refuseLeavingHouseholdsForOrganizations(
        List<Contact> records,
        Map<Id, Contact> previousById
    ) {
        if (records == null || previousById == null || isJunctionMode()) {
            return;
        }
        Id householdType = householdRecordTypeId();
        List<Contact> moving = new List<Contact>();
        Set<Id> accountIds = new Set<Id>();
        for (Contact record : records) {
            Contact previous = previousById.get(record.Id);
            if (
                householdType != null &&
                previous != null &&
                previous.AccountId != null &&
                record.AccountId != null &&
                record.AccountId != previous.AccountId
            ) {
                moving.add(record);
                accountIds.add(previous.AccountId);
                accountIds.add(record.AccountId);
            }
        }
        if (moving.isEmpty()) {
            return;
        }
        Map<Id, Id> typeByAccount = new Map<Id, Id>();
        for (Account account : HouseholdSelector.getAccountRecordTypes(accountIds)) {
            typeByAccount.put(account.Id, account.RecordTypeId);
        }
        List<Contact> leaving = new List<Contact>();
        Set<Id> targets = new Set<Id>();
        for (Contact record : moving) {
            Id household = previousById.get(record.Id).AccountId;
            if (
                typeByAccount.get(household) == householdType &&
                typeByAccount.containsKey(record.AccountId) &&
                typeByAccount.get(record.AccountId) != householdType
            ) {
                leaving.add(record);
                targets.add(record.AccountId);
            }
        }
        if (leaving.isEmpty()) {
            return;
        }
        Set<Id> nativeHouseholds = HouseholdSelector.nativeHouseholdAccountsAmong(targets);
        for (Contact record : leaving) {
            if (!nativeHouseholds.contains(record.AccountId)) {
                record.addError(Contact.AccountId, Label.Core_Households_ErrorPersonToOrganization);
            }
        }
    }

    /**
     * Gives every contact that arrives without a household one of its own, named from the
     * org's pattern. Runs before insert, so the new household id is simply assigned to the
     * contact and no second pass over contacts is needed. R-H1.
     *
     * Contact mode only. In junction mode the household is a membership row rather than a
     * reference on the contact, and a membership row needs an id the contact does not have
     * yet, so that mode is served after insert by createHouseholdsForNewContacts.
     *
     * Mutual exclusion (product-plan Section 11.2 item 9) needs no extra check here: only a
     * contact with no AccountId at all reaches the loop below, so a contact whose AccountId
     * already points at an Account carrying a native Nonprofit Cloud household group, or at
     * anything else, is never a candidate for a new household in the first place.
     */
    @NamespaceAccessible
    public static void ensureHouseholds(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty() || isJunctionMode()) {
            return;
        }
        if (!automaticCreationEnabled()) {
            return;
        }
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            ErrorLogger.log(
                new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing),
                Label.Core_Households_ErrorContextMembership
            );
            return;
        }
        List<Contact> waiting = new List<Contact>();
        List<Account> households = new List<Account>();
        for (Contact record : contacts) {
            if (record.AccountId != null) {
                continue;
            }
            waiting.add(record);
            households.add(
                newHousehold(new List<Person>{ new Person(record) }, recordTypeId, settings)
            );
        }
        if (households.isEmpty()) {
            return;
        }
        // The household is the package's own bookkeeping, so it is saved by HouseholdWriter,
        // which explains why that one write does not run with the saving user's access.
        List<Database.SaveResult> created = HouseholdWriter.createHouseholds(households);
        HOUSEHOLD_ID_BY_PERSON.clear();
        for (Integer i = 0; i < created.size(); i++) {
            if (created[i].isSuccess()) {
                waiting[i].AccountId = created[i].getId();
                HOUSEHOLDS_AWAITING_PRIMARY.add(created[i].getId());
            } else {
                failPersonSave(waiting[i], created[i]);
            }
        }
    }

    /**
     * Puts a refused household creation on the person's own save. Every person gets a
     * household (R-C1), so a person whose household could not be made is not saved
     * quietly without one: their row fails, with the platform's reason, in the same place
     * a data loader or a screen reports any other failed row. The Error Log entry
     * HouseholdWriter has already written is for the administrator; this is for whoever
     * pressed save.
     */
    private static void failPersonSave(SObject person, Database.SaveResult refused) {
        person.addError(
            String.format(
                Label.Core_Households_ErrorCreateFailedForPerson,
                new List<String>{ HouseholdWriter.failureReason(refused) }
            )
        );
    }

    /**
     * The household catch-up for people stored as accounts (ADR-0124): each of these people
     * that no current membership row names is given what a new person account is given on
     * insert, through the same creation pass. Junction mode, a person account org and the
     * automatic creation setting only, as on insert; anywhere else it does nothing. The
     * membership is checked again here, so a person who joined a household after the batch
     * started is left alone.
     */
    @NamespaceAccessible
    public static void catchUpPersonAccounts(Set<Id> personIds) {
        if (
            personIds == null ||
            personIds.isEmpty() ||
            !isPersonAccountOrg() ||
            !isJunctionMode() ||
            !automaticCreationEnabled()
        ) {
            return;
        }
        Set<Id> waiting = new Set<Id>();
        Map<Id, Id> householdByPerson = getHouseholdIdsFor(personIds);
        for (Id personId : personIds) {
            if (householdByPerson.get(personId) == null) {
                waiting.add(personId);
            }
        }
        if (waiting.isEmpty()) {
            return;
        }
        createHouseholdsForPersonAccounts(PersonRecordSelector.getPersonRecords(waiting));
    }

    /**
     * Creates a household and a membership row for each new person that the org stores as
     * an account. R-H2. Called only when the org has person records and membership is in
     * junction mode; the caller has already read the automatic creation setting.
     *
     * Mutual exclusion (product-plan Section 11.2 item 9): here the person's own Account is
     * the person, so a person account that already carries a native Nonprofit Cloud
     * household group gets no BarnCRM household of its own. Membership in a native
     * group is really carried on the native membership object HouseholdSelector already
     * names, which is forbidden to query (ADR-0009, ADR-0013); this is the weaker, safe
     * question this file's guards all ask instead: whether the Account itself carries the
     * group.
     */
    @NamespaceAccessible
    public static void createHouseholdsForPersonAccounts(List<SObject> personRecords) {
        if (
            personRecords == null ||
            personRecords.isEmpty() ||
            creatingAutomaticHouseholds ||
            automaticCreationSuspended
        ) {
            return;
        }
        List<SObject> eligible = withoutNativeHouseholds(personRecords);
        if (eligible.isEmpty()) {
            return;
        }
        createHouseholdsAndMemberships(PersonRecordSelector.toPersons(eligible), byId(eligible));
    }

    /**
     * The person account records among these whose own Account does not already carry a
     * native Nonprofit Cloud household group. One predicate query for the whole batch.
     */
    private static List<SObject> withoutNativeHouseholds(List<SObject> personRecords) {
        Set<Id> personIds = new Set<Id>();
        for (SObject record : personRecords) {
            if (record.Id != null) {
                personIds.add(record.Id);
            }
        }
        Set<Id> nativeHouseholds = HouseholdSelector.nativeHouseholdAccountsAmong(personIds);
        if (nativeHouseholds.isEmpty()) {
            return personRecords;
        }
        List<SObject> result = new List<SObject>();
        for (SObject record : personRecords) {
            if (!nativeHouseholds.contains(record.Id)) {
                result.add(record);
            }
        }
        return result;
    }

    /**
     * Creates a household and a membership row for each contact that has just been saved
     * into junction mode with no household of their own. R-H2, ADR-0037.
     *
     * This is the junction mode counterpart of ensureHouseholds, and it runs after insert
     * rather than before it, because the membership row that joins a person to a household
     * needs the person's id.
     */
    @NamespaceAccessible
    public static void createHouseholdsForNewContacts(List<Contact> contacts) {
        if (
            contacts == null ||
            contacts.isEmpty() ||
            creatingAutomaticHouseholds ||
            !isJunctionMode() ||
            !automaticCreationEnabled()
        ) {
            return;
        }
        List<Contact> waiting = withoutAHousehold(contacts);
        createHouseholdsAndMemberships(toPersons(waiting), byId(waiting));
    }

    /**
     * Contact mode: the person a household was just created for is its Primary Contact, as
     * junction mode already does by marking them the primary member (R-H2, PEOPLE-27).
     * Called after insert, once the person has an id.
     */
    @NamespaceAccessible
    public static void seedPrimaryContactsOfNewHouseholds(List<Contact> contacts) {
        if (contacts == null || HOUSEHOLDS_AWAITING_PRIMARY.isEmpty()) {
            return;
        }
        List<Account> updates = new List<Account>();
        for (Contact record : contacts) {
            if (record.Id != null && HOUSEHOLDS_AWAITING_PRIMARY.remove(record.AccountId)) {
                updates.add(new Account(Id = record.AccountId, Primary_Contact__c = record.Id));
            }
        }
        writePrimaryContacts(updates);
    }

    /**
     * Junction mode: a contact saved with its account set to a household joins that household
     * with a membership row, so the person is counted, named and found there (PEOPLE-10). An
     * account that is an organization (an employer, in this mode) or a native Nonprofit Cloud
     * household is left alone. The person joins as an ordinary member: who is primary stays a
     * decision somebody makes (R-H10). Runs before automatic creation, which then sees the
     * membership and creates nothing.
     */
    @NamespaceAccessible
    public static void joinHouseholdsNamedOnNewContacts(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty() || creatingAutomaticHouseholds) {
            return;
        }
        if (!isJunctionMode()) {
            return;
        }
        Set<Id> accountIds = new Set<Id>();
        for (Contact record : contacts) {
            if (record.Id != null && record.AccountId != null) {
                accountIds.add(record.AccountId);
            }
        }
        Set<Id> households = householdsAmong(accountIds);
        households.removeAll(HouseholdSelector.nativeHouseholdAccountsAmong(households));
        if (households.isEmpty()) {
            return;
        }
        List<Household_Member__c> memberships = new List<Household_Member__c>();
        for (Contact record : contacts) {
            if (record.Id != null && households.contains(record.AccountId)) {
                memberships.add(newMembership(record.Id, record.AccountId, null, false));
            }
        }
        HouseholdWriter.createMemberships(memberships);
        HOUSEHOLD_ID_BY_PERSON.clear();
    }

    /** The records themselves, by id, so that a failure can be put back on the right one. */
    private static Map<Id, SObject> byId(List<SObject> records) {
        Map<Id, SObject> result = new Map<Id, SObject>();
        for (SObject record : records) {
            if (record.Id != null) {
                result.put(record.Id, record);
            }
        }
        return result;
    }

    /**
     * The contacts among these that belong to no household yet.
     *
     * Three ways of belonging count, so that automatic creation never makes a second
     * household for somebody who already has one: a membership row that already joins them
     * to one, a household account they were saved against directly (which is how a person
     * arrives from the merge and split screens and from an import that names their
     * household), and mutual exclusion (product-plan Section 11.2 item 9): an Account that
     * already carries a native Nonprofit Cloud household group.
     *
     * Membership in a native group is really carried on the native membership object
     * HouseholdSelector already names, which is forbidden to query (ADR-0009, ADR-0013), so
     * this asks the weaker, safe question instead: whether the contact's own AccountId
     * already points at an Account carrying a native group at all. A person truly
     * native-only and not yet linked to that Account by an AccountId still gets a BarnCRM
     * household from this method; that gap is smaller
     * than the harm of a duplicate, and no migration or sync is in scope here.
     */
    private static List<Contact> withoutAHousehold(List<Contact> contacts) {
        Set<Id> personIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Contact record : contacts) {
            if (record.Id == null) {
                continue;
            }
            personIds.add(record.Id);
            if (record.AccountId != null) {
                accountIds.add(record.AccountId);
            }
        }
        List<Contact> result = new List<Contact>();
        if (personIds.isEmpty()) {
            return result;
        }
        Map<Id, Id> householdByPerson = getHouseholdIdsFor(personIds);
        Set<Id> households = householdsAmong(accountIds);
        // One predicate query for the whole batch, never one per contact.
        Set<Id> nativeHouseholds = HouseholdSelector.nativeHouseholdAccountsAmong(accountIds);
        for (Contact record : contacts) {
            if (record.Id == null || householdByPerson.get(record.Id) != null) {
                continue;
            }
            if (
                record.AccountId != null &&
                (households.contains(record.AccountId) ||
                nativeHouseholds.contains(record.AccountId))
            ) {
                continue;
            }
            result.add(record);
        }
        return result;
    }

    /** Which of these accounts are households rather than organizations. */
    private static Set<Id> householdsAmong(Set<Id> accountIds) {
        Set<Id> result = new Set<Id>();
        Id recordTypeId = householdRecordTypeId();
        if (accountIds.isEmpty() || recordTypeId == null) {
            return result;
        }
        for (Account record : HouseholdSelector.getAccountRecordTypes(accountIds)) {
            if (record.RecordTypeId == recordTypeId) {
                result.add(record.Id);
            }
        }
        return result;
    }

    /**
     * One household each, and the membership row that joins each person to theirs. The one
     * creation pass both automatic paths use, so that a person stored as a contact and a
     * person stored as an account are given the same thing in the same way.
     *
     * The records come along with the people so that a household that could not be
     * created fails that person's own save (R-C1) rather than leaving them saved and
     * quietly householdless.
     */
    private static void createHouseholdsAndMemberships(
        List<Person> people,
        Map<Id, SObject> recordsByPersonId
    ) {
        if (people == null || people.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            ErrorLogger.log(
                new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing),
                Label.Core_Households_ErrorContextMembership
            );
            return;
        }
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        creatingAutomaticHouseholds = true;
        try {
            List<Account> households = new List<Account>();
            for (Person person : people) {
                households.add(newHousehold(new List<Person>{ person }, recordTypeId, settings));
            }
            List<Database.SaveResult> created = HouseholdWriter.createHouseholds(households);
            List<Household_Member__c> memberships = new List<Household_Member__c>();
            for (Integer i = 0; i < created.size(); i++) {
                if (people[i].id == null) {
                    continue;
                }
                if (!created[i].isSuccess()) {
                    SObject record = recordsByPersonId.get(people[i].id);
                    if (record != null) {
                        failPersonSave(record, created[i]);
                    }
                    continue;
                }
                memberships.add(newMembership(people[i].id, created[i].getId(), ROLE_HEAD, true));
            }
            if (!memberships.isEmpty()) {
                HouseholdWriter.createMemberships(memberships);
                HOUSEHOLD_ID_BY_PERSON.clear();
            }
        } finally {
            creatingAutomaticHouseholds = false;
        }
    }

    private static Account newHousehold(
        List<Person> members,
        Id recordTypeId,
        BarnCRM_Settings__c settings
    ) {
        String namePattern = settings == null ? null : settings.Household_Name_Pattern__c;
        String formalPattern = settings == null ? null : settings.Formal_Greeting_Pattern__c;
        String informalPattern = settings == null ? null : settings.Informal_Greeting_Pattern__c;
        String name = HouseholdNamingService.computeName(members, namePattern);
        return new Account(
            Name = String.isBlank(name) ? Label.Core_Households_NamePlaceholder : name,
            RecordTypeId = recordTypeId,
            Custom_Name__c = false,
            Member_Count__c = members.size(),
            Household_Formal_Greeting__c = HouseholdNamingService.computeFormalGreeting(
                members,
                formalPattern
            ),
            Household_Informal_Greeting__c = HouseholdNamingService.computeInformalGreeting(
                members,
                informalPattern
            )
        );
    }

    /**
     * Moves one person to another household and leaves both households correct: counts,
     * names, greetings, and the empty household tidied away when the org asks for that.
     * R-H12.
     */
    @NamespaceAccessible
    public static void moveContact(Id contactId, Id targetHouseholdId) {
        moveContact(contactId, targetHouseholdId, null);
    }

    /**
     * The same, naming the household the person is leaving. In junction mode a person can
     * belong to several households, and only the membership in this one ends: a child in
     * two households who is moved out of one stays in the other. With no household named,
     * every other household the person is in is left, which is what contact mode always
     * means (a contact has one household).
     */
    @NamespaceAccessible
    public static void moveContact(Id contactId, Id targetHouseholdId, Id sourceHouseholdId) {
        if (contactId == null || targetHouseholdId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveMissingInput);
        }
        // Somebody moving a person by hand is changing the household they chose, so they
        // need edit access to it, checked against sharing the way a merge or a split checks
        // both of its ends. The reads that follow run in system mode (ADR-0021) and would
        // otherwise let a person be moved into a household the user cannot even see.
        if (
            !HouseholdSelector.getEditableIds(new Set<Id>{ targetHouseholdId })
                .contains(targetHouseholdId)
        ) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNoEditAccess);
        }
        // The person and membership handlers are stood down for the move, and the households
        // are settled once here, rather than once by each trigger and again by this method.
        afterMembershipChange(
            moveMembersWithoutUpkeep(
                new Set<Id>{ contactId },
                targetHouseholdId,
                sourceHouseholdId,
                false
            )
        );
    }

    /**
     * `moveMembers` with the person and membership trigger handlers stood down, for a caller
     * that settles the households itself straight after (a single move, a split, a merge).
     * The bypass is per transaction and is always cleared, including when the move throws.
     * A merge keeps the dates people joined on (`keepStartDates`); a move or a split does not.
     */
    @NamespaceAccessible
    public static Set<Id> moveMembersWithoutUpkeep(
        Set<Id> personIds,
        Id targetHouseholdId,
        Id sourceHouseholdId,
        Boolean keepStartDates
    ) {
        AutomationControl.bypass(CONTACT_HANDLER);
        AutomationControl.bypass(MEMBER_HANDLER);
        try {
            return move(personIds, targetHouseholdId, sourceHouseholdId, keepStartDates == true);
        } finally {
            AutomationControl.clearBypass(CONTACT_HANDLER);
            AutomationControl.clearBypass(MEMBER_HANDLER);
        }
    }

    /**
     * Moves several people to one household in a single pass, whichever object holds each
     * of them and whichever membership mode the org uses, and answers with every household
     * the move touched: the target, and each household somebody left.
     *
     * Nothing is recounted, renamed, or tidied away here. The caller decides when to settle
     * up by calling `afterMembershipChange` with the answer, so that a merge or a split of
     * fifty people settles once rather than fifty times. `moveContact` is that caller for a
     * single move. R-H12.
     */
    @NamespaceAccessible
    public static Set<Id> moveMembers(Set<Id> personIds, Id targetHouseholdId) {
        return moveMembers(personIds, targetHouseholdId, null);
    }

    /**
     * The same, naming the household the people are leaving. In junction mode only their
     * memberships in that household end, so a person who also belongs to a third household
     * stays there. With no household named, every other current membership ends.
     */
    @NamespaceAccessible
    public static Set<Id> moveMembers(
        Set<Id> personIds,
        Id targetHouseholdId,
        Id sourceHouseholdId
    ) {
        return move(personIds, targetHouseholdId, sourceHouseholdId, false);
    }

    private static Set<Id> move(
        Set<Id> personIds,
        Id targetHouseholdId,
        Id sourceHouseholdId,
        Boolean keepStartDates
    ) {
        if (personIds == null || personIds.isEmpty() || targetHouseholdId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveMissingInput);
        }
        List<Account> targets = HouseholdSelector.getHouseholdsByIds(
            new Set<Id>{ targetHouseholdId }
        );
        if (targets.isEmpty()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (targets[0].RecordTypeId != householdRecordTypeId()) {
            throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
        }
        Set<Id> contactPeople = idsOfType(personIds, Contact.SObjectType);
        Set<Id> accountPeople = idsOfType(personIds, Account.SObjectType);
        if (contactPeople.size() + accountPeople.size() != personIds.size()) {
            // An id of any other object is not a person this service can move.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (!accountPeople.isEmpty() && !isJunctionMode()) {
            // A person stored as an account has no account reference of their own to move,
            // so this org has to be in the flexible membership mode to move them at all.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNeedsJunction);
        }
        // Everybody named is read through the object that holds them, and everybody named
        // has to exist. A merge or a split that names somebody who has since been deleted
        // is refused rather than quietly moving the rest.
        Map<Id, Contact> contacts = new Map<Id, Contact>(
            HouseholdSelector.getContactsByIds(contactPeople)
        );
        if (contacts.size() != contactPeople.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Set<Id> foundAsAccount = new Set<Id>();
        for (Person person : PersonRecordSelector.getPersons(accountPeople)) {
            foundAsAccount.add(person.id);
        }
        if (foundAsAccount.size() != accountPeople.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Set<Id> affected = new Set<Id>{ targetHouseholdId };
        if (isJunctionMode()) {
            moveJunctionMembers(
                personIds,
                targetHouseholdId,
                sourceHouseholdId,
                keepStartDates,
                affected
            );
        } else {
            moveContactMembers(contacts.values(), targetHouseholdId, affected);
        }
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    /**
     * In contact mode the move is the person's own account reference, so everybody moves in
     * one update. Somebody already in the target is left alone.
     */
    private static void moveContactMembers(
        List<Contact> people,
        Id targetHouseholdId,
        Set<Id> affected
    ) {
        List<Contact> updates = new List<Contact>();
        Map<Id, Id> leftHouseholdByContact = new Map<Id, Id>();
        for (Contact person : people) {
            if (person.AccountId == targetHouseholdId) {
                continue;
            }
            if (person.AccountId != null) {
                affected.add(person.AccountId);
                leftHouseholdByContact.put(person.Id, person.AccountId);
            }
            updates.add(new Contact(Id = person.Id, AccountId = targetHouseholdId));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
            removeRelationsLeftBehind(leftHouseholdByContact);
        }
    }

    /**
     * With Contacts to Multiple Accounts on, changing a contact's account can leave the old
     * direct relation behind as an indirect one, which keeps the emptied household from being
     * tidied and blocks a later merge (ADR-0130). A content test, not an org-shape test: only
     * the relation between each moved contact and the household this move took them out of
     * is removed, only once it is indirect (this move turned it so, since that household was
     * the contact's own account until now), and only when nobody recorded roles or dates on
     * it. Only a household's relation goes: a contact moved off an organization keeps that
     * link (an employer, a board), which is not BarnCRM's to delete. Anything else stays. Runs
     * as the person moving; a row the platform will not remove stays too, and the delete guard
     * then keeps the household, as before. Without Contacts to Multiple Accounts there are no
     * rows and no further query.
     */
    private static void removeRelationsLeftBehind(Map<Id, Id> leftHouseholdByContact) {
        if (leftHouseholdByContact.isEmpty()) {
            return;
        }
        Set<Id> leftAccounts = new Set<Id>(leftHouseholdByContact.values());
        List<HouseholdSelector.NativeMembership> rows = HouseholdSelector.nativeMembershipRows(
            leftAccounts,
            leftHouseholdByContact.keySet()
        );
        if (rows.isEmpty()) {
            return;
        }
        Set<Id> households = new Set<Id>();
        for (Account left : HouseholdSelector.getHouseholdsByIds(leftAccounts)) {
            if (left.RecordTypeId == householdRecordTypeId()) {
                households.add(left.Id);
            }
        }
        List<Id> leftBehind = new List<Id>(
            relationsLeftBehind(leftHouseholdByContact, households, rows)
        );
        if (!leftBehind.isEmpty()) {
            Database.delete(leftBehind, false, AccessLevel.USER_MODE);
        }
    }

    /**
     * Of these rows, the indirect, unannotated ones between a moved contact and the household
     * (never an organization) the move took them out of.
     */
    @TestVisible
    private static Set<Id> relationsLeftBehind(
        Map<Id, Id> leftHouseholdByContact,
        Set<Id> households,
        List<HouseholdSelector.NativeMembership> rows
    ) {
        Set<Id> leftBehind = new Set<Id>();
        for (HouseholdSelector.NativeMembership row : rows) {
            if (
                !row.isDirect &&
                !row.hasDetails &&
                households.contains(row.accountId) &&
                row.accountId == leftHouseholdByContact.get(row.contactId)
            ) {
                leftBehind.add(row.id);
            }
        }
        return leftBehind;
    }

    /**
     * In junction mode a person who is already a current member of the target keeps that
     * one membership: their other memberships are end dated and no second row is written,
     * so that a move never leaves a person in the same household twice.
     *
     * The role a person had comes with them, so that a move does not quietly turn a Head
     * into nobody in particular. The primary flag comes with them only where the target has
     * room for it: at most one current member of a household is primary (R-M3), so if the
     * target already has a primary, or two people arrive holding the flag, the arrivals
     * join as ordinary members and the household keeps the one primary it is allowed.
     *
     * With a source household named, only the memberships in that household end: the
     * person's other households are none of this move's business. A merge keeps the start
     * date the person joined the merged-away household on, since the two households were
     * one family all along; a move starts the new membership today.
     */
    private static void moveJunctionMembers(
        Set<Id> personIds,
        Id targetHouseholdId,
        Id sourceHouseholdId,
        Boolean keepStartDates,
        Set<Id> affected
    ) {
        Boolean primaryIsFree = true;
        for (
            Household_Member__c membership : HouseholdSelector.getMemberships(
                new Set<Id>{ targetHouseholdId }
            )
        ) {
            if (membership.Is_Primary__c == true) {
                primaryIsFree = false;
            }
        }
        Set<Id> alreadyInTarget = new Set<Id>();
        Map<Id, String> roleByPerson = new Map<Id, String>();
        Set<Id> wasPrimary = new Set<Id>();
        Map<Id, Date> startByPerson = new Map<Id, Date>();
        List<Household_Member__c> ended = new List<Household_Member__c>();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(personIds)
        ) {
            Id personId = personOf(membership);
            if (personId == null || !personIds.contains(personId)) {
                continue;
            }
            if (membership.Household__c == targetHouseholdId) {
                alreadyInTarget.add(personId);
                continue;
            }
            if (sourceHouseholdId != null && membership.Household__c != sourceHouseholdId) {
                continue;
            }
            affected.add(membership.Household__c);
            Date started = membership.Start_Date__c;
            if (
                started != null &&
                (!startByPerson.containsKey(personId) || started < startByPerson.get(personId))
            ) {
                startByPerson.put(personId, started);
            }
            if (
                String.isBlank(roleByPerson.get(personId)) && String.isNotBlank(membership.Role__c)
            ) {
                roleByPerson.put(personId, membership.Role__c);
            }
            if (membership.Is_Primary__c == true) {
                wasPrimary.add(personId);
            }
            // Ended today, and the current-membership filter counts only a membership that
            // ends after today, so the person leaves the old household straight away.
            ended.add(new Household_Member__c(Id = membership.Id, End_Date__c = Date.today()));
        }
        if (!ended.isEmpty()) {
            Database.update(ended, AccessLevel.USER_MODE);
        }
        Boolean primaryStillFree = primaryIsFree && wasPrimary.size() == 1;
        List<Household_Member__c> joined = new List<Household_Member__c>();
        for (Id personId : personIds) {
            if (alreadyInTarget.contains(personId)) {
                continue;
            }
            Boolean takesPrimary = primaryStillFree && wasPrimary.contains(personId);
            if (takesPrimary) {
                primaryStillFree = false;
            }
            Household_Member__c membership = newMembership(
                personId,
                targetHouseholdId,
                roleByPerson.get(personId),
                takesPrimary
            );
            if (keepStartDates && startByPerson.containsKey(personId)) {
                membership.Start_Date__c = startByPerson.get(personId);
            }
            joined.add(membership);
        }
        if (!joined.isEmpty()) {
            Database.insert(joined, AccessLevel.USER_MODE);
        }
    }

    /**
     * Joins people to households, whichever way the org stores membership, and answers with
     * every household the join touched.
     *
     * The counterpart of `moveMembers` for a caller that is building people and households
     * together (a sample data set, an import) rather than moving somebody who already
     * belongs somewhere. Each entry names one household and the people joining it, so a
     * caller with two hundred households joins them in one pass.
     *
     * What "joining" means is the mode's business, not the caller's (R-M5). In contact mode
     * a person's household is the account their contact points at, so joining reparents
     * them and the household they left is in the answer. In junction mode a membership row
     * is added and the person keeps any other household they belong to, which is what that
     * mode is for. Somebody who is already a current member of the household they are being
     * joined to is left alone, so calling twice does not make two memberships.
     *
     * A person is joined as an ordinary member with no role and no primary flag on the
     * membership row: the role the person carries on their own record is the one that
     * naming and greetings read, and a household's primary member (R-M3) is a decision
     * somebody makes rather than a side effect of a join.
     *
     * Nothing is recounted or renamed here. The write fires the trigger that settles the
     * households up, exactly as it does when a person is saved by hand; a caller that has
     * suppressed that automation settles by passing the answer to `afterMembershipChange`.
     */
    @NamespaceAccessible
    public static Set<Id> addMembers(Map<Id, Set<Id>> personIdsByHouseholdId) {
        Set<Id> affected = new Set<Id>();
        if (personIdsByHouseholdId == null || personIdsByHouseholdId.isEmpty()) {
            return affected;
        }
        Set<Id> householdIds = new Set<Id>(personIdsByHouseholdId.keySet());
        Set<Id> everybody = new Set<Id>();
        for (Id householdId : householdIds) {
            Set<Id> people = personIdsByHouseholdId.get(householdId);
            if (people != null) {
                everybody.addAll(people);
            }
        }
        if (everybody.isEmpty()) {
            return affected;
        }
        Id recordTypeId = householdRecordTypeId();
        Set<Id> found = new Set<Id>();
        for (Account household : HouseholdSelector.getHouseholdsByIds(householdIds)) {
            if (recordTypeId != null && household.RecordTypeId != recordTypeId) {
                throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
            }
            found.add(household.Id);
        }
        if (found.size() != householdIds.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        Map<Id, Id> accountBehindContact = PersonRecordSelector.getAccountsBehindPersonContacts(
            idsOfType(everybody, Contact.SObjectType)
        );
        if (!accountBehindContact.isEmpty()) {
            // The hidden contact behind a person stored as an account joins as that account,
            // so the person has one membership, on the side the Account trigger maintains
            // (PEOPLE-7).
            personIdsByHouseholdId = withAccountsForPersonContacts(
                personIdsByHouseholdId,
                accountBehindContact
            );
            everybody = withAccountsForPersonContacts(everybody, accountBehindContact);
        }
        Set<Id> contactPeople = idsOfType(everybody, Contact.SObjectType);
        Set<Id> accountPeople = idsOfType(everybody, Account.SObjectType);
        if (contactPeople.size() + accountPeople.size() != everybody.size()) {
            // An id of any other object is not a person this service can join.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        if (!accountPeople.isEmpty() && !isJunctionMode()) {
            // A person stored as an account has no account reference of their own, so only
            // the flexible membership mode can hold them.
            throw new HouseholdException(Label.Core_Households_ErrorMoveNeedsJunction);
        }
        affected.addAll(householdIds);
        if (isJunctionMode()) {
            joinThroughJunction(personIdsByHouseholdId, everybody);
        } else {
            joinThroughContacts(personIdsByHouseholdId, contactPeople, affected);
        }
        HOUSEHOLD_ID_BY_PERSON.clear();
        return affected;
    }

    private static Map<Id, Set<Id>> withAccountsForPersonContacts(
        Map<Id, Set<Id>> personIdsByHouseholdId,
        Map<Id, Id> accountBehindContact
    ) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        for (Id householdId : personIdsByHouseholdId.keySet()) {
            Set<Id> people = personIdsByHouseholdId.get(householdId);
            result.put(
                householdId,
                people == null ? null : withAccountsForPersonContacts(people, accountBehindContact)
            );
        }
        return result;
    }

    private static Set<Id> withAccountsForPersonContacts(
        Set<Id> people,
        Map<Id, Id> accountBehindContact
    ) {
        Set<Id> result = new Set<Id>();
        for (Id personId : people) {
            result.add(
                accountBehindContact.containsKey(personId)
                    ? accountBehindContact.get(personId)
                    : personId
            );
        }
        return result;
    }

    /**
     * One membership row per person who is not already a current member of the household
     * they are joining. Read once for everybody, written once.
     */
    private static void joinThroughJunction(
        Map<Id, Set<Id>> personIdsByHouseholdId,
        Set<Id> everybody
    ) {
        Set<String> alreadyMembers = new Set<String>();
        for (
            Household_Member__c membership : HouseholdSelector.getMembershipsForPeople(everybody)
        ) {
            Id personId = membership.Contact__c != null
                ? membership.Contact__c
                : membership.Account__c;
            if (personId != null) {
                alreadyMembers.add(membership.Household__c + ':' + personId);
            }
        }
        List<Household_Member__c> joined = new List<Household_Member__c>();
        for (Id householdId : personIdsByHouseholdId.keySet()) {
            Set<Id> people = personIdsByHouseholdId.get(householdId);
            if (people == null) {
                continue;
            }
            for (Id personId : people) {
                if (alreadyMembers.contains(householdId + ':' + personId)) {
                    continue;
                }
                joined.add(newMembership(personId, householdId, null, false));
            }
        }
        if (!joined.isEmpty()) {
            Database.insert(joined, AccessLevel.USER_MODE);
        }
    }

    /**
     * In contact mode joining is the person's own account reference, so everybody moves in
     * one update and every household somebody left is added to the answer.
     */
    private static void joinThroughContacts(
        Map<Id, Set<Id>> personIdsByHouseholdId,
        Set<Id> contactPeople,
        Set<Id> affected
    ) {
        Map<Id, Contact> people = new Map<Id, Contact>(
            HouseholdSelector.getContactsByIds(contactPeople)
        );
        if (people.size() != contactPeople.size()) {
            throw new HouseholdException(Label.Core_Households_ErrorMoveNotFound);
        }
        List<Contact> updates = new List<Contact>();
        Map<Id, Id> leftHouseholdByContact = new Map<Id, Id>();
        for (Id householdId : personIdsByHouseholdId.keySet()) {
            Set<Id> joining = personIdsByHouseholdId.get(householdId);
            if (joining == null) {
                continue;
            }
            for (Id personId : joining) {
                Contact person = people.get(personId);
                if (person == null || person.AccountId == householdId) {
                    continue;
                }
                if (person.AccountId != null) {
                    affected.add(person.AccountId);
                    leftHouseholdByContact.put(personId, person.AccountId);
                }
                updates.add(new Contact(Id = personId, AccountId = householdId));
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
            removeRelationsLeftBehind(leftHouseholdByContact);
        }
    }

    /**
     * A membership row that points at the person through whichever object holds them, so
     * that an org storing people as accounts is joined up the same way as any other.
     */
    private static Household_Member__c newMembership(
        Id personId,
        Id householdId,
        String role,
        Boolean isPrimary
    ) {
        Household_Member__c membership = new Household_Member__c(
            Household__c = householdId,
            Role__c = role,
            Is_Primary__c = isPrimary,
            Start_Date__c = Date.today()
        );
        if (personId.getSObjectType() == Contact.SObjectType) {
            membership.Contact__c = personId;
        } else {
            membership.Account__c = personId;
        }
        return membership;
    }

    /**
     * Creates one household named from the people who are about to join it, for a split
     * that has no household to move them into yet. The people are not attached here: the
     * caller moves them, so that one move path serves every caller.
     *
     * The split is a person's request, so the household is created with the checks of
     * HouseholdWriter.createHouseholdsForUser: `touchedHouseholdIds` are the households the
     * same split edits, and the running user needs edit access to each.
     */
    @NamespaceAccessible
    public static Id createHouseholdFor(List<Person> members, Set<Id> touchedHouseholdIds) {
        Database.SaveResult created = saveNewHousehold(members, touchedHouseholdIds);
        if (!created.isSuccess()) {
            // HouseholdWriter has already logged why. Nobody is moved into a household
            // that does not exist, so the split stops here rather than half happening.
            throw new HouseholdException(Label.Core_Households_ErrorCreateFailed);
        }
        return created.getId();
    }

    /**
     * Creates one household with no members yet, named with the placeholder until people join
     * it, for New Household on BarnCRM Home. Staff never get the Household record type
     * (ADR-0141), so this is the way a person creates a household by hand.
     */
    @NamespaceAccessible
    public static Id createEmptyHousehold() {
        Database.SaveResult created = saveNewHousehold(new List<Person>(), new Set<Id>());
        if (!created.isSuccess()) {
            throw new HouseholdException(
                String.format(
                    Label.Core_HubHomeActions_NewHouseholdFailed,
                    new List<Object>{ HouseholdWriter.failureReason(created) }
                )
            );
        }
        return created.getId();
    }

    private static Database.SaveResult saveNewHousehold(
        List<Person> members,
        Set<Id> touchedHouseholdIds
    ) {
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            throw new HouseholdException(Label.Core_Households_ErrorRecordTypeMissing);
        }
        List<Person> people = members == null ? new List<Person>() : members;
        Account household = newHousehold(people, recordTypeId, SettingsService.getSettings());
        household.Member_Count__c = 0;
        // The name, the greetings and the count on this record are the package's own
        // bookkeeping, and nobody is given the Household record type, so it is saved by
        // HouseholdWriter, which checks the person's own access first.
        List<Database.SaveResult> created = HouseholdWriter.createHouseholdsForUser(
            new List<Account>{ household },
            touchedHouseholdIds
        );
        HOUSEHOLD_ID_BY_PERSON.clear();
        return created[0];
    }

    /**
     * Brings each household's Primary Contact into line with its membership, in whichever
     * membership mode the org uses (R-M3, R-H10, ADR-0044 primary contact mirrors the primary
     * member). Part of every membership change's upkeep; public for the one caller that
     * settles a household without the rest of that upkeep (a merge that keeps a custom name).
     *
     * In contact mode the field is the mark itself, set by a person, so it is only cleared
     * when the person it names has left. In junction mode the field mirrors the membership
     * marked Is Primary, and this is the only thing that writes it.
     */
    @NamespaceAccessible
    public static void settlePrimaryContacts(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            return;
        }
        List<Account> households = HouseholdSelector.getHouseholdsByIds(householdIds);
        Map<Id, Id> primaryByHousehold = settledPrimaries(
            households,
            getMembers(householdIds),
            recordTypeId
        );
        List<Account> updates = new List<Account>();
        for (Account household : households) {
            Id primaryId = primaryByHousehold.get(household.Id);
            if (
                primaryByHousehold.containsKey(household.Id) &&
                household.Primary_Contact__c != primaryId
            ) {
                updates.add(new Account(Id = household.Id, Primary_Contact__c = primaryId));
            }
        }
        writePrimaryContacts(updates);
    }

    /** The id of the first current member marked primary, in member order (R-H5). */
    private static Id firstPrimaryId(List<Person> members) {
        List<Person> primaries = new List<Person>();
        if (members != null) {
            for (Person member : members) {
                if (member.isPrimary == true && member.id != null) {
                    primaries.add(member);
                }
            }
        }
        if (primaries.isEmpty()) {
            return null;
        }
        primaries.sort();
        return primaries[0].id;
    }

    /**
     * Package upkeep of a household, saved the way every other piece of household upkeep is
     * saved, for the reason ADR-0021 gives: an ordinary membership save must not fail because
     * the saving user cannot edit the household. Marked as the package's own write, so the
     * junction mode guard against a hand edit lets it through.
     */
    private static void writePrimaryContacts(List<Account> updates) {
        if (updates.isEmpty()) {
            return;
        }
        writingPrimaryContacts = true;
        try {
            HouseholdWriter.updateHouseholds(updates);
        } finally {
            writingPrimaryContacts = false;
        }
    }

    /**
     * Refuses a hand edit of Primary Contact on a household in junction mode, where the field
     * mirrors the member marked primary and this service is its only writer (R-M3). Setting it
     * on a new household counts as an edit. The refusal names the place to make the change
     * instead. An organization, contact mode, and this service's own write are all left alone.
     * Called from the Account trigger before insert and before update.
     */
    @NamespaceAccessible
    public static void refuseHandSetPrimaryContacts(
        List<Account> records,
        Map<Id, Account> previousById
    ) {
        if (writingPrimaryContacts || records == null || records.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        if (recordTypeId == null) {
            return;
        }
        if (!isJunctionMode()) {
            refuseNonMemberPrimaryContacts(records, previousById, recordTypeId);
            return;
        }
        for (Account record : records) {
            if (record.RecordTypeId != recordTypeId) {
                continue;
            }
            Account previous = previousById == null ? null : previousById.get(record.Id);
            Id before = previous == null ? null : previous.Primary_Contact__c;
            if (record.Primary_Contact__c != before) {
                record.Primary_Contact__c.addError(
                    Label.Core_Households_PrimaryContactFollowsMembers
                );
            }
        }
    }

    /**
     * Contact mode: a household's Primary Contact must be one of its members, a contact whose
     * account is this household (R-H10, PEOPLE-27). Checked only when the field is set or
     * changed to somebody, so clearing it, or saving a household whose primary has since
     * left, is never blocked. One read for the whole save, in system mode under ADR-0021: the
     * question is about the household's membership, not about what the saver can see.
     */
    private static void refuseNonMemberPrimaryContacts(
        List<Account> records,
        Map<Id, Account> previousById,
        Id recordTypeId
    ) {
        List<Account> checked = new List<Account>();
        Set<Id> contactIds = new Set<Id>();
        for (Account record : records) {
            if (record.RecordTypeId != recordTypeId || record.Primary_Contact__c == null) {
                continue;
            }
            Account previous = previousById == null ? null : previousById.get(record.Id);
            if (previous != null && previous.Primary_Contact__c == record.Primary_Contact__c) {
                continue;
            }
            checked.add(record);
            contactIds.add(record.Primary_Contact__c);
        }
        if (checked.isEmpty()) {
            return;
        }
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        for (Contact person : HouseholdSelector.getContactsWithHouseholds(contactIds)) {
            accountByContact.put(person.Id, person.AccountId);
        }
        for (Account record : checked) {
            Id householdOfPrimary = accountByContact.get(record.Primary_Contact__c);
            if (record.Id == null || householdOfPrimary != record.Id) {
                record.Primary_Contact__c.addError(
                    Label.Core_Households_PrimaryContactMustBeMember
                );
            }
        }
    }

    /**
     * Recounts current members on each household given. R-H11.
     */
    @NamespaceAccessible
    public static void recalculateMemberCounts(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        Map<Id, List<Person>> membersByHousehold = getMembers(householdIds);
        List<Account> updates = new List<Account>();
        for (Account household : HouseholdSelector.getHouseholdsByIds(householdIds)) {
            // Only a household is counted. An organization a contact happens to belong to
            // never gets a member count stamped on it.
            if (recordTypeId != null && household.RecordTypeId != recordTypeId) {
                continue;
            }
            List<Person> members = membersByHousehold.get(household.Id);
            Decimal count = members == null ? 0 : members.size();
            if (household.Member_Count__c != count) {
                updates.add(new Account(Id = household.Id, Member_Count__c = count));
            }
        }
        if (!updates.isEmpty()) {
            HouseholdWriter.updateHouseholds(updates);
        }
    }

    /**
     * Deletes households that have been left with no members, when the org asks for that and
     * nothing outside BarnCRM still depends on the account. R-H12, ADR-0036.
     *
     * "Empty" is decided from BarnCRM's own membership, which is the only membership BarnCRM
     * can see. In an org running Salesforce Nonprofit Cloud a household account can
     * carry a native household group and native membership rows as well, and the account is
     * the master of that group, so deleting it would destroy the group rather than orphan it.
     * Such a household is left alone and the skip is reported, because a tidy-up that quietly
     * deletes somebody else's data is worse than a tidy-up left undone.
     *
     * A household that an installed package still credits records to is kept as well, asked
     * through `HouseholdDependentsExtensions` because Core may not know what those records
     * are (ADR-0070 `0070-empty-household-tidy-up-keeps-households-with-gifts.md`).
     */
    @NamespaceAccessible
    public static void deleteEmptyHouseholds(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return;
        }
        if (!deletesEmptyHouseholds()) {
            return;
        }
        deleteEmptyHouseholds(
            HouseholdSelector.getHouseholdsByIds(householdIds),
            getMembers(householdIds)
        );
    }

    private static Boolean deletesEmptyHouseholds() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && settings.Delete_Empty_Households__c == true;
    }

    /** The same, from households and members the caller has already read. */
    private static void deleteEmptyHouseholds(
        List<Account> households,
        Map<Id, List<Person>> membersByHousehold
    ) {
        if (!deletesEmptyHouseholds()) {
            return;
        }
        Id recordTypeId = householdRecordTypeId();
        List<Account> empties = new List<Account>();
        for (Account household : households) {
            List<Person> members = membersByHousehold.get(household.Id);
            Boolean isHousehold = recordTypeId != null && household.RecordTypeId == recordTypeId;
            if (isHousehold && (members == null || members.isEmpty())) {
                empties.add(household);
            }
        }
        if (empties.isEmpty()) {
            return;
        }
        // One probe for the whole batch, so a split of fifty households still asks once.
        Set<Id> emptyIds = new Map<Id, Account>(empties).keySet();
        if (!isJunctionMode()) {
            // Contact mode reads members with sharing, so a household can look empty to
            // somebody who cannot see the people still in it. Those households are kept.
            Set<Id> occupied = HouseholdSelector.householdsWithAnyContact(emptyIds);
            if (!occupied.isEmpty()) {
                List<Account> stillEmpty = new List<Account>();
                for (Account household : empties) {
                    if (!occupied.contains(household.Id)) {
                        stillEmpty.add(household);
                    }
                }
                empties = stillEmpty;
                if (empties.isEmpty()) {
                    return;
                }
                emptyIds = new Map<Id, Account>(empties).keySet();
            }
        }
        Set<Id> dependent = HouseholdSelector.getAccountsWithNativeDependents(emptyIds);
        // Records another BarnCRM package still credits to the household, such as the gifts
        // given from it, which keep that household when the donor moves (R-G2). Kept quietly:
        // it is the ordinary outcome of a move, not something to act on.
        Set<Id> credited = HouseholdDependentsExtensions.householdsWithDependents(emptyIds);
        List<Account> deletable = new List<Account>();
        List<String> skipped = new List<String>();
        for (Account household : empties) {
            if (credited.contains(household.Id) && !dependent.contains(household.Id)) {
                continue;
            }
            if (dependent.contains(household.Id)) {
                if (!REPORTED_KEPT_HOUSEHOLDS.add(household.Id)) {
                    continue;
                }
                skipped.add(
                    String.format(
                        Label.Core_Households_SkippedNativeDependents,
                        new List<String>{ household.Name, String.valueOf(household.Id) }
                    )
                );
            } else {
                deletable.add(new Account(Id = household.Id));
            }
        }
        if (!skipped.isEmpty()) {
            // Not an error: an administrator is being told what was deliberately left alone,
            // and why, so that the empty household on their list is explained rather than
            // mysterious.
            ErrorLogger.logMessages(
                skipped,
                Label.Core_Households_ErrorContextMembership,
                ErrorLogger.SEVERITY_INFO
            );
        }
        if (!deletable.isEmpty()) {
            HouseholdWriter.deleteHouseholds(deletable);
        }
    }
}
