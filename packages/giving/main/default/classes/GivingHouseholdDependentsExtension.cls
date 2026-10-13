/**
 * The class Core finds by name (in `HouseholdDependentsExtensions.EXTENSION_CLASSES`) and asks
 * before the empty household tidy-up deletes a household: a household that a gift or a
 * commitment is credited to is kept (R-H12, R-G2, ADR-0070
 * `0070-empty-household-tidy-up-keeps-households-with-gifts.md`). Both Household lookups clear
 * on delete, so deleting the household would leave that history with no household at all.
 *
 * `@NamespaceAccessible` with a public no-argument constructor because Core resolves it with
 * `Type.forName` under ADR-0017, as it does `GivingHealthCheckExtension`.
 *
 * `without sharing` and `WITH SYSTEM_MODE` (ADR-0021): the answer is a fact about the org, not
 * about what the person moving a donor may see. A gift that person cannot see would otherwise
 * read as absent and the household would be deleted anyway. Only package upkeep calls it, its
 * only input is household identifiers upkeep computed, it returns identifiers only, and it
 * elevates nothing else.
 */
@NamespaceAccessible
public without sharing class GivingHouseholdDependentsExtension implements HouseholdDependentsExtension {
    public Set<Id> householdsWithDependents(Set<Id> householdIds) {
        Set<Id> dependent = new Set<Id>();
        if (householdIds == null || householdIds.isEmpty()) {
            return dependent;
        }
        // Semi-joins, so each query returns at most one row per household asked about, however
        // many gifts it has.
        for (Account household : [
            SELECT Id
            FROM Account
            WHERE Id IN :householdIds AND Id IN (SELECT Household__c FROM Gift__c)
            WITH SYSTEM_MODE
        ]) {
            dependent.add(household.Id);
        }
        Set<Id> notYetDependent = new Set<Id>(householdIds);
        notYetDependent.removeAll(dependent);
        if (notYetDependent.isEmpty()) {
            return dependent;
        }
        for (Account household : [
            SELECT Id
            FROM Account
            WHERE Id IN :notYetDependent AND Id IN (SELECT Household__c FROM Commitment__c)
            WITH SYSTEM_MODE
        ]) {
            dependent.add(household.Id);
        }
        return dependent;
    }
}
