from django.conf import settings
from django.db import models
from django.db.models import Q, F
from django.utils import timezone


class Item(models.Model):
    asset_tag = models.CharField(max_length=40, unique=True)
    name = models.CharField(max_length=120)
    description = models.CharField(max_length=300, blank=True)
    enabled = models.BooleanField(default=True)

    class Meta:
        ordering = ["name", "id"]
        constraints = [models.CheckConstraint(condition=~Q(asset_tag=""), name="item_tag_not_empty"),
                       models.CheckConstraint(condition=~Q(name=""), name="item_name_not_empty")]

    def __str__(self):
        return f"{self.name} ({self.asset_tag})"


class Loan(models.Model):
    item = models.ForeignKey(Item, on_delete=models.PROTECT, related_name="loans")
    borrower = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="equipment_loans")
    checked_out_at = models.DateTimeField(default=timezone.now)
    returned_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-checked_out_at", "-id"]
        constraints = [
            models.UniqueConstraint(fields=["item"], condition=Q(returned_at__isnull=True), name="one_active_loan_per_item"),
            models.CheckConstraint(condition=Q(returned_at__isnull=True) | Q(returned_at__gte=F("checked_out_at")), name="return_after_checkout"),
        ]
        indexes = [models.Index(fields=["borrower", "returned_at"], name="borrower_active_loans")]
