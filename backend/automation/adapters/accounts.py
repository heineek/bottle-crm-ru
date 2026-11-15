from django.utils.translation import gettext_lazy as _

from accounts.models import Account
from accounts.updates import update_account
from automation.objects import Adapter, FieldSpec, model_choices
from webhooks.events import account_data


class AccountAdapter(Adapter):
    route = "/accounts/{id}"
    FIELDS = (
        FieldSpec("name", _("Name"), "text"),
        FieldSpec("email", _("Email"), "text"),
        FieldSpec("phone", _("Phone"), "text"),
        FieldSpec("website", _("Website"), "text"),
        FieldSpec("city", _("City"), "text"),
        FieldSpec("country", _("Country"), "choice", model_choices(Account, "country")),
        FieldSpec(
            "industry", _("Industry"), "choice", model_choices(Account, "industry")
        ),
        FieldSpec("number_of_employees", _("Employees"), "number"),
        FieldSpec("annual_revenue", _("Annual revenue"), "number"),
        FieldSpec("assigned_to", _("Assigned to"), "people"),
    )

    def name(self, record):
        return record.name

    def task_parent(self, record):
        return {"account": str(record.pk)}

    def webhook_data(self, record):
        return account_data(record)

    def update(self, request, record, data):
        return update_account(request, record, data)
