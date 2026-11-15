from django.utils.translation import gettext_lazy as _

from automation.objects import Adapter, FieldSpec, model_choices
from contacts.models import Contact
from contacts.updates import update_contact
from webhooks.events import contact_data


class ContactAdapter(Adapter):
    route = "/contacts/{id}"
    FIELDS = (
        FieldSpec("first_name", _("First name"), "text"),
        FieldSpec("last_name", _("Last name"), "text"),
        FieldSpec("email", _("Email"), "text"),
        FieldSpec("phone", _("Phone"), "text"),
        FieldSpec("organization", _("Company"), "text"),
        FieldSpec("title", _("Job title"), "text"),
        FieldSpec("department", _("Department"), "text"),
        FieldSpec("city", _("City"), "text"),
        FieldSpec("country", _("Country"), "choice", model_choices(Contact, "country")),
        FieldSpec("do_not_call", _("Do not call"), "boolean"),
        FieldSpec("assigned_to", _("Assigned to"), "people"),
    )

    def name(self, record):
        full = f"{record.first_name or ''} {record.last_name or ''}".strip()
        return full or record.email or "Unnamed contact"

    def task_parent(self, record):
        return {"contacts": [str(record.pk)]}

    def webhook_data(self, record):
        return contact_data(record)

    def update(self, request, record, data):
        return update_contact(request, record, data)
