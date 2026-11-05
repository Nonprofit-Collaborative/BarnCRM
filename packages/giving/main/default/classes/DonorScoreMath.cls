/**
 * The arithmetic of donor scoring (feature G-19, canonical model R-DT2 to R-DT4), with no org
 * access at all: numbers in, numbers and a segment name out.
 *
 * Keeping it separate from `DonorScoreService` is what makes the rules testable as plain
 * functions and portable to another platform (plan 9.9). The cutoffs are four numbers in a text
 * setting; a value that is not four numbers in the right order is ignored in favour of the
 * default, so a typo in the console never stops donors being scored.
 */
public with sharing class DonorScoreMath {
	public static final List<Decimal> DEFAULT_RECENCY_DAYS = new List<Decimal>{ 90, 180, 365, 730 };
	public static final List<Decimal> DEFAULT_FREQUENCY_GIFTS = new List<Decimal>{ 6, 4, 2, 1 };
	public static final List<Decimal> DEFAULT_MONETARY_AMOUNTS = new List<Decimal>{
		5000,
		1000,
		250,
		50
	};

	public static final String CHAMPION = 'Champion';
	public static final String LOYAL = 'Loyal';
	public static final String PROMISING = 'Promising';
	public static final String AT_RISK = 'At Risk';
	public static final String LAPSED = 'Lapsed';
	public static final String OCCASIONAL = 'Occasional';

	/**
	 * Four cutoffs from comma-separated text, or the defaults when the text is blank, is not four
	 * numbers, or runs the wrong way (rising for days, falling for gifts and amounts).
	 */
	public static List<Decimal> cutoffs(String text, List<Decimal> defaults, Boolean rising) {
		if (String.isBlank(text)) {
			return defaults;
		}
		List<Decimal> parsed = new List<Decimal>();
		for (String part : text.split(',')) {
			String trimmed = part.trim();
			if (!trimmed.isNumeric() && !isDecimal(trimmed)) {
				return defaults;
			}
			parsed.add(Decimal.valueOf(trimmed));
		}
		if (parsed.size() != 4) {
			return defaults;
		}
		for (Integer i = 1; i < 4; i++) {
			if (rising ? parsed[i] <= parsed[i - 1] : parsed[i] >= parsed[i - 1]) {
				return defaults;
			}
		}
		return parsed;
	}

	/** 5 when the days are at or under the first cutoff, down to 1 beyond the fourth. */
	public static Integer recencyScore(Integer days, List<Decimal> cutoffs) {
		for (Integer i = 0; i < 4; i++) {
			if (days <= cutoffs[i]) {
				return 5 - i;
			}
		}
		return 1;
	}

	/** 5 when the value reaches the first cutoff, down to 1 below the fourth. A missing value is 0. */
	public static Integer highScore(Decimal value, List<Decimal> cutoffs) {
		Decimal amount = value == null ? 0 : value;
		for (Integer i = 0; i < 4; i++) {
			if (amount >= cutoffs[i]) {
				return 5 - i;
			}
		}
		return 1;
	}

	/** The first segment that fits (R-DT4). */
	public static String segment(Integer recency, Integer frequency, Integer monetary) {
		if (recency >= 4 && frequency >= 4 && monetary >= 4) {
			return CHAMPION;
		}
		if (recency >= 3 && frequency >= 3) {
			return LOYAL;
		}
		if (recency >= 4 && frequency <= 2) {
			return PROMISING;
		}
		if (recency <= 2 && (frequency >= 3 || monetary >= 4)) {
			return AT_RISK;
		}
		if (recency <= 2) {
			return LAPSED;
		}
		return OCCASIONAL;
	}

	private static Boolean isDecimal(String text) {
		try {
			Decimal.valueOf(text);
			return true;
		} catch (Exception notANumber) {
			return false;
		}
	}
}
