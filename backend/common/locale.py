"""Which language a request, an email or a PDF is written in.

The one place that decides it, for the same reason ``common.org_time`` is the
one place that decides the day: a rule spread across every view and task can
only be re-audited, never changed.

A request is answered in, first to last: the user's own choice
(``User.language``), the client's ``Accept-Language``, the org's default
(``Org.default_language``), then ``settings.LANGUAGE_CODE``. Mail has no
request, so a member gets their own language and a customer (a contact, who
has no ``User``) gets the org's.

Only system text is translated. Tenant text (stage names, custom fields,
``Org.terminology``) is shown as written.
"""

from contextlib import contextmanager

from django.conf import settings
from django.utils import translation
from django.utils.translation.trans_real import parse_accept_lang_header


def supported_language(code):
    """``code`` as one of ``settings.LANGUAGES``, or None.

    A regional tag falls back to its base language (``en-GB`` is ``en``), so a
    browser's or a phone's header matches without listing every region.
    """
    if not code or not isinstance(code, str):
        return None
    codes = {c for c, _ in settings.LANGUAGES}
    code = code.strip().lower().replace("_", "-")
    if code in codes:
        return code
    base = code.split("-", 1)[0]
    return base if base in codes else None


def language_from_header(header):
    """The best supported language in an ``Accept-Language`` value, or None."""
    if not header:
        return None
    for code, _q in parse_accept_lang_header(header):
        if code == "*":
            break
        found = supported_language(code)
        if found:
            return found
    return None


def resolve_language(user=None, org=None, accept_language=None):
    """The language code to answer in, by the order in the module docstring."""
    return (
        supported_language(getattr(user, "language", None))
        or language_from_header(accept_language)
        or supported_language(getattr(org, "default_language", None))
        or settings.LANGUAGE_CODE
    )


def request_language(request):
    profile = getattr(request, "profile", None)
    return resolve_language(
        user=getattr(profile, "user", None),
        org=getattr(request, "org", None),
        accept_language=request.headers.get("Accept-Language"),
    )


@contextmanager
def language_for_user(user, org=None):
    """Write mail or other text addressed to a member in their language.

    For Celery tasks and signals: a worker runs no middleware, and
    ``translation.override`` restores whatever was active on exit, so one
    recipient's language never leaks into the next task on a reused thread.
    """
    with translation.override(resolve_language(user=user, org=org)):
        yield


@contextmanager
def language_for_org(org):
    """Write text addressed to a customer (a contact, a portal visitor) in the org's language."""
    with translation.override(resolve_language(org=org)):
        yield
