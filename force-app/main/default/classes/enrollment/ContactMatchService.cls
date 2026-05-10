/**
 * @description Match-or-create SFSC Contact from external inbound payloads.
 *
 * MATCHING STRATEGY (in priority order):
 *   1. Exact email match (most reliable for web/CRM sources)
 *   2. Phone match (E.164 normalized)
 *   3. Loyalty ID match (for POS and batch file sources)
 *   4. Epsilon profile ID match (migration legacy cross-reference)
 *   5. Create new Contact if no match found
 *
 * DESIGN NOTES:
 *   - Always perform matching in a single SOQL query to stay within governor limits.
 *   - Email match takes precedence; if email and phone both match different Contacts,
 *     return the email match and flag a potential duplicate for manual review.
 *   - This class is called with sharing — no cross-user record access.
 */
public with sharing class ContactMatchService {

    /**
     * @description Primary entry point for match-or-create from an external profile.
     *              Returns the matched or newly created Contact Id.
     *
     * @param dto  External profile data (from POS, batch file, or event payload)
     * @return     The SFSC Contact Id (18-digit)
     */
    public Id matchOrCreateContact(ExternalProfileDTO dto) {
        Contact matched = findBestMatch(dto);

        if (matched != null) {
            updateContactFields(matched, dto);
            update matched;
            return matched.Id;
        }

        return createContact(dto);
    }

    /**
     * @description Finds an existing Contact by email only.
     *              Used by LoyaltyEnrollmentService.checkDuplicateMember.
     */
    public Contact findContactByEmail(String email) {
        if (String.isBlank(email)) return null;
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Phone,
                   Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c,
                   Country_Code__c, RCC_Active__c
            FROM   Contact
            WHERE  Email = :email.trim().toLowerCase()
            LIMIT  1
        ];
        return contacts.isEmpty() ? null : contacts[0];
    }

    /**
     * @description Finds an existing Contact by phone (normalized E.164).
     */
    public Contact findContactByPhone(String phone) {
        if (String.isBlank(phone)) return null;
        String normalized = normalizePhone(phone);
        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email, Phone,
                   Has_Loyalty__c, Loyalty_Member_Id__c
            FROM   Contact
            WHERE  Phone = :normalized
            LIMIT  1
        ];
        return contacts.isEmpty() ? null : contacts[0];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private Contact findBestMatch(ExternalProfileDTO dto) {
        // Single SOQL for all match criteria
        String email     = String.isBlank(dto.email)      ? null : dto.email.trim().toLowerCase();
        String phone     = String.isBlank(dto.phone)      ? null : normalizePhone(dto.phone);
        String loyaltyId = String.isBlank(dto.loyaltyId)  ? null : dto.loyaltyId;
        String epsilonId = String.isBlank(dto.epsilonId)  ? null : dto.epsilonId;

        List<Contact> candidates = [
            SELECT Id, FirstName, LastName, Email, Phone,
                   Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c,
                   Epsilon_Profile_Id__c, Country_Code__c, RCC_Active__c
            FROM   Contact
            WHERE  (Email = :email          AND :email != null)
               OR  (Phone = :phone          AND :phone != null)
               OR  (Loyalty_Member_Id__c = :loyaltyId AND :loyaltyId != null)
               OR  (Epsilon_Profile_Id__c = :epsilonId AND :epsilonId != null)
            LIMIT  5
        ];

        if (candidates.isEmpty()) return null;

        // Return the first match in priority order
        for (Contact c : candidates) {
            if (email != null && email == c.Email?.toLowerCase()) return c; // email match wins
        }
        for (Contact c : candidates) {
            if (phone != null && phone == c.Phone) return c;
        }
        for (Contact c : candidates) {
            if (loyaltyId != null && loyaltyId == c.Loyalty_Member_Id__c) return c;
        }
        return candidates[0]; // epsilon or first found
    }

    private Id createContact(ExternalProfileDTO dto) {
        Contact c = new Contact(
            FirstName           = dto.firstName,
            LastName            = String.isNotBlank(dto.lastName) ? dto.lastName : 'Unknown',
            Email               = dto.email?.trim().toLowerCase(),
            Phone               = normalizePhone(dto.phone),
            Country_Code__c     = dto.countryCode,
            Epsilon_Profile_Id__c = dto.epsilonId
        );
        insert c;
        return c.Id;
    }

    private void updateContactFields(Contact c, ExternalProfileDTO dto) {
        if (String.isNotBlank(dto.email)       && c.Email  == null) c.Email  = dto.email.toLowerCase();
        if (String.isNotBlank(dto.phone)       && c.Phone  == null) c.Phone  = normalizePhone(dto.phone);
        if (String.isNotBlank(dto.countryCode) && c.Country_Code__c == null) {
            c.Country_Code__c = dto.countryCode;
        }
        if (String.isNotBlank(dto.epsilonId) && c.Epsilon_Profile_Id__c == null) {
            c.Epsilon_Profile_Id__c = dto.epsilonId;
        }
    }

    /**
     * @description Strips formatting from phone numbers to normalized digit-only form.
     *              Handles US/CA 10-digit format; prepends +1 for NANP numbers.
     */
    @TestVisible
    private String normalizePhone(String raw) {
        if (String.isBlank(raw)) return null;
        String digits = raw.replaceAll('[^0-9]', '');
        if (digits.length() == 10) return '+1' + digits;
        if (digits.length() == 11 && digits.startsWith('1')) return '+' + digits;
        return '+' + digits;
    }
}
