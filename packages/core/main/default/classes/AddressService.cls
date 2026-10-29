/**
 * Addresses (C-17, canonical model Section 29).
 *
 * Two directions, and a single in-transaction flag keeps them from calling each other
 * round in a circle:
 *
 * 1. syncDefaultToStandardFields: the address marked default is copied into the standard
 *    address fields on its owner, and on every current household member who does not keep
 *    an address of their own, so mail merges, reports, and other apps keep reading the
 *    address they have always read (R-AD3).
 * 2. captureFromStandardFields: an address typed into the standard fields, or changed
 *    there, becomes or updates an address record, so the records stay the truth (R-AD5).
 *    A person account's mailing address is captured the same way, on insert and on update
 *    (capturePersonMailingChanges), and so is a household's or organization's billing
 *    address changed after it was created (captureBillingChanges).
 *
 * No Person Account field is referenced statically anywhere in this class. Where people
 * are person accounts their mailing fields are written dynamically, by name, only in an
 * org that has them (plan Section 4.2, ADR-0009), and only on an account that actually
 * holds a person: in such an org those fields exist on every account, but only a person
 * account will accept a value in one, so the record type decides the write and not the
 * org shape. See personAccountIdsAmong.
 */
public with sharing class AddressService {
    @TestVisible
    private static Boolean isPropagating = false;

    @TestVisible
    private static final String BEHAVIOR_UPDATE_HOUSEHOLD = 'Update household';
    @TestVisible
    private static final String BEHAVIOR_PERSONAL_ADDRESS = 'Create personal address';
    /** "Nobody moves until you choose" (ADR-0140). */
    @TestVisible
    private static final String BEHAVIOR_MANUAL = 'Manual';

    /**
     * Raised while a household move nobody has to wait for is saved: the seasonal swap, and a
     * move someone chose on the address card. In "Nobody moves until you choose" a household's
     * new primary address reaches its members only then (R-AD3, ADR-0140).
     */
    private static Boolean householdMoveChosen = false;

    private static final String TYPE_HOME = 'Home';
    private static final String TYPE_WORK = 'Work';
    public static final String TYPE_SEASONAL = 'Seasonal';

    /** The three address statuses (R-AD10). A blank reads as Current. */
    public static final String STATUS_CURRENT = 'Current';
    public static final String STATUS_FORMER = 'Former';
    public static final String STATUS_UNDELIVERABLE = 'Undeliverable';

    private static final String RECORD_TYPE_HOUSEHOLD = 'Household';

    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_STREET = 'PersonMailingStreet';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_CITY = 'PersonMailingCity';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_STATE = 'PersonMailingState';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_POSTAL_CODE = 'PersonMailingPostalCode';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_COUNTRY = 'PersonMailingCountry';

    private static Map<String, Schema.SObjectField> accountFields;

    /**
     * Test seam. Household membership is read only through HouseholdService, which hides
     * whether the org uses contact mode or the membership junction. Junction mode, and
     * households whose people are person accounts, are reproduced here by handing this
     * class the membership HouseholdService would return, because the junction object and
     * person accounts cannot both be created in one org shape. Never set outside a test.
     */
    @TestVisible
    private static Map<Id, Set<Id>> membersByHouseholdOverride;

    // ---------------------------------------------------------------- direction one

    /**
     * Copies each default address into the standard address fields of its owner. An
     * address owned by an account writes the account's billing address and the mailing
     * address of every current household member; an address owned by one person writes
     * that person's mailing address only.
     */
    public static void syncDefaultToStandardFields(List<Address__c> addresses) {
        syncDefaultToStandardFields(addresses, false);
    }

    /**
     * The same, saying whether the addresses were just added: a new address saved as the
     * primary is a move, which ends the primary it replaces (R-AD10).
     */
    public static void syncDefaultToStandardFields(List<Address__c> addresses, Boolean areNew) {
        if (addresses == null || addresses.isEmpty() || isPropagating) {
            return;
        }
        List<Address__c> defaults = defaultsOnly(addresses);
        if (defaults.isEmpty()) {
            return;
        }
        isPropagating = true;
        try {
            clearOtherDefaults(defaults, areNew == true);
            applyToStandardFields(defaults);
        } finally {
            isPropagating = false;
        }
    }

    /**
     * After a default address is deleted, promotes the most recently created remaining
     * address for that owner, preferring one that is not seasonal: a seasonal address put in
     * use outside its season would send the mail to the wrong home (PEOPLE-49). A seasonal one
     * is promoted only when nothing else is left. Deleting a default is allowed: refusing it
     * would leave a household stuck with an address it no longer uses.
     */
    public static void promoteDefaultAfterDelete(List<Address__c> deletedAddresses) {
        if (deletedAddresses == null || deletedAddresses.isEmpty() || isPropagating) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        Set<Id> deletedIds = new Set<Id>();
        for (Address__c address : deletedAddresses) {
            deletedIds.add(address.Id);
            if (address.Is_Default__c == true && ownerIdOf(address) != null) {
                ownerIds.add(ownerIdOf(address));
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }
        Map<Id, Address__c> newestByOwner = new Map<Id, Address__c>();
        // Status (R-AD10) is read through withHistory: a Former address is the last choice.
        for (
            Address__c address : AddressSelector.withHistory(
                AddressSelector.selectByOwnerIds(ownerIds)
            )
        ) {
            Id ownerId = ownerIdOf(address);
            if (deletedIds.contains(address.Id) || ownerId == null) {
                continue;
            }
            if (betterReplacement(address, newestByOwner.get(ownerId))) {
                newestByOwner.put(ownerId, address);
            }
        }
        if (newestByOwner.isEmpty()) {
            return;
        }
        List<Address__c> promoted = new List<Address__c>();
        for (Address__c address : newestByOwner.values()) {
            address.Is_Default__c = true;
            promoted.add(new Address__c(Id = address.Id, Is_Default__c = true));
        }
        // The flag is raised before the promotion is saved, so the address trigger this
        // update fires does not propagate a second time: the propagation below is the one
        // that runs, and the standard fields are written once for the whole batch.
        isPropagating = true;
        try {
            Database.update(promoted, AccessLevel.USER_MODE);
            applyToStandardFields(new List<Address__c>(newestByOwner.values()));
        } finally {
            isPropagating = false;
        }
    }

    /**
     * Whether `candidate` is a better address to put in use than `held`, the best so far. A
     * Former address only when nothing else is left (R-AD10), then a seasonal one only when
     * nothing else is left.
     */
    private static Boolean betterReplacement(Address__c candidate, Address__c held) {
        if (held == null) {
            return true;
        }
        Boolean candidateFormer = candidate.Status__c == STATUS_FORMER;
        Boolean heldFormer = held.Status__c == STATUS_FORMER;
        if (candidateFormer != heldFormer) {
            return !candidateFormer;
        }
        Boolean candidateSeasonal = candidate.Type__c == TYPE_SEASONAL;
        Boolean heldSeasonal = held.Type__c == TYPE_SEASONAL;
        if (candidateSeasonal != heldSeasonal) {
            return !candidateSeasonal;
        }
        return candidate.CreatedDate > held.CreatedDate;
    }

    // ---------------------------------------------------------------- before the save

    /**
     * One default per owner within a single save (R-AD2, PEOPLE-22). When one insert or
     * update marks two or more addresses of the same owner as default (an import can), the
     * last of them in the save keeps the flag and the others are saved without it; the
     * defaults already on file are cleared after the save, as for any new default.
     */
    public static void keepOneDefaultPerOwnerInSave(List<Address__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        Map<Id, Address__c> lastDefaultByOwner = new Map<Id, Address__c>();
        for (Address__c address : records) {
            Id ownerId = ownerIdOf(address);
            if (address.Is_Default__c != true || ownerId == null) {
                continue;
            }
            Address__c earlier = lastDefaultByOwner.put(ownerId, address);
            if (earlier != null) {
                earlier.Is_Default__c = false;
            }
        }
    }

    /**
     * Status before the save (R-AD10): an address with none is Current, and an address put in
     * use as the primary while Former is Current again, its End Date cleared, so the primary is
     * never Former. Undeliverable is a person's call and is never changed here.
     *
     * @param previousById the addresses before an update, or null on insert
     */
    public static void applyStatusBeforeSave(
        List<Address__c> records,
        Map<Id, SObject> previousById
    ) {
        if (records == null) {
            return;
        }
        for (Address__c address : records) {
            if (String.isBlank(address.Status__c)) {
                address.Status__c = STATUS_CURRENT;
            }
            Address__c previous = previousById == null
                ? null
                : (Address__c) previousById.get(address.Id);
            Boolean putInUse =
                address.Is_Default__c == true &&
                (previous == null ||
                previous.Is_Default__c != true);
            if (putInUse && address.Status__c == STATUS_FORMER) {
                address.Status__c = STATUS_CURRENT;
                address.End_Date__c = null;
            }
        }
    }

    /**
     * Refuses unticking the address an owner has in use when nothing else in the same save
     * puts another in use and the owner has no other default on file (PEOPLE-49). Without
     * it the owner would have no address in use and standard fields still showing this one.
     * Choosing another address as the default, or deleting this one, is how it is changed.
     * The package's own writes (a new default clearing the old one, the seasonal swap, a
     * promotion after a delete) always put another in use in the same save, or run while
     * propagation is under way, so they are never refused.
     */
    public static void refuseLeavingAnOwnerWithoutADefault(
        List<Address__c> records,
        Map<Id, SObject> previousById
    ) {
        if (records == null || previousById == null || isPropagating) {
            return;
        }
        Map<Id, List<Address__c>> untickedByOwner = new Map<Id, List<Address__c>>();
        Set<Id> ownersWithADefaultInSave = new Set<Id>();
        for (Address__c address : records) {
            Id ownerId = ownerIdOf(address);
            if (ownerId == null) {
                continue;
            }
            if (address.Is_Default__c == true) {
                ownersWithADefaultInSave.add(ownerId);
                continue;
            }
            Address__c previous = (Address__c) previousById.get(address.Id);
            if (previous != null && previous.Is_Default__c == true) {
                if (!untickedByOwner.containsKey(ownerId)) {
                    untickedByOwner.put(ownerId, new List<Address__c>());
                }
                untickedByOwner.get(ownerId).add(address);
            }
        }
        untickedByOwner.keySet().removeAll(ownersWithADefaultInSave);
        if (untickedByOwner.isEmpty()) {
            return;
        }
        Set<Id> ownersWithAnotherDefault = new Set<Id>();
        for (
            Address__c other : AddressSelector.selectDefaultsByOwnerIds(
                untickedByOwner.keySet(),
                previousById.keySet()
            )
        ) {
            ownersWithAnotherDefault.add(ownerIdOf(other));
        }
        for (Id ownerId : untickedByOwner.keySet()) {
            if (ownersWithAnotherDefault.contains(ownerId)) {
                continue;
            }
            for (Address__c address : untickedByOwner.get(ownerId)) {
                address.addError(Label.Core_Address_CannotUntickOnlyDefault);
            }
        }
    }

    /**
     * Leaves each of these owners with one default address (R-AD2), for the survivor of a
     * merge, which arrives with the other record's default as well as its own (PEOPLE-15).
     *
     * The default kept is the one that matches the owner's standard address fields (billing
     * for a household or organization, mailing for a contact or a person account), because
     * those hold the address the merge chose; otherwise the most recently created, as when a
     * default is deleted. A person account's mailing fields are named as strings, so this runs
     * in an org without person accounts. The others stay as ordinary addresses. Nothing is copied into the standard
     * fields: the kept default is the one they already hold, or the merge left them as chosen.
     */
    public static void keepOneDefault(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return;
        }
        Map<Id, List<Address__c>> defaultsByOwner = new Map<Id, List<Address__c>>();
        // Newest first, so the first address held for an owner is the fallback to keep.
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(ownerIds, null)) {
            Id ownerId = ownerIdOf(address);
            if (!defaultsByOwner.containsKey(ownerId)) {
                defaultsByOwner.put(ownerId, new List<Address__c>());
            }
            defaultsByOwner.get(ownerId).add(address);
        }
        Set<Id> crowded = new Set<Id>();
        Set<Id> crowdedAccounts = new Set<Id>();
        Set<Id> crowdedContacts = new Set<Id>();
        for (Id ownerId : defaultsByOwner.keySet()) {
            if (defaultsByOwner.get(ownerId).size() > 1) {
                crowded.add(ownerId);
                if (ownerId.getSObjectType() == Contact.SObjectType) {
                    crowdedContacts.add(ownerId);
                } else {
                    crowdedAccounts.add(ownerId);
                }
            }
        }
        if (crowded.isEmpty()) {
            return;
        }
        Map<Id, String> standardKeyByOwner = new Map<Id, String>();
        Set<Id> personAccounts = personAccountIdsAmong(crowdedAccounts);
        List<String> personFields = personAccounts.isEmpty()
            ? null
            : new List<String>{
                  PERSON_MAILING_STREET,
                  PERSON_MAILING_CITY,
                  PERSON_MAILING_POSTAL_CODE
              };
        for (
            Account owner : AddressSelector.selectAccountBillingAddresses(
                crowdedAccounts,
                personFields
            )
        ) {
            standardKeyByOwner.put(
                owner.Id,
                personAccounts.contains(owner.Id)
                    ? addressKey(
                          (String) owner.get(PERSON_MAILING_STREET),
                          (String) owner.get(PERSON_MAILING_CITY),
                          (String) owner.get(PERSON_MAILING_POSTAL_CODE)
                      )
                    : addressKey(owner.BillingStreet, owner.BillingCity, owner.BillingPostalCode)
            );
        }
        for (Contact owner : AddressSelector.selectContactMailingAddresses(crowdedContacts)) {
            standardKeyByOwner.put(
                owner.Id,
                addressKey(owner.MailingStreet, owner.MailingCity, owner.MailingPostalCode)
            );
        }
        List<Address__c> stale = new List<Address__c>();
        for (Id ownerId : crowded) {
            List<Address__c> defaults = defaultsByOwner.get(ownerId);
            Address__c kept = defaults[0];
            for (Address__c address : defaults) {
                String key = addressKey(address.Street__c, address.City__c, address.Postal_Code__c);
                if (key == standardKeyByOwner.get(ownerId)) {
                    kept = address;
                    break;
                }
            }
            for (Address__c address : defaults) {
                if (address.Id != kept.Id) {
                    stale.add(new Address__c(Id = address.Id, Is_Default__c = false));
                }
            }
        }
        isPropagating = true;
        try {
            Database.update(stale, AccessLevel.USER_MODE);
        } finally {
            isPropagating = false;
        }
    }

    private static String addressKey(String street, String city, String postalCode) {
        return (String.isBlank(street) ? '' : street.trim().toLowerCase()) +
            '|' +
            (String.isBlank(city) ? '' : city.trim().toLowerCase()) +
            '|' +
            (String.isBlank(postalCode) ? '' : postalCode.trim().toLowerCase());
    }

    // ---------------------------------------------------------------- direction two

    /**
     * Turns an address typed into the standard fields into an address record.
     *
     * A household or organization account created with a billing address gets a primary
     * address record of type Home (Work for an organization), so nothing staff typed or
     * an import loaded is lost. A person whose mailing address changes either moves their
     * whole household or gains an address of their own, depending on the org's
     * Contact_Address_Change_Behavior__c setting (Address Updates).
     */
    public static void captureFromStandardFields(List<Account> accounts, List<Contact> contacts) {
        Boolean nothingToDo =
            (accounts == null || accounts.isEmpty()) && (contacts == null || contacts.isEmpty());
        if (nothingToDo || isPropagating) {
            return;
        }
        isPropagating = true;
        try {
            // A changed address is always a new record (R-AD7): the old one is kept as
            // history and loses the default flag below, rather than being overwritten.
            List<Address__c> toInsert = new List<Address__c>();
            captureAccounts(accounts, toInsert);
            captureContacts(contacts, toInsert);
            insertCaptured(toInsert);
        } finally {
            isPropagating = false;
        }
    }

    /**
     * A person account saved with a mailing address, or whose mailing address was changed,
     * gets an address record of their own, so the records stay the truth for people held as
     * accounts too (R-AD5, PEOPLE-17). Contact triggers do not fire for person account saves,
     * so the Account handler calls this after update. Only a person whose mailing address
     * differs from the one before the save is looked at. Does nothing, and runs no query, in an
     * org with no person accounts.
     */
    public static void capturePersonMailingChanges(
        List<Account> accounts,
        Map<Id, SObject> previousById
    ) {
        if (accounts == null || accounts.isEmpty() || isPropagating) {
            return;
        }
        Set<Id> personTypes = personRecordTypeIds();
        if (personTypes.isEmpty()) {
            return;
        }
        List<Account> moved = new List<Account>();
        for (Account account : accounts) {
            SObject before = previousById == null ? null : previousById.get(account.Id);
            if (
                personTypes.contains(account.RecordTypeId) &&
                (before == null || personMailingChanged(account, before))
            ) {
                moved.add(account);
            }
        }
        if (moved.isEmpty()) {
            return;
        }
        isPropagating = true;
        try {
            List<Address__c> toInsert = new List<Address__c>();
            capturePersonAccounts(moved, toInsert);
            insertCaptured(toInsert);
        } finally {
            isPropagating = false;
        }
    }

    /**
     * A household or organization whose billing address was changed after it was created gets
     * the new address as its default address record, exactly as one created with it does, so
     * an edit made in the billing fields (on the page, by an import, by another app) is kept
     * and reaches the household's members instead of being put back by the next default saved
     * (R-AD3). The address it replaces stays on file as history (R-AD7).
     *
     * Only an account whose billing address differs from the one before the save is looked
     * at, so an ordinary account save runs no query. A billing address emptied is not an
     * address and is not captured, and one the account's default already holds is not added a
     * second time. BarnCRM's own billing writes are made with the propagation flag raised and
     * never come back here. A household that carries a native Nonprofit Cloud household group
     * is left alone, as the propagation leaves it alone (product-plan Section 11.2 item 9).
     * A person account is capturePersonMailingChanges' to capture, not this method's.
     */
    public static void captureBillingChanges(
        List<Account> accounts,
        Map<Id, SObject> previousById
    ) {
        if (accounts == null || accounts.isEmpty() || previousById == null || isPropagating) {
            return;
        }
        List<Account> changed = new List<Account>();
        for (Account account : accounts) {
            Account before = (Account) previousById.get(account.Id);
            if (before != null && billingChanged(account, before)) {
                changed.add(account);
            }
        }
        if (changed.isEmpty()) {
            return;
        }
        Map<Id, Address__c> typedByAccount = new Map<Id, Address__c>();
        for (Address__c typed : billingAddressesOf(changed, new List<Account>())) {
            typedByAccount.put(typed.Account__c, typed);
        }
        if (typedByAccount.isEmpty()) {
            return;
        }
        for (
            Id nativeHousehold : HouseholdSelector.nativeHouseholdAccountsAmong(
                typedByAccount.keySet()
            )
        ) {
            typedByAccount.remove(nativeHousehold);
        }
        if (typedByAccount.isEmpty()) {
            return;
        }
        for (
            Address__c existing : AddressSelector.selectDefaultsByOwnerIds(
                typedByAccount.keySet(),
                null
            )
        ) {
            if (
                existing.Account__c != null &&
                sameAddress(existing, typedByAccount.get(existing.Account__c))
            ) {
                typedByAccount.remove(existing.Account__c);
            }
        }
        if (typedByAccount.isEmpty()) {
            return;
        }
        isPropagating = true;
        try {
            insertCaptured(typedByAccount.values());
        } finally {
            isPropagating = false;
        }
    }

    private static Boolean billingChanged(Account account, Account before) {
        return !sameText(account.BillingStreet, before.BillingStreet) ||
            !sameText(account.BillingCity, before.BillingCity) ||
            !sameText(account.BillingState, before.BillingState) ||
            !sameText(account.BillingPostalCode, before.BillingPostalCode) ||
            !sameText(account.BillingCountry, before.BillingCountry);
    }

    private static void insertCaptured(List<Address__c> toInsert) {
        if (toInsert.isEmpty()) {
            return;
        }
        insertAsMoves(toInsert).save();
        applyToStandardFields(toInsert);
    }

    // ---------------------------------------------------------------- seasonal helper

    /**
     * Whether a seasonal address covers today. A range may wrap the end of the year, so
     * November 1 to March 31 is one range and not two (R-AD4). The v0.4 seasonal swap job
     * (C-18) is the only planned caller; it needs no change to this object.
     */
    public static Boolean isSeasonalActiveToday(Address__c address) {
        return isSeasonalActiveOn(address, Date.today());
    }

    /** The same test against any day, so the swap job and its tests can name a date. */
    public static Boolean isSeasonalActiveOn(Address__c address, Date day) {
        if (address == null || day == null || address.Type__c != TYPE_SEASONAL) {
            return false;
        }
        // A Former seasonal address is one the owner no longer goes to (R-AD10).
        if (address.Status__c == STATUS_FORMER) {
            return false;
        }
        if (
            address.Seasonal_Start_Month__c == null ||
            address.Seasonal_Start_Day__c == null ||
            address.Seasonal_End_Month__c == null ||
            address.Seasonal_End_Day__c == null
        ) {
            return false;
        }
        Integer today = (day.month() * 100) + day.day();
        Integer start =
            (address.Seasonal_Start_Month__c.intValue() * 100) +
            address.Seasonal_Start_Day__c.intValue();
        Integer finish =
            (address.Seasonal_End_Month__c.intValue() * 100) +
            address.Seasonal_End_Day__c.intValue();
        if (start <= finish) {
            return today >= start && today <= finish;
        }
        return today >= start || today <= finish;
    }

    // ---------------------------------------------------------------- moves someone chose

    /** A move refused with a message the address card shows as it is (R-AD9). */
    public class AddressMoveException extends Exception {
    }

    /** Who a household's primary address reaches, for the confirmation (R-AD9). */
    public class HouseholdMove {
        /** The household's primary address, or null when it has none. */
        public Address__c primary;
        /** The members who take the household's address (R-AD3). */
        public Set<Id> taking = new Set<Id>();
        /** The members left where they are for an address of their own, unless ticked. */
        public Set<Id> withTheirOwn = new Set<Id>();
    }

    /**
     * Use for Whole Household (R-AD9, ADR-0140). A copy of each person's address becomes the
     * primary address of the household named for it, which must be one that person currently
     * belongs to; one already holding exactly that address is not given it twice. A person
     * stored as a contact, for whom that household is their household (R-M3), stops having a
     * primary address of their own, so they follow the household again; their addresses stay
     * on file (R-AD7). The household's new primary reaches every member who takes it (R-AD3),
     * whatever the Address Updates setting. Written as the user, many at once.
     *
     * @param householdByAddressId the household each person's address is to be used for
     * @return the household addresses added
     */
    public static List<Address__c> useForWholeHousehold(Map<Id, Id> householdByAddressId) {
        List<Address__c> added = new List<Address__c>();
        if (householdByAddressId == null || householdByAddressId.isEmpty()) {
            return added;
        }
        List<Address__c> sources = AddressSelector.selectByIds(householdByAddressId.keySet());
        if (sources.size() != householdByAddressId.size()) {
            throw new AddressMoveException(System.Label.Core_Address_MoveNotFound);
        }
        Set<Id> personIds = new Set<Id>();
        for (Address__c source : sources) {
            Id personId = source.Contact__c != null ? source.Contact__c : source.Person_Account__c;
            if (personId == null) {
                throw new AddressMoveException(System.Label.Core_Address_MoveNotAPersonsAddress);
            }
            personIds.add(personId);
        }
        Map<Id, Set<Id>> householdsByPerson = HouseholdService.currentHouseholdIdsByPerson(
            personIds
        );
        Map<Id, Id> ownHouseholdByPerson = HouseholdService.getHouseholdIdsFor(personIds);
        Map<Id, Address__c> primaryByHousehold = new Map<Id, Address__c>();
        for (
            Address__c current : AddressSelector.selectDefaultsByOwnerIds(
                new Set<Id>(householdByAddressId.values()),
                null
            )
        ) {
            if (current.Account__c != null) {
                primaryByHousehold.put(current.Account__c, current);
            }
        }
        Map<Id, Id> released = new Map<Id, Id>();
        for (Address__c source : sources) {
            Id personId = source.Contact__c != null ? source.Contact__c : source.Person_Account__c;
            Id householdId = householdByAddressId.get(source.Id);
            Set<Id> theirs = householdsByPerson.get(personId);
            if (householdId == null || theirs == null || !theirs.contains(householdId)) {
                throw new AddressMoveException(System.Label.Core_Address_MoveNotTheirHousehold);
            }
            if (source.Contact__c != null && ownHouseholdByPerson.get(personId) == householdId) {
                released.put(personId, householdId);
            }
            if (!sameAddress(primaryByHousehold.get(householdId), source)) {
                Address__c copy = householdCopyOf(source, householdId);
                added.add(copy);
                primaryByHousehold.put(householdId, copy);
            }
        }
        moveChosen(added, released, primaryByHousehold.values());
        return added;
    }

    /** A new primary address for the household, with what the person's address says. */
    private static Address__c householdCopyOf(Address__c source, Id householdId) {
        Address__c copy = new Address__c(
            Account__c = householdId,
            Type__c = source.Type__c,
            Street__c = source.Street__c,
            City__c = source.City__c,
            State__c = source.State__c,
            Postal_Code__c = source.Postal_Code__c,
            Country__c = source.Country__c,
            Is_Default__c = true
        );
        if (source.Type__c == TYPE_SEASONAL) {
            copy.Seasonal_Start_Month__c = source.Seasonal_Start_Month__c;
            copy.Seasonal_Start_Day__c = source.Seasonal_Start_Day__c;
            copy.Seasonal_End_Month__c = source.Seasonal_End_Month__c;
            copy.Seasonal_End_Day__c = source.Seasonal_End_Day__c;
        }
        return copy;
    }

    /**
     * Who each household's primary address would reach, for the Update Everyone's Address
     * confirmation (R-AD9). Every household asked about is in the answer.
     */
    public static Map<Id, HouseholdMove> householdMoves(Set<Id> householdIds) {
        Map<Id, HouseholdMove> moves = new Map<Id, HouseholdMove>();
        if (householdIds == null || householdIds.isEmpty()) {
            return moves;
        }
        for (Id householdId : householdIds) {
            moves.put(householdId, new HouseholdMove());
        }
        for (Address__c primary : AddressSelector.selectDefaultsByOwnerIds(householdIds, null)) {
            if (moves.containsKey(primary.Account__c)) {
                moves.get(primary.Account__c).primary = primary;
            }
        }
        Map<Id, Set<Id>> keptBack = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> taking = membersWhoTakeTheHouseholdAddress(
            membersOf(householdIds),
            keptBack
        );
        for (Id householdId : householdIds) {
            HouseholdMove move = moves.get(householdId);
            if (taking.get(householdId) != null) {
                move.taking.addAll(taking.get(householdId));
            }
            if (keptBack.get(householdId) != null) {
                move.withTheirOwn.addAll(keptBack.get(householdId));
            }
        }
        return moves;
    }

    /**
     * Update Everyone's Address (R-AD9, ADR-0140). Each household's primary address is copied
     * to every member who takes it (R-AD3), and to the members ticked from among those with an
     * address of their own, whose own primary stops being primary and stays on file (R-AD7).
     * A tick on anyone else is ignored. Whatever the Address Updates setting, as the user, many
     * households at once.
     *
     * @param tickedByHousehold each household to move, with the members with an address of
     *        their own who are to move too (empty or null for none)
     */
    public static void updateEveryonesAddress(Map<Id, Set<Id>> tickedByHousehold) {
        if (tickedByHousehold == null || tickedByHousehold.isEmpty()) {
            return;
        }
        Map<Id, HouseholdMove> moves = householdMoves(tickedByHousehold.keySet());
        List<Address__c> primaries = new List<Address__c>();
        Map<Id, Id> released = new Map<Id, Id>();
        for (Id householdId : tickedByHousehold.keySet()) {
            HouseholdMove move = moves.get(householdId);
            if (move.primary == null) {
                throw new AddressMoveException(System.Label.Core_Address_MoveNoPrimary);
            }
            primaries.add(move.primary);
            Set<Id> ticked = tickedByHousehold.get(householdId);
            for (Id personId : ticked == null ? new Set<Id>() : ticked) {
                if (move.withTheirOwn.contains(personId)) {
                    released.put(personId, householdId);
                }
            }
        }
        moveChosen(new List<Address__c>(), released, primaries);
    }

    /**
     * Saves a move someone chose: the household addresses to add, the people whose own primary
     * address stops being primary, then the copy of every household primary to its members.
     * Raised as a chosen move, so it reaches members in "Nobody moves until you choose" too.
     * A released person's own primary is ended when it is a different place from the
     * household primary they now take (R-AD10).
     *
     * @param householdByReleased each person whose own primary stops being primary, with the
     *        household whose primary they take from now on
     */
    private static void moveChosen(
        List<Address__c> toAdd,
        Map<Id, Id> householdByReleased,
        List<Address__c> primaries
    ) {
        Boolean movesWereChosen = chooseHouseholdMoves(true);
        isPropagating = true;
        try {
            // The household moves and the released people are saved in one write below.
            Move move = insertAsMoves(toAdd);
            Map<Id, Address__c> primaryByHousehold = new Map<Id, Address__c>();
            for (Address__c primary : primaries) {
                primaryByHousehold.put(primary.Account__c, primary);
            }
            for (
                Address__c own : AddressSelector.withHistory(
                    AddressSelector.selectDefaultsByOwnerIds(householdByReleased.keySet(), null)
                )
            ) {
                if (own.Contact__c == null) {
                    continue;
                }
                move.cleared.put(own.Id, new Address__c(Id = own.Id, Is_Default__c = false));
                Address__c taken = primaryByHousehold.get(householdByReleased.get(own.Contact__c));
                if (taken != null && own.Type__c != TYPE_SEASONAL && !sameAddress(own, taken)) {
                    Address__c closing = new Address__c(Id = own.Id);
                    endAddress(closing, own);
                    move.history.put(own.Id, closing);
                }
            }
            move.save();
            applyToStandardFields(primaries);
        } finally {
            isPropagating = false;
            chooseHouseholdMoves(movesWereChosen);
        }
    }

    // ---------------------------------------------------------------- internals

    private static List<Address__c> defaultsOnly(List<Address__c> addresses) {
        List<Address__c> defaults = new List<Address__c>();
        for (Address__c address : addresses) {
            if (address.Is_Default__c == true && ownerIdOf(address) != null) {
                defaults.add(address);
            }
        }
        return defaults;
    }

    /** The owner of an address: its household or organization, or the person it belongs to. */
    public static Id ownerIdOf(Address__c address) {
        if (address == null) {
            return null;
        }
        if (address.Account__c != null) {
            return address.Account__c;
        }
        if (address.Contact__c != null) {
            return address.Contact__c;
        }
        return address.Person_Account__c;
    }

    /**
     * At most one address per owner is the default (R-AD2). When the defaults were just added
     * the save is a move (R-AD10): the primary each replaces is ended and the new one started.
     */
    private static void clearOtherDefaults(List<Address__c> defaults, Boolean areNew) {
        new Move(defaults, areNew).save();
    }

    /**
     * Inserts new primary addresses as the user, as a move (R-AD10). What each one replaces is
     * read before the insert, so a new primary's start date goes in with the insert instead of
     * a second update of the same rows. The move is returned unsaved, for the caller to add to.
     */
    private static Move insertAsMoves(List<Address__c> toAdd) {
        Move move = new Move(toAdd, true);
        if (!toAdd.isEmpty()) {
            Database.insert(toAdd, AccessLevel.USER_MODE);
        }
        return move;
    }

    /**
     * The writes one move makes to addresses already on file: the old primaries cleared, and
     * the history fields a move sets (Status, Start Date, End Date, R-AD10).
     */
    private with sharing class Move {
        /** The addresses that stop being the primary, by Id. */
        public Map<Id, Address__c> cleared = new Map<Id, Address__c>();
        /** The history fields to set, by Id. */
        public Map<Id, Address__c> history = new Map<Id, Address__c>();
        /** New primaries saved without the start date they are given, until they have an Id. */
        private List<Address__c> starting = new List<Address__c>();

        public Move(List<Address__c> defaults, Boolean areNew) {
            Map<Id, Address__c> newByOwner = new Map<Id, Address__c>();
            Set<Id> keepIds = new Set<Id>();
            for (Address__c address : defaults) {
                Id ownerId = ownerIdOf(address);
                if (address.Is_Default__c != true || ownerId == null) {
                    continue;
                }
                newByOwner.put(ownerId, address);
                if (address.Id != null) {
                    keepIds.add(address.Id);
                }
            }
            if (newByOwner.isEmpty()) {
                return;
            }
            Map<Id, Address__c> replacedByOwner = new Map<Id, Address__c>();
            List<Address__c> replaced = AddressSelector.selectDefaultsByOwnerIds(
                newByOwner.keySet(),
                keepIds
            );
            if (areNew) {
                AddressSelector.withHistory(replaced);
            }
            for (Address__c address : replaced) {
                cleared.put(address.Id, new Address__c(Id = address.Id, Is_Default__c = false));
                replacedByOwner.put(ownerIdOf(address), address);
            }
            if (areNew) {
                recordMoves(replacedByOwner, newByOwner, this);
            }
        }

        /** A new primary starts today: with its insert when the user may set it, else after. */
        public void start(Address__c moved) {
            if (
                moved.Id == null &&
                Schema.SObjectType.Address__c.fields.Start_Date__c.isCreateable()
            ) {
                moved.Start_Date__c = Date.today();
            } else {
                starting.add(moved);
            }
        }

        /**
         * Saves the move. The flag is always cleared as the user. The history fields are kept
         * by BarnCRM on every move, not edited by the person saving, so someone who may save
         * addresses without access to them (a profile that grants Address__c, no BarnCRM
         * permission set) must not have an ordinary address save fail on them: for that person
         * they are saved after, in system mode, for this internal bookkeeping write only, with
         * the class's sharing still applied. For anyone who may edit them, the flag and the
         * history go in one user-mode update.
         */
        public void save() {
            for (Address__c moved : starting) {
                history.put(moved.Id, new Address__c(Id = moved.Id, Start_Date__c = Date.today()));
            }
            Map<Id, Address__c> changed = new Map<Id, Address__c>();
            for (Address__c change : history.values()) {
                // Id alone is one populated field: nothing to save.
                if (change.getPopulatedFieldsAsMap().size() > 1) {
                    changed.put(change.Id, change);
                }
            }
            if (historyEditableByUser()) {
                for (Address__c change : changed.values()) {
                    Address__c write = cleared.get(change.Id);
                    if (write == null) {
                        cleared.put(change.Id, change);
                        continue;
                    }
                    Map<String, Object> fields = change.getPopulatedFieldsAsMap();
                    for (String field : fields.keySet()) {
                        if (field != 'Id') {
                            write.put(field, fields.get(field));
                        }
                    }
                }
                changed.clear();
            }
            if (!cleared.isEmpty()) {
                Database.update(cleared.values(), AccessLevel.USER_MODE);
            }
            if (!changed.isEmpty()) {
                Database.update(changed.values(), AccessLevel.SYSTEM_MODE);
            }
        }
    }

    /** Whether the running user may edit all three history fields (R-AD10). */
    private static Boolean historyEditableByUser() {
        for (
            Schema.SObjectField field : new List<Schema.SObjectField>{
                Address__c.Status__c,
                Address__c.Start_Date__c,
                Address__c.End_Date__c
            }
        ) {
            if (!field.getDescribe().isUpdateable()) {
                return false;
            }
        }
        return true;
    }

    /**
     * A move (R-AD10): each owner's replaced primary gets End Date today, and Status Former when
     * it was Current, and the new primary gets Start Date today when it has none, unless the
     * two are the same place or the new one is seasonal. A Seasonal primary is not ended: the
     * address waiting for its season to end is, since that is the home the owner left.
     */
    private static void recordMoves(
        Map<Id, Address__c> replacedByOwner,
        Map<Id, Address__c> newByOwner,
        Move move
    ) {
        Map<Id, Address__c> history = move.history;
        Map<Id, Address__c> endingByOwner = new Map<Id, Address__c>();
        Set<Id> seasonalOwners = new Set<Id>();
        for (Id ownerId : replacedByOwner.keySet()) {
            Address__c replaced = replacedByOwner.get(ownerId);
            if (replaced.Type__c == TYPE_SEASONAL) {
                seasonalOwners.add(ownerId);
            } else {
                endingByOwner.put(ownerId, replaced);
            }
        }
        // Newest first, so the first one held for an owner is the one the swap would restore.
        for (
            Address__c waiting : AddressSelector.withHistory(
                AddressSelector.selectWaitingForSeason(seasonalOwners)
            )
        ) {
            if (!endingByOwner.containsKey(ownerIdOf(waiting))) {
                endingByOwner.put(ownerIdOf(waiting), waiting);
            }
        }
        for (Id ownerId : endingByOwner.keySet()) {
            Address__c ending = endingByOwner.get(ownerId);
            Address__c moved = newByOwner.get(ownerId);
            if (moved.Type__c == TYPE_SEASONAL || sameAddress(ending, moved)) {
                continue;
            }
            if (!history.containsKey(ending.Id)) {
                history.put(ending.Id, new Address__c(Id = ending.Id));
            }
            endAddress(history.get(ending.Id), ending);
            if (moved.Start_Date__c == null) {
                move.start(moved);
            }
        }
    }

    /** Ends an address on today's date, keeping an end date a person already gave it. */
    private static void endAddress(Address__c changes, Address__c ending) {
        if (ending.End_Date__c == null) {
            changes.End_Date__c = Date.today();
        }
        if (String.isBlank(ending.Status__c) || ending.Status__c == STATUS_CURRENT) {
            changes.Status__c = STATUS_FORMER;
        }
    }

    /**
     * Writes the standard address fields. Only ever called with the propagation flag
     * already raised, so nothing it writes comes back round as another capture.
     */
    private static void applyToStandardFields(List<Address__c> defaults) {
        Map<Id, Address__c> byOwner = new Map<Id, Address__c>();
        for (Address__c address : defaults) {
            Id ownerId = ownerIdOf(address);
            if (address.Is_Default__c == true && ownerId != null) {
                byOwner.put(ownerId, address);
            }
        }
        if (byOwner.isEmpty()) {
            return;
        }

        // Mutual exclusion (product-plan Section 11.2 item 9): an owner that is itself an
        // Account, household or person account alike, is left out here when it already
        // carries a native Nonprofit Cloud household group, so its billing or person
        // mailing fields are never overwritten and its address is never propagated to
        // household members from this default. A Contact owner cannot carry a native group,
        // so only Account and person-account owners are asked. One predicate query for the
        // whole batch.
        Set<Id> accountOwnerIds = new Set<Id>();
        for (Id ownerId : byOwner.keySet()) {
            Address__c owned = byOwner.get(ownerId);
            if (owned.Account__c != null || owned.Person_Account__c != null) {
                accountOwnerIds.add(ownerId);
            }
        }
        for (Id nativeHousehold : HouseholdSelector.nativeHouseholdAccountsAmong(accountOwnerIds)) {
            byOwner.remove(nativeHousehold);
        }
        if (byOwner.isEmpty()) {
            return;
        }

        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        Map<Id, Contact> contactUpdates = new Map<Id, Contact>();
        Map<Id, Address__c> addressByHousehold = new Map<Id, Address__c>();
        Map<Id, Address__c> addressByPersonOwner = new Map<Id, Address__c>();

        for (Id ownerId : byOwner.keySet()) {
            Address__c address = byOwner.get(ownerId);
            if (address.Account__c != null) {
                accountUpdates.put(ownerId, billingCopy(ownerId, address));
                addressByHousehold.put(ownerId, address);
            } else if (address.Contact__c != null) {
                contactUpdates.put(ownerId, mailingCopy(ownerId, address));
            } else if (address.Person_Account__c != null) {
                addressByPersonOwner.put(ownerId, address);
            }
        }

        // Every account this save might write person mailing fields on, asked about once,
        // before anything is built: an account that does not hold a person must be left
        // out rather than written and refused. See personAccountIdsAmong. In "Nobody moves
        // until you choose" a household's members are not asked about at all, unless this is
        // a move that was chosen (R-AD3).
        Map<Id, Set<Id>> membersByHousehold = membersMoveWithTheHousehold()
            ? membersWhoTakeTheHouseholdAddress(membersOf(addressByHousehold.keySet()))
            : new Map<Id, Set<Id>>();
        Set<Id> candidates = new Set<Id>(addressByPersonOwner.keySet());
        candidates.addAll(memberAccountIds(membersByHousehold));
        Set<Id> personAccountIds = personAccountIdsAmong(candidates);

        for (Id ownerId : addressByPersonOwner.keySet()) {
            if (!personAccountIds.contains(ownerId)) {
                continue;
            }
            Account personAccount = personMailingCopy(
                ownerId,
                addressByPersonOwner.get(ownerId),
                accountUpdates.get(ownerId)
            );
            if (personAccount != null) {
                accountUpdates.put(ownerId, personAccount);
            }
        }

        propagateToHouseholdMembers(
            addressByHousehold,
            membersByHousehold,
            personAccountIds,
            accountUpdates,
            contactUpdates
        );

        List<SObject> contactWrites = withChanges(contactUpdates.values());
        if (!contactWrites.isEmpty()) {
            Database.update(contactWrites, AccessLevel.USER_MODE);
        }
        List<SObject> accountWrites = withChanges(accountUpdates.values());
        if (!accountWrites.isEmpty()) {
            // As the user; a new household's Primary Contact rides along (D-143).
            HouseholdService.saveAccountCopiesAsUser(accountWrites);
        }
    }

    /**
     * The copies that would change something, in the order given. A person saved with an
     * address is the source of the household address captured from it, so copying that
     * address back writes exactly what the person already holds, and the same is true of an
     * account saved with a billing address. Such a write changed no value but cost a whole
     * second save of every record, with every Contact or Account automation running again.
     * A copy is kept when any field it names differs from the stored value (text compared
     * with its case), and when the record is not found.
     *
     * One query per object, and only when there is something to write. The stored values are
     * read in system mode (ADR-0021): they decide whether a write is sent and never reach a
     * screen, and the write itself stays in user mode.
     */
    @TestVisible
    private static List<SObject> withChanges(List<SObject> copies) {
        List<SObject> changed = new List<SObject>();
        if (copies == null || copies.isEmpty()) {
            return changed;
        }
        Set<String> fieldNames = new Set<String>();
        Set<Id> recordIds = new Set<Id>();
        for (SObject copy : copies) {
            recordIds.add(copy.Id);
            fieldNames.addAll(copy.getPopulatedFieldsAsMap().keySet());
        }
        Map<Id, SObject> stored = new Map<Id, SObject>(
            AddressSelector.selectStoredValues(copies[0].getSObjectType(), fieldNames, recordIds)
        );
        for (SObject copy : copies) {
            SObject current = stored.get(copy.Id);
            if (current == null || differsFrom(copy, current)) {
                changed.add(copy);
            }
        }
        return changed;
    }

    private static Boolean differsFrom(SObject copy, SObject current) {
        for (String field : copy.getPopulatedFieldsAsMap().keySet()) {
            Object wanted = copy.get(field);
            Object held = current.get(field);
            if (wanted == null || held == null) {
                if (wanted != held) {
                    return true;
                }
            } else if (wanted instanceof String && held instanceof String) {
                if (!((String) wanted).equals((String) held)) {
                    return true;
                }
            } else if (!wanted.equals(held)) {
                return true;
            }
        }
        return false;
    }

    /**
     * The people in each of these households, as HouseholdService reports them, so that
     * contact mode and the membership junction look the same from here.
     */
    private static Map<Id, Set<Id>> membersOf(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new Map<Id, Set<Id>>();
        }
        Map<Id, Set<Id>> members = membersByHouseholdOverride != null
            ? membersByHouseholdOverride
            : HouseholdService.getMemberPersonIds(householdIds);
        return members == null ? new Map<Id, Set<Id>>() : members;
    }

    /**
     * The members a household's default address is copied to (R-AD3). Left out, keeping the
     * address they have:
     *
     * - a person stored as a contact who has a default address of their own (R-AD1), such as
     *   the one "Only that person moves" gives them, so one person can live apart from their
     *   household with no field to say so, and the seasonal swap does not move them either;
     * - in junction mode, a person for whom this household is not their household (R-M3):
     *   belonging to a second household does not move them to its address.
     *
     * A member held as a person account is not asked about an address of its own: every
     * person account carries one, captured from its mailing fields (R-AD5), so the first rule
     * would stop every household move reaching people held as accounts.
     *
     * One query for the personal addresses, and in junction mode one for the households,
     * whatever the number of households. Returns new sets: the map given is not changed.
     * When `keptForTheirOwn` is given, each household's members left out only for an address
     * of their own are put in it, for the Update Everyone's Address confirmation (R-AD9).
     */
    private static Map<Id, Set<Id>> membersWhoTakeTheHouseholdAddress(
        Map<Id, Set<Id>> membersByHousehold
    ) {
        return membersWhoTakeTheHouseholdAddress(membersByHousehold, null);
    }

    private static Map<Id, Set<Id>> membersWhoTakeTheHouseholdAddress(
        Map<Id, Set<Id>> membersByHousehold,
        Map<Id, Set<Id>> keptForTheirOwn
    ) {
        Set<Id> personIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id householdId : membersByHousehold.keySet()) {
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (memberIds == null) {
                continue;
            }
            for (Id memberId : memberIds) {
                if (memberId == null || memberId == householdId) {
                    continue;
                }
                personIds.add(memberId);
                if (memberId.getSObjectType() == contactType) {
                    contactIds.add(memberId);
                }
            }
        }
        if (personIds.isEmpty()) {
            return membersByHousehold;
        }
        Set<Id> withAnAddressOfTheirOwn = new Set<Id>();
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(contactIds, null)) {
            if (address.Contact__c != null) {
                withAnAddressOfTheirOwn.add(address.Contact__c);
            }
        }
        Map<Id, Id> ownHouseholdByPerson = HouseholdService.isJunctionMode()
            ? HouseholdService.getHouseholdIdsFor(personIds)
            : new Map<Id, Id>();
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        for (Id householdId : membersByHousehold.keySet()) {
            Set<Id> taking = new Set<Id>();
            Set<Id> keptBack = new Set<Id>();
            Set<Id> memberIds = membersByHousehold.get(householdId);
            for (Id memberId : memberIds == null ? new Set<Id>() : memberIds) {
                Id ownHousehold = ownHouseholdByPerson.get(memberId);
                Boolean livesElsewhere = ownHousehold != null && ownHousehold != householdId;
                if (livesElsewhere || memberId == null || memberId == householdId) {
                    continue;
                }
                if (withAnAddressOfTheirOwn.contains(memberId)) {
                    keptBack.add(memberId);
                } else {
                    taking.add(memberId);
                }
            }
            result.put(householdId, taking);
            if (keptForTheirOwn != null) {
                keptForTheirOwn.put(householdId, keptBack);
            }
        }
        return result;
    }

    /** The members that are account records rather than contacts, households excluded. */
    private static Set<Id> memberAccountIds(Map<Id, Set<Id>> membersByHousehold) {
        Set<Id> accountIds = new Set<Id>();
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id householdId : membersByHousehold.keySet()) {
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (memberIds == null) {
                continue;
            }
            for (Id memberId : memberIds) {
                if (
                    memberId != null &&
                    memberId != householdId &&
                    memberId.getSObjectType() != contactType
                ) {
                    accountIds.add(memberId);
                }
            }
        }
        return accountIds;
    }

    /**
     * Which of these accounts actually hold a person.
     *
     * In an org that stores people as accounts, the person mailing fields exist on every
     * account record, so asking the object whether it has them says only what the org is
     * shaped like. Only an account whose record type is a person type will accept a value
     * in them: writing one on a household or an organization fails the whole save, and the
     * address the user was trying to save is refused with it. So the question that decides
     * the write is asked of the record, not of the org, and it is asked the same way
     * captureAccounts already asks it, through the record types OrgShapeDetector found.
     *
     * The record types are read in system mode (ADR-0021): a household member the saving
     * user cannot see would otherwise come back as nothing at all, read as an organization,
     * and be skipped, so the address would silently reach some of a household and not the
     * rest. The answer decides which fields a write may name and never reaches a screen.
     */
    /**
     * Moves an address that names a person account through `Account__c` over to
     * `Person_Account__c`, before insert. Does nothing, and runs no query, in an org with
     * no person accounts.
     */
    public static void ownPersonAccountsAsPeople(List<Address__c> addresses) {
        Set<Id> accountIds = new Set<Id>();
        for (Address__c address : addresses) {
            if (address.Account__c != null && address.Person_Account__c == null) {
                accountIds.add(address.Account__c);
            }
        }
        Set<Id> people = personAccountIdsAmong(accountIds);
        if (people.isEmpty()) {
            return;
        }
        for (Address__c address : addresses) {
            if (address.Person_Account__c == null && people.contains(address.Account__c)) {
                address.Person_Account__c = address.Account__c;
                address.Account__c = null;
            }
        }
    }

    private static Set<Id> personAccountIdsAmong(Set<Id> accountIds) {
        Set<Id> found = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty() || !personAccountFieldsAvailable()) {
            return found;
        }
        Set<Id> personRecordTypeIds = OrgShapeDetector.personAccountRecordTypeIds();
        if (personRecordTypeIds == null || personRecordTypeIds.isEmpty()) {
            return found;
        }
        for (Account account : HouseholdSelector.getAccountRecordTypes(accountIds)) {
            if (personRecordTypeIds.contains(account.RecordTypeId)) {
                found.add(account.Id);
            }
        }
        return found;
    }

    private static void propagateToHouseholdMembers(
        Map<Id, Address__c> addressByHousehold,
        Map<Id, Set<Id>> membersByHousehold,
        Set<Id> personAccountIds,
        Map<Id, Account> accountUpdates,
        Map<Id, Contact> contactUpdates
    ) {
        if (addressByHousehold.isEmpty() || membersByHousehold.isEmpty()) {
            return;
        }
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id householdId : membersByHousehold.keySet()) {
            Address__c address = addressByHousehold.get(householdId);
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (address == null || memberIds == null) {
                continue;
            }
            for (Id memberId : memberIds) {
                if (memberId == null || memberId == householdId) {
                    continue;
                }
                if (memberId.getSObjectType() == contactType) {
                    contactUpdates.put(memberId, mailingCopy(memberId, address));
                } else if (personAccountIds.contains(memberId)) {
                    Account personAccount = personMailingCopy(
                        memberId,
                        address,
                        accountUpdates.get(memberId)
                    );
                    if (personAccount != null) {
                        accountUpdates.put(memberId, personAccount);
                    }
                }
            }
        }
    }

    private static Account billingCopy(Id accountId, Address__c address) {
        Account record = new Account(
            Id = accountId,
            BillingStreet = address.Street__c,
            BillingCity = address.City__c,
            BillingPostalCode = address.Postal_Code__c
        );
        putStateAndCountry(record, 'BillingState', 'BillingCountry', address);
        return record;
    }

    private static Contact mailingCopy(Id contactId, Address__c address) {
        Contact record = new Contact(
            Id = contactId,
            MailingStreet = address.Street__c,
            MailingCity = address.City__c,
            MailingPostalCode = address.Postal_Code__c
        );
        putStateAndCountry(record, 'MailingState', 'MailingCountry', address);
        return record;
    }

    /**
     * Writes an address's state and country onto a standard address. In an org with State and
     * Country Picklists the text fields take only a full name ("Illinois", "United States"), so
     * a code such as "IL" or "US", which is how most people type an address, goes to the code
     * field (`BillingStateCode`) instead: written as text the platform refuses the whole save.
     * A state code is used only once the country is known, since state codes repeat between
     * countries. Anything else is written as text, as in an org without the picklists.
     *
     * @param record the account or contact being written
     * @param stateField the text state field, such as `BillingState`
     * @param countryField the text country field, such as `BillingCountry`
     * @param address the address being copied
     */
    private static void putStateAndCountry(
        SObject record,
        String stateField,
        String countryField,
        Address__c address
    ) {
        String state = address.State__c;
        String country = address.Country__c;
        if (!usesStateAndCountryPicklists()) {
            record.put(stateField, state);
            record.put(countryField, country);
            return;
        }
        String countryCode = String.isBlank(country)
            ? null
            : countryCodeByText.get(country.trim().toUpperCase());
        if (countryCode == null) {
            record.put(countryField, country);
        } else {
            record.put(countryField + 'Code', countryCode);
        }
        String stateCode = String.isBlank(state) ? null : state.trim().toUpperCase();
        if (countryCode != null && stateCodes.contains(stateCode)) {
            record.put(stateField + 'Code', stateCode);
        } else {
            record.put(stateField, state);
        }
    }

    /** Country codes by code and by name, upper case; null until the picklists are read. */
    private static Map<String, String> countryCodeByText;
    /** Every state code the org knows, upper case. */
    private static Set<String> stateCodes;

    /**
     * Whether the org has State and Country Picklists turned on, read once per transaction from
     * the contact's mailing address, which carries the code fields only when they are on.
     */
    @TestVisible
    private static Boolean usesStateAndCountryPicklists() {
        if (countryCodeByText != null) {
            return !countryCodeByText.isEmpty();
        }
        countryCodeByText = new Map<String, String>();
        stateCodes = new Set<String>();
        Map<String, Schema.SObjectField> contactFields = Contact.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .fields
            .getMap();
        Schema.SObjectField countryCode = contactFields.get('mailingcountrycode');
        Schema.SObjectField stateCode = contactFields.get('mailingstatecode');
        if (countryCode == null || stateCode == null) {
            return false;
        }
        for (Schema.PicklistEntry entry : countryCode.getDescribe().getPicklistValues()) {
            countryCodeByText.put(entry.getValue().toUpperCase(), entry.getValue());
            countryCodeByText.put(entry.getLabel().toUpperCase(), entry.getValue());
        }
        for (Schema.PicklistEntry entry : stateCode.getDescribe().getPicklistValues()) {
            stateCodes.add(entry.getValue().toUpperCase());
        }
        return !countryCodeByText.isEmpty();
    }

    /**
     * Writes the mailing fields a person account carries. The field names are held as
     * strings and written with put, so this class compiles and runs in an org where those
     * fields do not exist.
     */
    private static Account personMailingCopy(Id accountId, Address__c address, Account existing) {
        if (!personAccountFieldsAvailable()) {
            return null;
        }
        Account record = existing == null ? new Account(Id = accountId) : existing;
        record.put(PERSON_MAILING_STREET, address.Street__c);
        record.put(PERSON_MAILING_CITY, address.City__c);
        record.put(PERSON_MAILING_POSTAL_CODE, address.Postal_Code__c);
        putStateAndCountry(record, PERSON_MAILING_STATE, PERSON_MAILING_COUNTRY, address);
        return record;
    }

    private static Boolean personAccountFieldsAvailable() {
        if (!OrgShapeDetector.hasPersonAccounts()) {
            return false;
        }
        if (accountFields == null) {
            accountFields = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields
                .getMap();
        }
        return accountFields.containsKey(PERSON_MAILING_STREET.toLowerCase());
    }

    private static void captureAccounts(List<Account> accounts, List<Address__c> toInsert) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        List<Account> people = new List<Account>();
        toInsert.addAll(billingAddressesOf(accounts, people));
        capturePersonAccounts(people, toInsert);
    }

    /**
     * The billing address of each household or organization among these accounts, as a
     * default address record of type Home (Work for an organization, an account of the record
     * type `AccountKinds` names), not yet saved. An account with an empty billing address, or
     * of any other record type, gives none. The
     * people held as accounts are added to `people` instead, for the person capture.
     */
    private static List<Address__c> billingAddressesOf(
        List<Account> accounts,
        List<Account> people
    ) {
        List<Address__c> typed = new List<Address__c>();
        Map<Id, Schema.RecordTypeInfo> recordTypes = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosById();
        Set<Id> personRecordTypeIds = OrgShapeDetector.personRecordTypeIds();
        for (Account account : accounts) {
            if (personRecordTypeIds.contains(account.RecordTypeId)) {
                people.add(account);
                continue;
            }
            String developerName = account.RecordTypeId == null ||
                recordTypes.get(account.RecordTypeId) == null
                ? null
                : recordTypes.get(account.RecordTypeId).getDeveloperName();
            // Organizations are the accounts of the record type the org chose (ADR-0141).
            Boolean isOrganization =
                developerName != RECORD_TYPE_HOUSEHOLD &&
                AccountKinds.isOrganizationRecordTypeName(developerName);
            if (developerName != RECORD_TYPE_HOUSEHOLD && !isOrganization) {
                continue;
            }
            if (
                !hasAnyValue(
                    account.BillingStreet,
                    account.BillingCity,
                    account.BillingState,
                    account.BillingPostalCode,
                    account.BillingCountry
                )
            ) {
                continue;
            }
            typed.add(
                new Address__c(
                    Account__c = account.Id,
                    Type__c = isOrganization ? TYPE_WORK : TYPE_HOME,
                    Is_Default__c = true,
                    Street__c = account.BillingStreet,
                    City__c = account.BillingCity,
                    State__c = account.BillingState,
                    Postal_Code__c = account.BillingPostalCode,
                    Country__c = account.BillingCountry
                )
            );
        }
        return typed;
    }

    /**
     * People held as accounts keep their mailing address as an address record of their own
     * (type Home, default). The person fields are read by name with get, never referenced, so
     * this compiles in an org with no person accounts, where it returns at once.
     */
    private static void capturePersonAccounts(List<Account> people, List<Address__c> toInsert) {
        if (people == null || people.isEmpty() || !personAccountFieldsAvailable()) {
            return;
        }
        List<Account> withAddress = new List<Account>();
        for (Account person : people) {
            if (
                hasAnyValue(
                    (String) person.get(PERSON_MAILING_STREET),
                    (String) person.get(PERSON_MAILING_CITY),
                    (String) person.get(PERSON_MAILING_STATE),
                    (String) person.get(PERSON_MAILING_POSTAL_CODE),
                    (String) person.get(PERSON_MAILING_COUNTRY)
                )
            ) {
                withAddress.add(person);
            }
        }
        if (withAddress.isEmpty()) {
            return;
        }
        Map<Id, Address__c> defaultByPerson = new Map<Id, Address__c>();
        for (
            Address__c address : AddressSelector.selectDefaultsByOwnerIds(
                new Map<Id, Account>(withAddress).keySet(),
                null
            )
        ) {
            if (address.Person_Account__c != null) {
                defaultByPerson.put(address.Person_Account__c, address);
            }
        }
        for (Account person : withAddress) {
            Address__c existing = defaultByPerson.get(person.Id);
            Address__c typed = new Address__c(
                Person_Account__c = person.Id,
                Type__c = TYPE_HOME,
                Is_Default__c = true,
                Street__c = (String) person.get(PERSON_MAILING_STREET),
                City__c = (String) person.get(PERSON_MAILING_CITY),
                State__c = (String) person.get(PERSON_MAILING_STATE),
                Postal_Code__c = (String) person.get(PERSON_MAILING_POSTAL_CODE),
                Country__c = (String) person.get(PERSON_MAILING_COUNTRY)
            );
            if (!sameAddress(existing, typed)) {
                toInsert.add(typed);
            }
        }
    }

    private static Set<Id> personRecordTypeIds() {
        if (!personAccountFieldsAvailable()) {
            return new Set<Id>();
        }
        Set<Id> found = OrgShapeDetector.detect().personAccountRecordTypeIds;
        return found == null ? new Set<Id>() : found;
    }

    private static Boolean personMailingChanged(Account person, SObject before) {
        for (
            String field : new List<String>{
                PERSON_MAILING_STREET,
                PERSON_MAILING_CITY,
                PERSON_MAILING_STATE,
                PERSON_MAILING_POSTAL_CODE,
                PERSON_MAILING_COUNTRY
            }
        ) {
            if (!sameText((String) person.get(field), (String) before.get(field))) {
                return true;
            }
        }
        return false;
    }

    private static void captureContacts(List<Contact> contacts, List<Address__c> toInsert) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        List<Contact> withAddress = new List<Contact>();
        for (Contact contact : contacts) {
            if (
                hasAnyValue(
                    contact.MailingStreet,
                    contact.MailingCity,
                    contact.MailingState,
                    contact.MailingPostalCode,
                    contact.MailingCountry
                )
            ) {
                withAddress.add(contact);
            }
        }
        if (withAddress.isEmpty()) {
            return;
        }
        // Only "Everyone in the household moves together" moves the household; the other two
        // choices keep a person's edit as their own address (R-AD5).
        if (behavior() == BEHAVIOR_UPDATE_HOUSEHOLD) {
            captureHouseholdAddresses(withAddress, toInsert);
        } else {
            capturePersonalAddresses(withAddress, toInsert);
        }
    }

    private static void captureHouseholdAddresses(
        List<Contact> contacts,
        List<Address__c> toInsert
    ) {
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(contactIds);
        if (householdByPerson == null) {
            householdByPerson = new Map<Id, Id>();
        }
        Map<Id, Contact> sourceByHousehold = new Map<Id, Contact>();
        List<Contact> withoutAHousehold = new List<Contact>();
        for (Contact contact : contacts) {
            Id householdId = householdByPerson.get(contact.Id);
            if (householdId == null) {
                withoutAHousehold.add(contact);
                continue;
            }
            sourceByHousehold.put(householdId, contact);
        }
        // A person with no household to move still keeps the address they were given, as
        // their own (PEOPLE-24, R-AD5).
        if (!withoutAHousehold.isEmpty()) {
            capturePersonalAddresses(withoutAHousehold, toInsert);
        }
        if (sourceByHousehold.isEmpty()) {
            return;
        }
        Map<Id, Address__c> defaultByHousehold = new Map<Id, Address__c>();
        for (
            Address__c address : AddressSelector.selectDefaultsByOwnerIds(
                sourceByHousehold.keySet(),
                null
            )
        ) {
            if (address.Account__c != null) {
                defaultByHousehold.put(address.Account__c, address);
            }
        }
        for (Id householdId : sourceByHousehold.keySet()) {
            Contact source = sourceByHousehold.get(householdId);
            if (!sameAddress(defaultByHousehold.get(householdId), source)) {
                toInsert.add(newAddressFromContact(source, TYPE_HOME, householdId, null));
            }
        }
    }

    private static void capturePersonalAddresses(
        List<Contact> contacts,
        List<Address__c> toInsert
    ) {
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        Map<Id, Address__c> defaultByContact = new Map<Id, Address__c>();
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(contactIds, null)) {
            if (address.Contact__c != null) {
                defaultByContact.put(address.Contact__c, address);
            }
        }
        for (Contact contact : contacts) {
            if (!sameAddress(defaultByContact.get(contact.Id), contact)) {
                toInsert.add(newAddressFromContact(contact, TYPE_HOME, null, contact.Id));
            }
        }
    }

    /**
     * Whether the owner's default already holds exactly what the person typed, so that a
     * second household member saved with the shared address, or a save that rewrites the
     * same address, does not add a duplicate record.
     */
    private static Boolean sameAddress(Address__c existing, Contact source) {
        return existing != null &&
            sameText(existing.Street__c, source.MailingStreet) &&
            sameText(existing.City__c, source.MailingCity) &&
            sameText(existing.State__c, source.MailingState) &&
            sameText(existing.Postal_Code__c, source.MailingPostalCode) &&
            sameText(existing.Country__c, source.MailingCountry);
    }

    /** The same test against an address record built from a person account's mailing fields. */
    private static Boolean sameAddress(Address__c existing, Address__c typed) {
        return existing != null &&
            sameText(existing.Street__c, typed.Street__c) &&
            sameText(existing.City__c, typed.City__c) &&
            sameText(existing.State__c, typed.State__c) &&
            sameText(existing.Postal_Code__c, typed.Postal_Code__c) &&
            sameText(existing.Country__c, typed.Country__c);
    }

    private static Boolean sameText(String left, String right) {
        String a = left == null ? '' : left;
        String b = right == null ? '' : right;
        return a.equals(b);
    }

    private static Address__c newAddressFromContact(
        Contact source,
        String addressType,
        Id accountId,
        Id contactId
    ) {
        Address__c address = new Address__c(
            Account__c = accountId,
            Contact__c = contactId,
            Type__c = addressType,
            Is_Default__c = true
        );
        return copyContactAddressOnto(address, source);
    }

    private static Address__c copyContactAddressOnto(Address__c address, Contact source) {
        address.Street__c = source.MailingStreet;
        address.City__c = source.MailingCity;
        address.State__c = source.MailingState;
        address.Postal_Code__c = source.MailingPostalCode;
        address.Country__c = source.MailingCountry;
        address.Is_Default__c = true;
        return address;
    }

    /**
     * The org's Address Updates choice (R-AD5). A blank, or anything the console never
     * offers, reads as the shipped choice, "Everyone in the household moves together".
     */
    private static String behavior() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        String value = settings == null ? null : settings.Contact_Address_Change_Behavior__c;
        if (value == BEHAVIOR_MANUAL) {
            return BEHAVIOR_MANUAL;
        }
        return value == BEHAVIOR_PERSONAL_ADDRESS
            ? BEHAVIOR_PERSONAL_ADDRESS
            : BEHAVIOR_UPDATE_HOUSEHOLD;
    }

    /**
     * Marks what is saved next as a household move that was chosen, or puts the mark back,
     * and answers with what it was, so a caller can restore it in a finally block. The
     * seasonal swap raises it: in "Nobody moves until you choose" a household's new primary
     * address reaches its members only on a move that was chosen (R-AD3, ADR-0140).
     */
    public static Boolean chooseHouseholdMoves(Boolean chosen) {
        Boolean previous = householdMoveChosen;
        householdMoveChosen = chosen == true;
        return previous;
    }

    /** Whether a household's new primary address reaches its members in this save (R-AD3). */
    private static Boolean membersMoveWithTheHousehold() {
        return householdMoveChosen || behavior() != BEHAVIOR_MANUAL;
    }

    private static Boolean hasAnyValue(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        return String.isNotBlank(street) ||
            String.isNotBlank(city) ||
            String.isNotBlank(state) ||
            String.isNotBlank(postalCode) ||
            String.isNotBlank(country);
    }
}
