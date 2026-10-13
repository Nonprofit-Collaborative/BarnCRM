/**
 * Affiliations (C-16, canonical model Section 28).
 *
 * One rule carries the feature: at most one current affiliation per person is the primary
 * one, and the organization it names is copied to that person's Primary Affiliation field so
 * that a list view or a mail merge can show an employer without a subquery (R-AF2).
 *
 * It is done by recomputing rather than by patching. Whatever changed, this class works out
 * from the affiliations a person actually has which one should be primary, clears the flag
 * from the others, and writes the person's field only when what it holds is wrong. That is
 * the same amount of work for one save and for two hundred, and it is correct after an
 * insert, an edit, a delete, and an undelete without four separate pieces of reasoning.
 *
 * Two bypasses, both cleared in a finally block:
 *
 * 1. This automation and the validation automation that runs before it, while it clears the
 *    flag from a person's other affiliations, because those writes would otherwise re-enter
 *    this same handler and would put a second set of checks over records the package itself
 *    wrote. The two are separate registry rows so an administrator can switch this maintenance
 *    off and keep the checks; the package's own writes are exempt from both.
 * 2. The contact and account handlers, while it writes the person's Primary Affiliation
 *    field. R-AF3 is explicit that an affiliation never changes a person's household or their
 *    address, and standing those handlers down is how that is guaranteed rather than hoped
 *    for. The household merge service stands the same two down for the same kind of reason.
 *
 * Nothing here asks whether a person is held as a contact or as an account. The affiliation
 * carries both lookups with exactly one set (canonical model Section 4), and the field being
 * written exists on both objects, so the only difference between the two shapes is which of
 * two lists the update goes into.
 *
 * The upkeep reads and writes run in system mode through `AffiliationUpkeepSelector` and
 * `AffiliationUpkeepWriter` (ADR-0021, category 2): the affiliation the user saved has already
 * been authorized in user mode, and the corrections that follow from it must not fail, or miss
 * rows, because the user cannot edit or see the person and their other affiliations.
 */
