/**
 * The funds, appeals and brands a gift import's rows name, found in one query each per chunk
 * (R-GI3, R-GI4). A word is matched to a record by identifier, then by name, then (for a
 * fund) by accounting code, ignoring case; a word two records answer to is ambiguous and
 * rejects the row rather than guessing.
 */
public with sharing class GiftImportReferences {
	/** Finds each row's funds, appeal and brand, and refuses a row naming one not there. */
	public static void resolve(List<GiftImportRow> gifts) {
		resolveFunds(pending(gifts));
		resolveNamed(pending(gifts), false);
		resolveNamed(pending(gifts), true);
		requireADefaultFund(pending(gifts));
	}

	private static List<GiftImportRow> pending(List<GiftImportRow> gifts) {
		List<GiftImportRow> result = new List<GiftImportRow>();
		for (GiftImportRow item : gifts) {
			if (item.error == null) {
				result.add(item);
			}
		}
		return result;
	}

	private static void resolveFunds(List<GiftImportRow> gifts) {
		Set<String> words = new Set<String>();
		for (GiftImportRow item : gifts) {
			for (GiftImportRow.Part part : partsOf(item)) {
				words.add(part.fund);
			}
		}
		if (words.isEmpty()) {
			return;
		}
		Lookup funds = new Lookup();
		for (Fund__c fund : GiftImportSelector.selectFundsNamed(words)) {
			funds.add(fund.Id, fund.Name, fund.Accounting_Code__c);
		}
		for (GiftImportRow item : gifts) {
			for (GiftImportRow.Part part : partsOf(item)) {
				part.fundId = funds.find(part.fund);
				if (part.fundId == null && item.error == null) {
					item.error = String.format(
						funds.isAmbiguous(part.fund)
							? Label.Giving_Import_ErrorFundAmbiguous
							: Label.Giving_Import_ErrorFundNotFound,
						new List<String>{ part.fund }
					);
				}
			}
		}
	}

	private static List<GiftImportRow.Part> partsOf(GiftImportRow item) {
		List<GiftImportRow.Part> result = new List<GiftImportRow.Part>(item.parts);
		if (item.singleFund != null) {
			result.add(item.singleFund);
		}
		return result;
	}

	/** The appeal (R-GI3) or, C-47d, the brand each row names, by identifier or name. */
	private static void resolveNamed(List<GiftImportRow> gifts, Boolean brands) {
		Set<String> words = new Set<String>();
		for (GiftImportRow item : gifts) {
			String word = brands ? item.brand : item.appeal;
			if (word != null) {
				words.add(word);
			}
		}
		if (words.isEmpty()) {
			return;
		}
		Lookup found = new Lookup();
		for (
			SObject record : brands
				? (List<SObject>) GiftImportSelector.selectBrandsNamed(words)
				: (List<SObject>) GiftImportSelector.selectAppealsNamed(words)
		) {
			found.add(record.Id, (String) record.get('Name'), null);
		}
		for (GiftImportRow item : gifts) {
			String word = brands ? item.brand : item.appeal;
			if (word == null) {
				continue;
			}
			Id recordId = found.find(word);
			if (brands) {
				item.brandId = recordId;
			} else {
				item.appealId = recordId;
			}
			if (recordId == null) {
				item.error = String.format(
					notFound(brands, found.isAmbiguous(word)),
					new List<String>{ word }
				);
			}
		}
	}

	private static String notFound(Boolean brands, Boolean ambiguous) {
		if (brands) {
			return ambiguous
				? BarnHelp.text('Giving', 'Giving_Import_ErrorBrandAmbiguous')
				: BarnHelp.text('Giving', 'Giving_Import_ErrorBrandNotFound');
		}
		return ambiguous
			? Label.Giving_Import_ErrorAppealAmbiguous
			: Label.Giving_Import_ErrorAppealNotFound;
	}

	/**
	 * A gift with no fund goes to the default fund (R-GA2); where there is none the gift
	 * trigger refuses it, so the dry run says so first.
	 */
	private static void requireADefaultFund(List<GiftImportRow> gifts) {
		Boolean needed = false;
		for (GiftImportRow item : gifts) {
			needed = needed || (item.singleFund == null && !item.isSplit());
		}
		if (!needed || GiftService.resolveDefaultFundId() != null) {
			return;
		}
		for (GiftImportRow item : gifts) {
			if (item.singleFund == null && !item.isSplit()) {
				item.error = Label.Giving_Gift_DefaultFundMissing;
			}
		}
	}

	/**
	 * Records found by identifier, by name or by a code, each matched ignoring case. A word
	 * two records answer to is ambiguous and finds nothing.
	 */
	private class Lookup {
		private final Set<Id> ids = new Set<Id>();
		private final Map<String, Set<Id>> byName = new Map<String, Set<Id>>();
		private final Map<String, Set<Id>> byCode = new Map<String, Set<Id>>();

		void add(Id recordId, String name, String code) {
			ids.add(recordId);
			index(byName, name, recordId);
			index(byCode, code, recordId);
		}

		private void index(Map<String, Set<Id>> byWord, String word, Id recordId) {
			if (String.isBlank(word)) {
				return;
			}
			String key = word.trim().toLowerCase();
			if (!byWord.containsKey(key)) {
				byWord.put(key, new Set<Id>());
			}
			byWord.get(key).add(recordId);
		}

		Id find(String word) {
			if (String.isBlank(word)) {
				return null;
			}
			for (Id recordId : ids) {
				String text = String.valueOf(recordId);
				if (text.equals(word) || text.left(15).equals(word)) {
					return recordId;
				}
			}
			String key = word.trim().toLowerCase();
			for (Map<String, Set<Id>> byWord : new List<Map<String, Set<Id>>>{ byName, byCode }) {
				Set<Id> found = byWord.get(key);
				if (found != null && !found.isEmpty()) {
					return found.size() == 1 ? new List<Id>(found)[0] : null;
				}
			}
			return null;
		}

		Boolean isAmbiguous(String word) {
			String key = word == null ? null : word.trim().toLowerCase();
			Set<Id> named = byName.get(key);
			Set<Id> coded = byCode.get(key);
			return (named != null && named.size() > 1) ||
				((named == null || named.isEmpty()) &&
				coded != null &&
				coded.size() > 1);
		}
	}
}
