/**
 * The address panel's server side. Every method validates what it is given and returns a
 * typed result or a message the panel can show a person (plan Section 7.2).
 */
public with sharing class AddressController {
    /** One address as the panel draws it. */
    public class AddressView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String addressNumber;
        @AuraEnabled
        public String addressType;
        @AuraEnabled
        public String street;
        @AuraEnabled
        public String city;
        @AuraEnabled
        public String state;
        @AuraEnabled
        public String postalCode;
        @AuraEnabled
        public String country;
        @AuraEnabled
        public Boolean isDefault;
        @AuraEnabled
        public Boolean isSeasonal;
        @AuraEnabled
        public String seasonalStart;
        @AuraEnabled
        public String seasonalEnd;
        @AuraEnabled
        public Boolean isSeasonalActiveToday;
        @AuraEnabled
        public String verificationStatus;
    }

    /**
     * Every address on file for a household, an organization, or a person, with the one
     * in use first.
     */
    @AuraEnabled(cacheable=true)
    public static List<AddressView> getAddresses(Id ownerId) {
        if (ownerId == null) {
            throw messageFor(Label.Core_Address_OwnerRequired);
        }
        try {
            return toViews(AddressSelector.selectByOwnerIds(new Set<Id>{ ownerId }));
        } catch (Exception e) {
            ErrorLogger.log(e, 'AddressController.getAddresses');
            throw messageFor(Label.Core_Address_LoadFailed);
        }
    }

    /**
     * Makes one address the default for its owner and returns that owner's addresses as
     * they now stand. Clearing the previous default and copying the new one into the
     * standard address fields is the trigger's work, not this method's.
     */
    @AuraEnabled
    public static List<AddressView> setDefault(Id addressId) {
        if (addressId == null) {
            throw messageFor(Label.Core_Address_NotFound);
        }
        List<Address__c> found = AddressSelector.selectByIds(new Set<Id>{ addressId });
        if (found.isEmpty()) {
            throw messageFor(Label.Core_Address_NotFound);
        }
        Address__c address = found[0];
        Id ownerId = AddressService.ownerIdOf(address);
        if (ownerId == null) {
            throw messageFor(Label.Core_Address_OwnerRequired);
        }
        try {
            Database.update(
                new List<Address__c>{ new Address__c(Id = addressId, Is_Default__c = true) },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            ErrorLogger.log(e, 'AddressController.setDefault');
            throw messageFor(Label.Core_Address_SetDefaultFailed);
        }
        return toViews(AddressSelector.selectByOwnerIds(new Set<Id>{ ownerId }));
    }

    private static List<AddressView> toViews(List<Address__c> addresses) {
        List<AddressView> views = new List<AddressView>();
        for (Address__c address : addresses) {
            AddressView view = new AddressView();
            view.id = address.Id;
            view.addressNumber = address.Name;
            view.addressType = address.Type__c;
            view.street = address.Street__c;
            view.city = address.City__c;
            view.state = address.State__c;
            view.postalCode = address.Postal_Code__c;
            view.country = address.Country__c;
            view.isDefault = address.Is_Default__c == true;
            view.isSeasonal = address.Type__c == AddressService.TYPE_SEASONAL;
            view.seasonalStart = monthAndDay(
                address.Seasonal_Start_Month__c,
                address.Seasonal_Start_Day__c
            );
            view.seasonalEnd = monthAndDay(
                address.Seasonal_End_Month__c,
                address.Seasonal_End_Day__c
            );
            view.isSeasonalActiveToday = AddressService.isSeasonalActiveToday(address);
            view.verificationStatus = address.Verification_Status__c;
            views.add(view);
        }
        return views;
    }

    /** "January 1", in the reader's own language, from the two numbers we store. */
    private static String monthAndDay(Decimal month, Decimal day) {
        if (month == null || day == null || month < 1 || month > 12 || day < 1 || day > 31) {
            return null;
        }
        Integer safeDay = Math.min(day.intValue(), 28);
        Datetime sample = Datetime.newInstance(2001, month.intValue(), safeDay, 12, 0, 0);
        return sample.format('MMMM') + ' ' + String.valueOf(day.intValue());
    }

    private static AuraHandledException messageFor(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
