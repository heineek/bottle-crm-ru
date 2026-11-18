"""Ticket mail and API errors in English, the source language, stay exactly
as they were once their strings moved into catalogs.

Which language a reader gets is tested in ``common/tests/test_locale.py``.
In Russian, a customer (CSAT survey, portal update) reads the org's default
language; a member reads their own `User.language`; an API error follows the
request.
"""

import pytest
from django.core import mail
from django.utils import timezone

from cases.models import Case
from cases.tasks import notify_portal_contacts, send_csat_survey
from contacts.models import Contact
from tasks.celery_tasks import send_email_to_assigned_user
from tasks.models import Task


@pytest.fixture
def contact(org_a):
    return Contact.objects.create(
        org=org_a, first_name="Pat", last_name="Smith", email="pat@example.com"
    )


@pytest.fixture
def closed_case(org_a, contact):
    case = Case.objects.create(
        org=org_a,
        name="Login bug",
        status="Closed",
        priority="Normal",
        closed_on=timezone.localdate(),
        resolved_at=timezone.now(),
    )
    case.contacts.add(contact)
    return case


def _russian_org(org):
    org.default_language = "ru"
    org.save(update_fields=["default_language"])


class TestCsatSurveyEmail:
    def test_follows_the_org_default_language(self, org_a, closed_case):
        _russian_org(org_a)
        mail.outbox.clear()
        send_csat_survey(str(closed_case.id), str(org_a.id))
        (message,) = mail.outbox
        assert message.subject == "Как мы справились? Login bug"
        assert "Здравствуйте, Pat!" in message.body
        assert "Плохо" in message.body
        assert "How did we do" not in message.body

    def test_english_org_is_unchanged(self, org_a, closed_case):
        mail.outbox.clear()
        send_csat_survey(str(closed_case.id), str(org_a.id))
        (message,) = mail.outbox
        assert message.subject == "How did we do?, Login bug"
        assert "Hi Pat," in message.body
        assert "Not good" in message.body

    def test_a_member_language_does_not_reach_the_customer(
        self, org_a, closed_case, admin_profile
    ):
        admin_profile.user.language = "ru"
        admin_profile.user.save(update_fields=["language"])
        closed_case.assigned_to.add(admin_profile)
        mail.outbox.clear()
        send_csat_survey(str(closed_case.id), str(org_a.id))
        assert mail.outbox[0].subject == "How did we do?, Login bug"


class TestPortalStatusEmail:
    def test_follows_the_org_default_language(self, org_a, closed_case):
        _russian_org(org_a)
        mail.outbox.clear()
        notify_portal_contacts(str(closed_case.id), str(org_a.id), "status")
        (message,) = mail.outbox
        assert "Здравствуйте, Pat!" in message.body
        assert "Статус вашего запроса" in message.body
        # The `[Case #...]` tag is how a reply threads back, so it stays.
        assert "[Case #" in message.subject

    def test_english_org_is_unchanged(self, org_a, closed_case):
        mail.outbox.clear()
        notify_portal_contacts(str(closed_case.id), str(org_a.id), "status")
        (message,) = mail.outbox
        assert "Hello Pat," in message.body
        assert "is now <strong>Closed</strong>." in message.body


class TestTaskAssignmentEmail:
    @pytest.fixture
    def task(self, org_a):
        return Task.objects.create(
            org=org_a, title="Call back", status="New", priority="Low"
        )

    def test_follows_the_member_language(self, org_a, task, user_profile):
        user_profile.user.language = "ru"
        user_profile.user.save(update_fields=["language"])
        mail.outbox.clear()
        send_email_to_assigned_user([str(user_profile.id)], str(task.id), str(org_a.id))
        (message,) = mail.outbox
        assert message.subject == "Вам назначена задача."
        assert "Открыть задачу" in message.body

    def test_member_language_beats_the_org_default(
        self, org_a, task, user_profile, admin_profile
    ):
        _russian_org(org_a)
        user_profile.user.language = "en"
        user_profile.user.save(update_fields=["language"])
        mail.outbox.clear()
        send_email_to_assigned_user(
            [str(user_profile.id), str(admin_profile.id)], str(task.id), str(org_a.id)
        )
        subjects = {m.to[0]: m.subject for m in mail.outbox}
        assert subjects == {
            user_profile.user.email: "Assigned a task for you.",
            admin_profile.user.email: "Вам назначена задача.",
        }


class TestApiErrors:
    def test_validation_error_in_russian(self, admin_client):
        response = admin_client.post(
            "/api/cases/bulk/update/",
            {"fields": {"priority": "High"}},
            format="json",
            HTTP_ACCEPT_LANGUAGE="ru",
        )
        assert response.status_code == 400
        assert response.json()["errors"] == "Укажите ids"

    def test_validation_error_in_english(self, admin_client):
        response = admin_client.post(
            "/api/cases/bulk/update/",
            {"fields": {"priority": "High"}},
            format="json",
            HTTP_ACCEPT_LANGUAGE="en",
        )
        assert response.status_code == 400
        assert response.json()["errors"] == "ids required"

    def test_serializer_error_in_russian(self, admin_client):
        response = admin_client.post(
            "/api/cases/",
            {"name": "Ticket", "status": "New", "priority": "Normal", "parent": None},
            format="json",
            HTTP_ACCEPT_LANGUAGE="ru",
        )
        assert response.status_code == 200, response.content
        response = admin_client.post(
            "/api/cases/",
            {"name": "ticket", "status": "New", "priority": "Normal"},
            format="json",
            HTTP_ACCEPT_LANGUAGE="ru",
        )
        assert response.status_code == 400
        assert response.json()["errors"]["name"] == [
            "Обращение с таким названием уже существует"
        ]
