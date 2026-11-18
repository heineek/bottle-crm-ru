"""Background work for web forms.

A Celery worker does not run Django middleware, so `set_rls_context` has to be
called explicitly before any ORM query. Without it every query below runs with
an empty `app.current_org` and returns zero rows, which reads as "no submission
found" rather than as a bug.
"""

import logging

from celery import shared_task
from django.template.loader import render_to_string
from django.utils.translation import gettext

from common.links import frontend_url
from common.locale import language_for_user, resolve_language
from common.tasks import set_rls_context
from leads.intake import converted_contact
from leads.tasks import send_email
from webforms.models import WebFormSubmission
from webforms.service import active_assignee

logger = logging.getLogger(__name__)


@shared_task
def send_webform_submission_email(submission_id, org_id):
    """Tell the form's recipients that a lead or ticket came in.

    The only mail a submission sends. Recipients are the form's active
    `notify_profiles` plus the record's assignee: on a lead form the lead's
    own active assignees who keep lead alerts by email on
    (`Profile.lead_alerts_email`), or, once the lead is converted, those of
    the contact it became; the form's active `assign_to` on a ticket form. One
    message to the union, so an assignee who is also a notify recipient
    receives one email rather than two, and one per language within it: each
    member reads it in their own (`common.locale.language_for_user`).

    Rejected submissions notify nobody. Telling an org about every bot that
    hits their form is how they learn to ignore the notification, and then to
    miss the real one.

    `send_email` is called directly rather than through `.delay()`. This is
    already inside a task, so enqueuing a second one buys nothing and would
    only add a hop where the message can be lost.
    """
    set_rls_context(org_id)

    submission = (
        WebFormSubmission.objects.filter(id=submission_id, org_id=org_id)
        .select_related("form", "form__org", "lead", "case", "form__assign_to")
        .first()
    )
    if submission is None:
        logger.info(
            "Web form submission %s is gone or belongs to another org; "
            "nothing to notify.",
            submission_id,
        )
        return

    if submission.status not in WebFormSubmission.ACCEPTED_STATUSES:
        return

    form = submission.form
    # Active members only: a deactivated one has left, and this mail carries
    # the prospect's details.
    profiles = set(
        form.notify_profiles.filter(is_active=True).select_related("user").all()
    )
    contact = None
    if submission.case_id:
        assignee = active_assignee(form)
        if assignee is not None:
            profiles.add(assignee)
    elif submission.lead_id:
        # Whoever the lead actually belongs to, not the form's `assign_to`. A
        # rotation form picks a different member each time, and a repeat
        # submission merges into a lead somebody else may already own.
        lead = submission.lead
        if lead.status == "converted":
            contact = converted_contact(lead)
        profiles.update(
            (contact or lead)
            .assigned_to.filter(
                org_id=org_id,
                is_active=True,
                user__is_active=True,
                lead_alerts_email=True,
            )
            .select_related("user")
        )

    users = {
        profile.user.email: profile.user
        for profile in profiles
        if getattr(profile, "user", None) and profile.user.email
    }
    if not users:
        logger.info("Web form %s has no notification recipients.", form.id)
        return

    by_language = {}
    for email in sorted(users):
        language = resolve_language(user=users[email], org=form.org)
        by_language.setdefault(language, []).append(email)

    if submission.case_id:
        record_url = frontend_url(f"/tickets/{submission.case_id}")
    else:
        record = (
            f"/contacts/{contact.id}" if contact else f"/leads/{submission.lead_id}"
        )
        record_url = frontend_url(record)
    for recipients in by_language.values():
        with language_for_user(users[recipients[0]], form.org):
            if submission.case_id:
                subject = gettext("New ticket: %(form)s") % {"form": form.name}
            else:
                subject = gettext("New submission: %(form)s") % {"form": form.name}
            html_content = render_to_string(
                "webforms/submission_email.html",
                {
                    "form": form,
                    "submission": submission,
                    "lead": submission.lead,
                    "case": submission.case,
                    "contact": contact,
                    "record_url": record_url,
                    "is_duplicate": (
                        submission.status == WebFormSubmission.ACCEPTED_DUPLICATE
                    ),
                },
            )
        send_email(
            subject=subject,
            html_content=html_content,
            recipients=recipients,
        )
