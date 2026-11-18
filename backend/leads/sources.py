"""Each org's list of lead sources, and the defaults every org starts with."""

from django.utils.translation import pgettext_lazy

from common.locale import language_for_org
from leads.models import LeadSource

DEFAULT_SOURCES = [
    ("call", pgettext_lazy("lead source", "Call")),
    ("email", pgettext_lazy("lead source", "Email")),
    ("existing customer", pgettext_lazy("lead source", "Existing customer")),
    ("partner", pgettext_lazy("lead source", "Partner")),
    ("public relations", pgettext_lazy("lead source", "Public relations")),
    ("campaign", pgettext_lazy("lead source", "Campaign")),
    ("other", pgettext_lazy("lead source", "Other")),
    ("web form", pgettext_lazy("lead source", "Web form")),
    ("meta ads", pgettext_lazy("lead source", "Meta ads")),
    ("google ads", pgettext_lazy("lead source", "Google ads")),
    ("linkedin ads", pgettext_lazy("lead source", "LinkedIn ads")),
    (
        "directory or marketplace",
        pgettext_lazy("lead source", "Directory or marketplace"),
    ),
    ("whatsapp", pgettext_lazy("lead source", "WhatsApp")),
    ("referral", pgettext_lazy("lead source", "Referral")),
    ("walk-in", pgettext_lazy("lead source", "Walk-in")),
]


def derive_key(label: str) -> str:
    """A source's key: its label lowercased, with single spaces."""
    return " ".join(label.lower().split())


def org_sources(org, create=True) -> list[LeadSource]:
    """The org's sources by `order`, retired ones included, with every default.

    `create` saves any default the org lacks first. Sources cannot be deleted,
    so that is only ever the first use, or the first after a pack added its
    own, and `ignore_conflicts` lets two first requests race safely. With
    `create=False` nothing is written and missing defaults come back unsaved,
    for a caller that only reads keys and labels.
    """
    sources = list(LeadSource.objects.filter(org=org))
    present = {source.key for source in sources}
    # A default's label is the org's own data once saved, so it is written
    # in the org's language, never the requester's.
    with language_for_org(org):
        missing = [
            LeadSource(org=org, key=key, label=str(label), order=order)
            for order, (key, label) in enumerate(DEFAULT_SOURCES)
            if key not in present
        ]
    if not missing:
        return sources
    if not create:
        return sorted(sources + missing, key=lambda s: (s.order, s.label))
    LeadSource.objects.bulk_create(missing, ignore_conflicts=True)
    return list(LeadSource.objects.filter(org=org))


def source_keys(org, active_only=True) -> set[str]:
    return {
        s.key for s in org_sources(org, create=False) if s.is_active or not active_only
    }


def source_labels(org) -> dict[str, str]:
    return {s.key: s.label for s in org_sources(org, create=False)}
