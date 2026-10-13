/**
 * The one place package owned household bookkeeping is saved.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. The household name, the two greetings and the member
 * count are computed by the package: no person types them, and no screen offers them for
 * editing. A staff user saving a contact must not need edit access on them, and an org's
 * own profile, an integration user or a data loader user cannot be given that access by a
 * packaged permission set at all. Writing them with the running user's access therefore
 * turns an ordinary contact save into a raw DML error, which is the failure this class
 * exists to prevent, so these writes run in `AccessLevel.SYSTEM_MODE`.
 *
 * This class is deliberately `with sharing` where ADR-0021 says `without sharing`, and the
 * ADR allows a writer to narrow it: household upkeep never needs to cross sharing, and it
 * must not create, rename or delete a household the running user cannot see, so the
 * narrower declaration is the correct one here.
 *
 * The exception is kept narrow in every other way too:
 *
 * - Only these fields are written here, and only on the Household record type.
 * - No value written here comes from user input: every one is computed by
 *   HouseholdNamingService or counted by HouseholdService.
 * - Deleting an emptied household, and removing or restoring a membership row, are NOT
 *   covered by the exception: those remove or bring back a record rather than compute a
 *   value, so they run with the user's own access and are logged rather than thrown when
 *   they are refused.
 * - Everything a person types (a contact, a membership row, a move) is saved elsewhere in
 *   user mode, and everything a screen reads is read in user mode.
 */
public with sharing class HouseholdWriter {
    /**
     * Creates households the package is making on the user's behalf and returns one save
     * result per household, in the same order.
     *
     * The whole result comes back rather than just the ids, because a household that could
     * not be created leaves a person with no household (R-C1), and only the caller knows
     * which person each row was for. The failure is logged here so that an administrator
     * can find it; the caller puts it on the person's own save so that whoever saved them
     * sees it too.
     */
    public static List<Database.SaveResult> createHouseholds(List<Account> households) {
        if (households == null || households.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        List<Database.SaveResult> saves = Database.insert(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
        return saves;
    }

    /**
     * The platform's own reason a save was refused, for putting on the record the save was
     * made for. Empty when the save succeeded.
     */
    public static String failureReason(Database.SaveResult save) {
        return save.isSuccess() ? '' : firstMessage(save.getErrors());
    }

    /**
     * Saves computed values on existing households: the name, the two greetings, and the
     * member count.
     */
    public static void updateHouseholds(List<Account> households) {
        updateHouseholdsReportingRefusals(households);
    }

    /**
     * The same, answering the ids of the households the save refused, so a caller can save
     * part of a refused change again (each refusal is logged). A refused save carries no id,
     * so the refused records are found by their position in the list.
     */
    public static Set<Id> updateHouseholdsReportingRefusals(List<Account> households) {
        Set<Id> refused = new Set<Id>();
        if (households == null || households.isEmpty()) {
            return refused;
        }
        List<Database.SaveResult> saves = Database.update(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextNaming);
        for (Integer i = 0; i < saves.size(); i++) {
            if (!saves[i].isSuccess()) {
                refused.add(households[i].Id);
            }
        }
        return refused;
    }

    /**
     * Creates the membership rows the package is making on the user's behalf, for a person
     * the org stores as an account.
     */
    public static void createMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saves = Database.insert(
            memberships,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
    }

    /**
     * The membership rows a people merge gives the survivor, and the survivor's rows it makes
     * primary. All or none, in system mode (upkeep, ADR-0021): a row that cannot be written
     * fails the merge, so nothing is lost and the merged-away person's households are
     * untouched, rather than a membership quietly going missing.
     */
    public static void saveMergedMemberships(
        List<Household_Member__c> created,
        List<Household_Member__c> promoted
    ) {
        if (created != null && !created.isEmpty()) {
            Database.insert(created, true, AccessLevel.SYSTEM_MODE);
        }
        if (promoted != null && !promoted.isEmpty()) {
            Database.update(promoted, true, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * Removes households the package created that have been left with no members. This one
     * runs with the user's own access, and a refusal is logged rather than thrown, so that
     * tidying up never fails somebody's save.
     */
    public static void deleteHouseholds(List<Account> households) {
        if (households == null || households.isEmpty()) {
            return;
        }
        try {
            List<Database.DeleteResult> deletes = Database.delete(
                households,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.DeleteResult result : deletes) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    /**
     * Removes the membership rows that join a person to their households, on the one path
     * that needs it: the person record itself is being deleted, and a row that survives it
     * would be left naming nobody.
     *
     * Like `deleteHouseholds` this runs with the user's own access rather than in system
     * mode, and a refusal is logged rather than thrown: removing a record is not the
     * package writing one of its own computed values, and tidying up must never fail
     * somebody's save.
     */
    public static void deleteMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        try {
            List<Database.DeleteResult> deletes = Database.delete(
                memberships,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.DeleteResult result : deletes) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    /**
     * Puts back the membership rows that were removed when a person record was deleted,
     * on the same terms as the removal: the user's own access, and a refusal logged.
     */
    public static void undeleteMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        try {
            List<Database.UndeleteResult> restores = Database.undelete(
                memberships,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.UndeleteResult result : restores) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    private static void logFailures(List<Database.SaveResult> saves, String context) {
        for (Database.SaveResult save : saves) {
            if (!save.isSuccess()) {
                log(firstMessage(save.getErrors()), context);
            }
        }
    }

    private static String firstMessage(List<Database.Error> errors) {
        return errors == null || errors.isEmpty() ? '' : errors[0].getMessage();
    }

    private static void log(String message, String context) {
        ErrorLogger.log(
            new HouseholdException(Label.Core_Households_ErrorSaveFailed + ' ' + message),
            context
        );
    }
}
