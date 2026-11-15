"""Regenerate (and optionally compile) every app's message catalogs.

Each first-party app keeps its own ``locale/``. Django's ``makemessages`` has to
run from inside the app directory to write there, and from there an app's own
``tasks.py`` shadows the top-level ``tasks`` app on import, so it cannot be run
as ``cd <app> && manage.py makemessages``. This sets Django up from ``backend/``
first, then changes into each app.

    manage.py update_messages            # refresh every catalog, every language
    manage.py update_messages -l de      # also start a new language
    manage.py update_messages --compile  # then build the .mo files
"""

import os
from pathlib import Path

from django.apps import apps
from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand


def app_dirs_with_locale():
    base = Path(settings.BASE_DIR).resolve()
    dirs = []
    for config in apps.get_app_configs():
        path = Path(config.path).resolve()
        # A direct child of backend/: the virtualenv also lives under BASE_DIR.
        if path.parent == base and (path / "locale").is_dir():
            dirs.append(path)
    return sorted(dirs)


class Command(BaseCommand):
    help = "Run makemessages (and with --compile, compilemessages) in every app with a locale/ dir."

    def add_arguments(self, parser):
        parser.add_argument(
            "-l",
            "--locale",
            action="append",
            default=[],
            help="Also create catalogs for this language. Repeatable.",
        )
        parser.add_argument(
            "--compile", action="store_true", help="Compile .mo files afterwards."
        )

    def handle(self, *args, **options):
        start = os.getcwd()
        try:
            for path in app_dirs_with_locale():
                os.chdir(path)
                kwargs = {
                    "extensions": ["html", "txt", "py"],
                    "no_location": True,
                    "verbosity": 0,
                }
                call_command("makemessages", all=True, **kwargs)
                if options["locale"]:
                    call_command("makemessages", locale=options["locale"], **kwargs)
                if options["compile"]:
                    call_command("compilemessages", verbosity=0)
                self.stdout.write(f"{path.name}: done")
        finally:
            os.chdir(start)
