"""The public web form in English, the source language.

A public form follows the visitor's `Accept-Language` when it names a language
we ship, else the org's default. Field labels and the button are tenant text
and are never translated.

The Russian cases also cover automation and webhook mail, which follows the
member's language.
"""

import json

import pytest
from django.core import mail

from automation.tasks import send_member_email
from webforms.models import WebForm, WebFormField
from webforms.service import submit_form
from webforms.tasks import send_webform_submission_email


@pytest.fixture
def ru_org(org_a):
    org_a.default_language = "ru"
    org_a.save(update_fields=["default_language"])
    return org_a


@pytest.fixture
def form(org_a, admin_profile):
    web_form = WebForm.objects.create(
        name="Contact us",
        org=org_a,
        is_published=True,
        submit_button_label="Send",
        assign_to=admin_profile,
    )
    WebFormField.objects.create(
        form=web_form,
        org=org_a,
        order=0,
        source=WebFormField.SOURCE_LEAD,
        lead_field="email",
        label="Your email",
        is_required=True,
    )
    return web_form


def embed_url(form):
    return f"/api/public/forms/{form.org_id}/{form.id}/embed/"


def submit_url(form):
    return f"/api/public/forms/{form.org_id}/{form.id}/submit/"


class TestPublicForm:
    def test_follows_the_org_default_without_a_header(
        self, unauthenticated_client, ru_org, form
    ):
        response = unauthenticated_client.get(embed_url(form))
        html = response.content.decode()
        assert response["Content-Language"] == "ru"
        assert '<html lang="ru">' in html
        assert "Оставьте это поле пустым" in html
        assert 'data-msg-thanks="Спасибо."' in html
        assert "Your email" in html
        assert ">Send</button>" in html

    def test_english_org_stays_english(self, unauthenticated_client, org_a, form):
        html = unauthenticated_client.get(embed_url(form)).content.decode()
        assert '<html lang="en">' in html
        assert "Leave this field empty" in html
        assert 'data-msg-thanks="Thanks."' in html

    def test_accept_language_beats_the_org_default(
        self, unauthenticated_client, ru_org, form
    ):
        response = unauthenticated_client.get(
            embed_url(form), HTTP_ACCEPT_LANGUAGE="en-GB,en;q=0.9"
        )
        html = response.content.decode()
        assert response["Content-Language"] == "en"
        assert "Leave this field empty" in html
        assert "Оставьте" not in html

    def test_an_unsupported_header_falls_back_to_the_org_default(
        self, unauthenticated_client, ru_org, form
    ):
        html = unauthenticated_client.get(
            embed_url(form), HTTP_ACCEPT_LANGUAGE="de-DE"
        ).content.decode()
        assert "Оставьте это поле пустым" in html

    def test_the_script_embed_carries_translated_messages(
        self, unauthenticated_client, ru_org, form
    ):
        js = unauthenticated_client.get(
            f"/api/public/forms/{form.org_id}/{form.id}/embed.js"
        ).content.decode()
        assert json.dumps("Спасибо.") in js
        assert '"label": "Your email"' in js

    def test_a_refusal_is_in_the_org_language(
        self, unauthenticated_client, ru_org, form
    ):
        form.allowed_origins = ["https://customer.example"]
        form.save(update_fields=["allowed_origins"])
        response = unauthenticated_client.post(
            submit_url(form),
            {"email": "pat@example.com"},
            format="json",
            HTTP_ORIGIN="https://elsewhere.example",
        )
        assert response.status_code == 403
        assert response.json() == {
            "detail": "Эту форму нельзя отправить с этого сайта."
        }

    def test_a_refusal_follows_the_header(self, unauthenticated_client, ru_org, form):
        form.allowed_origins = ["https://customer.example"]
        form.save(update_fields=["allowed_origins"])
        response = unauthenticated_client.post(
            submit_url(form),
            {"email": "pat@example.com"},
            format="json",
            HTTP_ORIGIN="https://elsewhere.example",
            HTTP_ACCEPT_LANGUAGE="en",
        )
        assert response.json() == {
            "detail": "This form cannot be submitted from this site."
        }


class TestSubmissionEmail:
    def test_each_member_reads_it_in_their_own_language(
        self, form, org_a, admin_profile, user_profile
    ):
        user_profile.user.language = "ru"
        user_profile.user.save(update_fields=["language"])
        form.notify_profiles.add(user_profile)
        submission = submit_form(form, {"email": "pat@example.com"})
        mail.outbox.clear()

        send_webform_submission_email(str(submission.id), str(org_a.id))

        by_recipient = {tuple(m.recipients()): m for m in mail.outbox}
        assert len(by_recipient) == 2
        russian = by_recipient[(user_profile.user.email,)]
        english = by_recipient[(admin_profile.user.email,)]
        assert russian.subject == "Новая заявка: Contact us"
        assert "Открыть лид" in russian.alternatives[0][0]
        assert english.subject == "New submission: Contact us"
        assert "Open the lead" in english.alternatives[0][0]

    def test_members_without_a_choice_follow_the_org(self, form, ru_org, admin_profile):
        submission = submit_form(form, {"email": "pat@example.com"})
        mail.outbox.clear()
        send_webform_submission_email(str(submission.id), str(ru_org.id))
        assert [m.subject for m in mail.outbox] == ["Новая заявка: Contact us"]


class TestApiErrors:
    def test_webforms(self, admin_client, form):
        response = admin_client.post(
            f"/api/webforms/{form.id}/publish/", HTTP_ACCEPT_LANGUAGE="ru"
        )
        assert response.status_code == 400
        assert response.json()["errors"] == "Эта форма уже опубликована."

    def test_automation(self, admin_client):
        response = admin_client.post(
            "/api/automation/rules/",
            {
                "name": "Deal rule",
                "object_key": "deal",
                "trigger": {"event": "created", "field": None, "to": None},
                "match": "all",
                "conditions": [],
                "actions": [],
            },
            format="json",
            HTTP_ACCEPT_LANGUAGE="ru",
        )
        assert response.status_code == 400
        assert "Добавьте хотя бы одно действие." in json.dumps(
            response.json(), ensure_ascii=False
        )

    def test_webhooks(self, admin_client, admin_user):
        admin_user.language = "ru"
        admin_user.save(update_fields=["language"])
        response = admin_client.post(
            "/api/webhooks/",
            {"url": "http://hooks.example.com/in", "events": ["lead.created"]},
            format="json",
        )
        assert response.status_code == 400
        assert response.json()["url"] == ["URL должен начинаться с https://."]


def test_automation_member_email_translates_only_the_template(org_a, user_profile):
    user_profile.user.language = "ru"
    user_profile.user.save(update_fields=["language"])
    send_member_email(
        [str(user_profile.pk)], "Deal won", "Call Acme today", "/leads/x", str(org_a.pk)
    )
    (message,) = mail.outbox
    assert message.subject == "Deal won"
    assert "Call Acme today" in message.body
    assert "Отправлено из BottleCRM" in message.body
    assert "Открыть запись" in message.alternatives[0][0]
