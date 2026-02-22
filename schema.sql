-- =====================================================
-- ENUM TYPES
-- =====================================================

-- User role enumeration
CREATE TYPE user_role AS ENUM ('user', 'artist', 'admin');

-- User subscription type
CREATE TYPE subscription_type AS ENUM ('basic', 'plus', 'premium');

-- =====================================================
-- TABLES
-- =====================================================

-- Users table (artists are users with role = 'artist')
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    role user_role DEFAULT 'user',
    subscription subscription_type DEFAULT 'basic',
    cover VARCHAR(512),
    is_verified BOOLEAN DEFAULT FALSE,
    verification_token VARCHAR(512),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for username searches (used in login)
CREATE INDEX idx_users_username ON users(username);

-- Index for verification token lookups
CREATE INDEX idx_users_verification_token ON users(verification_token);

-- Index for artist searches
CREATE INDEX idx_users_is_artist ON users(role) WHERE role = 'artist';

-- Index for subscription-based sorting
CREATE INDEX idx_users_subscription ON users(subscription);


-- Albums table
CREATE TABLE albums (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    artist_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cover VARCHAR(512),
    release_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for albums by artist
CREATE INDEX idx_albums_artist_id ON albums(artist_id);

-- Index for album name searches
CREATE INDEX idx_albums_name ON albums(name);


-- Songs table
CREATE TABLE songs (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    artist_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL,
    path VARCHAR(512) NOT NULL,
    cover VARCHAR(512) NOT NULL,
    plays INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for songs
CREATE INDEX idx_songs_artist_id ON songs(artist_id);
CREATE INDEX idx_songs_album_id ON songs(album_id);
CREATE INDEX idx_songs_name ON songs(name);
CREATE INDEX idx_songs_plays ON songs(plays DESC);


-- Playlists table
CREATE TABLE playlists (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for playlists by user
CREATE INDEX idx_playlists_user_id ON playlists(user_id);


-- Playlist songs junction table
CREATE TABLE playlist_songs (
    id SERIAL PRIMARY KEY,
    playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    song_id INTEGER NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
    position INTEGER,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(playlist_id, song_id)
);

-- Index for playlist songs
CREATE INDEX idx_playlist_songs_playlist_id ON playlist_songs(playlist_id);
CREATE INDEX idx_playlist_songs_song_id ON playlist_songs(song_id);


-- =====================================================
-- FUNCTIONS (Stored Procedures)
-- =====================================================

-- Function to create a new user
CREATE OR REPLACE FUNCTION create_user(
    p_username VARCHAR,
    p_password VARCHAR,
    p_email VARCHAR
) RETURNS INTEGER AS $$
DECLARE
    new_user_id INTEGER;
BEGIN
    INSERT INTO users (username, password, email)
    VALUES (p_username, p_password, p_email)
    RETURNING id INTO new_user_id;
    
    RETURN new_user_id;
END;
$$ LANGUAGE plpgsql;


-- Function to create a song
CREATE OR REPLACE FUNCTION create_song(
    p_name VARCHAR,
    p_artist_id INTEGER
) RETURNS INTEGER AS $$
DECLARE
    new_song_id INTEGER;
BEGIN
    INSERT INTO songs (name, artist_id, path, cover)
    VALUES (
        p_name, 
        p_artist_id,
        'songs/' || nextval('songs_id_seq')::TEXT || '/song.mp3',
        'covers/songs/' || nextval('songs_id_seq')::TEXT || '/cover.png'
    )
    RETURNING id INTO new_song_id;
    
    RETURN new_song_id;
END;
$$ LANGUAGE plpgsql;


-- Function to create a song in an album
CREATE OR REPLACE FUNCTION create_song_in_album(
    p_name VARCHAR,
    p_artist_id INTEGER,
    p_album_id INTEGER
) RETURNS INTEGER AS $$
DECLARE
    new_song_id INTEGER;
BEGIN
    INSERT INTO songs (name, artist_id, album_id, path, cover)
    VALUES (
        p_name, 
        p_artist_id, 
        p_album_id,
        'songs/' || nextval('songs_id_seq')::TEXT || '/song.mp3',
        'covers/songs/' || nextval('songs_id_seq')::TEXT || '/cover.png'
    )
    RETURNING id INTO new_song_id;
    
    RETURN new_song_id;
END;
$$ LANGUAGE plpgsql;


-- Function to create an album
CREATE OR REPLACE FUNCTION create_album(
    p_name VARCHAR,
    p_artist_id INTEGER,
    p_release_date DATE
) RETURNS INTEGER AS $$
DECLARE
    new_album_id INTEGER;
BEGIN
    INSERT INTO albums (name, artist_id, release_date, cover)
    VALUES (
        p_name, 
        p_artist_id, 
        p_release_date,
        'covers/albums/' || nextval('albums_id_seq')::TEXT || '/cover.png'
    )
    RETURNING id INTO new_album_id;
    
    RETURN new_album_id;
END;
$$ LANGUAGE plpgsql;


-- Function to delete a song (cascade handled by triggers if needed)
CREATE OR REPLACE FUNCTION delete_song(p_song_id INTEGER)
RETURNS VOID AS $$
BEGIN
    DELETE FROM playlist_songs WHERE song_id = p_song_id;
    DELETE FROM songs WHERE id = p_song_id;
END;
$$ LANGUAGE plpgsql;


-- Function to delete an album
CREATE OR REPLACE FUNCTION delete_album(p_album_id INTEGER)
RETURNS VOID AS $$
BEGIN
    -- First set album_id to NULL for all songs in this album
    UPDATE songs SET album_id = NULL WHERE album_id = p_album_id;
    -- Then delete the album
    DELETE FROM albums WHERE id = p_album_id;
END;
$$ LANGUAGE plpgsql;


-- Function to create a playlist
CREATE OR REPLACE FUNCTION create_playlist(
    p_name VARCHAR,
    p_user_id INTEGER
) RETURNS INTEGER AS $$
DECLARE
    new_playlist_id INTEGER;
BEGIN
    INSERT INTO playlists (name, user_id)
    VALUES (p_name, p_user_id)
    RETURNING id INTO new_playlist_id;
    
    RETURN new_playlist_id;
END;
$$ LANGUAGE plpgsql;


-- Function to delete a playlist
CREATE OR REPLACE FUNCTION delete_playlist(p_playlist_id INTEGER)
RETURNS VOID AS $$
BEGIN
    DELETE FROM playlist_songs WHERE playlist_id = p_playlist_id;
    DELETE FROM playlists WHERE id = p_playlist_id;
END;
$$ LANGUAGE plpgsql;


-- Function to add a song to playlist
CREATE OR REPLACE FUNCTION add_to_playlist(
    p_playlist_id INTEGER,
    p_song_id INTEGER
) RETURNS VOID AS $$
BEGIN
    INSERT INTO playlist_songs (playlist_id, song_id)
    VALUES (p_playlist_id, p_song_id)
    ON CONFLICT (playlist_id, song_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;


-- Function to remove a song from playlist
CREATE OR REPLACE FUNCTION remove_from_playlist(
    p_playlist_id INTEGER,
    p_song_id INTEGER
) RETURNS VOID AS $$
BEGIN
    DELETE FROM playlist_songs 
    WHERE playlist_id = p_playlist_id AND song_id = p_song_id;
END;
$$ LANGUAGE plpgsql;


-- =====================================================
-- TRIGGERS for automatic updated_at
-- =====================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for each table
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_albums_updated_at
    BEFORE UPDATE ON albums
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_songs_updated_at
    BEFORE UPDATE ON songs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_playlists_updated_at
    BEFORE UPDATE ON playlists
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- =====================================================
-- VIEWS for common queries
-- =====================================================

-- View for songs with artist name
CREATE VIEW v_songs_with_artist AS
SELECT 
    s.id,
    s.name AS song_name,
    s.artist_id,
    u.username AS artist_name,
    s.album_id,
    a.name AS album_name,
    s.plays,
    s.cover,
    s.path,
    s.created_at
FROM songs s
LEFT JOIN users u ON s.artist_id = u.id
LEFT JOIN albums a ON s.album_id = a.id;

-- View for albums with artist name
CREATE VIEW v_albums_with_artist AS
SELECT 
    a.id,
    a.name AS album_name,
    a.artist_id,
    u.username AS artist_name,
    a.cover,
    a.release_date,
    a.created_at,
    COUNT(s.id) AS song_count
FROM albums a
LEFT JOIN users u ON a.artist_id = u.id
LEFT JOIN songs s ON a.id = s.album_id
GROUP BY a.id, u.username;

-- View for playlist details
CREATE VIEW v_playlist_details AS
SELECT 
    p.id,
    p.name AS playlist_name,
    p.user_id,
    u.username AS user_name,
    COUNT(ps.song_id) AS song_count,
    p.created_at
FROM playlists p
LEFT JOIN users u ON p.user_id = u.id
LEFT JOIN playlist_songs ps ON p.id = ps.playlist_id
GROUP BY p.id, u.username;