public with sharing class AffiliationService {
    /** The maintenance registry row this feature ships, and the name its bypass is keyed on. */
    public static final String AUTOMATION_NAME = 'Affiliation_Primary';

    /** The validation registry row, stood down alongside the maintenance one while this writes. */
    public static final String VALIDATION_AUTOMATION_NAME = 'Affiliation_Validation';

    private static final String CONTACT_HANDLER = 'ContactTriggerHandler';
    private static final String ACCOUNT_HANDLER = 'AccountTriggerHandler';
    private static final String CONTACT_ADDRESS_HANDLER = 'Contact_Address_Capture';
    private static final String ACCOUNT_ADDRESS_HANDLER = 'Account_Address_Capture';

    /**
     * Settles the primary affiliation of every person any of these records touches. The old
     * copies are passed in as well so that a person who has just lost an affiliation, or has
     * just had one moved to somebody else, is settled too.
     */
    public static void refreshPrimaries(
        List<Affiliation__c> records,
        List<Affiliation__c> previous
    ) {
        Set<Id> personIds = new Set<Id>();
        Set<Id> justSaved = new Set<Id>();
        collectPeople(records, personIds, justSaved);
        collectPeople(previous, personIds, null);
        if (personIds.isEmpty()) {
            return;
        }
        recompute(personIds, justSaved);
    }

    /**
     * Settles the primary affiliation of these people from scratch: the newest current one
     * marked primary keeps the flag. For the survivor of a merge, who can arrive with the
     * other record's primary affiliation as well as their own (PEOPLE-15).
     */
    public static void refreshPrimariesFor(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty()) {
            return;
        }
        recompute(personIds, new Set<Id>());
    }

    private static void collectPeople(
        List<Affiliation__c> records,
        Set<Id> personIds,
        Set<Id> justSaved
    ) {
        if (records == null) {
            return;
        }
        for (Affiliation__c record : records) {
            Id personId = PersonReference.idOf(record.Contact__c, record.Person_Account__c);
            if (personId != null) {
                personIds.add(personId);
            }
            if (justSaved != null && record.Id != null) {
                justSaved.add(record.Id);
            }
        }
    }

    /**
     * The whole rule, for a set of people at once: choose the primary, clear the flag from
     * everything else, and make the person's field agree.
     */
    private static void recompute(Set<Id> personIds, Set<Id> justSaved) {
        Map<Id, List<Affiliation__c>> byPerson = new Map<Id, List<Affiliation__c>>();
        for (Affiliation__c affiliation : AffiliationUpkeepSelector.selectForPrimary(personIds)) {
            Id personId = PersonReference.idOf(
                affiliation.Contact__c,
                affiliation.Person_Account__c
            );
            if (personId == null) {
                continue;
            }
            if (!byPerson.containsKey(personId)) {
                byPerson.put(personId, new List<Affiliation__c>());
            }
            byPerson.get(personId).add(affiliation);
        }

        List<Affiliation__c> flagsToClear = new List<Affiliation__c>();
        Map<Id, Id> wantedByPerson = new Map<Id, Id>();
        for (Id personId : personIds) {
            List<Affiliation__c> affiliations = byPerson.get(personId);
            Affiliation__c chosen = choosePrimary(affiliations, justSaved);
            wantedByPerson.put(personId, chosen == null ? null : chosen.Organization__c);
            if (affiliations == null) {
                continue;
            }
            for (Affiliation__c affiliation : affiliations) {
                Boolean shouldBePrimary = chosen != null && affiliation.Id == chosen.Id;
                if (affiliation.Is_Primary__c == true && !shouldBePrimary) {
                    flagsToClear.add(
                        new Affiliation__c(Id = affiliation.Id, Is_Primary__c = false)
                    );
                }
            }
        }

        clearFlags(flagsToClear);
        writePrimaryAffiliation(wantedByPerson);
    }

    /**
     * The one affiliation that should carry the primary flag for a person, or null when none
     * should.
     *
     * A former affiliation is never eligible (R-AF4). Among the current ones that are flagged,
     * the one the person just saved wins, because that is the choice they have just made; with
     * nothing in this save to go on, the newest wins. Nothing is promoted on its own: a person
     * with no flagged affiliation has no primary organization, which is the honest answer.
     */
    private static Affiliation__c choosePrimary(
        List<Affiliation__c> affiliations,
        Set<Id> justSaved
    ) {
        if (affiliations == null || affiliations.isEmpty()) {
            return null;
        }
        Affiliation__c fromThisSave;
        Affiliation__c newest;
        for (Affiliation__c affiliation : affiliations) {
            if (
                affiliation.Is_Primary__c != true ||
                affiliation.Status__c == ConnectionStatus.FORMER
            ) {
                continue;
            }
            if (justSaved != null && justSaved.contains(affiliation.Id)) {
                if (fromThisSave == null || affiliation.CreatedDate > fromThisSave.CreatedDate) {
                    fromThisSave = affiliation;
                }
            }
            if (newest == null || affiliation.CreatedDate > newest.CreatedDate) {
                newest = affiliation;
            }
        }
        return fromThisSave != null ? fromThisSave : newest;
    }

    /** Takes the flag off the affiliations that lost it, without re-entering this handler. */
    private static void clearFlags(List<Affiliation__c> flagsToClear) {
        if (flagsToClear.isEmpty()) {
            return;
        }
        AutomationControl.bypass(AUTOMATION_NAME);
        AutomationControl.bypass(VALIDATION_AUTOMATION_NAME);
        try {
            AffiliationUpkeepWriter.clearPrimaryFlags(flagsToClear);
        } finally {
            AutomationControl.clearBypass(AUTOMATION_NAME);
            AutomationControl.clearBypass(VALIDATION_AUTOMATION_NAME);
        }
    }

    /**
     * Makes each person's Primary Affiliation field name the organization they are chiefly
     * associated with, and writes nothing where it already does.
     */
    private static void writePrimaryAffiliation(Map<Id, Id> wantedByPerson) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id personId : wantedByPerson.keySet()) {
            if (personId.getSobjectType() == contactType) {
                contactIds.add(personId);
            } else {
                accountIds.add(personId);
            }
        }

        List<Contact> contactUpdates = new List<Contact>();
        for (Contact person : AffiliationUpkeepSelector.selectContactPrimaries(contactIds)) {
            Id wanted = wantedByPerson.get(person.Id);
            if (person.Primary_Affiliation__c != wanted) {
                contactUpdates.add(new Contact(Id = person.Id, Primary_Affiliation__c = wanted));
            }
        }
        List<Account> accountUpdates = new List<Account>();
        for (Account person : AffiliationUpkeepSelector.selectAccountPrimaries(accountIds)) {
            Id wanted = wantedByPerson.get(person.Id);
            if (person.Primary_Affiliation__c != wanted) {
                accountUpdates.add(new Account(Id = person.Id, Primary_Affiliation__c = wanted));
            }
        }
        if (contactUpdates.isEmpty() && accountUpdates.isEmpty()) {
            return;
        }
        // R-AF3: an affiliation never moves a person's household and never touches their
        // address, so the handlers that would do either are stood down for this write.
        AutomationControl.bypass(CONTACT_HANDLER);
        AutomationControl.bypass(ACCOUNT_HANDLER);
        AutomationControl.bypass(CONTACT_ADDRESS_HANDLER);
        AutomationControl.bypass(ACCOUNT_ADDRESS_HANDLER);
        try {
            AffiliationUpkeepWriter.savePrimaries(contactUpdates);
            AffiliationUpkeepWriter.savePrimaries(accountUpdates);
        } finally {
            AutomationControl.clearBypass(CONTACT_HANDLER);
            AutomationControl.clearBypass(ACCOUNT_HANDLER);
            AutomationControl.clearBypass(CONTACT_ADDRESS_HANDLER);
            AutomationControl.clearBypass(ACCOUNT_ADDRESS_HANDLER);
        }
    }
}
