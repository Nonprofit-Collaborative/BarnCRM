/**
 * Health Check's data skew questions (D-200 P12): one user with a role owning so many
 * records that a role or sharing change locks them all (ownership skew). Lookup skew, many
 * child rows under one parent, is asked by the module that owns the parent (Giving asks it
 * of Funds and Appeals), because Core cannot name those objects.
 *
 * Counting every owner's records would read every row, and a count over 50,000 rows is a
 * limit no try can catch. So the owners of the newest records are sampled, the ones with a
 * role are counted one at a time, each count stops one past the threshold, and a count only
 * runs while the transaction has the rows to spare.
 */
@NamespaceAccessible
public with sharing class HealthCheckSkew {
	/** Salesforce's own guidance: past 10,000 records per owner or parent, skew sets in. */
	@TestVisible
	private static Integer skewAt = 10000;

	/** The count past which an owner or a parent is skewed. */
	@NamespaceAccessible
	public static Integer threshold() {
		return skewAt;
	}

	private static final Integer SAMPLE_SIZE = 200;
	private static final Integer OWNERS_COUNTED = 3;
	private static final Integer ROWS_KEPT_SPARE = 5000;

	/** Households owned by one user with a role. */
	public class HouseholdOwnershipCheck implements HealthCheckService.Check {
		public HealthCheckService.Finding run() {
			Id householdType = HouseholdService.householdRecordTypeId();
			if (householdType == null) {
				return null;
			}
			return ownership(
				'household_ownership_skew',
				'Account',
				'RecordTypeId = :recordTypeId',
				new Map<String, Object>{ 'recordTypeId' => householdType },
				Schema.SObjectType.Account.getLabelPlural()
			);
		}
	}

	/**
	 * The ownership skew finding for one object, or null when no sampled owner with a role
	 * owns more than threshold() of its records.
	 * @param key the finding key
	 * @param objectName the object's API name
	 * @param condition a filter with bind names only, or null for every record
	 * @param binds the filter's binds
	 * @param pluralLabel what the records are called, for the finding
	 */
	@NamespaceAccessible
	public static HealthCheckService.Finding ownership(
		String key,
		String objectName,
		String condition,
		Map<String, Object> binds,
		String pluralLabel
	) {
		Map<String, Object> allBinds = binds == null
			? new Map<String, Object>()
			: new Map<String, Object>(binds);
		String filter = String.isBlank(condition) ? '' : ' WHERE ' + condition;
		Map<Id, Integer> sampled = new Map<Id, Integer>();
		for (
			SObject row : Database.queryWithBinds(
				'SELECT OwnerId FROM ' +
					objectName +
					filter +
					' ORDER BY CreatedDate DESC LIMIT ' +
					SAMPLE_SIZE,
				allBinds,
				AccessLevel.SYSTEM_MODE
			)
		) {
			Id owner = (Id) row.get('OwnerId');
			sampled.put(owner, sampled.containsKey(owner) ? sampled.get(owner) + 1 : 1);
		}
		Integer counted = 0;
		for (User owner : [
			SELECT Id, Name
			FROM User
			WHERE Id IN :sampled.keySet() AND UserRoleId != NULL
			WITH SYSTEM_MODE
			LIMIT 50
		]) {
			if (counted >= OWNERS_COUNTED || !rowsToSpare()) {
				break;
			}
			counted++;
			allBinds.put('skewOwner', owner.Id);
			Integer owned = Database.countQueryWithBinds(
				'SELECT COUNT() FROM ' +
					objectName +
					(filter == '' ? ' WHERE ' : filter + ' AND ') +
					'OwnerId = :skewOwner LIMIT ' +
					(skewAt + 1),
				allBinds,
				AccessLevel.SYSTEM_MODE
			);
			if (owned > skewAt) {
				return new HealthCheckService.Finding(
					key,
					String.format(
						BarnHelp.text('Core', 'Core_HealthCheck_OwnershipSkewTitle'),
						new List<Object>{ pluralLabel }
					),
					String.format(
						BarnHelp.text('Core', 'Core_HealthCheck_OwnershipSkewDetail'),
						new List<Object>{ owner.Name, skewAt.format(), pluralLabel }
					),
					HealthCheckService.SEVERITY_WARNING,
					HealthCheckService.CATEGORY_SETTINGS
				);
			}
		}
		return null;
	}

	private static Boolean rowsToSpare() {
		return Limits.getLimitQueryRows() - Limits.getQueryRows() > skewAt + 1 + ROWS_KEPT_SPARE;
	}
}
