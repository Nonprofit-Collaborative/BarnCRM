/**
 * What erasing a person does to Giving's records (canonical model R-ER8; ADR-0110
 * `0110-erase-a-person-anonymizes-in-place.md`, "Giving's defaults"). Core finds this class by
 * name in `PersonErasureExtensions.EXTENSION_CLASSES` and calls it inside the erasure's own
 * transaction, so a refusal here takes the whole erasure back.
 *
 * Gifts, soft credits, commitments and receipts are kept as they are, still credited to the
 * anonymized person, so every total stands and the books and tax records are untouched (posted
 * and receipted gifts are locked anyway, ADR-0024, ADR-0053). The one exception is the person's
 * automatic Household Member credits: they exist only because the person belonged to a
 * household (R-SC3), and the erasure has just taken them out of every household, so they are
 * deleted here, as the user, and listed as Deleted rather than left to the queued recompute.
 * What Giving holds as typed text about the person is emptied: tribute names typed for them, the message on a tribute of their
 * own gift, and the email address the acknowledgment ledger sent to. Running stewardship plans
 * for them are cancelled, so no more tasks are made about them, and their asks lose their Next
 * Step and are withdrawn if open (R-SO8). The donor level fields are kept,
 * like the totals.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class GivingPersonErasureExtension implements PersonErasureExtension {
    @NamespaceAccessible
    public GivingPersonErasureExtension() {
        return;
    }

    public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
        if (personType == Account.SObjectType) {
            return new Set<Schema.SObjectField>{
                Account.Donor_Level__c,
                Account.Previous_Donor_Level__c,
                Account.Donor_Level_Changed_Date__c
            };
        }
        return new Set<Schema.SObjectField>{
            Contact.Donor_Level__c,
            Contact.Previous_Donor_Level__c,
            Contact.Donor_Level_Changed_Date__c
        };
    }

    public List<PersonErasure.Change> erase(Id personId) {
        Boolean isContact = personId.getSObjectType() == Contact.SObjectType;
        Set<Id> people = new Set<Id>{ personId };
        Set<Id> contacts = isContact ? people : new Set<Id>();
        Set<Id> accounts = isContact ? new Set<Id>() : people;
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();

        // Kept, and counted so the preview says so.
        kept(
            changes,
            Gift__c.SObjectType,
            [
                SELECT COUNT()
                FROM Gift__c
                WHERE Donor_Contact__c IN :contacts OR Donor_Account__c IN :accounts
                WITH SYSTEM_MODE
            ],
            Label.Giving_Erase_GiftsKept
        );
        changes.addAll(deleteHouseholdCredits(contacts, accounts));
        kept(
            changes,
            Soft_Credit__c.SObjectType,
            [
                SELECT COUNT()
                FROM Soft_Credit__c
                WHERE Contact__c IN :contacts OR Account__c IN :accounts
                WITH SYSTEM_MODE
            ],
            Label.Giving_Erase_GiftsKept
        );
        kept(
            changes,
            Commitment__c.SObjectType,
            [
                SELECT COUNT()
                FROM Commitment__c
                WHERE Donor_Contact__c IN :contacts OR Donor_Account__c IN :accounts
                WITH SYSTEM_MODE
            ],
            Label.Giving_Erase_GiftsKept
        );
        kept(
            changes,
            Receipt__c.SObjectType,
            [
                SELECT COUNT()
                FROM Receipt__c
                WHERE Donor_Contact__c IN :contacts OR Donor_Account__c IN :accounts
                WITH SYSTEM_MODE
            ],
            Label.Giving_Erase_ReceiptsKept
        );

        changes.addAll(eraseTributes(contacts, accounts));
        changes.addAll(eraseAcknowledgments(contacts, accounts));
        changes.addAll(cancelStewardship(contacts, accounts));
        changes.addAll(endAsks(contacts, accounts));
        return changes;
    }

    /**
     * The person's asks, as the user (R-SO8): Next Step, the one free text an ask holds about the
     * donor, is emptied on all of them, and open ones are withdrawn so no more work is planned.
     * The asks are kept, like the gifts, still pointing at the anonymized person.
     */
    private static List<PersonErasure.Change> endAsks(Set<Id> contacts, Set<Id> accounts) {
        List<Ask__c> updates = new List<Ask__c>();
        for (Ask__c ask : [
            SELECT Id, Outcome__c
            FROM Ask__c
            WHERE
                (Donor_Contact__c IN :contacts
                OR Donor_Account__c IN :accounts)
                AND (Outcome__c = :AskRules.OUTCOME_OPEN
                OR Next_Step__c != NULL)
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            Ask__c updated = new Ask__c(Id = ask.Id, Next_Step__c = null);
            if (ask.Outcome__c == AskRules.OUTCOME_OPEN) {
                updated.Outcome__c = AskRules.OUTCOME_WITHDRAWN;
            }
            updates.add(updated);
        }
        if (updates.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.update(updates, true, AccessLevel.USER_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.ENDED,
                labelOf(Ask__c.SObjectType),
                new List<Id>(new Map<Id, Ask__c>(updates).keySet()),
                new List<String>{
                    Ask__c.Outcome__c.getDescribe().getLabel(),
                    Ask__c.Next_Step__c.getDescribe().getLabel()
                }
            )
        };
    }

    /**
     * The person's automatic Household Member credits, deleted as the user (R-SC3: only current
     * members are credited, and the person is now in no household). Deleted before the kept
     * credits are counted, so the count is only of what stays: credits a person entered and
     * other automatic roles such as Matched Donor.
     */
    private static List<PersonErasure.Change> deleteHouseholdCredits(
        Set<Id> contacts,
        Set<Id> accounts
    ) {
        List<Soft_Credit__c> credits = [
            SELECT Id
            FROM Soft_Credit__c
            WHERE
                (Contact__c IN :contacts
                OR Account__c IN :accounts)
                AND Is_Automatic__c = TRUE
                AND Role__c = :SoftCreditService.ROLE_HOUSEHOLD_MEMBER
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        if (credits.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.delete(credits, true, AccessLevel.USER_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.DELETED,
                Label.Giving_Erase_HouseholdCreditsLabel,
                new List<Id>(new Map<Id, Soft_Credit__c>(credits).keySet()),
                null
            )
        };
    }

    /** Names typed for the person, and the words of their own tributes, emptied as the user. */
    private static List<PersonErasure.Change> eraseTributes(Set<Id> contacts, Set<Id> accounts) {
        List<Tribute__c> updates = new List<Tribute__c>();
        for (Tribute__c tribute : [
            SELECT
                Id,
                Honoree_Contact__c,
                Honoree_Account__c,
                Honoree_Name__c,
                Notification_Recipient_Contact__c,
                Notification_Recipient_Account__c,
                Notification_Recipient_Name__c,
                Message__c,
                Gift__r.Donor_Contact__c,
                Gift__r.Donor_Account__c
            FROM Tribute__c
            WHERE
                Honoree_Contact__c IN :contacts
                OR Honoree_Account__c IN :accounts
                OR Notification_Recipient_Contact__c IN :contacts
                OR Notification_Recipient_Account__c IN :accounts
                OR Gift__r.Donor_Contact__c IN :contacts
                OR Gift__r.Donor_Account__c IN :accounts
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            Tribute__c updated = new Tribute__c(Id = tribute.Id);
            Boolean changed = false;
            if (
                isPerson(
                    tribute.Honoree_Contact__c,
                    tribute.Honoree_Account__c,
                    contacts,
                    accounts
                ) && tribute.Honoree_Name__c != null
            ) {
                updated.Honoree_Name__c = null;
                changed = true;
            }
            if (
                isPerson(
                    tribute.Notification_Recipient_Contact__c,
                    tribute.Notification_Recipient_Account__c,
                    contacts,
                    accounts
                ) && tribute.Notification_Recipient_Name__c != null
            ) {
                updated.Notification_Recipient_Name__c = null;
                changed = true;
            }
            if (
                isPerson(
                    tribute.Gift__r?.Donor_Contact__c,
                    tribute.Gift__r?.Donor_Account__c,
                    contacts,
                    accounts
                ) && tribute.Message__c != null
            ) {
                updated.Message__c = null;
                changed = true;
            }
            if (changed) {
                updates.add(updated);
            }
        }
        if (updates.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.update(updates, true, AccessLevel.USER_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.CLEARED,
                labelOf(Tribute__c.SObjectType),
                new List<Id>(new Map<Id, Tribute__c>(updates).keySet()),
                new List<String>{
                    Tribute__c.Honoree_Name__c.getDescribe().getLabel(),
                    Tribute__c.Notification_Recipient_Name__c.getDescribe().getLabel(),
                    Tribute__c.Message__c.getDescribe().getLabel()
                }
            )
        };
    }

    /**
     * The ledger's copy of the address an acknowledgment went to. The ledger is bookkeeping no
     * user edits (ADR-0032), so the two text fields are emptied in system mode (ADR-0021), on
     * rows sent to this person only: by recipient where people are contacts, and by the gift's
     * donor where they are accounts (the ledger names the person contact, which Giving does not
     * read).
     */
    private static List<PersonErasure.Change> eraseAcknowledgments(
        Set<Id> contacts,
        Set<Id> accounts
    ) {
        List<Acknowledgment__c> updates = new List<Acknowledgment__c>();
        for (Acknowledgment__c row : [
            SELECT Id
            FROM Acknowledgment__c
            WHERE
                (Recipient_Contact__c IN :contacts
                OR Gift__r.Donor_Account__c IN :accounts)
                AND (Recipient_Email__c != NULL
                OR Failure_Reason__c != NULL)
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            updates.add(
                new Acknowledgment__c(
                    Id = row.Id,
                    Recipient_Email__c = null,
                    Failure_Reason__c = null
                )
            );
        }
        if (updates.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.update(updates, true, AccessLevel.SYSTEM_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.CLEARED,
                labelOf(Acknowledgment__c.SObjectType),
                new List<Id>(new Map<Id, Acknowledgment__c>(updates).keySet()),
                new List<String>{
                    Acknowledgment__c.Recipient_Email__c.getDescribe().getLabel(),
                    Acknowledgment__c.Failure_Reason__c.getDescribe().getLabel()
                }
            )
        };
    }

    /** Running plans for the person, cancelled as the user; their tasks stay (R-SP8). */
    private static List<PersonErasure.Change> cancelStewardship(
        Set<Id> contacts,
        Set<Id> accounts
    ) {
        List<Stewardship_Plan__c> updates = new List<Stewardship_Plan__c>();
        for (Stewardship_Plan__c plan : [
            SELECT Id
            FROM Stewardship_Plan__c
            WHERE
                (Contact__c IN :contacts
                OR Account__c IN :accounts)
                AND Status__c = :StewardshipService.STATUS_RUNNING
            WITH SYSTEM_MODE
            LIMIT 10000
        ]) {
            updates.add(
                new Stewardship_Plan__c(
                    Id = plan.Id,
                    Status__c = StewardshipService.STATUS_CANCELLED,
                    Completed_Date__c = System.today()
                )
            );
        }
        if (updates.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.update(updates, true, AccessLevel.USER_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.ENDED,
                labelOf(Stewardship_Plan__c.SObjectType),
                new List<Id>(new Map<Id, Stewardship_Plan__c>(updates).keySet()),
                new List<String>{ Stewardship_Plan__c.Status__c.getDescribe().getLabel() }
            )
        };
    }

    private static void kept(
        List<PersonErasure.Change> changes,
        Schema.SObjectType type,
        Integer howMany,
        String note
    ) {
        if (howMany > 0) {
            changes.add(new PersonErasure.Change(PersonErasure.KEPT, labelOf(type), howMany, note));
        }
    }

    private static Boolean isPerson(
        Id contactId,
        Id accountId,
        Set<Id> contacts,
        Set<Id> accounts
    ) {
        return (contactId != null && contacts.contains(contactId)) ||
            (accountId != null && accounts.contains(accountId));
    }

    private static String labelOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
    }
}
