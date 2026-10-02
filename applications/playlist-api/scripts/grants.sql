GRANT USAGE ON SCHEMA playlist_api TO playlist_app;
GRANT SELECT ON playlist_api.accounts,playlist_api.playlists,playlist_api.items,playlist_api.tracks TO playlist_app;
GRANT INSERT(id,owner_id,name,revision),UPDATE(revision) ON playlist_api.playlists TO playlist_app;
GRANT INSERT(id,playlist_id,track_id,position),UPDATE(position) ON playlist_api.items TO playlist_app;
