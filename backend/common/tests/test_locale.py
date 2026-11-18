"""Which language the API answers in, and who may change it.

See ``common/locale.py`` for the order: the user's choice, then
``Accept-Language``, then the org default, then English.

The order only shows with a second language, so these tests configure one
(``OTHER``) on top of whatever ``settings.LANGUAGES`` ships. Django and DRF
carry their own catalogs for it, which is what the error test reads.
"""

import pytest
from django.conf import settings as django_settings
from django.utils import translation
from django.utils.functional import lazy
from rest_framework import status

from common.locale import (
    language_for_org,
    language_for_user,
    language_from_header,
    resolve_language,
    supported_language,
)
from common.models import User

PROFILE = "/api/profile/"
SETTINGS = "/api/org/settings/"
LOCALES = "/api/org/locales/"

OTHER = "fr"
OTHER_NAME = "Français"


@pytest.fixture(autouse=True)
def two_languages(settings):
    settings.LANGUAGES = [*django_settings.LANGUAGES, (OTHER, OTHER_NAME)]


class _Obj:
    def __init__(self, **kw):
        self.__dict__.update(kw)


class TestResolveLanguage:
    def test_regional_tag_falls_back_to_base(self):
        assert supported_language("fr-CA") == "fr"
        assert supported_language("FR_fr") == "fr"
        assert supported_language("de") is None
        assert supported_language("") is None
        assert supported_language(None) is None

    def test_header_takes_first_supported_by_quality(self):
        assert language_from_header("de-DE,fr;q=0.8,en;q=0.5") == "fr"
        assert language_from_header("de, it") is None
        assert language_from_header("*") is None
        assert language_from_header("") is None

    def test_order_user_then_header_then_org(self):
        user_fr = _Obj(language="fr")
        user_none = _Obj(language="")
        org_fr = _Obj(default_language="fr")
        org_en = _Obj(default_language="en")

        assert resolve_language(user_fr, org_en, "en") == "fr"
        assert resolve_language(user_none, org_en, "fr") == "fr"
        assert resolve_language(user_none, org_fr, None) == "fr"
        assert resolve_language(user_none, org_fr, "en") == "en"
        assert resolve_language() == "en"

    def test_stored_code_no_longer_supported_falls_through(self):
        """A language removed from LANGUAGES must not fail requests."""
        assert (
            resolve_language(_Obj(language="xx"), _Obj(default_language="xx")) == "en"
        )

    def test_context_managers_restore_the_previous_language(self):
        with translation.override("en"):
            with language_for_user(_Obj(language="fr")):
                assert translation.get_language() == "fr"
            assert translation.get_language() == "en"
            with language_for_org(_Obj(default_language="fr")):
                assert translation.get_language() == "fr"
            assert translation.get_language() == "en"

    def test_member_without_choice_gets_org_language_in_mail(self):
        with language_for_user(_Obj(language=""), org=_Obj(default_language="fr")):
            assert translation.get_language() == "fr"


class TestRequestLanguage:
    def test_english_by_default(self, user_client):
        response = user_client.get(PROFILE)

        assert response.status_code == status.HTTP_200_OK
        assert response["Content-Language"] == "en"
        assert "Accept-Language" in response["Vary"]

    def test_accept_language_is_honoured(self, user_client):
        response = user_client.get(PROFILE, HTTP_ACCEPT_LANGUAGE="fr-CA,fr;q=0.9")

        assert response["Content-Language"] == "fr"

    def test_errors_come_back_translated(self, user_client):
        """Proves the language is active while DRF renders, not just stamped
        on the header: DRF ships its own messages in ``OTHER``."""
        other = user_client.patch(
            PROFILE, {"language": "xx"}, format="json", HTTP_ACCEPT_LANGUAGE=OTHER
        )
        english = user_client.patch(PROFILE, {"language": "xx"}, format="json")

        assert other.status_code == english.status_code == 400
        message = str(other.data["language"][0])
        assert message != str(english.data["language"][0]), message

    def test_user_choice_beats_the_header(self, user_client, regular_user):
        regular_user.language = "en"
        regular_user.save(update_fields=["language"])

        response = user_client.get(PROFILE, HTTP_ACCEPT_LANGUAGE="fr")

        assert response["Content-Language"] == "en"

    def test_org_default_applies_without_choice_or_header(self, user_client, org_a):
        org_a.default_language = "fr"
        org_a.save(update_fields=["default_language"])

        response = user_client.get(PROFILE)

        assert response["Content-Language"] == "fr"

    def test_language_does_not_leak_to_the_next_request(self, user_client):
        user_client.get(PROFILE, HTTP_ACCEPT_LANGUAGE="fr")

        assert user_client.get(PROFILE)["Content-Language"] == "en"

    def test_auth_endpoints_without_org_use_the_header(self, unauthenticated_client):
        response = unauthenticated_client.post(
            "/api/auth/magic-link/request/",
            {},
            format="json",
            HTTP_ACCEPT_LANGUAGE="fr",
        )

        assert response["Content-Language"] == "fr"


