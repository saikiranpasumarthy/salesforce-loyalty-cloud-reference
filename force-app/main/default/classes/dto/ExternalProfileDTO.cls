/**
 * @description Inbound profile payload received from external systems (POS, batch file, web).
 *              Used by ContactMatchService.matchOrCreateContact as the input type.
 */
public with sharing class ExternalProfileDTO {

    public String  email         { get; set; }
    public String  phone         { get; set; }
    public String  firstName     { get; set; }
    public String  lastName      { get; set; }
    public String  loyaltyId     { get; set; }

    /** Epsilon legacy profile Id — used during migration for cross-reference matching */
    public String  epsilonId     { get; set; }

    /** Source system identifier (POS / WEB / BATCH / EVENT) */
    public String  sourceSystem  { get; set; }

    /** RCC card number from the external file */
    public String  rccCardNumber { get; set; }

    public String  countryCode   { get; set; }
}
