/**
 * The seasonal address swap (C-18, canonical model R-AD4 and R-AD8).
 *
 * A household that spends the winter in Arizona has two addresses on file and one of them is
 * right at a time. This is the job that keeps the right one marked as the address in use, so
 * that every mailing, receipt, and report reads the address the household is actually at, and
 * so that nobody has to remember to move it in November and move it back in April.
 *
 * The decision and the writing are deliberately separate. `planFor` is the whole rule, and it
 * takes a date and a list of records and returns the updates without touching the database, so
 * the days a swap turns on the answer, including a range that crosses New Year, are testable by
 * naming a date. `swapOwners` is the part that saves.
 *
 * What the job does not do: it does not copy the new address into the standard address fields.
 * Moving the default flag is enough, because the address automation copies it onward (R-AD3),
 * which means an administrator who has switched that automation off gets the same behavior from
 * the job as from a person pressing "Set as default" on the record.
 */
public with sharing class SeasonalAddressService {
    @TestVisible
    private static final String TYPE_SEASONAL = 'Seasonal';

    private static final String LOG_CONTEXT = 'Seasonal address swap';

    /**
     * How long after a run the Hub starts saying so. A run a day means anything past a day and
     * a half has missed one, and the same window the rollups use reads the same way to an
     * administrator looking at two tiles on one page.
     */
    private static final Integer STALE_AFTER_HOURS = 36;

    /** What one owner's swap comes to: the records to save and what it counted as. */
    public class Plan {
        /** The address updates, or empty when the right address is already the default. */
        public List<Address__c> updates = new List<Address__c>();

        /** True when a seasonal address is taking over from an ordinary one. */
        public Boolean movedIn = false;

        /** True when a season has ended and the ordinary address is coming back. */
        public Boolean movedBack = false;

        /**
         * The identifier of a second seasonal address in season on the same day, which is a
         * data entry mistake worth telling somebody about, or null.
         */
        public Id collidingAddressId;
    }

    /** What a whole run came to, and the sentence an administrator reads afterwards. */
    public class RunSummary {
        public Integer movedIn = 0;
        public Integer movedBack = 0;
        public Integer failed = 0;

        /** Adds another owner's outcome, so a batch can carry one summary across its chunks. */
        public void add(RunSummary other) {
            if (other == null) {
                return;
            }
            this.movedIn += other.movedIn;
            this.movedBack += other.movedBack;
            this.failed += other.failed;
        }

        /** One sentence, in the reader's language, for the Hub tile and the settings page. */
        public String text() {
            return String.format(
                System.Label.Core_SeasonalAddress_RunSummaryFormat,
                new List<String>{
                    String.valueOf(this.movedIn),
                    String.valueOf(this.movedBack),
                    String.valueOf(this.failed)
                }
            );
        }
    }

    // ------------------------------------------------------------------ the rule

    /**
     * What to do with one owner's addresses on one day. No database, so the boundary days are
     * an ordinary assertion in a test.
     *
     * The four outcomes are R-AD4's, in order:
     *
     * 1. A seasonal address is in season and is not the default. The current default is marked
     *    Replaced By Seasonal so the job knows what to put back in the spring, and the seasonal
     *    address takes the flag.
     * 2. The default is a seasonal address whose season has ended. The address marked Replaced
     *    By Seasonal comes back, or failing that the newest address that is not seasonal. An
     *    owner whose only address is the seasonal one keeps it: an out of date address is worth
     *    more than no address at all.
     * 3. Two seasonal addresses are in season on the same day. The oldest wins, so the answer
     *    does not change from night to night, and the collision is reported.
     * 4. Nothing to do.
     */
    public static Plan planFor(List<Address__c> ownerAddresses, Date today) {
        Plan plan = new Plan();
        if (ownerAddresses == null || ownerAddresses.isEmpty() || today == null) {
            return plan;
        }

        List<Address__c> inSeason = new List<Address__c>();
        Address__c currentDefault = null;
        for (Address__c address : ownerAddresses) {
            if (address.Is_Default__c == true && currentDefault == null) {
                currentDefault = address;
            }
            if (AddressService.isSeasonalActiveOn(address, today)) {
                inSeason.add(address);
            }
        }

        if (!inSeason.isEmpty()) {
            Address__c winner = oldest(inSeason);
            if (inSeason.size() > 1) {
                plan.collidingAddressId = winner.Id;
            }
            if (currentDefault != null && currentDefault.Id == winner.Id) {
                return plan;
            }
            if (currentDefault != null) {
                // Only an ordinary address is marked as waiting to come back. A seasonal
                // address whose own season has ended is not something to restore in the
                // spring, so it gives up the flag and is not marked.
                plan.updates.add(
                    new Address__c(
                        Id = currentDefault.Id,
                        Is_Default__c = false,
                        Replaced_By_Seasonal__c = currentDefault.Type__c != TYPE_SEASONAL
                    )
                );
            }
            plan.updates.add(
                new Address__c(
                    Id = winner.Id,
                    Is_Default__c = true,
                    Replaced_By_Seasonal__c = false
                )
            );
            plan.movedIn = true;
            return plan;
        }

        if (currentDefault == null) {
            return plan;
        }

        if (currentDefault.Type__c != TYPE_SEASONAL) {
            // The address in use is an ordinary one and no season is running, so the job has
            // nothing to move. It clears the mark if the address is still carrying one, which
            // happens when somebody set this address back as the default by hand during a
            // season: the mark means "waiting to come back", and this address is already back.
            if (currentDefault.Replaced_By_Seasonal__c == true) {
                plan.updates.add(
                    new Address__c(Id = currentDefault.Id, Replaced_By_Seasonal__c = false)
                );
            }
            return plan;
        }

        Address__c restore = addressToRestore(ownerAddresses, currentDefault.Id);
        if (restore == null) {
            return plan;
        }
        plan.updates.add(new Address__c(Id = currentDefault.Id, Is_Default__c = false));
        plan.updates.add(
            new Address__c(Id = restore.Id, Is_Default__c = true, Replaced_By_Seasonal__c = false)
        );
        plan.movedBack = true;
        return plan;
    }

    // ------------------------------------------------------------------ the run

    /**
     * Swaps the addresses of the given owners for the given day and reports what it did.
     *
     * One owner at a time, and one saved DML per owner, because a swap is a pair of writes and
     * a half-saved pair would leave a household with no default address and so with nothing in
     * its standard address fields. An owner whose save fails is written to the Error Log with
     * the reason and counted as a failure; the rest of the run carries on (R-AD8).
     */
    public static RunSummary swapOwners(Set<Id> ownerIds, Date today) {
        RunSummary summary = new RunSummary();
        if (ownerIds == null || ownerIds.isEmpty()) {
            return summary;
        }

        Map<Id, List<Address__c>> byOwner = groupByOwner(
            SeasonalAddressSelector.selectAllForOwners(ownerIds)
        );

        for (Id ownerId : byOwner.keySet()) {
            Plan plan = planFor(byOwner.get(ownerId), today);
            if (plan.collidingAddressId != null) {
                ErrorLogger.logMessage(
                    System.Label.Core_SeasonalAddress_CollisionWarning,
                    LOG_CONTEXT,
                    ErrorLogger.SEVERITY_WARNING,
                    plan.collidingAddressId
                );
            }
            if (plan.updates.isEmpty()) {
                continue;
            }
            try {
                SeasonalAddressWriter.save(plan.updates);
                if (plan.movedIn) {
                    summary.movedIn++;
                }
                if (plan.movedBack) {
                    summary.movedBack++;
                }
            } catch (Exception saveFailed) {
                summary.failed++;
                ErrorLogger.log(saveFailed, LOG_CONTEXT, ownerId);
            }
        }
        return summary;
    }

    /** Records that a run finished and what it came to, for the Hub and the settings page. */
    public static void recordRun(RunSummary summary, Datetime finishedAt) {
        try {
            SeasonalAddressWriter.recordRun(
                finishedAt,
                summary == null ? new RunSummary().text() : summary.text()
            );
            SettingsService.clearCaches();
        } catch (Exception recordFailed) {
            // A run that worked and could not say so is still a run that worked, so this is
            // logged rather than thrown. It is also exactly the failure that would otherwise
            // make the Hub quietly lie about when the job last ran.
            ErrorLogger.log(recordFailed, LOG_CONTEXT);
        }
    }

    // ------------------------------------------------------------------ what the Hub reads

    /** When the swap last finished, or null when it has never run in this org. */
    public static Datetime lastRun() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings == null ? null : settings.Seasonal_Address_Last_Run__c;
    }

    /** What the last run did, in one sentence, or null when it has never run. */
    public static String lastRunSummary() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings == null ? null : settings.Seasonal_Address_Last_Run_Summary__c;
    }

    /**
     * True when the nightly job is scheduled and has not run inside the freshness window.
     *
     * Being scheduled is half the test on purpose. An org that has not switched the job on has
     * not missed anything, and warning it about a run that was never going to happen teaches
     * administrators to ignore the tile. The page says "not scheduled" in that case instead,
     * which is a different sentence with a different button under it.
     */
    public static Boolean isStale() {
        return isStale(SeasonalAddressScheduler.isScheduled());
    }

    /** The same, for a caller that has already asked whether the job is scheduled. */
    public static Boolean isStale(Boolean scheduled) {
        if (scheduled != true) {
            return false;
        }
        Datetime latest = lastRun();
        return latest == null || latest < Datetime.now().addHours(-STALE_AFTER_HOURS);
    }

    // ------------------------------------------------------------------ internals

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

    private static Map<Id, List<Address__c>> groupByOwner(List<Address__c> addresses) {
        Map<Id, List<Address__c>> byOwner = new Map<Id, List<Address__c>>();
        for (Address__c address : addresses) {
            Id ownerId = ownerIdOf(address);
            if (ownerId == null) {
                continue;
            }
            if (!byOwner.containsKey(ownerId)) {
                byOwner.put(ownerId, new List<Address__c>());
            }
            byOwner.get(ownerId).add(address);
        }
        return byOwner;
    }

    /**
     * The address to put back: the one marked as waiting, and failing that the newest ordinary
     * address the owner has.
     *
     * Only an address that is not seasonal is ever a candidate. Restoring a seasonal address
     * whose own season is over would put mail back on a street the household is not at, which
     * is the mistake the whole feature exists to stop.
     */
    private static Address__c addressToRestore(List<Address__c> ownerAddresses, Id leavingId) {
        Address__c marked = null;
        Address__c newestOrdinary = null;
        for (Address__c address : ownerAddresses) {
            if (address.Id == leavingId || address.Type__c == TYPE_SEASONAL) {
                continue;
            }
            if (address.Replaced_By_Seasonal__c == true && isNewer(address, marked)) {
                marked = address;
            }
            if (isNewer(address, newestOrdinary)) {
                newestOrdinary = address;
            }
        }
        return marked != null ? marked : newestOrdinary;
    }

    private static Boolean isNewer(Address__c candidate, Address__c held) {
        if (held == null) {
            return true;
        }
        if (candidate.CreatedDate == null || held.CreatedDate == null) {
            return false;
        }
        return candidate.CreatedDate > held.CreatedDate;
    }

    /** The oldest of the addresses in season, so a collision resolves the same way every night. */
    private static Address__c oldest(List<Address__c> addresses) {
        Address__c held = addresses[0];
        for (Address__c address : addresses) {
            if (
                address.CreatedDate != null &&
                held.CreatedDate != null &&
                address.CreatedDate < held.CreatedDate
            ) {
                held = address;
            }
        }
        return held;
    }
}
