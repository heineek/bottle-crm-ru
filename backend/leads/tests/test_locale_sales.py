"""Leads, deals, accounts, contacts and orders in English, the source language.

English stays the source text byte for byte, so the English assertions here
are the same strings the older tests (and the mobile client) match on.
"""

from django.core import mail
from django.utils import translation

from leads.models import Lead
from opportunity.models import Opportunity
from opportunity.tasks import send_stale_deals_alert
from orders.models import Order

EN = {"HTTP_ACCEPT_LANGUAGE": "en"}


def _errors(response):
    return str(response.json())


class TestLeadErrors:
    def _duplicate(self, client, org, headers):
        Lead.objects.create(org=org, first_name="Ann", email="ann@example.com")
        return client.post(
            "/api/leads/",
            {"first_name": "Bob", "email": "ann@example.com"},
            format="json",
            **headers,
        )

    def test_duplicate_email_in_english(self, admin_client, org_a):
        response = self._duplicate(admin_client, org_a, EN)
        assert response.status_code == 400
        assert (
            "Another lead in this organisation already uses that email address."
            in _errors(response)
        )


class TestDealErrors:
    def _duplicate(self, client, headers):
        client.post("/api/opportunities/pipelines/", {"name": "Partners"}, **headers)
        return client.post(
            "/api/opportunities/pipelines/", {"name": "partners"}, **headers
        )

    def test_duplicate_pipeline_in_english(self, admin_client):
        response = self._duplicate(admin_client, EN)
        assert response.status_code == 400
        assert "A pipeline with this name exists." in _errors(response)


class TestAccountErrors:
    def _negative(self, client, headers):
        return client.post(
            "/api/accounts/",
            {"name": "Underwater Ltd", "annual_revenue": "-5000"},
            **headers,
        )

    def test_negative_revenue_in_english(self, admin_client):
        response = self._negative(admin_client, EN)
        assert response.status_code == 400
        assert "Annual revenue cannot be negative." in _errors(response)


class TestContactErrors:
    def test_missing_file_in_english(self, admin_client):
        response = admin_client.post("/api/contacts/import/preview/", {}, **EN)
        assert response.status_code == 400
        assert response.json()["message"] == "No file uploaded (expected field 'file')"


class TestOrderStatus:
    def test_status_label_in_english(self, org_a):
        order = Order(org=org_a, name="First order", status="CANCELLED")
        with translation.override("en"):
            assert order.get_status_display() == "Cancelled"


class TestStaleDealsAlert:
    def _send(self, org, profile, user):
        deal = Opportunity.objects.create(
            name="Very Stale", stage="PROSPECTING", org=org, created_by=user
        )
        deal.assigned_to.add(profile)
        send_stale_deals_alert(org, [(deal, "Prospecting", 30, 14)])
        return mail.outbox[-1]

    def test_member_without_a_choice_gets_the_org_default(
        self, org_a, admin_user, admin_profile
    ):
        message = self._send(org_a, admin_profile, admin_user)
        assert message.subject == "[BottleCRM] 1 deal went stale"
        assert "just went stale" in message.body
