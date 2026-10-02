diesel::table! {
    redirect_links.accounts (id) {
        id -> Text,
        link_count -> Int4,
    }
}

diesel::table! {
    redirect_links.links (id) {
        id -> Int8,
        account -> Text,
        slug -> Text,
        destination -> Text,
        expires_at -> Nullable<Timestamptz>,
        disabled_at -> Nullable<Timestamptz>,
        revision -> Int8,
        created_at -> Timestamptz,
    }
}

diesel::joinable!(links -> accounts (account));
diesel::allow_tables_to_appear_in_same_query!(accounts, links);
