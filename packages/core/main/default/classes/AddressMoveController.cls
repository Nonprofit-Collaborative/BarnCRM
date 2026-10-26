/**
 * The Addresses card's two household moves (R-AD9, ADR-0140): Use for Whole Household on a
 * person's own address, and Update Everyone's Address on a household's primary address.
 *
 * Everything is read and written as the user, as every other address write is: the moves run
 * through AddressService in user mode, so someone who cannot edit addresses, the household or
 * its people is refused, and nothing is half saved.
 */
public with sharing class AddressMoveController {
    /** What the card needs to offer the moves on this record. */
    public class CardContext {
        /** True on a household, where Update Everyone's Address is offered. */
        @AuraEnabled
        public Boolean isHousehold = false;
        /**
         * On a person, the households they currently belong to, their own first. The card asks
         * which one only when there is more than one.
         */
        @AuraEnabled
        public List<Choice> households = new List<Choice>();
    }

    /** A household or a person, by id and name. */
    public class Choice {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;

        Choice(Id id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    /** Who Update Everyone's Address would move, for the confirmation. */
    public class MovePreview {
        @AuraEnabled
        public Boolean hasPrimary = false;
        /** The members who take the household's address. */
        @AuraEnabled
        public List<Choice> moving = new List<Choice>();
        /** The members with an address of their own, left alone unless ticked. */
        @AuraEnabled
        public List<Choice> withTheirOwn = new List<Choice>();
    }

    @AuraEnabled(cacheable=true)
    public static CardContext getCardContext(Id recordId) {
        try {
            CardContext context = new CardContext();
            if (recordId == null) {
                return context;
            }
            Id householdType = HouseholdService.householdRecordTypeId();
            if (recordId.getSObjectType() == Account.SObjectType) {
                for (
                    Account record : HouseholdSelector.getAccountRecordTypes(
                        new Set<Id>{ recordId }
                    )
                ) {
                    context.isHousehold =
                        householdType != null &&
                        record.RecordTypeId == householdType;
                }
            }
            if (context.isHousehold) {
                return context;
            }
            Set<Id> person = new Set<Id>{ recordId };
            Set<Id> householdIds = HouseholdService.currentHouseholdIdsByPerson(person)
                .get(recordId);
            Id own = HouseholdService.getHouseholdIdsFor(person).get(recordId);
            Map<Id, String> names = AddressSelector.selectNames(null, householdIds);
            if (names.containsKey(own)) {
                context.households.add(new Choice(own, names.get(own)));
            }
            for (Id householdId : names.keySet()) {
                if (householdId != own) {
                    context.households.add(new Choice(householdId, names.get(householdId)));
                }
            }
            return context;
        } catch (Exception caught) {
            throw asUserError(caught, 'Addresses card: household moves');
        }
    }

    @AuraEnabled
    public static MovePreview getMovePreview(Id householdId) {
        try {
            MovePreview preview = new MovePreview();
            AddressService.HouseholdMove move = AddressService.householdMoves(
                    new Set<Id>{ householdId }
                )
                .get(householdId);
            if (move == null) {
                return preview;
            }
            preview.hasPrimary = move.primary != null;
            preview.moving = choicesFor(move.taking);
            preview.withTheirOwn = choicesFor(move.withTheirOwn);
            return preview;
        } catch (Exception caught) {
            throw asUserError(caught, 'Addresses card: Update Everyone\'s Address');
        }
    }

    @AuraEnabled
    public static void useForWholeHousehold(Id addressId, Id householdId) {
        Savepoint before = Database.setSavepoint();
        try {
            AddressService.useForWholeHousehold(new Map<Id, Id>{ addressId => householdId });
        } catch (Exception caught) {
            Database.rollback(before);
            throw asUserError(caught, 'Addresses card: Use for Whole Household');
        }
    }

    @AuraEnabled
    public static void updateEveryonesAddress(Id householdId, List<Id> alsoMove) {
        Savepoint before = Database.setSavepoint();
        try {
            AddressService.updateEveryonesAddress(
                new Map<Id, Set<Id>>{
                    householdId => alsoMove == null ? new Set<Id>() : new Set<Id>(alsoMove)
                }
            );
        } catch (Exception caught) {
            Database.rollback(before);
            throw asUserError(caught, 'Addresses card: Update Everyone\'s Address');
        }
    }

    /** The people named, as the user may read them, contacts and person accounts alike. */
    private static List<Choice> choicesFor(Set<Id> personIds) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Id personId : personIds) {
            if (personId.getSObjectType() == Contact.SObjectType) {
                contactIds.add(personId);
            } else {
                accountIds.add(personId);
            }
        }
        Map<Id, String> names = AddressSelector.selectNames(contactIds, accountIds);
        List<Choice> choices = new List<Choice>();
        for (Id personId : names.keySet()) {
            choices.add(new Choice(personId, names.get(personId)));
        }
        return choices;
    }

    /**
     * A refusal the card can show as it is passes through; anything else, a permission the
     * user lacks among them, is logged and shown as one plain sentence.
     */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof AddressService.AddressMoveException)) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_Address_MoveFailed;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
