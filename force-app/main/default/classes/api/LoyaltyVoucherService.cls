/**
 * @description Service for certificate/voucher operations against the Loyalty Cloud API.
 *
 * Endpoints covered:
 *   GET  /member-vouchers                          (getMemberVouchers)
 *   POST /program-processes/Validate Voucher       (validateVoucher)
 *   POST /program-processes/Redeem Voucher         (redeemVoucher)
 *   POST /program-processes/Cancel Voucher         (cancelVoucher)
 *   POST /program-processes/Issue Voucher          (issueVoucher)
 */
public with sharing class LoyaltyVoucherService {

    private final LoyaltyAPIClient client;

    public LoyaltyVoucherService() {
        this.client = new LoyaltyAPIClient();
    }

    @TestVisible
    private LoyaltyVoucherService(LoyaltyAPIClient client) {
        this.client = client;
    }

    /**
     * @description Returns all vouchers for the given member.
     *              The LWC loyaltyVoucherList calls this on component load and filters
     *              by status client-side to show ACTIVE / EXPIRED / REDEEMED tabs.
     */
    public List<VoucherDTO> getMemberVouchers(String lpmId) {
        String endpoint = '/member-vouchers?memberId=' + EncodingUtil.urlEncode(lpmId, 'UTF-8');
        Map<String, Object> raw = client.get(endpoint);
        return parseVoucherList(raw);
    }

    /**
     * @description Validates a voucher before attempting redemption.
     *              Call this during cart validation; call redeemVoucher at order submission.
     *              Returns true if the voucher is valid for the given member.
     *
     * @throws LoyaltyVoucherException (VOUCHER_EXPIRED / VOUCHER_NOT_FOUND / MEMBER_MISMATCH)
     */
    public Boolean validateVoucher(String voucherCode, String lpmId) {
        Map<String, Object> payload = new Map<String, Object>{
            'voucherCode' => voucherCode,
            'memberId'    => lpmId
        };
        Map<String, Object> resp = client.post(
            '/program-processes/Validate%20Voucher',
            JSON.serialize(payload)
        );
        Object valid = resp.get('isValid');
        return valid != null && Boolean.valueOf(String.valueOf(valid));
    }

    /**
     * @description Redeems a voucher against a specific order.
     *              Called at order submission time, not at cart-add.
     *              Idempotent — subsequent calls for an already-redeemed voucher throw
     *              LoyaltyVoucherException(ALREADY_REDEEMED).
     *
     * @param voucherCode Voucher code shown on the member's certificate
     * @param lpmId       Member who owns this voucher
     * @param orderId     External order reference for audit trail
     */
    public void redeemVoucher(String voucherCode, String lpmId, String orderId) {
        Map<String, Object> payload = new Map<String, Object>{
            'voucherCode' => voucherCode,
            'memberId'    => lpmId,
            'orderId'     => orderId
        };
        client.post('/program-processes/Redeem%20Voucher', JSON.serialize(payload));
    }

    /**
     * @description Cancels a voucher — typically called on order cancellation
     *              to return the redeemed value to the member for future use.
     *
     * @param voucherCode Voucher code to cancel
     * @param reason      Reason code (ORDER_CANCELLED / ADMIN_REVERSAL / EXPIRY_EXTENSION)
     */
    public void cancelVoucher(String voucherCode, String reason) {
        Map<String, Object> payload = new Map<String, Object>{
            'voucherCode' => voucherCode,
            'reason'      => reason
        };
        client.post('/program-processes/Cancel%20Voucher', JSON.serialize(payload));
    }

    /**
     * @description Issues a new voucher to the member from a specific voucher definition.
     *              Used for agent appeasement and promotion fulfillment.
     *
     * @param lpmId           Target member
     * @param voucherDefId    Id of the voucher definition in LC config
     */
    public VoucherDTO issueVoucher(String lpmId, String voucherDefId) {
        Map<String, Object> payload = new Map<String, Object>{
            'memberId'            => lpmId,
            'voucherDefinitionId' => voucherDefId
        };
        Map<String, Object> resp = client.post(
            '/program-processes/Issue%20Voucher',
            JSON.serialize(payload)
        );
        return parseVoucher(resp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private parsers
    // ─────────────────────────────────────────────────────────────────────────

    private List<VoucherDTO> parseVoucherList(Map<String, Object> raw) {
        List<VoucherDTO> result = new List<VoucherDTO>();
        List<Object> items = (List<Object>) raw.get('memberVouchers');
        if (items == null) return result;

        for (Object item : items) {
            result.add(parseVoucher((Map<String, Object>) item));
        }
        return result;
    }

    private VoucherDTO parseVoucher(Map<String, Object> v) {
        VoucherDTO dto         = new VoucherDTO();
        dto.voucherCode        = (String) v.get('voucherCode');
        dto.status             = (String) v.get('status');
        dto.voucherDefinitionId = (String) v.get('voucherDefinitionId');
        dto.voucherDefinitionName = (String) v.get('voucherDefinitionName');
        dto.redeemedOrderId    = (String) v.get('redeemedOrderId');
        dto.currencyIsoCode    = 'USD';

        Object val = v.get('faceValue');
        dto.value = val != null ? Decimal.valueOf(String.valueOf(val)) : 0;

        String expStr = (String) v.get('expirationDate');
        if (String.isNotBlank(expStr)) {
            dto.expiryDate = Date.valueOf(expStr.left(10));
        }
        return dto;
    }
}
