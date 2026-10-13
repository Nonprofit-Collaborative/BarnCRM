/**
 * The Current and Former status a relationship or an affiliation carries, and the one rule
 * that settles it against the dates (R-RL5, R-AF4). Held once so the two domains cannot
 * drift apart.
 */
public with sharing class ConnectionStatus {
    public static final String CURRENT = 'Current';
    public static final String FORMER = 'Former';

    /**
     * The status a record should carry after a save. A blank status becomes Current. An end
     * date always means Former. Clearing an end date (the previous version had one, this one
     * does not) returns the record to Current, because that edit means "this is on again". A
     * record with no end date that someone deliberately marked Former stays as marked.
     */
    public static String settle(String status, Date endDate, Date previousEndDate) {
        if (endDate != null) {
            return FORMER;
        }
        if (previousEndDate != null) {
            return CURRENT;
        }
        return String.isBlank(status) ? CURRENT : status;
    }
}