class TestOwnLanguage:
    # The profile serializer reads its choices from the shipped
    # settings.LANGUAGES at import, so PATCHes here pick English.
    def test_user_sets_and_reads_their_language(self, user_client, regular_user):
        response = user_client.patch(PROFILE, {"language": "en"}, format="json")

        assert response.status_code == status.HTTP_200_OK
        assert response.data["user_obj"]["language"] == "en"
        regular_user.refresh_from_db()
        assert regular_user.language == "en"
        assert user_client.get(PROFILE).data["user_obj"]["language"] == "en"

    def test_blank_clears_the_choice(self, user_client, regular_user):
        regular_user.language = OTHER
        regular_user.save(update_fields=["language"])

        response = user_client.patch(PROFILE, {"language": ""}, format="json")

        assert response.status_code == status.HTTP_200_OK
        regular_user.refresh_from_db()
        assert regular_user.language == ""

    def test_unsupported_code_is_refused(self, user_client, regular_user):
        response = user_client.patch(PROFILE, {"language": "xx"}, format="json")

        assert response.status_code == status.HTTP_400_BAD_REQUEST
        regular_user.refresh_from_db()
        assert regular_user.language == ""

    def test_only_the_caller_changes(self, user_client, admin_user, regular_user):
        """There is no target id: the endpoint writes request.user only."""
        user_client.patch(
            PROFILE, {"language": "en", "user": str(admin_user.id)}, format="json"
        )

        admin_user.refresh_from_db()
        assert admin_user.language == ""
        assert User.objects.get(pk=regular_user.pk).language == "en"

    def test_me_reports_the_language(self, user_client, regular_user):
        regular_user.language = OTHER
        regular_user.save(update_fields=["language"])

        assert user_client.get("/api/auth/me/").data["language"] == OTHER


class TestOrgDefaultLanguage:
    def test_admin_sets_it(self, admin_client, org_a):
        response = admin_client.patch(
            SETTINGS, {"default_language": OTHER}, format="json"
        )

        assert response.status_code == status.HTTP_200_OK
        assert response.data["default_language"] == OTHER
        org_a.refresh_from_db()
        assert org_a.default_language == OTHER

    def test_member_cannot(self, user_client, org_a):
        response = user_client.patch(
            SETTINGS, {"default_language": OTHER}, format="json"
        )

        assert response.status_code == status.HTTP_403_FORBIDDEN
        org_a.refresh_from_db()
        assert org_a.default_language == "en"

    def test_unsupported_code_is_refused(self, admin_client, org_a):
        response = admin_client.patch(
            SETTINGS, {"default_language": "xx"}, format="json"
        )

        assert response.status_code == status.HTTP_400_BAD_REQUEST
        org_a.refresh_from_db()
        assert org_a.default_language == "en"

    def test_it_changes_only_the_callers_org(self, admin_client, org_b):
        admin_client.patch(SETTINGS, {"default_language": OTHER}, format="json")

        org_b.refresh_from_db()
        assert org_b.default_language == "en"


class TestLocales:
    def test_lists_languages_countries_and_currencies(self, user_client):
        data = user_client.get(LOCALES).data

        configured = [code for code, _ in django_settings.LANGUAGES]
        assert [lang["code"] for lang in data["languages"]] == configured
        assert {"code": OTHER, "name": OTHER_NAME} in data["languages"]
        codes = {c["code"] for c in data["countries"]}
        assert {"DE", "US", "GB"} <= codes
        usd = next(c for c in data["currencies"] if c["code"] == "USD")
        assert usd["symbol"] == "$"

    def test_countries_are_sorted_by_name(self, user_client):
        names = [c["name"] for c in user_client.get(LOCALES).data["countries"]]

        assert names == sorted(names, key=str.casefold)

    def test_countries_are_named_in_the_callers_language(
        self, user_client, monkeypatch
    ):
        """A name stands in for a catalog entry: it is the language active
        when the view renders it, so a name fixed at import would fail."""
        en = user_client.get(LOCALES).data
        assert {c["code"]: c["name"] for c in en["countries"]}["DE"] == "Germany"

        active = lazy(translation.get_language, str)
        monkeypatch.setattr(
            "common.views.org_settings_views.COUNTRIES", [("DE", active())]
        )
        other = user_client.get(LOCALES, HTTP_ACCEPT_LANGUAGE=OTHER).data

        assert other["countries"] == [{"code": "DE", "name": OTHER}]

    def test_it_needs_a_signed_in_user(self, unauthenticated_client):
        response = unauthenticated_client.get(LOCALES)

        assert response.status_code in (
            status.HTTP_401_UNAUTHORIZED,
            status.HTTP_403_FORBIDDEN,
        )


@pytest.mark.parametrize("code", [c for c, _ in django_settings.LANGUAGES])
def test_every_configured_language_resolves_to_itself(code):
    assert supported_language(code) == code


class TestTokenClaims:
    """The web client reads the language from the JWT, with no API call."""

    def test_token_carries_the_users_and_the_orgs_language(
        self, regular_user, org_a, user_profile
    ):
        from common.serializer import OrgAwareRefreshToken

        regular_user.language = OTHER
        org_a.default_language = OTHER
        token = OrgAwareRefreshToken.for_user_and_org(regular_user, org_a, user_profile)

        assert token.access_token["language"] == OTHER
        assert token.access_token["org_settings"]["default_language"] == OTHER

    def test_blank_choice_stays_blank(self, regular_user, org_a, user_profile):
        from common.serializer import OrgAwareRefreshToken

        token = OrgAwareRefreshToken.for_user_and_org(regular_user, org_a, user_profile)

        assert token.access_token["language"] == ""
