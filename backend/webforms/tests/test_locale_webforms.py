"""The public web form in English, the source language.

A public form follows the visitor's `Accept-Language` when it names a language
we ship, else the org's default. Field labels and the button are tenant text
and are never translated.
"""

import pytest

from webforms.models import WebForm, WebFormField


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
    def test_english_org_stays_english(self, unauthenticated_client, org_a, form):
        html = unauthenticated_client.get(embed_url(form)).content.decode()
        assert '<html lang="en">' in html
        assert "Leave this field empty" in html
        assert 'data-msg-thanks="Thanks."' in html
