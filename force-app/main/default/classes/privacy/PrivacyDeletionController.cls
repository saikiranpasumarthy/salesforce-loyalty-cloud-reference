/**
 * @description Invocable Apex wrapper called by Privacy_Request_Handler_Flow.
 *              Delegates to PrivacyDeletionService for the actual 4-gate deletion workflow.
 */
public with sharing class PrivacyDeletionController {

    public class DeletionRequest {
        @InvocableVariable(required=true label='Contact Id')
        public Id contactId;

        @InvocableVariable(required=false label='Privacy Request Id')
        public Id privacyRequestId;
    }

    @InvocableMethod(
        label='Execute Privacy Deletion'
        description='Processes a privacy erasure request for a Contact. Called from Privacy_Request_Handler_Flow.'
    )
    public static void processPrivacyRequest(List<DeletionRequest> requests) {
        for (DeletionRequest req : requests) {
            PrivacyDeletionService svc = new PrivacyDeletionService();
            svc.processPrivacyRequest(
                req.contactId,
                'FlowTrigger',
                req.privacyRequestId != null ? String.valueOf(req.privacyRequestId) : null
            );
        }
    }
}
