"""Ticket mail and API errors in English, the source language, stay exactly
as they were once their strings moved into catalogs.

Which language a reader gets is tested in ``common/tests/test_locale.py``.
"""

import pytest
from django.core import mail
from django.utils import timezone

from cases.models import Case
from cases.tasks import notify_portal_contacts, send_csat_survey
from contacts.models import Contact


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


class TestCsatSurveyEmail:
    def test_english_org_is_unchanged(self, org_a, closed_case):
        mail.outbox.clear()
        send_csat_survey(str(closed_case.id), str(org_a.id))
        (message,) = mail.outbox
        assert message.subject == "How did we do?, Login bug"
        assert "Hi Pat," in message.body
        assert "Not good" in message.body


class TestPortalStatusEmail:
    def test_english_org_is_unchanged(self, org_a, closed_case):
        mail.outbox.clear()
        notify_portal_contacts(str(closed_case.id), str(org_a.id), "status")
        (message,) = mail.outbox
        assert "Hello Pat," in message.body
        assert "is now <strong>Closed</strong>." in message.body


class TestApiErrors:
    def test_validation_error_in_english(self, admin_client):
        response = admin_client.post(
            "/api/cases/bulk/update/",
            {"fields": {"priority": "High"}},
            format="json",
            HTTP_ACCEPT_LANGUAGE="en",
        )
        assert response.status_code == 400
        assert response.json()["errors"] == "ids required"
