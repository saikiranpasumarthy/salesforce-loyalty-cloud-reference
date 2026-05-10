/**
 * @description Shared HttpCalloutMock implementation for all Loyalty Cloud service tests.
 *
 * Usage in test classes:
 *   Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());
 *   // → returns default 200 success responses
 *
 *   Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(400, '{"errorCode":"BAD_REQUEST"}'));
 *   // → returns custom status / body for error-path testing
 *
 *   Test.setMock(HttpCalloutMock.class, LoyaltyMockHttpCallout.forEndpoint('/member-benefits', 200, BENEFITS_BODY));
 *   // → returns specific body only for the matched endpoint; other endpoints return 200 empty
 */
@IsTest
public class LoyaltyMockHttpCallout implements HttpCalloutMock {

    // ── Canned response payloads ──────────────────────────────────────────────

    public static final String ENROLLMENT_SUCCESS_BODY = JSON.serialize(new Map<String, Object>{
        'loyaltyProgramMember' => new Map<String, Object>{
            'id'               => 'LPM001',
            'membershipNumber' => 'MBR-10001',
            'memberStatus'     => 'Active',
            'currentTierName'  => 'Preferred'
        }
    });

    public static final String MEMBER_BENEFITS_BODY = JSON.serialize(new Map<String, Object>{
        'loyaltyProgramMemberBenefits' => new Map<String, Object>{
            'currentPointsBalance' => 1500,
            'currentTierName'      => 'Preferred',
            'nextTierName'         => 'Elite',
            'pointsToNextTier'     => 3500,
            'loyaltyCurrencyName'  => 'Reward Points'
        }
    });

    public static final String VOUCHER_LIST_BODY = JSON.serialize(new Map<String, Object>{
        'memberVouchers' => new List<Object>{
            new Map<String, Object>{
                'voucherCode'            => 'CERT-001',
                'faceValue'              => 10.00,
                'status'                 => 'ACTIVE',
                'expirationDate'         => '2099-12-31',
                'voucherDefinitionId'    => 'VD001',
                'voucherDefinitionName'  => '$10 Reward Certificate'
            }
        }
    });

    public static final String TXN_SUCCESS_BODY = JSON.serialize(new Map<String, Object>{
        'transactionJournals' => new List<Object>{
            new Map<String, Object>{
                'id'                 => 'TJ001',
                'totalPointsAwarded' => 150,
                'bonusPoints'        => 25,
                'status'             => 'Success'
            }
        }
    });

    public static final String MEMBER_PROMOTIONS_BODY = JSON.serialize(new Map<String, Object>{
        'memberPromotions' => new List<Object>{
            new Map<String, Object>{
                'promotionId'    => 'PROMO001',
                'promotionName'  => 'Double Points Weekend',
                'enrollmentStatus' => 'Enrolled',
                'startDate'      => '2025-01-01',
                'endDate'        => '2025-12-31'
            }
        }
    });

    public static final String ERROR_400_BODY = JSON.serialize(new Map<String, Object>{
        'message'   => 'Invalid request payload',
        'errorCode' => 'BAD_REQUEST'
    });

    public static final String ERROR_401_BODY = JSON.serialize(new Map<String, Object>{
        'message'   => 'Session expired or invalid token',
        'errorCode' => 'INVALID_SESSION_ID'
    });

    public static final String ERROR_422_INSUFFICIENT_BALANCE = JSON.serialize(new Map<String, Object>{
        'message'   => 'Insufficient points balance',
        'errorCode' => 'INSUFFICIENT_BALANCE'
    });

    public static final String ERROR_422_VOUCHER_EXPIRED = JSON.serialize(new Map<String, Object>{
        'message'   => 'Voucher has expired',
        'errorCode' => 'VOUCHER_EXPIRED'
    });

    // ── Instance fields ───────────────────────────────────────────────────────

    private Integer    responseStatus;
    private String     responseBody;
    private String     endpointFilter; // when set, only match requests containing this substring

    // ── Constructors ──────────────────────────────────────────────────────────

    /** Returns 200 with a generic success body for any endpoint */
    public LoyaltyMockHttpCallout() {
        this(200, '{"success":true}');
    }

    /** Returns the given status and body for any endpoint */
    public LoyaltyMockHttpCallout(Integer status, String body) {
        this.responseStatus = status;
        this.responseBody   = body;
    }

    /** Factory: returns specific body only for requests whose endpoint contains the filter string */
    public static LoyaltyMockHttpCallout forEndpoint(String endpointSubstring, Integer status, String body) {
        LoyaltyMockHttpCallout mock = new LoyaltyMockHttpCallout(status, body);
        mock.endpointFilter = endpointSubstring;
        return mock;
    }

    // ── HttpCalloutMock interface ─────────────────────────────────────────────

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');

        if (endpointFilter != null && !req.getEndpoint().contains(endpointFilter)) {
            // Default pass-through for unmatched endpoints
            res.setStatusCode(200);
            res.setBody('{}');
        } else {
            res.setStatusCode(responseStatus);
            res.setBody(responseBody);
        }
        return res;
    }
}
