import httpx2
import pytest
from anthropic import AuthenticationError, PermissionDeniedError, RateLimitError, InternalServerError, APIConnectionError
from atlas_runtime.errors import public_error
from server.planning_core import PlanningError


@pytest.mark.parametrize('kind,status,expected', [
    (AuthenticationError, 401, 'reconfigured'),
    (PermissionDeniedError, 403, 'account'),
    (RateLimitError, 429, 'busy'),
    (InternalServerError, 503, 'temporarily unavailable'),
])
def test_provider_failures_have_useful_messages_without_provider_body_or_secrets(kind,status,expected):
    request=httpx2.Request('POST','https://api.anthropic.com/v1/messages')
    response=httpx2.Response(status,request=request)
    exc=kind('private-provider-detail secret-test-value',response=response,body={'secret':'secret-test-value'})
    message=public_error(exc)
    assert expected in message and 'Your trip is unchanged.' in message
    assert 'secret-test-value' not in message and 'private-provider-detail' not in message


def test_connection_and_unknown_errors_do_not_expose_exception_details():
    request=httpx2.Request('POST','https://api.anthropic.com/v1/messages')
    for exc in [APIConnectionError(message='secret-test-value',request=request),RuntimeError('secret-test-value')]:
        message=public_error(exc)
        assert 'secret-test-value' not in message and 'Your trip is unchanged.' in message


def test_intentional_domain_errors_keep_the_actionable_explanation():
    assert public_error(PlanningError('Keep the booked flight intact.'))=='Keep the booked flight intact.'
