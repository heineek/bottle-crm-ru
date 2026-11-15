"""The ``common`` app's own text in Russian: module copy, API errors, mail.

English stays the source text, byte for byte; tenant text (``Org.terminology``)
is never translated.
"""

from django.core import mail
from django.utils import translation

from common.module_deletes import DELETE_GUARDS, _body
from common.modules import module_label, module_off_message
from common.tasks import send_email_user_delete, send_welcome_email

MODULES = "/api/org/modules/"
SAVED_VIEWS = "/api/saved-views/"


def _row(response, key):
    return next(m for m in response.data["modules"] if m["key"] == key)


class TestModuleCopy:
    def test_label_and_stops_follow_the_callers_language(self, user_client):
        ru = _row(user_client.get(MODULES, HTTP_ACCEPT_LANGUAGE="ru"), "deals")
        en = _row(user_client.get(MODULES), "deals")

        assert ru["label"] == "Воронка"
        assert ru["stops"].startswith("Всё из раздела «Воронка»")
        assert en["label"] == "Pipeline"
        assert en["stops"].startswith("Everything in Pipeline leaves every menu")

    def test_a_terminology_override_is_shown_as_written(self, org_a):
        org_a.terminology = {"lead.plural": "Enquiries"}

        with translation.override("ru"):
            assert module_label(org_a, "leads") == "Enquiries"
            assert module_off_message(org_a, "leads") == (
                "Модуль «Enquiries» отключён в этой организации."
            )
            assert module_label(org_a, "tasks") == "Задачи"
        with translation.override("en"):
            assert module_off_message(org_a, "leads") == (
                "Enquiries is switched off for this organization."
            )

    def test_a_delete_refusal_counts_in_russian(self, org_a):
        guard = DELETE_GUARDS["accounts.Account"][0]
        with translation.override("ru"):
            one = _body(org_a, "tickets", "Эта компания", guard, 1)["errors"]
            five = _body(org_a, "tickets", "Эта компания", guard, 5)["errors"]
        with translation.override("en"):
            two = _body(org_a, "tickets", "This account", guard, 2)["errors"]

        assert "(1 обращение)" in one
        assert "(5 обращений)" in five
        assert two == (
            "This account has 2 tickets. Tickets is switched off, so switch it on "
            "to review them before deleting."
        )


class TestApiErrors:
    def test_a_drf_error_follows_the_callers_language(self, user_client):
        ru = user_client.get(SAVED_VIEWS, {"module": "nope"}, HTTP_ACCEPT_LANGUAGE="ru")
        en = user_client.get(SAVED_VIEWS, {"module": "nope"})

        assert ru.status_code == en.status_code == 400
        assert ru.data["module"][0].startswith("Выберите одно из значений: ")
        assert en.data["module"][0].startswith("Choose one of: ")

    def test_a_permission_message_is_translated(self, user_client):
        ru = user_client.put(
            MODULES, {"off": [], "order": []}, format="json", HTTP_ACCEPT_LANGUAGE="ru"
        )

        assert ru.status_code == 403
        assert (
            ru.data["errors"]
            == "Включать и отключать модули могут только администраторы."
        )


class TestMail:
    def test_a_member_is_written_to_in_their_own_language(self, regular_user, org_a):
        regular_user.language = "ru"
        regular_user.save(update_fields=["language"])

        send_email_user_delete(regular_user.email, "admin@test.com", str(org_a.id))

        message = mail.outbox[-1]
        assert message.subject == "CRM: ваша учётная запись удалена. "
        assert "Вашу учётную запись удалил пользователь admin@test.com." in message.body
        assert 'lang="ru"' in message.body

    def test_without_a_choice_the_org_default_applies(self, regular_user, org_a):
        org_a.default_language = "ru"
        org_a.save(update_fields=["default_language"])

        send_email_user_delete(regular_user.email, "admin@test.com", str(org_a.id))

        assert mail.outbox[-1].subject == "CRM: ваша учётная запись удалена. "

    def test_english_mail_is_unchanged(self, regular_user):
        send_email_user_delete(regular_user.email, "admin@test.com")

        message = mail.outbox[-1]
        assert message.subject == "CRM : Your account is Deleted. "
        assert (
            "Your account has been deleted by admin@test.com. You are no longer "
            "able to access your account." in message.body
        )
        assert 'lang="en"' in message.body

    def test_a_new_account_is_welcomed_in_the_request_language(self, regular_user):
        send_welcome_email(str(regular_user.id), language="ru")

        assert mail.outbox[-1].subject == "Добро пожаловать в BottleCRM"
        assert "Начать работу" in mail.outbox[-1].body

    def test_the_language_does_not_leak_out_of_a_task(self, regular_user):
        with translation.override("en"):
            send_welcome_email(str(regular_user.id), language="ru")

            assert translation.get_language() == "en"
