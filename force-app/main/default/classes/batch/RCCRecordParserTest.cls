/**
 * @description Tests for RCCRecordParser.
 */
@IsTest
private class RCCRecordParserTest {

    @IsTest
    static void testParseRecord_validRow() {
        String csvRow = 'RCC-001,Active,Retail,test@example.com,5551234567,John,Doe,2025-01-01';

        Test.startTest();
        RCC_Import_Record__c rec = RCCRecordParser.parseRecord(csvRow);
        Test.stopTest();

        System.assertEquals('RCC-001',          rec.Card_Number__c);
        System.assertEquals('Active',           rec.Card_Status__c);
        System.assertEquals('Retail',           rec.Card_Type__c);
        System.assertEquals('test@example.com', rec.Email__c);
        System.assertEquals('John',             rec.First_Name__c);
        System.assertEquals('Doe',              rec.Last_Name__c);
        System.assertEquals('Pending',          rec.Processing_Status__c);
    }

    @IsTest
    static void testParseRecord_quotedFields() {
        String csvRow = '"RCC-002","Active","Pro","quoted,email@example.com",5559876543,"Jane","Smith"';

        Test.startTest();
        RCC_Import_Record__c rec = RCCRecordParser.parseRecord(csvRow);
        Test.stopTest();

        System.assertEquals('RCC-002', rec.Card_Number__c);
        System.assertEquals('quoted,email@example.com', rec.Email__c);
    }

    @IsTest
    static void testParseRecord_emptyRow_throws() {
        Test.startTest();
        try {
            RCCRecordParser.parseRecord('');
            System.assert(false, 'Should have thrown');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Empty'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testParseRecord_insufficientColumns_throws() {
        Test.startTest();
        try {
            RCCRecordParser.parseRecord('RCC-001,Active');
            System.assert(false, 'Should have thrown');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('insufficient columns'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateRecord_valid() {
        RCC_Import_Record__c rec = new RCC_Import_Record__c(
            Card_Number__c = 'RCC-001',
            Card_Status__c = 'Active',
            Email__c       = 'valid@example.com',
            Last_Name__c   = 'Smith'
        );

        Test.startTest();
        RCCRecordParser.ValidationResult result = RCCRecordParser.validateRecord(rec);
        Test.stopTest();

        System.assertEquals(true, result.isValid);
        System.assertEquals(null, result.errorMessage);
    }

    @IsTest
    static void testValidateRecord_missingCardNumber() {
        RCC_Import_Record__c rec = new RCC_Import_Record__c(
            Card_Status__c = 'Active',
            Email__c       = 'test@example.com',
            Last_Name__c   = 'Smith'
        );

        Test.startTest();
        RCCRecordParser.ValidationResult result = RCCRecordParser.validateRecord(rec);
        Test.stopTest();

        System.assertEquals(false, result.isValid);
        System.assert(result.errorMessage.contains('Card number'));
    }

    @IsTest
    static void testValidateRecord_invalidStatus() {
        RCC_Import_Record__c rec = new RCC_Import_Record__c(
            Card_Number__c = 'RCC-001',
            Card_Status__c = 'Unknown',
            Email__c       = 'test@example.com',
            Last_Name__c   = 'Smith'
        );

        Test.startTest();
        RCCRecordParser.ValidationResult result = RCCRecordParser.validateRecord(rec);
        Test.stopTest();

        System.assertEquals(false, result.isValid);
        System.assert(result.errorMessage.containsIgnoreCase('Invalid card status'));
    }

    @IsTest
    static void testValidateRecord_noEmailOrPhone() {
        RCC_Import_Record__c rec = new RCC_Import_Record__c(
            Card_Number__c = 'RCC-001',
            Card_Status__c = 'Active',
            Last_Name__c   = 'Smith'
        );

        Test.startTest();
        RCCRecordParser.ValidationResult result = RCCRecordParser.validateRecord(rec);
        Test.stopTest();

        System.assertEquals(false, result.isValid);
        System.assert(result.errorMessage.containsIgnoreCase('Email or Phone'));
    }
}
