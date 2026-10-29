/**
 * SeasonalAddressService: the swap rule on the days it turns on the answer, the swap itself,
 * and the record of the run that the Hub reads.
 *
 * The household is the Garcia family from the admin guide, who spend the winter in Phoenix.
 * Two ranges are used throughout: January 1 to March 31, which is the simple case, and
 * November 1 to March 31, which wraps the end of the year and is the case a real snowbird
 * address is in.
 */
@IsTest(testFor='ApexClass:SeasonalAddressService')
private class SeasonalAddressServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String HOME_STREET = '812 Willow Lane';
    private static final String HOME_CITY = 'Springfield';
    private static final String WINTER_STREET = '4120 East Camelback Road';
    private static final String WINTER_CITY = 'Phoenix';

    // ------------------------------------------------------------------ the boundary days

    @IsTest
    static void seasonStartsOnItsFirstDayAndNotTheDayBefore() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(1, 1, 3, 31);

            SeasonalAddressService.Plan dayBefore = SeasonalAddressService.planFor(
                garcia.addresses(),
                Date.newInstance(2026, 12, 31)
            );
            SeasonalAddressService.Plan firstDay = SeasonalAddressService.planFor(
                garcia.addresses(),
                Date.newInstance(2027, 1, 1)
            );

            Assert.isFalse(
                dayBefore.movedIn,
                'December 31 is outside January 1 to March 31, so nothing should move.'
            );
            Assert.areEqual(
                0,
                dayBefore.updates.size(),
                'A day outside the season should produce no updates at all.'
            );
            Assert.isTrue(
                firstDay.movedIn,
                'January 1 is the first day of the season, so the winter address takes over.'
            );
            Assert.areEqual(
                garcia.winterId,
                defaultIdIn(firstDay),
                'The address made default on the first day should be the winter address.'
            );
            Assert.areEqual(
                garcia.homeId,
                markedIdIn(firstDay),
                'The home address should be marked so the job knows what to put back in April.'
            );
        }
    }

    @IsTest
    static void seasonEndsOnItsLastDayAndTheAddressComesBackTheDayAfter() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(1, 1, 3, 31);
            garcia.makeWinterCurrent();

            SeasonalAddressService.Plan lastDay = SeasonalAddressService.planFor(
                garcia.addresses(),
                Date.newInstance(2027, 3, 31)
            );
            SeasonalAddressService.Plan dayAfter = SeasonalAddressService.planFor(
                garcia.addresses(),
                Date.newInstance(2027, 4, 1)
            );

            Assert.areEqual(
                0,
                lastDay.updates.size(),
                'March 31 is still inside the season, so the winter address stays in use.'
            );
            Assert.isTrue(
                dayAfter.movedBack,
                'April 1 is the day after the season, so the home address comes back.'
            );
            Assert.areEqual(
                garcia.homeId,
                defaultIdIn(dayAfter),
                'The address put back on April 1 should be the one the season displaced.'
            );
        }
    }

    @IsTest
    static void aSeasonThatWrapsTheEndOfTheYearIsOneSeason() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(11, 1, 3, 31);

            Map<Date, Boolean> expected = new Map<Date, Boolean>{
                Date.newInstance(2026, 10, 31) => false,
                Date.newInstance(2026, 11, 1) => true,
                Date.newInstance(2026, 12, 25) => true,
                Date.newInstance(2027, 1, 1) => true,
                Date.newInstance(2027, 3, 31) => true,
                Date.newInstance(2027, 4, 1) => false
            };

            for (Date day : expected.keySet()) {
                SeasonalAddressService.Plan plan = SeasonalAddressService.planFor(
                    garcia.addresses(),
                    day
                );
                Assert.areEqual(
                    expected.get(day),
                    plan.movedIn,
                    'November 1 to March 31 is one season, so ' +
                        day.format() +
                        ' should be inside it: ' +
                        expected.get(day)
                );
            }
        }
    }

    // ------------------------------------------------------------------ what a run does

    @IsTest
    static void aRunMovesTheHouseholdToItsWinterAddressAndTheStandardFieldsFollow() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(11, 1, 3, 31);

            Test.startTest();
            SeasonalAddressService.RunSummary summary = SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.householdId },
                Date.newInstance(2027, 1, 15)
            );
            Test.stopTest();

            Assert.areEqual(1, summary.movedIn, 'One household moved to its seasonal address.');
            Assert.areEqual(0, summary.failed, 'Nothing should have failed.');
            Map<Id, Address__c> saved = addressesById(garcia.householdId);
            Assert.isTrue(
                saved.get(garcia.winterId).Is_Default__c,
                'The winter address should be the one in use in January.'
            );
            Assert.isFalse(
                saved.get(garcia.homeId).Is_Default__c,
                'The home address should no longer be the one in use.'
            );
            Assert.isTrue(
                saved.get(garcia.homeId).Replaced_By_Seasonal__c,
                'The home address should be marked as the one waiting to come back.'
            );
            Account moved = [SELECT BillingCity FROM Account WHERE Id = :garcia.householdId];
            Assert.areEqual(
                WINTER_CITY,
                moved.BillingCity,
                'The address automation should copy the new default into the standard fields.'
            );
        }
    }

    @IsTest
    static void aRunPutsTheHomeAddressBackWhenTheSeasonEnds() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(11, 1, 3, 31);
            SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.householdId },
                Date.newInstance(2027, 1, 15)
            );

            Test.startTest();
            SeasonalAddressService.RunSummary summary = SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.householdId },
                Date.newInstance(2027, 4, 1)
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                summary.movedBack,
                'One household came back from its winter address.'
            );
            Map<Id, Address__c> saved = addressesById(garcia.householdId);
            Assert.isTrue(
                saved.get(garcia.homeId).Is_Default__c,
                'The home address should be the one in use again on April 1.'
            );
            Assert.isFalse(
                saved.get(garcia.homeId).Replaced_By_Seasonal__c,
                'The mark should be cleared once the address is back in use.'
            );
            Account moved = [SELECT BillingCity FROM Account WHERE Id = :garcia.householdId];
            Assert.areEqual(
                HOME_CITY,
                moved.BillingCity,
                'The standard fields should follow the address back home.'
            );
        }
    }

    @IsTest
    static void runningTwiceOnTheSameDayChangesNothingTheSecondTime() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(11, 1, 3, 31);
            Date january = Date.newInstance(2027, 1, 15);
            SeasonalAddressService.swapOwners(new Set<Id>{ garcia.householdId }, january);

            Test.startTest();
            SeasonalAddressService.RunSummary second = SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.householdId },
                january
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                second.movedIn,
                'The right address is already in use, so a second run should move nothing.'
            );
            Assert.isTrue(
                addressesById(garcia.householdId).get(garcia.winterId).Is_Default__c,
                'The winter address should still be the one in use.'
            );
        }
    }

    @IsTest
    static void anOwnerWhoseOnlyAddressIsSeasonalKeepsIt() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Address__c winter = seasonalAddress(garcia.Id, 11, 1, 3, 31);
            winter.Is_Default__c = true;
            insert winter;

            Test.startTest();
            SeasonalAddressService.RunSummary summary = SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.Id },
                Date.newInstance(2027, 6, 1)
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                summary.movedBack,
                'There is no other address to put back, so nothing moves.'
            );
            Assert.isTrue(
                addressesById(garcia.Id).get(winter.Id).Is_Default__c,
                'An out of date address is worth more than no address at all, so it stays in use.'
            );
        }
    }

    @IsTest
    static void twoSeasonalAddressesOnTheSameDayPickTheOlderOneAndAreReported() {
        System.runAs(TestUsers.admin()) {
            Fixture garcia = winterInArizona(11, 1, 3, 31);
            Address__c second = seasonalAddress(garcia.householdId, 12, 1, 2, 28);
            second.City__c = 'Tucson';
            insert second;

            Test.startTest();
            SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.householdId },
                Date.newInstance(2027, 1, 15)
            );
            Test.stopTest();

            Assert.isTrue(
                addressesById(garcia.householdId).get(garcia.winterId).Is_Default__c,
                'The seasonal address added first should win, so the answer is the same every night.'
            );
            List<Error_Log__c> logged = [
                SELECT Id, Severity__c, Message__c
                FROM Error_Log__c
                WHERE Record_Reference__c = :String.valueOf(garcia.winterId)
            ];
            Assert.areEqual(
                1,
                logged.size(),
                'Two seasonal addresses covering one day is a data entry mistake worth reporting.'
            );
            Assert.areEqual(
                ErrorLogger.SEVERITY_WARNING,
                logged[0].Severity__c,
                'A collision is a warning: the job still did something sensible.'
            );
        }
    }

    @IsTest
    static void aPersonalSeasonalAddressMovesWithoutMovingTheHousehold() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Contact harper = AddressTestDataFactory.newContact('Harper', 'Garcia', garcia.Id);
            harper.MailingStreet = HOME_STREET;
            harper.MailingCity = HOME_CITY;
            insert harper;

            Address__c campus = seasonalAddress(null, 9, 1, 5, 31);
            campus.Contact__c = harper.Id;
            campus.Street__c = '1 University Drive';
            campus.City__c = 'Urbana';
            insert campus;

            Test.startTest();
            SeasonalAddressService.RunSummary summary = SeasonalAddressService.swapOwners(
                new Set<Id>{ harper.Id },
                Date.newInstance(2027, 10, 1)
            );
            Test.stopTest();

            Assert.areEqual(1, summary.movedIn, 'The student address should take over in October.');
            Contact moved = [SELECT MailingCity FROM Contact WHERE Id = :harper.Id];
            Assert.areEqual(
                'Urbana',
                moved.MailingCity,
                'A personal address writes that person mailing fields.'
            );
        }
    }

    @IsTest
    static void aWholeChunkOfHouseholdsSwapsInOneTransaction() {
        System.runAs(TestUsers.admin()) {
            // A whole chunk rather than two hundred households, because a chunk is the largest
            // number of owners the job ever handles in one transaction on purpose: each owner is
            // saved on its own so that half a swap can never leave a household with no address in
            // use (see SeasonalAddressWriter.save). This is the governor-limit proof for the shape
            // the job actually runs in.
            Integer chunk = SeasonalAddressBatch.CHUNK_SIZE;
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < chunk; i++) {
                Account household = AddressTestDataFactory.newHousehold('Snowbird ' + i);
                household.BillingStreet = HOME_STREET;
                household.BillingCity = HOME_CITY;
                households.add(household);
            }
            Database.insert(households, AccessLevel.SYSTEM_MODE);
            List<Address__c> winters = new List<Address__c>();
            Set<Id> ownerIds = new Set<Id>();
            for (Account household : households) {
                winters.add(seasonalAddress(household.Id, 11, 1, 3, 31));
                ownerIds.add(household.Id);
            }
            insert winters;

            Test.startTest();
            SeasonalAddressService.RunSummary summary = SeasonalAddressService.swapOwners(
                ownerIds,
                Date.newInstance(2027, 1, 15)
            );
            Test.stopTest();

            Assert.areEqual(
                chunk,
                summary.movedIn,
                'Every household in the chunk should have moved.'
            );
            Assert.areEqual(0, summary.failed, 'A full chunk should stay inside the limits.');
            Assert.areEqual(
                chunk,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Account__c IN :ownerIds AND Is_Default__c = TRUE AND Type__c = 'Seasonal'
                ],
                'Every household should have its seasonal address in use.'
            );
        }
    }

    // ------------------------------------------------------------------ the visible last run

    @IsTest
    static void recordingARunStoresWhenItFinishedAndWhatItDid() {
        System.runAs(TestUsers.admin()) {
            SeasonalAddressService.RunSummary summary = new SeasonalAddressService.RunSummary();
            summary.movedIn = 3;
            summary.movedBack = 2;
            summary.failed = 1;
            Datetime finishedAt = Datetime.newInstance(2027, 1, 15, 0, 30, 0);

            Test.startTest();
            SeasonalAddressService.recordRun(summary, finishedAt);
            Test.stopTest();

            Assert.areEqual(
                finishedAt,
                SeasonalAddressService.lastRun(),
                'The Hub reads the time the run finished from the settings record.'
            );
            String text = SeasonalAddressService.lastRunSummary();
            Assert.isTrue(
                text.contains('3') && text.contains('2') && text.contains('1'),
                'The summary should carry all three counts, and read: ' + text
            );
        }
    }

    @IsTest
    static void aRunThatDidNothingIsStillRecorded() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SeasonalAddressService.recordRun(
                new SeasonalAddressService.RunSummary(),
                Datetime.now()
            );
            Test.stopTest();

            Assert.isNotNull(
                SeasonalAddressService.lastRun(),
                'The job ran and had nothing to do, which is a different fact from the job not running.'
            );
            Assert.isTrue(
                SeasonalAddressService.lastRunSummary().contains('0'),
                'A run that moved nothing should say so rather than say nothing.'
            );
        }
    }

    @IsTest
    static void anOrgThatHasNotScheduledTheJobIsNeverStale() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Boolean stale = SeasonalAddressService.isStale();
            Test.stopTest();

            Assert.isFalse(
                stale,
                'An org that has not switched the job on has not missed a run, so it is not warned.'
            );
        }
    }

    // ------------------------------------------------------------------ fixtures

    /** The Garcia household with a home address in use and a winter address on file. */
    private class Fixture {
        public Id householdId;
        public Id homeId;
        public Id winterId;

        public List<Address__c> addresses() {
            return SeasonalAddressSelector.selectAllForOwners(new Set<Id>{ this.householdId });
        }

        /** Puts the winter address in use, as a season that has already started would have. */
        public void makeWinterCurrent() {
            update new List<Address__c>{
                new Address__c(
                    Id = this.homeId,
                    Is_Default__c = false,
                    Replaced_By_Seasonal__c = true
                ),
                new Address__c(Id = this.winterId, Is_Default__c = true)
            };
        }
    }

    private static Fixture winterInArizona(
        Integer startMonth,
        Integer startDay,
        Integer endMonth,
        Integer endDay
    ) {
        Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
        garcia.BillingStreet = HOME_STREET;
        garcia.BillingCity = HOME_CITY;
        Database.insert(garcia, AccessLevel.SYSTEM_MODE);

        Address__c winter = seasonalAddress(garcia.Id, startMonth, startDay, endMonth, endDay);
        insert winter;

        Fixture fixture = new Fixture();
        fixture.householdId = garcia.Id;
        fixture.winterId = winter.Id;
        for (Address__c address : [
            SELECT Id, Type__c
            FROM Address__c
            WHERE Account__c = :garcia.Id AND Type__c = 'Home'
            WITH SYSTEM_MODE
        ]) {
            fixture.homeId = address.Id;
        }
        Assert.isNotNull(
            fixture.homeId,
            'The household should have kept the address it was created with.'
        );
        return fixture;
    }

    private static Address__c seasonalAddress(
        Id accountId,
        Integer startMonth,
        Integer startDay,
        Integer endMonth,
        Integer endDay
    ) {
        return new Address__c(
            Account__c = accountId,
            Type__c = 'Seasonal',
            Street__c = WINTER_STREET,
            City__c = WINTER_CITY,
            State__c = 'AZ',
            Postal_Code__c = '85018',
            Country__c = 'United States',
            Seasonal_Start_Month__c = startMonth,
            Seasonal_Start_Day__c = startDay,
            Seasonal_End_Month__c = endMonth,
            Seasonal_End_Day__c = endDay
        );
    }

    private static Map<Id, Address__c> addressesById(Id ownerId) {
        return new Map<Id, Address__c>(
            [
                SELECT Id, Is_Default__c, Replaced_By_Seasonal__c, Type__c, City__c
                FROM Address__c
                WHERE Account__c = :ownerId OR Contact__c = :ownerId
                WITH SYSTEM_MODE
            ]
        );
    }

    /** The address a plan makes the default, or null when the plan makes none. */
    private static Id defaultIdIn(SeasonalAddressService.Plan plan) {
        for (Address__c change : plan.updates) {
            if (change.Is_Default__c == true) {
                return change.Id;
            }
        }
        return null;
    }

    /** The address a plan marks as waiting to come back, or null. */
    private static Id markedIdIn(SeasonalAddressService.Plan plan) {
        for (Address__c change : plan.updates) {
            if (change.Replaced_By_Seasonal__c == true) {
                return change.Id;
            }
        }
        return null;
    }
}
