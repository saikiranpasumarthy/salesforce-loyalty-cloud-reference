/**
 * @description Parses inbound RCC file rows and validates staging records before batch processing.
 *
 * Input: CSV row from the RCC card provider file
 * Output: RCC_Import_Record__c staging record
 *
 * EXPECTED CSV COLUMN ORDER:
 *   CardNumber, CardStatus, CardType, Email, Phone, FirstName, LastName, ImportDate
 */
public with sharing class RCCRecordParser {

    public class ValidationResult {
        public Boolean isValid       { get; set; }
        public String  errorMessage  { get; set; }
        public ValidationResult(Boolean valid, String msg) {
            this.isValid      = valid;
            this.errorMessage = msg;
        }
    }

    /**
     * @description Parses a single CSV row into a staging RCC_Import_Record__c.
     *              Does not insert the record — callers batch-insert after parsing all rows.
     *
     * @param csvRow Single comma-delimited CSV row (values may be quoted)
     * @return       Populated RCC_Import_Record__c (not yet inserted)
     */
    public static RCC_Import_Record__c parseRecord(String csvRow) {
        if (String.isBlank(csvRow)) {
            throw new IllegalArgumentException('Empty CSV row provided to parseRecord');
        }

        List<String> cols = splitCsvRow(csvRow);
        if (cols.size() < 4) {
            throw new IllegalArgumentException('CSV row has insufficient columns: ' + cols.size());
        }

        RCC_Import_Record__c rec = new RCC_Import_Record__c();
        rec.Card_Number__c  = cols[0].trim();
        rec.Status__c       = cols[1].trim();   // Active | Inactive | Cancelled
        rec.Member_Type__c  = cols[2].trim();   // Retail | Pro
        rec.Email__c        = cols[3].trim().toLowerCase();

        return rec;
    }

    /**
     * @description Validates a staging record's required fields before processing.
     *              Called inside RCCCardBatchProcessor.execute() to skip invalid records gracefully.
     */
    public static ValidationResult validateRecord(RCC_Import_Record__c rec) {
        List<String> issues = new List<String>();

        if (String.isBlank(rec.Card_Number__c)) issues.add('Card number is blank');
        if (String.isBlank(rec.Status__c)) issues.add('Card status is blank');
        if (!new Set<String>{'Active','Inactive','Cancelled'}.contains(rec.Status__c)) {
            issues.add('Invalid card status: ' + rec.Status__c);
        }
        if (String.isBlank(rec.Email__c)) {
            issues.add('Email is required');
        }
        if (String.isNotBlank(rec.Email__c) && !rec.Email__c.contains('@')) {
            issues.add('Invalid email format: ' + rec.Email__c);
        }

        if (issues.isEmpty()) {
            return new ValidationResult(true, null);
        }
        return new ValidationResult(false, String.join(issues, '; '));
    }

    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Simple CSV parser that handles quoted fields containing commas.
     */
    @TestVisible
    private static List<String> splitCsvRow(String row) {
        List<String> result = new List<String>();
        String remaining = row;
        while (remaining.length() > 0) {
            if (remaining.startsWith('"')) {
                Integer closeQuote = remaining.indexOf('"', 1);
                while (closeQuote < remaining.length() - 1 && remaining.charAt(closeQuote + 1) == '"'.charAt(0)) {
                    closeQuote = remaining.indexOf('"', closeQuote + 2);
                }
                result.add(remaining.substring(1, closeQuote).replace('""', '"'));
                remaining = closeQuote + 2 < remaining.length() ? remaining.substring(closeQuote + 2) : '';
            } else {
                Integer comma = remaining.indexOf(',');
                if (comma == -1) {
                    result.add(remaining);
                    break;
                }
                result.add(remaining.left(comma));
                remaining = remaining.substring(comma + 1);
            }
        }
        return result;
    }
}
