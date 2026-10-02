from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db import DatabaseError
from django.db.models import Exists, OuterRef
from django.shortcuts import redirect, render
from django.http import HttpResponse
from django.views.decorators.http import require_GET, require_POST
from .models import Item, Loan
from .services import borrow_item, complete_return, Unavailable


def render_board(request, notice="", status=200):
    active = Loan.objects.filter(item=OuterRef("pk"), returned_at__isnull=True)
    items = Item.objects.annotate(on_loan=Exists(active))
    loans = Loan.objects.filter(returned_at__isnull=True).select_related("item", "borrower")
    if not request.user.is_staff:
        loans = loans.filter(borrower=request.user)
    template = "board/_board.html" if request.headers.get("HX-Request") == "true" else "board/index.html"
    response = render(request, template, {"items": items, "loans": loans, "notice": notice}, status=status)
    response["Cache-Control"] = "no-store"
    response["Vary"] = "HX-Request, Cookie"
    return response


@login_required
@require_GET
def board(request):
    return render_board(request)


def mutation_response(request, notice, status=200):
    if request.headers.get("HX-Request") == "true" or status != 200:
        return render_board(request, notice, status)
    messages.success(request, notice)
    return redirect("board")


@login_required
@require_POST
def borrow(request, item_id):
    try:
        loan, created = borrow_item(item_id, request.user)
    except Unavailable as error:
        return mutation_response(request, str(error), 409)
    except DatabaseError:
        return HttpResponse('<div id="board"><p role="status">The database is busy. <a href="/">Refresh and try again.</a></p></div>', status=503)
    return mutation_response(request, f"Borrowed {loan.item.name}." if created else "You already have this item.")


@login_required
@require_POST
def return_loan(request, loan_id):
    try:
        loan = complete_return(loan_id, request.user)
    except DatabaseError:
        return HttpResponse('<div id="board"><p role="status">The database is busy. <a href="/">Refresh and try again.</a></p></div>', status=503)
    return mutation_response(request, f"Returned {loan.item.name}.")
