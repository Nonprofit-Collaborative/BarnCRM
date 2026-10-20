/**
 * The class Core finds by name (in `HouseholdDependentsExtensions.EXTENSION_CLASSES`) and asks
 * before a household is deleted by the empty household tidy-up, the nightly tidy-up of
 * households emptied by deleting people, or an import undo: a household that volunteer hours
 * are credited to is kept (R-H12, R-H12a, R-VG2, ADR-0070). Hours stay with the household they
 * were given in when the person moves (ADR-0071), and the Household lookup clears on delete, so
 * deleting the household would take the household's share of those hours out of its history.
 * A sign-up names a person, never a household, so only hours are asked about. A household merge
 * needs nothing here: the platform's merge moves the hours to the household kept.
 *
 * `@NamespaceAccessible` with a public no-argument constructor because Core resolves it with
 * `Type.forName` under ADR-0017, as it does Giving's.
 *
 * `without sharing` and `WITH SYSTEM_MODE` (ADR-0021), as Giving's: the answer is a fact about
 * the org, not about what the person moving someone may see, and Volunteer Hours are Private, so
 * an entry that person cannot see would otherwise read as absent and the household would be
 * deleted anyway. Only package upkeep calls it, its only input is household identifiers upkeep
 * computed, it returns identifiers only, and it elevates nothing else.
 */
@NamespaceAccessible
public without sharing class VolunteersHouseholdDependentsExtension implements HouseholdDependentsExtension {
    @NamespaceAccessible
    public VolunteersHouseholdDependentsExtension() {
        return;
    }

    public Set<Id> householdsWithDependents(Set<Id> householdIds) {
        Set<Id> dependent = new Set<Id>();
        if (householdIds == null || householdIds.isEmpty()) {
            return dependent;
        }
        // A semi-join, so the query returns at most one row per household asked about, however
        // many hours it has.
        for (Account household : [
            SELECT Id
            FROM Account
            WHERE Id IN :householdIds AND Id IN (SELECT Household__c FROM Volunteer_Hours__c)
            WITH SYSTEM_MODE
        ]) {
            dependent.add(household.Id);
        }
        return dependent;
    }
}
