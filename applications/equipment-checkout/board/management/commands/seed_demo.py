import os
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from board.models import Item


class Command(BaseCommand):
    help = "Create demo members and inventory; set passwords only when creating users."

    @transaction.atomic
    def handle(self, *args, **kwargs):
        password = os.environ.get("DEMO_PASSWORD", "")
        if len(password) < 12:
            raise CommandError("Set DEMO_PASSWORD to at least 12 characters.")
        for name, staff in [("alex", False), ("sam", False), ("staff", True)]:
            user, created = get_user_model().objects.get_or_create(username=name)
            if created:
                user.set_password(password)
                user.is_staff = staff
                user.is_superuser = staff
                user.save()
        for tag, name, description in [
            ("CAM-01", "Mirrorless camera", "Camera, battery and lens in one case."),
            ("MIC-01", "USB microphone", "For recording calls and workshops."),
            ("PRJ-01", "Portable projector", "Includes HDMI cable and remote."),
            ("TRI-01", "Travel tripod", "Lightweight tripod with quick release plate."),
        ]:
            Item.objects.get_or_create(asset_tag=tag, defaults={"name": name, "description": description})
        self.stdout.write(self.style.SUCCESS("Demo members and four equipment items are ready."))
