"""The ``common`` app's own text: module copy, API errors, mail.

English stays the source text, byte for byte; tenant text (``Org.terminology``)
is never translated.
"""

from django.core import mail
from django.utils import translation

from common.modules import module_label, module_off_message
from common.tasks import send_email_user_delete, send_welcome_email

MODULES = "/api/org/modules/"
SAVED_VIEWS = "/api/saved-views/"


def _row(response, key):
    return next(m for m in response.data["modules"] if m["key"] == key)


class TestModuleCopy:
    def test_label_and_stops_in_english(self, user_client):
        en = _row(user_client.get(MODULES), "deals")

        assert en["label"] == "Pipeline"
        assert en["stops"].startswith("Everything in Pipeline leaves every menu")

    def test_a_terminology_override_is_shown_as_written(self, org_a):
        org_a.terminology = {"lead.plural": "Enquiries"}

        with translation.override("en"):
            assert module_label(org_a, "leads") == "Enquiries"
            assert module_off_message(org_a, "leads") == (
                "Enquiries is switched off for this organization."
            )


class TestApiErrors:
    def test_a_drf_error_in_english(self, user_client):
        en = user_client.get(SAVED_VIEWS, {"module": "nope"})

        assert en.status_code == 400
        assert en.data["module"][0].startswith("Choose one of: ")


class TestMail:
    def test_english_mail_is_unchanged(self, regular_user):
        send_email_user_delete(regular_user.email, "admin@test.com")

        message = mail.outbox[-1]
        assert message.subject == "CRM : Your account is Deleted. "
        assert (
            "Your account has been deleted by admin@test.com. You are no longer "
            "able to access your account." in message.body
        )
        assert 'lang="en"' in message.body

    def test_the_language_does_not_leak_out_of_a_task(self, regular_user, settings):
        # A second configured language, so the task really switches to it.
        settings.LANGUAGES = [("en", "English"), ("fr", "Français")]
        with translation.override("en"):
            send_welcome_email(str(regular_user.id), language="fr")

            assert translation.get_language() == "en"
