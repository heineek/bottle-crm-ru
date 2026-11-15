"""Mail to a customer and every PDF follow the org's language; mail to a
member follows theirs; an API error follows the request's."""

from datetime import timedelta
from unittest.mock import patch

import pytest
from django.core import mail
from django.utils import timezone, translation

from invoices.models import Estimate, Invoice
from invoices.pdf import generate_estimate_pdf, generate_invoice_pdf
from invoices.tasks import send_email, send_invoice_to_client, send_payment_reminder


@pytest.fixture
def ru_org(org_a):
    org_a.default_language = "ru"
    org_a.save(update_fields=["default_language"])
    return org_a


def _invoice(org, **extra):
    return Invoice.objects.create(
        org=org,
        invoice_title="Consulting",
        client_name="Ada",
        client_email="client@example.com",
        **extra,
    )


def _pdf_html(render, document):
    """The HTML ``render(document)`` hands WeasyPrint."""
    captured = []

    def capture(html, css):
        captured.append(html)
        return b"%PDF"

    with (
        patch("invoices.pdf.check_weasyprint"),
        patch("invoices.pdf._write_pdf", side_effect=capture),
    ):
        render(document)
    return captured[0]


class TestClientEmail:
    def test_russian_org_mails_the_client_in_russian(self, ru_org):
        invoice = _invoice(ru_org)

        send_invoice_to_client(str(invoice.id), str(ru_org.id), include_pdf=False)

        message = mail.outbox[0]
        assert message.subject == (f"Счёт №{invoice.invoice_number} от {ru_org.name}")
        assert "Здравствуйте, Ada!" in message.body
        assert "Dear" not in message.body
        assert translation.get_language() != "ru"

    def test_english_org_is_unchanged(self, org_a):
        invoice = _invoice(org_a)

        send_invoice_to_client(str(invoice.id), str(org_a.id), include_pdf=False)

        message = mail.outbox[0]
        assert message.subject == (
            f"Invoice #{invoice.invoice_number} from {org_a.name}"
        )
        assert "<p>Dear Ada,</p>" in message.body
        assert '<html lang="en">' in message.body

    @pytest.mark.parametrize(
        "days, phrase", [(1, "1 день"), (3, "3 дня"), (5, "5 дней"), (21, "21 день")]
    )
    def test_overdue_reminder_counts_days_in_russian(self, ru_org, days, phrase):
        invoice = _invoice(
            ru_org,
            status="Sent",
            due_date=timezone.localdate() - timedelta(days=days),
        )

        send_payment_reminder(str(invoice.id), str(ru_org.id))

        assert f"просрочена на {phrase}</span>" in mail.outbox[0].body


class TestMemberEmail:
    def test_assignment_mail_follows_the_members_language(
        self, org_a, admin_profile, user_profile
    ):
        user_profile.user.language = "ru"
        user_profile.user.save(update_fields=["language"])
        invoice = _invoice(org_a)

        send_email(
            str(invoice.id),
            [str(admin_profile.id), str(user_profile.id)],
            str(org_a.id),
        )

        by_recipient = {m.to[0]: m for m in mail.outbox}
        number = invoice.invoice_number
        assert by_recipient[user_profile.user.email].subject == (
            f"Вам назначен счёт №{number}"
        )
        assert by_recipient[admin_profile.user.email].subject == (
            f"Invoice #{number} has been assigned to you"
        )


class TestPdf:
    def test_invoice_pdf_is_in_the_orgs_language_whoever_renders_it(self, ru_org):
        invoice = _invoice(ru_org)

        with translation.override("en"):
            html = _pdf_html(generate_invoice_pdf, invoice)

        assert '<html lang="ru">' in html
        assert "Промежуточный итог" in html
        assert "Subtotal" not in html

    def test_estimate_status_agrees_with_the_estimate(self, ru_org):
        estimate = Estimate.objects.create(
            org=ru_org, title="Quote", client_name="Ada", status="Sent"
        )

        html = _pdf_html(generate_estimate_pdf, estimate)

        assert ">Отправлено</span>" in html

    def test_english_pdf_is_unchanged(self, org_a):
        invoice = _invoice(org_a)

        with translation.override("ru"):
            html = _pdf_html(generate_invoice_pdf, invoice)

        assert '<html lang="en">' in html
        assert '<td class="totals-label">Subtotal</td>' in html
        assert "<p>Yours Sincerely,</p>" in html


class TestApiErrors:
    def test_validation_error_follows_accept_language(self, admin_client):
        body = {"invoice_title": "Bill", "tax_rate": "-1"}

        ru = admin_client.post(
            "/api/invoices/", body, format="json", HTTP_ACCEPT_LANGUAGE="ru"
        )
        en = admin_client.post("/api/invoices/", body, format="json")

        assert ru.status_code == en.status_code == 400
        assert ru.json()["errors"]["tax_rate"] == [
            "Ставка налога не может быть отрицательной."
        ]
        assert en.json()["errors"]["tax_rate"] == ["Tax rate cannot be negative."]

    def test_not_found_message_follows_accept_language(self, admin_client):
        missing = "00000000-0000-0000-0000-000000000000"

        ru = admin_client.get(f"/api/invoices/{missing}/", HTTP_ACCEPT_LANGUAGE="ru")

        assert ru.status_code == 404
        assert ru.json()["message"] == "Счёт не найден"
