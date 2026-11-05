/**
 * Where Used (C-59, admin guide where-used.md): the one call the Where Used window makes from the
 * Data Dictionary, Field Utilization and the Record Inspector. It needs Manage BarnCRM Settings,
 * because the answer lists setup records across the org, including private saved queries
 * (named only by their owner). Read only: BarnCRM never deletes a field.
 */
public with sharing class WhereUsedController {
    /** Every BarnCRM setup record that names the field, or the whole object when no field is given. */
    @AuraEnabled
    public static WhereUsedService.Result findReferences(String objectName, String fieldName) {
        try {
            if (!BarnCRMPermissions.canManageSettings()) {
                throw new WhereUsedService.WhereUsedException(
                    BarnHelp.text('Core', 'Core_WhereUsed_ErrorNoPermission')
                );
            }
            return WhereUsedService.find(objectName, fieldName);
        } catch (Exception caught) {
            throw UserErrors.wrap(
                caught,
                'Where Used',
                !(caught instanceof WhereUsedService.WhereUsedException)
            );
        }
    }
}
