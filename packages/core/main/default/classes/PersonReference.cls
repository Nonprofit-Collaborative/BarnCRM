/**
 * The pair of lookups that names a person, and the four questions the packaged code asks of
 * it (canonical model Section 4, "Person references").
 *
 * Every attribute in the model that points at a person carries two lookups, a Contact and an
 * Account, and exactly one of them is set: the Contact where the org holds people as
 * contacts, the Account where it holds them as person accounts. Relationships and
 * affiliations both need to compare two people, tell a complete reference from an incomplete
 * one, and turn a reference into something they can use as a map key. Doing that in one place
 * is what keeps a relationship between two people held as accounts from being a second code
 * path (plan Section 4.2, ADR-0009).
 *
 * Nothing here names a Person Account field or asks whether an account holds a person. It
 * does not need to: the id is an id whichever kind of record it points at, and the code that
 * has to know reads it through HouseholdService and PersonRecordSelector.
 */
@NamespaceAccessible
public with sharing class PersonReference {
    /**
     * The id of whichever half of the pair is set, or null when neither is.
     */
    @NamespaceAccessible
    public static Id idOf(Id contactId, Id accountId) {
        if (contactId != null) {
            return contactId;
        }
        return accountId;
    }

    /**
     * A reference is well formed when exactly one of the two lookups is set. Both set is as
     * wrong as neither: it would say the same person is stored two ways at once, and every
     * comparison after that would be guesswork.
     */
    @NamespaceAccessible
    public static Boolean isComplete(Id contactId, Id accountId) {
        return (contactId == null) != (accountId == null);
    }

    @NamespaceAccessible
    public static Boolean isEmpty(Id contactId, Id accountId) {
        return contactId == null && accountId == null;
    }

    @NamespaceAccessible
    public static Boolean isAmbiguous(Id contactId, Id accountId) {
        return contactId != null && accountId != null;
    }

    /**
     * A stable key for one person, safe to use in a map and safe to compare across the two
     * ways a person can be held. Two references produce the same key only when they are the
     * same record, so a contact and an account never collide.
     */
    @NamespaceAccessible
    public static String keyOf(Id contactId, Id accountId) {
        Id personId = idOf(contactId, accountId);
        if (personId == null) {
            return null;
        }
        return (contactId != null ? 'c:' : 'a:') + String.valueOf(personId);
    }

    /** True when both references name the same person, whichever object holds them. */
    @NamespaceAccessible
    public static Boolean isSamePerson(
        Id firstContactId,
        Id firstAccountId,
        Id secondContactId,
        Id secondAccountId
    ) {
        String first = keyOf(firstContactId, firstAccountId);
        String second = keyOf(secondContactId, secondAccountId);
        return first != null && first == second;
    }

    /**
     * The name to show for a person held as a contact or as a person account, whichever
     * record is present with a name, or the given fallback (the caller's "unnamed" label).
     */
    @NamespaceAccessible
    public static String nameOf(Contact asContact, Account asAccount, String fallback) {
        if (asContact != null && String.isNotBlank(asContact.Name)) {
            return asContact.Name;
        }
        if (asAccount != null && String.isNotBlank(asAccount.Name)) {
            return asAccount.Name;
        }
        return fallback;
    }
}
