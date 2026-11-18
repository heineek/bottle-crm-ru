"""Invoice mail, PDFs and API errors in English, the source language, stay
exactly as they were once their strings moved into catalogs.

Which language a reader gets is tested in ``common/tests/test_locale.py``.
"""

from unittest.mock import patch

from django.core import mail

from invoices.models import Invoice
from invoices.pdf import generate_invoice_pdf
from invoices.tasks import send_invoice_to_client


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
    def test_english_org_is_unchanged(self, org_a):
        invoice = _invoice(org_a)

        send_invoice_to_client(str(invoice.id), str(org_a.id), include_pdf=False)

        message = mail.outbox[0]
        assert message.subject == (
            f"Invoice #{invoice.invoice_number} from {org_a.name}"
        )
        assert "<p>Dear Ada,</p>" in message.body
        assert '<html lang="en">' in message.body


class TestPdf:
    def test_english_pdf_is_unchanged(self, org_a):
        invoice = _invoice(org_a)

        html = _pdf_html(generate_invoice_pdf, invoice)

        assert '<html lang="en">' in html
        assert '<td class="totals-label">Subtotal</td>' in html
        assert "<p>Yours Sincerely,</p>" in html


class TestApiErrors:
    def test_validation_error_in_english(self, admin_client):
        body = {"invoice_title": "Bill", "tax_rate": "-1"}

        en = admin_client.post("/api/invoices/", body, format="json")

        assert en.status_code == 400
        assert en.json()["errors"]["tax_rate"] == ["Tax rate cannot be negative."]
