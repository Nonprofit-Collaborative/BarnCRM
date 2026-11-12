/**
 * The NPSP Gifts kit's rows (MIG-05, canonical model R-MK1), named by the kit `NPSP_Gifts`.
 * One gift per won Opportunity, keyed by the Opportunity so the Opportunity mirror never copies
 * it again: the donor by record Id (the primary contact of an individual's gift, else the
 * account), the payment method and reference of its first paid payment, and its General
 * Accounting Unit allocations as the split. The soft credit steps keep one row per record and
 * get BarnCRM's role and the amount (a partial soft credit's own amount). NPSP is read by
 * describe only, in the running user's access; its names are text here, written with `~` for
 * the namespace separator and built at run time, and Mirror may name standard objects as text
 * (plan Section 4.2). Core builds this class by name (ADR-0017).
 */
@NamespaceAccessible
public with sharing class NpspGiftsKit implements MigrationKitExtension {
	@TestVisible
	private static final String KIT = 'NPSP_Gifts';
	/** The soft credit roles BarnCRM has besides Household Member and Other. */
	private static final List<String> ROLES = new List<String>{
		'Matched Donor',
		'Solicitor',
		'Honoree',
		'Influencer'
	};

	/** One part of a gift's split: a fund's name and amount (also the Nonprofit Cloud kit's). */
	public class Part {
		String fund;
		Decimal amount;
		public Part(String fund, Decimal amount) {
			this.fund = fund;
			this.amount = amount;
		}
	}

	@NamespaceAccessible
	public NpspGiftsKit() {
		// Built by name from the kit's Extension Class; holds no state.
		return;
	}

	@NamespaceAccessible
	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		if (stepKey == 'appeals') {
			return null;
		}
		List<Map<String, Object>> rows = new MigrationKitService.Source(
				MigrationKitService.stepNamed(MigrationKitService.kitNamed(KIT), stepKey)
			)
			.rows(records);
		if (stepKey == 'gifts') {
			shapeGifts(rows);
		} else {
			shapeCredits(rows);
		}
		return rows;
	}

	@NamespaceAccessible
	public MigrationCheck verify(String stepKey) {
		// Every step keeps one row per record, so the Assistant's own counts are the check.
		return null;
	}

	private static void shapeGifts(List<Map<String, Object>> rows) {
		Set<String> ids = column(rows, 'Id');
		Map<String, List<String>> payments = new Map<String, List<String>>();
		for (
			SObject payment : read(
				'npe01~OppPayment__c',
				'SELECT npe01~Opportunity__c, npe01~Payment_Method__c, npe01~Check_Reference_Number__c' +
					' FROM npe01~OppPayment__c WHERE npe01~Opportunity__c IN :ids' +
					' AND npe01~Paid__c = true ORDER BY npe01~Payment_Date__c',
				ids
			)
		) {
			String key = (String) payment.get(n('npe01~Opportunity__c'));
			if (!payments.containsKey(key)) {
				payments.put(
					key,
					new List<String>{
						(String) payment.get(n('npe01~Payment_Method__c')),
						(String) payment.get(n('npe01~Check_Reference_Number__c'))
					}
				);
			}
		}
		Map<String, List<Part>> parts = new Map<String, List<Part>>();
		for (
			SObject allocation : read(
				'npsp~Allocation__c',
				'SELECT npsp~Opportunity__c, npsp~General_Accounting_Unit__r.Name, npsp~Amount__c' +
					' FROM npsp~Allocation__c WHERE npsp~Opportunity__c IN :ids' +
					' ORDER BY npsp~Amount__c DESC NULLS LAST',
				ids
			)
		) {
			String key = (String) allocation.get(n('npsp~Opportunity__c'));
			if (!parts.containsKey(key)) {
				parts.put(key, new List<Part>());
			}
			SObject unit = allocation.getSObject(n('npsp~General_Accounting_Unit__r'));
			parts.get(key)
				.add(
					new Part(
						unit == null ? null : (String) unit.get('Name'),
						(Decimal) allocation.get(n('npsp~Amount__c'))
					)
				);
		}
		for (Map<String, Object> row : rows) {
			String key = (String) row.get('Id');
			giftRow(row, payments.get(key), parts.get(key));
		}
	}

	/**
	 * One Opportunity's row as a gift: donor choice and Id, payment method (Other when it has no
	 * paid payment), reference, and the split.
	 */
	@TestVisible
	private static void giftRow(Map<String, Object> row, List<String> payment, List<Part> split) {
		String primary = (String) row.get('npsp.Primary_Contact__c');
		Boolean person =
			row.get('Account.npe01.SYSTEM_IsIndividual__c') == 'true' && String.isNotBlank(primary);
		row.put('Donor', person ? 'Contact1' : 'Organization');
		row.put('ContactId', person ? primary : '');
		row.put('OrganizationId', person ? '' : row.get('AccountId'));
		row.put('OpportunityId', row.get('Id'));
		String method = payment == null ? null : payment[0];
		row.put('Method', String.isBlank(method) ? 'Other' : method);
		row.put('Reference', payment == null || payment[1] == null ? '' : payment[1]);
		putSplit(row, split, (String) row.get('Amount'));
	}

	/**
	 * A gift's split as the Fund1 to Fund5 and Amount1 to Amount5 columns. A single part of the
	 * whole amount is the gift's one fund; more than five parts keep the first five, so the
	 * split no longer adds up and the preview rejects the row where it can be seen.
	 */
	public static void putSplit(Map<String, Object> row, List<Part> split, String amount) {
		if (split == null || split.isEmpty()) {
			return;
		}
		if (
			split.size() == 1 &&
			split[0].amount != null &&
			String.isNotBlank(amount) &&
			split[0].amount == Decimal.valueOf(amount)
		) {
			row.put('Fund1', split[0].fund);
			return;
		}
		for (Integer index = 0; index < Math.min(split.size(), 5); index++) {
			row.put('Fund' + (index + 1), split[index].fund);
			row.put(
				'Amount' + (index + 1),
				split[index].amount == null ? '' : split[index].amount.toPlainString()
			);
		}
	}

	private static void shapeCredits(List<Map<String, Object>> rows) {
		Set<String> ids = column(rows, 'OpportunityId');
		Map<String, Decimal> partial = new Map<String, Decimal>();
		for (
			SObject credit : read(
				'npsp~Partial_Soft_Credit__c',
				'SELECT npsp~Opportunity__c, npsp~Contact__c, npsp~Amount__c' +
				' FROM npsp~Partial_Soft_Credit__c WHERE npsp~Opportunity__c IN :ids',
				ids
			)
		) {
			partial.put(
				(String) credit.get(n('npsp~Opportunity__c')) +
				(String) credit.get(n('npsp~Contact__c')),
				(Decimal) credit.get(n('npsp~Amount__c'))
			);
		}
		for (Map<String, Object> row : rows) {
			Boolean ofAccount = row.containsKey('npsp.Role__c');
			creditRow(
				row,
				(String) row.get(ofAccount ? 'npsp.Role__c' : 'Role'),
				ofAccount
					? null
					: partial.get((String) row.get('OpportunityId') + (String) row.get('ContactId'))
			);
		}
	}

	/**
	 * A soft credit row's BarnCRM role (an NPSP role BarnCRM lacks becomes Other, keeping its
	 * name as the custom role) and, for a contact's credit, its amount: the partial soft
	 * credit's when there is one, else the whole Opportunity's.
	 */
	@TestVisible
	private static void creditRow(Map<String, Object> row, String role, Decimal partialAmount) {
		putRole(row, role);
		if (!row.containsKey('npsp.Role__c')) {
			row.put(
				'Amount',
				partialAmount != null
					? partialAmount.toPlainString()
					: row.get('Opportunity.Amount')
			);
		}
	}

	/**
	 * A soft credit's CreditRole and CustomRole columns: BarnCRM's role of the same name, else
	 * Other keeping the source's name (Soft Credit when blank) as the custom role.
	 */
	public static void putRole(Map<String, Object> row, String role) {
		String chosen = 'Other';
		for (String known : ROLES) {
			chosen = known.equalsIgnoreCase(String.isBlank(role) ? '' : role.trim())
				? known
				: chosen;
		}
		row.put('CreditRole', chosen);
		row.put('CustomRole', chosen != 'Other' ? '' : String.isBlank(role) ? 'Soft Credit' : role);
	}

	/** The distinct non-blank values of one column. */
	public static Set<String> column(List<Map<String, Object>> rows, String name) {
		Set<String> result = new Set<String>();
		for (Map<String, Object> row : rows) {
			if (String.isNotBlank((String) row.get(name))) {
				result.add((String) row.get(name));
			}
		}
		return result;
	}

	/** An NPSP name as the platform writes it: `~` stands for the namespace separator. */
	private static String n(String written) {
		return written.replace('~', '__');
	}

	/** The records of an NPSP object, in the user's access; none when NPSP lacks the object. */
	private static List<SObject> read(String objectName, String query, Set<String> ids) {
		if (
			ids.isEmpty() ||
			!NamespaceUtil.globalDescribe().containsKey(n(objectName).toLowerCase())
		) {
			return new List<SObject>();
		}
		// Every name is NPSP's own, fixed here; the only value is a bind.
		return Database.queryWithBinds(
			n(query),
			new Map<String, Object>{ 'ids' => ids },
			AccessLevel.USER_MODE
		);
	}
}
