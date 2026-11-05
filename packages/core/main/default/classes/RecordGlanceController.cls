/**
 * The server side of the glance card on Core's Contact and Account record pages (people-14,
 * ADR-0167). Core has nothing of its own to show there: it
 * asks every installed module (`RecordGlanceExtensions`) and returns their cards, so an org with
 * Core alone gets an empty list and the card draws nothing.
 *
 * Not cacheable on purpose: a module that fails is logged, which a cacheable call could not do,
 * and the figures should move as soon as a gift is saved.
 */
public with sharing class RecordGlanceController {
	@AuraEnabled
	public static List<RecordGlance.Card> getCards(Id recordId) {
		return RecordGlanceExtensions.cardsFor(recordId);
	}
}
