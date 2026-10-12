/**
 * Every query against Soft Credit (plan Section 9.3).
 *
 * Maintenance reads run in system mode on purpose: the credits BarnCRM created are the
 * package's own records, and it has to see all of them to keep them right, whatever the person
 * saving the gift can see. Everything a person asked for on a screen reads in user mode.
 */
public with sharing class SoftCreditSelector {
    private static final Integer MAX_ROWS = 10000;

    /**
     * The credits BarnCRM created for these gifts in one role, for recomputation.
     */
    public static List<Soft_Credit__c> selectAutomaticForGifts(Set<Id> giftIds, String role) {
        if (giftIds == null || giftIds.isEmpty() || String.isBlank(role)) {
            return new List<Soft_Credit__c>();
        }
        String wantedRole = role;
        return [
            SELECT Id, Gift__c, Contact__c, Account__c, Role__c, Amount__c, Percent__c
            FROM Soft_Credit__c
            WHERE Gift__c IN :giftIds AND Is_Automatic__c = TRUE AND Role__c = :wantedRole
            WITH SYSTEM_MODE
            LIMIT :MAX_ROWS
        ];
    }

    /**
     * Every credit BarnCRM created for these gifts, whatever the role, for removal.
     */
    public static List<Soft_Credit__c> selectAutomaticForGifts(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Soft_Credit__c>();
        }
        return [
            SELECT Id, Gift__c, Contact__c, Account__c, Role__c, Amount__c, Percent__c
            FROM Soft_Credit__c
            WHERE Gift__c IN :giftIds AND Is_Automatic__c = TRUE
            WITH SYSTEM_MODE
            LIMIT :MAX_ROWS
        ];
    }

    /**
     * The credits on one gift as the record page shows them.
     */
    public static List<Soft_Credit__c> selectForGifts(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Soft_Credit__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Gift__c,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name,
                Role__c,
                Custom_Role__c,
                Amount__c,
                Percent__c,
                Is_Automatic__c
            FROM Soft_Credit__c
            WHERE Gift__c IN :giftIds
            WITH USER_MODE
            ORDER BY Is_Automatic__c DESC, Name
            LIMIT 1000
        ];
    }

    public static List<Soft_Credit__c> selectByIds(Set<Id> softCreditIds) {
        if (softCreditIds == null || softCreditIds.isEmpty()) {
            return new List<Soft_Credit__c>();
        }
        return [
            SELECT Id, Gift__c, Contact__c, Account__c, Role__c, Amount__c, Is_Automatic__c
            FROM Soft_Credit__c
            WHERE Id IN :softCreditIds
            WITH USER_MODE
            LIMIT 200
        ];
    }
}
