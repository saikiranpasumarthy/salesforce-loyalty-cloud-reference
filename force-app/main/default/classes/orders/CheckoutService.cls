/**
 * @description Checkout-time loyalty operations: voucher redemption, promo code validation,
 *              and fulfilment payload assembly.
 *
 * Called from the commerce storefront at order submission time.
 * All point-awarding is deferred to OrderFulfilmentEventHandler — checkout only handles
 * redemption (certificate apply) and pending status tracking.
 */
public with sharing class CheckoutService {

    private final LoyaltyVoucherService      voucherSvc;
    private final PointsPendingStatusService statusSvc;

    public CheckoutService() {
        this.voucherSvc = new LoyaltyVoucherService();
        this.statusSvc  = new PointsPendingStatusService();
    }

    @TestVisible
    private CheckoutService(LoyaltyVoucherService voucherSvc, PointsPendingStatusService statusSvc) {
        this.voucherSvc = voucherSvc;
        this.statusSvc  = statusSvc;
    }

    /**
     * @description Redeems one or more certificates against an order at submission.
     *              All vouchers are validated before any redemption attempts.
     *
     * @param orderId     External order Id
     * @param lpmId       Member's LPM Id
     * @param voucherCodes List of voucher codes to apply
     */
    public void redeemCertificatesAtSubmission(String orderId, String lpmId, List<String> voucherCodes) {
        if (voucherCodes == null || voucherCodes.isEmpty()) return;

        // Validate all vouchers first — fail fast before redeeming any
        for (String code : voucherCodes) {
            voucherSvc.validateVoucher(code, lpmId);
        }

        // All valid — redeem
        for (String code : voucherCodes) {
            voucherSvc.redeemVoucher(code, lpmId, orderId);
        }
    }

    /**
     * @description Validates and applies a promo code at checkout.
     *              Promo codes map to LC promotions; enrollment is required before earn-rate applies.
     *
     * @param promoCode  The promo code entered by the customer
     * @param lpmId      Member's LPM Id
     * @param orderId    Current order Id (for audit)
     * @return           True if the promo code was valid and the member enrolled
     */
    public Boolean validateAndRedeemPromoCode(String promoCode, String lpmId, String orderId) {
        if (String.isBlank(promoCode)) return false;

        // Look up the promotion mapping from CMDT or a dedicated promo lookup
        // For reference: in a real implementation, this would query a PromoCode__c custom object
        // that maps code strings to LC promotion Ids.
        List<Loyalty_Exclusion_Rule__mdt> promos = [
            SELECT DeveloperName FROM Loyalty_Exclusion_Rule__mdt
            WHERE DeveloperName = :promoCode LIMIT 1
        ];

        if (promos.isEmpty()) return false;

        // In practice, replace this with the actual promotion lookup
        String promotionId = promos[0].DeveloperName;
        new LoyaltyPromotionService().enrollForPromotion(lpmId, promotionId);
        return true;
    }

    /**
     * @description Assembles the fulfilment TJ payload from an Order record.
     *              Called by integrations when building the Order_Fulfilment_Event__e payload.
     *
     * @param order          SFSC Order record (must include OrderItems)
     * @param fulfilmentType BOPIS | SDD | Standard
     */
    public Map<String, Object> buildFulfilmentPayload(Order order, String fulfilmentType) {
        Map<String, Boolean> exclusions = LoyaltyCartEvaluationService.getExclusionRules();
        List<Map<String, Object>> lines = new List<Map<String, Object>>();

        for (OrderItem item : order.OrderItems) {
            Boolean excluded = exclusions.containsKey(item.Product2.Family)
                               && exclusions.get(item.Product2.Family);
            lines.add(new Map<String, Object>{
                'productId'   => item.Product2Id,
                'sku'         => item.Product2.ProductCode,
                'category'    => item.Product2.Family,
                'quantity'    => item.Quantity,
                'unitPrice'   => item.UnitPrice,
                'lineTotal'   => item.TotalPrice,
                'isExcluded'  => excluded
            });
        }

        return new Map<String, Object>{
            'orderId'        => order.Id,
            'fulfilmentType' => fulfilmentType,
            'lineItems'      => lines
        };
    }
}
