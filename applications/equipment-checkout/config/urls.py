from django.contrib import admin
from django.contrib.auth import views as auth_views
from django.urls import path
from board import views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("accounts/login/", auth_views.LoginView.as_view(), name="login"),
    path("accounts/logout/", auth_views.LogoutView.as_view(), name="logout"),
    path("", views.board, name="board"),
    path("items/<int:item_id>/borrow/", views.borrow, name="borrow"),
    path("loans/<int:loan_id>/return/", views.return_loan, name="return_loan"),
]
