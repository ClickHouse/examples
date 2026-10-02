from django.db import transaction
from django.http import Http404
from django.utils import timezone
from .models import Item, Loan


class Unavailable(Exception):
    pass


@transaction.atomic
def borrow_item(item_id, user):
    # Every writer uses item first. The partial unique constraint also protects
    # the invariant if a future writer forgets this locking protocol.
    try:
        item = Item.objects.select_for_update().get(pk=item_id)
    except Item.DoesNotExist:
        raise Http404
    if not item.enabled:
        raise Unavailable("This item is out of service.")
    active = Loan.objects.filter(item=item, returned_at__isnull=True).first()
    if active:
        if active.borrower_id == user.pk:
            return active, False
        raise Unavailable("Someone has already borrowed this item.")
    return Loan.objects.create(item=item, borrower=user), True


@transaction.atomic
def complete_return(loan_id, user):
    visible = Loan.objects.all() if user.is_staff else Loan.objects.filter(borrower=user)
    try:
        item_id = visible.values_list("item_id", flat=True).get(pk=loan_id)
    except Loan.DoesNotExist:
        raise Http404
    Item.objects.select_for_update().get(pk=item_id)
    loan = visible.select_for_update().get(pk=loan_id)
    if loan.returned_at is None:
        loan.returned_at = timezone.now()
        loan.save(update_fields=["returned_at"])
    return loan
