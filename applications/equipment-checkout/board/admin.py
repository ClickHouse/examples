from django.contrib import admin
from .models import Item, Loan


@admin.register(Item)
class ItemAdmin(admin.ModelAdmin):
    list_display = ["name", "asset_tag", "enabled"]
    search_fields = ["name", "asset_tag"]
    list_filter = ["enabled"]

    def save_model(self, request, obj, form, change):
        if change:
            # Django admin wraps save in atomic; coordinate disabling with borrow.
            Item.objects.select_for_update().get(pk=obj.pk)
        super().save_model(request, obj, form, change)

    def has_delete_permission(self, request, obj=None):
        return False  # Disable items instead; keep the loan history.


@admin.register(Loan)
class LoanAdmin(admin.ModelAdmin):
    list_display = ["item", "borrower", "checked_out_at", "returned_at"]
    list_filter = ["returned_at"]
    readonly_fields = ["item", "borrower", "checked_out_at", "returned_at"]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
