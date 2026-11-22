/**
 * Core's C-10 sample data removal, as the stages SampleDataRemoveBatch runs one per
 * transaction (ADMIN-3). It runs after every installed module has removed its own records,
 * because a gift points at a person and a household.
 *
 * Each stage deletes one chunk (SampleDataLoader.REMOVE_CHUNK_SIZE records) of the first kind
 * that still has sample records, in this order, so nothing is left pointing at a record that
 * has just gone: connections, affiliations, addresses, contacts, then the accounts. Addresses
 * go before their people and households because the lookups on an address only clear when the
 * owner is deleted, which would leave the address behind with no owner. The number of stages
 * is the number of chunks each kind needs, counted when the batch starts. Every stage reads
 * its list again, so a record an earlier stage's automation already removed (the other side
 * of a connection, a household that upkeep tidied away) is never asked for a second time, and
 * a stage that finds nothing left does nothing.
 *
 * Everything the loader creates is either flagged itself, a detail of something that is, or an
 * address the address automation made for a sample person or household (found through its
 * owner, since an address has no flag of its own), which is what keeps this to "delete only
 * what the loader created". Records an administrator entered, and the addresses of people
 * they entered, have the box clear and are never in these lists.
 *
 * In junction mode the membership rows the load created go with the households: the Household
 * field on a household member record is a required lookup that cascades, so deleting a
 * household flagged Sample_Data__c takes its own membership rows with it.
 *
 * Nothing is kept between stages: each one reads what is left.
 *
 * Every kind is found and deleted through Core's `SampleDataRemover`, in system mode past
 * sharing, so any admin with Manage BarnCRM Settings removes the whole set, whoever loaded it
 * (SR-01, D-219). The conditions below are the sample tracking itself.
 */
public with sharing class SampleDataRemoveStages implements SampleDataStages {
	private static final String FLAGGED = 'Sample_Data__c = TRUE';

	/** Each kind as its object and condition, in removal order (one per address owner lookup). */
	private static final List<List<String>> KINDS = new List<List<String>>{
		new List<String>{ 'Relationship__c', FLAGGED },
		new List<String>{ 'Affiliation__c', FLAGGED },
		new List<String>{ 'Address__c', 'Account__c IN (SELECT Id FROM Account WHERE Sample_Data__c = TRUE)' },
		new List<String>{ 'Address__c', 'Contact__c IN (SELECT Id FROM Contact WHERE Sample_Data__c = TRUE)' },
		new List<String>{ 'Address__c', 'Person_Account__c IN (SELECT Id FROM Account WHERE Sample_Data__c = TRUE)' },
		new List<String>{ 'Contact', FLAGGED },
		new List<String>{ 'Account', FLAGGED }
	};

	public String name() {
		return 'SampleDataRemoveStages';
	}

	/** One stage per chunk of each kind of record, so the whole set is covered. */
	public Integer stageCount() {
		Integer stages = 0;
		for (List<String> kind : KINDS) {
			stages += chunksFor(SampleDataRemover.count(kind[0], kind[1]));
		}
		return stages;
	}

	public void runStage(Integer stage) {
		removeNextChunk();
	}

	/** Nothing follows Core's records: the card sees the batch end and reports Not loaded. */
	public void finish() {
		return;
	}

	/**
	 * Deletes the next chunk of sample records and returns true when it deleted anything.
	 * Static and public so the tests drive a stage without a batch.
	 */
	public static Boolean removeNextChunk() {
		for (List<String> kind : KINDS) {
			List<Id> chunk = SampleDataRemover.ids(kind[0], kind[1], null, SampleDataLoader.REMOVE_CHUNK_SIZE);
			if (!chunk.isEmpty()) {
				SampleDataRemover.remove(chunk, true);
				return true;
			}
		}
		return false;
	}

	private static Integer chunksFor(Integer recordCount) {
		Integer size = SampleDataLoader.REMOVE_CHUNK_SIZE;
		return (recordCount + size - 1) / size;
	}
}
