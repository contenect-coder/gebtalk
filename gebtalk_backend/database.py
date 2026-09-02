import sqlite3
import os
import psycopg2  # type: ignore
from psycopg2.extras import RealDictCursor  # type: ignore
from psycopg2.pool import ThreadedConnectionPool  # type: ignore

def load_env():
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    os.environ[key.strip()] = val.strip()

load_env()

_connection_pool = None
_use_sqlite_fallback = False

class CaseInsensitiveDict(dict):
    def __getitem__(self, key):
        if isinstance(key, str):
            key_lower = key.lower()
            for k in self:
                if k.lower() == key_lower:
                    return super().__getitem__(k)
            if 'count(*)' in [k.lower() for k in self]:
                for k in self:
                    if k.lower() == 'count(*)':
                        return super().__getitem__(k)
        return super().__getitem__(key)

    def get(self, key, default=None):
        try:
            return self[key]
        except KeyError:
            return default

class SQLiteCursorWrapper:
    def __init__(self, cursor):
        self._cursor = cursor
        self.lastrowid = cursor.lastrowid

    def _clean_sql(self, sql):
        sql_clean = (sql.replace('%s', '?')
                     .replace('::jsonb', '')
                     .replace('JSONB', 'TEXT')
                     .replace('ILIKE', 'LIKE')
                     .replace('RETURNING *', '')
                     .replace('RETURNING id', '')
                     .replace('TIMESTAMP WITH TIME ZONE', 'TIMESTAMP')
                     .replace('SERIAL PRIMARY KEY', 'INTEGER PRIMARY KEY AUTOINCREMENT'))
        if 'DISTINCT ON (contact_id)' in sql_clean:
            sql_clean = 'SELECT * FROM messages WHERE id IN (SELECT MAX(id) FROM messages GROUP BY contact_id) ORDER BY contact_id, id DESC'
        return sql_clean

    def execute(self, sql, params=None):
        sql_converted = self._clean_sql(sql)
        if params is None:
            self._cursor.execute(sql_converted)
        else:
            self._cursor.execute(sql_converted, params)
        self.lastrowid = self._cursor.lastrowid
        return self

    def executemany(self, sql, seq_of_params):
        sql_converted = self._clean_sql(sql)
        self._cursor.executemany(sql_converted, seq_of_params)
        return self

    def fetchone(self):
        row = self._cursor.fetchone()
        if row is None:
            return None
        return CaseInsensitiveDict(row)

    def fetchall(self):
        rows = self._cursor.fetchall()
        return [CaseInsensitiveDict(r) for r in rows]

    def __iter__(self):
        for row in self._cursor.fetchall():
            yield CaseInsensitiveDict(row)

class SQLiteConnectionWrapper:
    def __init__(self, db_path=None):
        if db_path is None:
            db_path = os.path.join(os.path.dirname(__file__), 'gebtalk.db')
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self.closed = 0

    def cursor(self):
        return SQLiteCursorWrapper(self._conn.cursor())

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        try:
            self._conn.close()
        except Exception:
            pass
        self.closed = 1

class PoolConnectionWrapper:
    def __init__(self, conn, pool):
        self._conn = conn
        self._pool = pool

    def __getattr__(self, name):
        if self._conn is None:
            raise psycopg2.InterfaceError("Connection is closed")
        return getattr(self._conn, name)

    @property
    def closed(self):
        if self._conn is None:
            return 1  # 0 means open, non-zero means closed
        return self._conn.closed

    def close(self):
        if self._conn is not None:
            try:
                self._pool.putconn(self._conn)
            except Exception as e:
                print(f"Error returning connection to pool: {e}")
            self._conn = None

def get_db_connection():
    global _connection_pool, _use_sqlite_fallback
    if _use_sqlite_fallback:
        return SQLiteConnectionWrapper()

    db_url = os.environ.get('SUPABASE_DB_URL', '')
    if not db_url or 'YOUR_PASSWORD' in db_url:
        _use_sqlite_fallback = True
        return SQLiteConnectionWrapper()

    try:
        if _connection_pool is None:
            conn_url = db_url
            if 'connect_timeout=' not in conn_url:
                conn_url += ('&' if '?' in conn_url else '?') + 'connect_timeout=3'
            _connection_pool = ThreadedConnectionPool(2, 20, conn_url, cursor_factory=RealDictCursor)
        conn = _connection_pool.getconn()
        return PoolConnectionWrapper(conn, _connection_pool)
    except Exception as e:
        print(f"PostgreSQL connection failed ({e}). Falling back to local SQLite database (gebtalk.db).")
        _use_sqlite_fallback = True
        return SQLiteConnectionWrapper()

def init_db(seed_test_data=False):
    try:
        conn = get_db_connection()
    except Exception as e:
        print(f"Database connection failed: {e}")
        return


    cursor = conn.cursor()

    # Create Contacts table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS contacts (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            role TEXT,
            avatar TEXT,
            status TEXT,
            folder TEXT,
            unread_count INTEGER DEFAULT 0,
            assigned_staff_id TEXT,
            email TEXT,
            notes TEXT,
            country_code TEXT,
            manager_id TEXT,
            FOREIGN KEY (assigned_staff_id) REFERENCES contacts (id) ON DELETE SET NULL,
            FOREIGN KEY (manager_id) REFERENCES contacts (id) ON DELETE SET NULL
        )
    ''')

    # Create Folders table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT
        )
    ''')

    # Create Tags table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT
        )
    ''')

    # Create Chat Tags mapping table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS chat_tags (
            contact_id TEXT,
            tag_id TEXT,
            PRIMARY KEY (contact_id, tag_id),
            FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
        )
    ''')

    # Create Messages table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS messages (
            id SERIAL PRIMARY KEY,
            contact_id TEXT,
            text TEXT,
            is_user BOOLEAN,
            time TEXT,
            is_audio BOOLEAN DEFAULT FALSE,
            duration TEXT,
            is_file BOOLEAN DEFAULT FALSE,
            file_name TEXT,
            file_size TEXT,
            reactions JSONB DEFAULT '[]'::jsonb,
            status TEXT DEFAULT 'sent',
            is_broadcast BOOLEAN DEFAULT FALSE,
            FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
        )
    ''')

    # Create User Profile table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_profile (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            phone TEXT NOT NULL,
            avatar TEXT,
            email TEXT,
            notifications_enabled BOOLEAN DEFAULT TRUE,
            notification_sound BOOLEAN DEFAULT TRUE,
            notification_vibration BOOLEAN DEFAULT TRUE,
            security_2fa BOOLEAN DEFAULT FALSE,
            read_receipts BOOLEAN DEFAULT TRUE,
            last_seen_visible BOOLEAN DEFAULT TRUE,
            country_code TEXT,
            country_name TEXT,
            country_flag TEXT,
            created_at TEXT,
            verification_status TEXT
        )
    ''')

    # Create WebRTC Calls table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS webrtc_calls (
            id SERIAL PRIMARY KEY,
            caller_id TEXT,
            callee_id TEXT,
            sdp_offer TEXT,
            sdp_answer TEXT,
            status TEXT DEFAULT 'ringing',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create WebRTC Candidates table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS webrtc_candidates (
            id SERIAL PRIMARY KEY,
            call_id INTEGER REFERENCES webrtc_calls (id) ON DELETE CASCADE,
            sender_id TEXT,
            candidate TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Statuses (Stories) table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS statuses (
            id TEXT PRIMARY KEY,
            contact_id TEXT NOT NULL,
            user_name TEXT,
            user_avatar TEXT,
            content_text TEXT,
            media_url TEXT,
            caption TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP,
            FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
        )
    ''')

    # Create Polls table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS polls (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            question TEXT NOT NULL,
            options_json TEXT NOT NULL,
            multiple_answers BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Poll Votes table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS poll_votes (
            id TEXT PRIMARY KEY,
            poll_id TEXT REFERENCES polls (id) ON DELETE CASCADE,
            option_index INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Call Logs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS call_logs (
            id SERIAL PRIMARY KEY,
            contact_id TEXT NOT NULL,
            contact_name TEXT,
            contact_avatar TEXT,
            call_type TEXT NOT NULL,
            direction TEXT NOT NULL,
            time_str TEXT NOT NULL,
            duration TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Schema migration helper for user_profile, contacts, and messages columns
    for table, col_def in [
        ("user_profile", "country_code TEXT"),
        ("user_profile", "country_name TEXT"),
        ("user_profile", "country_flag TEXT"),
        ("user_profile", "created_at TEXT"),
        ("user_profile", "verification_status TEXT"),
        ("user_profile", "app_lock_enabled BOOLEAN DEFAULT FALSE"),
        ("user_profile", "app_lock_pin TEXT"),
        ("contacts", "email TEXT"),
        ("contacts", "notes TEXT"),
        ("contacts", "country_code TEXT"),
        ("contacts", "manager_id TEXT"),
        ("contacts", "is_group BOOLEAN DEFAULT FALSE"),
        ("contacts", "is_channel BOOLEAN DEFAULT FALSE"),
        ("contacts", "disappearing_timer INTEGER DEFAULT 0"),
        ("contacts", "is_locked BOOLEAN DEFAULT FALSE"),
        ("messages", "status TEXT DEFAULT 'sent'"),
        ("messages", "is_broadcast BOOLEAN DEFAULT FALSE"),
        ("messages", "reply_to_id INTEGER"),
        ("messages", "reply_to_text TEXT"),
        ("messages", "reply_to_sender TEXT"),
        ("messages", "is_edited BOOLEAN DEFAULT FALSE"),
        ("messages", "is_deleted BOOLEAN DEFAULT FALSE"),
        ("messages", "is_pinned BOOLEAN DEFAULT FALSE"),
        ("messages", "is_starred BOOLEAN DEFAULT FALSE"),
        ("messages", "poll_id TEXT"),
        ("messages", "latitude REAL"),
        ("messages", "longitude REAL"),
        ("messages", "location_name TEXT"),
        ("messages", "contact_card_id TEXT"),
        ("messages", "contact_card_name TEXT"),
        ("messages", "contact_card_phone TEXT"),
        ("statuses", "background_color TEXT"),
        ("statuses", "font_style TEXT"),
        ("statuses", "views_json TEXT DEFAULT '[]'"),
        # Phase 1: Message media & forwarding columns
        ("messages", "media_type TEXT"),
        ("messages", "thumbnail_url TEXT"),
        ("messages", "media_width INTEGER"),
        ("messages", "media_height INTEGER"),
        ("messages", "forward_count INTEGER DEFAULT 0"),
        ("messages", "is_view_once BOOLEAN DEFAULT FALSE"),
        ("messages", "is_viewed BOOLEAN DEFAULT FALSE"),
        ("messages", "pinned_at TIMESTAMP"),
        # Phase 1: User profile about & privacy columns
        ("user_profile", "about TEXT DEFAULT 'Hey there! I am using GebTalk'"),
        ("user_profile", "profile_photo_privacy TEXT DEFAULT 'everyone'"),
        ("user_profile", "about_privacy TEXT DEFAULT 'everyone'"),
        ("user_profile", "status_privacy TEXT DEFAULT 'contacts'"),
        ("user_profile", "groups_privacy TEXT DEFAULT 'everyone'"),
        ("user_profile", "last_seen_privacy TEXT DEFAULT 'everyone'"),
        ("user_profile", "online_privacy TEXT DEFAULT 'everyone'"),
        ("user_profile", "username TEXT DEFAULT 'marcus_sterling'"),
        ("user_profile", "user_uid TEXT DEFAULT 'USR_883392'"),
        ("contacts", "username TEXT"),
        ("contacts", "connection_status TEXT DEFAULT 'connected'"),
        ("messages", "email_ref_id TEXT"),
        ("messages", "client_msg_id TEXT"),
        # RBAC & Credentials columns
        ("users", "password TEXT DEFAULT 'password123'"),
        ("users", "password_hash TEXT"),
        ("users", "is_active BOOLEAN DEFAULT TRUE"),
        ("users", "created_by TEXT"),
        ("users", "assigned_staff_id TEXT"),
        ("user_profile", "password TEXT DEFAULT 'password123'"),
        ("user_profile", "password_hash TEXT"),
        ("user_profile", "is_active BOOLEAN DEFAULT TRUE"),
        ("user_profile", "created_by TEXT"),
        ("user_profile", "assigned_staff_id TEXT"),
    ]:
        try:
            cursor.execute(f"ALTER TABLE {table} ADD COLUMN {col_def}")
        except Exception:
            pass

    # Create Call Links table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS call_links (
            id TEXT PRIMARY KEY,
            created_by TEXT NOT NULL,
            call_type TEXT DEFAULT 'video',
            link_name TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP
        )
    ''')

    # Create Status Views table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS status_views (
            id SERIAL PRIMARY KEY,
            status_id TEXT NOT NULL,
            viewer_id TEXT NOT NULL,
            viewer_name TEXT,
            viewer_avatar TEXT,
            viewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(status_id, viewer_id)
        )
    ''')

    # Create Groups table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            avatar TEXT,
            created_by TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Group Members table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS group_members (
            group_id TEXT,
            contact_id TEXT,
            role TEXT DEFAULT 'member',
            joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (group_id, contact_id)
        )
    ''')

    # Create Channels table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            avatar TEXT,
            owner_id TEXT,
            follower_count INTEGER DEFAULT 0,
            is_verified BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Channel Posts table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS channel_posts (
            id TEXT PRIMARY KEY,
            channel_id TEXT NOT NULL,
            text TEXT,
            media_url TEXT,
            reactions_json TEXT DEFAULT '{}',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Channel Followers table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS channel_followers (
            channel_id TEXT,
            contact_id TEXT,
            PRIMARY KEY (channel_id, contact_id)
        )
    ''')


    # Create Broadcast Lists table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS broadcast_lists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL
        )
    ''')

    # Create Broadcast List Members table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS broadcast_list_members (
            list_id TEXT,
            contact_id TEXT,
            PRIMARY KEY (list_id, contact_id),
            FOREIGN KEY (list_id) REFERENCES broadcast_lists (id) ON DELETE CASCADE,
            FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
        )
    ''')

    # Create Broadcast History table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS broadcast_history (
            id SERIAL PRIMARY KEY,
            text TEXT,
            time TEXT,
            date TEXT,
            recipient_count INTEGER,
            delivered_count INTEGER,
            is_file BOOLEAN DEFAULT FALSE,
            file_name TEXT,
            file_size TEXT,
            recipients TEXT
        )
    ''')

    # Create OTPs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS otps (
            phone TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Email OTPs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_otps (
            email TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            expires_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Email Call Invites table (Google Meet style)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_call_invites (
            id TEXT PRIMARY KEY,
            host_id TEXT,
            host_name TEXT,
            host_email TEXT,
            host_avatar TEXT,
            recipient_email TEXT NOT NULL,
            recipient_name TEXT,
            contact_id TEXT,
            call_type TEXT DEFAULT 'video',
            subject TEXT,
            security_pin TEXT,
            status TEXT DEFAULT 'ringing',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create Email Call Meetings table (Google Meet style)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_call_meetings (
            id TEXT PRIMARY KEY,
            host_email TEXT NOT NULL,
            host_name TEXT,
            recipient_email TEXT NOT NULL,
            recipient_name TEXT,
            contact_id TEXT,
            subject TEXT,
            call_type TEXT DEFAULT 'video',
            status TEXT DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP
        )
    ''')

    # ========== PHASE 1: WhatsApp Feature Parity Tables ==========

    # Typing Indicators table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS typing_indicators (
            user_id TEXT NOT NULL,
            contact_id TEXT NOT NULL,
            is_typing BOOLEAN DEFAULT FALSE,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, contact_id)
        )
    ''')

    # User Presence (Online/Last Seen) table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_presence (
            user_id TEXT PRIMARY KEY,
            is_online BOOLEAN DEFAULT FALSE,
            last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Message Read Receipts (per-user, for groups) table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS message_receipts (
            message_id INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            status TEXT DEFAULT 'delivered',
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (message_id, user_id)
        )
    ''')

    # Archived Chats table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS archived_chats (
            user_id TEXT NOT NULL,
            contact_id TEXT NOT NULL,
            archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, contact_id)
        )
    ''')

    # Muted Chats table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS muted_chats (
            user_id TEXT NOT NULL,
            contact_id TEXT NOT NULL,
            muted_until TIMESTAMP,
            PRIMARY KEY (user_id, contact_id)
        )
    ''')

    # Chat Wallpapers table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS chat_wallpapers (
            user_id TEXT NOT NULL,
            contact_id TEXT DEFAULT '__default__',
            wallpaper_url TEXT,
            PRIMARY KEY (user_id, contact_id)
        )
    ''')

    # Blocked Contacts table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS blocked_contacts (
            user_id TEXT NOT NULL,
            blocked_id TEXT NOT NULL,
            blocked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, blocked_id)
        )
    ''')

    # Pinned Chats table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS pinned_chats (
            user_id TEXT NOT NULL,
            contact_id TEXT NOT NULL,
            pinned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, contact_id)
        )
    ''')

    # ========== PHASE 2: Media & Stickers Tables ==========

    # Sticker Packs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sticker_packs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            author TEXT DEFAULT 'GebTalk',
            thumbnail_url TEXT,
            is_default BOOLEAN DEFAULT FALSE
        )
    ''')

    # Stickers table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS stickers (
            id TEXT PRIMARY KEY,
            pack_id TEXT REFERENCES sticker_packs(id) ON DELETE CASCADE,
            image_url TEXT NOT NULL,
            emoji TEXT DEFAULT '😀'
        )
    ''')

    # User Installed Sticker Packs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_sticker_packs (
            user_id TEXT NOT NULL,
            pack_id TEXT NOT NULL,
            installed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, pack_id)
        )
    ''')

    # Shared Documents table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS shared_documents (
            id SERIAL PRIMARY KEY,
            message_id INTEGER,
            contact_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_type TEXT,
            file_size TEXT,
            file_url TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Seed Default Sticker Pack
    try:
        cursor.execute("INSERT INTO sticker_packs (id, name, author, is_default) VALUES ('gebtalk_express', 'GebTalk Express', 'GebTalk Team', TRUE) ON CONFLICT (id) DO NOTHING")
        default_stickers = [
            ('s1', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Happy', '😀'),
            ('s2', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Love', '❤️'),
            ('s3', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Cool', '😎'),
            ('s4', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Party', '🎉'),
            ('s5', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Fire', '🔥'),
            ('s6', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Like', '👍'),
            ('s7', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Rocket', '🚀'),
            ('s8', 'gebtalk_express', 'https://api.dicebear.com/7.x/bottts/svg?seed=Star', '⭐'),
        ]
        for s_id, p_id, url, emoji in default_stickers:
            cursor.execute("INSERT INTO stickers (id, pack_id, image_url, emoji) VALUES (%s, %s, %s, %s) ON CONFLICT (id) DO NOTHING", (s_id, p_id, url, emoji))
    except Exception as e:
        print(f"Sticker seed error: {e}")

    # ========== PHASE 3: Communities, Payments & Newsletters Tables ==========

    # Communities table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS communities (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            avatar TEXT,
            owner_id TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Community Groups table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS community_groups (
            community_id TEXT REFERENCES communities(id) ON DELETE CASCADE,
            group_id TEXT NOT NULL,
            is_announcement BOOLEAN DEFAULT FALSE,
            PRIMARY KEY (community_id, group_id)
        )
    ''')

    # Wallets table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS wallets (
            user_id TEXT PRIMARY KEY,
            balance REAL DEFAULT 150.00,
            currency TEXT DEFAULT 'USD'
        )
    ''')

    # Transactions table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            amount REAL NOT NULL,
            currency TEXT DEFAULT 'USD',
            note TEXT,
            status TEXT DEFAULT 'completed',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Newsletters table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS newsletters (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            avatar TEXT,
            owner_id TEXT,
            subscriber_count INTEGER DEFAULT 1200,
            is_following BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Seed Sample Data
    try:
        cursor.execute("INSERT INTO communities (id, name, description, owner_id) VALUES ('c1', 'GebTalk Global Community', 'Official global community for all GebTalk users', 'system') ON CONFLICT (id) DO NOTHING")
        cursor.execute("INSERT INTO newsletters (id, name, description, subscriber_count) VALUES ('n1', 'GebTalk Tech Daily', 'Latest news in AI, software and tech', 15400) ON CONFLICT (id) DO NOTHING")
    except Exception as e:
        print(f"Phase 3 seed error: {e}")

    # ========== PHASE 4: Linked Devices & Settings Tables ==========

    # Linked Devices table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS linked_devices (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            device_name TEXT NOT NULL,
            device_type TEXT DEFAULT 'web',
            linked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            is_active BOOLEAN DEFAULT TRUE
        )
    ''')

    # Reports table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS reports (
            id SERIAL PRIMARY KEY,
            reporter_id TEXT NOT NULL,
            reported_id TEXT NOT NULL,
            report_type TEXT DEFAULT 'spam',
            reason TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Email Call Invites (Google Meet Style) Table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_call_invites (
            id TEXT PRIMARY KEY,
            host_id TEXT,
            host_name TEXT,
            host_email TEXT,
            host_avatar TEXT,
            recipient_email TEXT NOT NULL,
            recipient_name TEXT,
            contact_id TEXT,
            call_type TEXT DEFAULT 'video',
            subject TEXT DEFAULT 'GebTalk HD Video Meeting',
            security_pin TEXT DEFAULT '123456',
            scheduled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status TEXT DEFAULT 'ringing',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # ========== END PHASE 4 TABLES ==========

    # Create Email Verifications OTP table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_verifications (
            id SERIAL PRIMARY KEY,
            user_phone TEXT NOT NULL,
            email TEXT NOT NULL,
            otp TEXT NOT NULL,
            expires_at TIMESTAMP,
            is_verified BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # ========== EMAIL-FIRST UNIFIED COMMUNICATIONS TABLES ==========

    # Universal Users Identity table (Email as permanent identity + RBAC)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            username TEXT UNIQUE,
            name TEXT NOT NULL,
            phone TEXT,
            avatar TEXT,
            role TEXT NOT NULL DEFAULT 'Staff',
            status_text TEXT DEFAULT 'Available',
            about TEXT DEFAULT 'Hey there! I am using GEBTALK',
            presence TEXT DEFAULT 'online',
            last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            is_verified BOOLEAN DEFAULT TRUE,
            password TEXT DEFAULT 'password123',
            password_hash TEXT,
            is_active BOOLEAN DEFAULT TRUE,
            created_by TEXT,
            assigned_staff_id TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Contact Requests & Handshake Privacy table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS contact_requests (
            id SERIAL PRIMARY KEY,
            sender_id TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            sender_name TEXT,
            sender_email TEXT,
            sender_avatar TEXT,
            sender_username TEXT,
            status TEXT DEFAULT 'pending',
            message TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(sender_id, receiver_id)
        )
    ''')

    # Integrated Email Accounts table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_accounts (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            email_address TEXT NOT NULL,
            provider TEXT DEFAULT 'native',
            is_primary BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Unified Email Messages table (Inbox, Sent, Drafts, Starred, Trash)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS email_messages (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            folder TEXT DEFAULT 'inbox',
            from_address TEXT NOT NULL,
            from_name TEXT,
            to_addresses TEXT NOT NULL,
            subject TEXT,
            body_text TEXT,
            body_html TEXT,
            has_attachments BOOLEAN DEFAULT FALSE,
            attachments_json TEXT DEFAULT '[]',
            is_read BOOLEAN DEFAULT FALSE,
            is_starred BOOLEAN DEFAULT FALSE,
            linked_contact_id TEXT,
            received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create indexes for optimized lookup performance
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_user_profile_phone ON user_profile (phone);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_user_profile_email ON user_profile (email);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications (email);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_contacts_phone ON contacts (phone);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_contacts_email ON contacts (email);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_messages_contact_id ON messages (contact_id);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_typing_contact ON typing_indicators (contact_id);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_presence_user ON user_presence (user_id);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_archived_user ON archived_chats (user_id);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_pinned_user ON pinned_chats (user_id);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_muted_user ON muted_chats (user_id);')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_blocked_user ON blocked_contacts (user_id);')

    # Seed CEO User Profile
    cursor.execute('''
        INSERT INTO user_profile (id, name, role, phone, avatar, email, notifications_enabled, notification_sound, notification_vibration, security_2fa, read_receipts, last_seen_visible, country_code, country_name, country_flag, created_at, verification_status)
        VALUES ('marcus', 'Marcus Sterling', 'Executive VP | Global EB Tech', '+1 (555) 019-8833', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80', 'marcus.sterling@ebglobal.com', TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, '+1', 'United States', '🇺🇸', '2026-06-18', 'Verified')
        ON CONFLICT (id) DO NOTHING
    ''')

    # Seed Folders
    folders = [
        ('all', 'All', '#3b82f6'),
        ('customers', 'Customers', '#10b981'),
        ('staff', 'Staff', '#3b82f6')
    ]
    cursor.executemany('INSERT INTO folders (id, name, color) VALUES (%s, %s, %s) ON CONFLICT (id) DO NOTHING', folders)

    # Seed Tags
    tags = [
        ('vip', 'VIP', '#ef4444'),
        ('customer', 'Customer', '#10b981'),
        ('alumni', 'Alumni', '#8b5cf6'),
        ('sponsor', 'Sponsor', '#f59e0b'),
        ('urgent', 'Urgent', '#ef4444')
    ]
    cursor.executemany('INSERT INTO tags (id, name, color) VALUES (%s, %s, %s) ON CONFLICT (id) DO NOTHING', tags)

    # Primary CEO User in Directory
    cursor.execute('''
        INSERT INTO users (id, email, username, name, phone, avatar, role, status_text, about, presence, is_verified, password, assigned_staff_id)
        VALUES ('USR_883392', 'marcus.sterling@ebglobal.com', 'marcus_sterling', 'Marcus Sterling', '+1 (555) 019-8833', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80', 'CEO', 'Available', 'CEO & Founder | Global EB Tech', 'online', TRUE, 'password123', NULL)
        ON CONFLICT (id) DO NOTHING
    ''')

    if seed_test_data:
        _seed_test_fixtures(cursor)

    conn.commit()
    conn.close()
    print("Database initialized successfully.")

def _seed_test_fixtures(cursor):
    # Seed Contacts (Staff & Customers) for automated test verification
    contacts = [
        ('sarah', 'Sarah Jenkins', '+1 (555) 019-2834', 'Staff', 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=100&q=80', 'Active Now', 'staff', 0, None),
        ('emma', 'Emma Watson', '+1 (555) 014-9821', 'Manager', 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=100&q=80', 'Offline', 'staff', 0, None),
        ('john', 'John Doe', '+1 (555) 012-3456', 'Staff', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=100&q=80', 'Active Now', 'staff', 0, None),
        ('michael', 'Michael Chang', '+1 (555) 017-6543', 'Staff', 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=100&q=80', 'Away', 'staff', 0, None),
        ('ebi', 'EBI (AI Engine)', '', 'Support', '', 'Operational', 'support', 0, None),
        ('support', 'Support Desk', '+1 (555) 010-0000', 'Support', 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&w=100&q=80', 'Online', 'support', 0, None),
        ('david', 'David Miller', '+1 (555) 015-1122', 'Customer', 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=100&q=80', 'Away', 'customers', 1, 'sarah'),
        ('customer_a', 'Alice Johnson', '+1 (555) 016-3344', 'Customer', '', 'Offline', 'customers', 0, 'john'),
        ('customer_b', 'Bob Smith', '+1 (555) 018-5566', 'Customer', '', 'Offline', 'customers', 0, 'john'),
        ('customer_c', 'Charlie Brown', '+1 (555) 011-7788', 'Customer', '', 'Online', 'customers', 0, 'john'),
        ('customer_d', 'Diana Prince', '+1 (555) 013-9900', 'Customer', '', 'Active Now', 'customers', 2, 'sarah'),
        ('customer_e', 'Ethan Hunt', '+1 (555) 015-2233', 'Customer', '', 'Online', 'customers', 0, 'sarah'),
        ('customer_f', 'Fiona Gallagher', '+1 (555) 017-4455', 'Customer', '', 'Offline', 'customers', 0, 'michael'),
        ('customer_g', 'George Clark', '+1 (555) 019-6677', 'Customer', '', 'Online', 'customers', 0, 'michael')
    ]
    cursor.executemany('''
        INSERT INTO contacts (id, name, phone, role, avatar, status, folder, unread_count, assigned_staff_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT (id) DO UPDATE SET
            role = EXCLUDED.role,
            folder = EXCLUDED.folder,
            assigned_staff_id = EXCLUDED.assigned_staff_id
    ''', contacts)

    cursor.execute("UPDATE contacts SET manager_id = 'emma' WHERE id IN ('sarah', 'john')")
    cursor.execute("UPDATE contacts SET email = 'sarah.jenkins@gmail.com', username = '@sarahj' WHERE id = 'sarah'")
    cursor.execute("UPDATE contacts SET email = 'david.miller@gmail.com', username = '@davidm' WHERE id = 'david'")
    cursor.execute("UPDATE contacts SET email = 'emma.watson@gmail.com', username = '@emmaw' WHERE id = 'emma'")
    cursor.execute("UPDATE contacts SET email = 'john.doe@gmail.com', username = '@johndoe' WHERE id = 'john'")
    cursor.execute("UPDATE contacts SET email = 'michael.chang@gmail.com', username = '@mchang' WHERE id = 'michael'")
    cursor.execute("UPDATE contacts SET email = 'alice.johnson@aurora.com', username = '@alicej' WHERE id = 'customer_a'")
    cursor.execute("UPDATE contacts SET email = 'bob.smith@aurora.com', username = '@bobsmith' WHERE id = 'customer_b'")
    cursor.execute("UPDATE contacts SET email = 'charlie.brown@aurora.com', username = '@charlieb' WHERE id = 'customer_c'")
    cursor.execute("UPDATE contacts SET email = 'diana.prince@vortex.io', username = '@dianap' WHERE id = 'customer_d'")
    cursor.execute("UPDATE contacts SET email = 'ethan.hunt@vortex.io', username = '@ethanh' WHERE id = 'customer_e'")
    cursor.execute("UPDATE contacts SET email = 'fiona.gallagher@titan.io', username = '@fionag' WHERE id = 'customer_f'")
    cursor.execute("UPDATE contacts SET email = 'george.clark@titan.io', username = '@georgec' WHERE id = 'customer_g'")

    users_data = [
        ('USR_883392', 'marcus.sterling@ebglobal.com', 'marcus_sterling', 'Marcus Sterling', '+1 (555) 019-8833', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80', 'CEO', 'Available', 'CEO & Founder | Global EB Tech', 'online', True, 'password123', None),
        ('USR_103', 'emma.watson@gmail.com', 'emmaw', 'Emma Watson', '+1 (555) 014-9821', 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=100&q=80', 'Manager', 'Available', 'Operations & Team Manager', 'offline', True, 'password123', None),
        ('USR_101', 'sarah.jenkins@gmail.com', 'sarahj', 'Sarah Jenkins', '+1 (555) 019-2834', 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=100&q=80', 'Staff', 'Available', 'Senior Client Specialist', 'online', True, 'password123', None),
        ('USR_104', 'john.doe@gmail.com', 'johndoe', 'John Doe', '+1 (555) 012-3456', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=100&q=80', 'Staff', 'Available', 'Key Account Architect', 'online', True, 'password123', None),
        ('USR_105', 'michael.chang@gmail.com', 'mchang', 'Michael Chang', '+1 (555) 017-6543', 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=100&q=80', 'Staff', 'Away', 'Solutions Specialist', 'away', True, 'password123', None),
        ('USR_201', 'david.miller@gmail.com', 'davidm', 'David Miller', '+1 (555) 015-1122', 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=100&q=80', 'Customer', 'Away', 'Client Executive', 'away', True, 'password123', 'sarah'),
        ('USR_202', 'alice.johnson@aurora.com', 'alicej', 'Alice Johnson', '+1 (555) 016-3344', '', 'Customer', 'Offline', 'Aurora Corp Account', 'offline', True, 'password123', 'john'),
        ('USR_203', 'bob.smith@aurora.com', 'bobsmith', 'Bob Smith', '+1 (555) 018-5566', '', 'Customer', 'Offline', 'Aurora Corp Account', 'offline', True, 'password123', 'john'),
        ('USR_204', 'diana.prince@vortex.io', 'dianap', 'Diana Prince', '+1 (555) 013-9900', '', 'Customer', 'Active Now', 'Vortex Account', 'online', True, 'password123', 'sarah'),
        ('USR_205', 'fiona.gallagher@titan.io', 'fionag', 'Fiona Gallagher', '+1 (555) 017-4455', '', 'Customer', 'Offline', 'Titan Account', 'offline', True, 'password123', 'michael'),
    ]
    for u in users_data:
        try:
            cursor.execute('''
                INSERT INTO users (id, email, username, name, phone, avatar, role, status_text, about, presence, is_verified, password, assigned_staff_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET 
                    role = EXCLUDED.role,
                    email = EXCLUDED.email,
                    password = EXCLUDED.password,
                    assigned_staff_id = EXCLUDED.assigned_staff_id
            ''', u)
        except Exception:
            pass

    # Test sample messages
    messages = [
        ('sarah', 'Hi! EBI informed me you wanted to review the project status.', 0, '10:24 AM', 0, None, 0, None, None, '[]', 'read'),
        ('david', 'Hi Marcus, the Aurora prototype looks great. Can we review the pricing contract today?', 0, '9:45 AM', 0, None, 0, None, None, '[]', 'unread'),
        ('customer_a', 'Hello, Alice here. Looking forward to our sync.', 0, 'Tuesday', 0, None, 0, None, None, '[]', 'read'),
    ]
    for msg in messages:
        try:
            cursor.execute('''
                INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, reactions, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ''', (msg[0], msg[1], bool(msg[2]), msg[3], bool(msg[4]), msg[5], bool(msg[6]), msg[7], msg[8], msg[9], msg[10]))
        except Exception:
            pass

    # Test sample emails
    sample_emails = [
        ('em_1', 'USR_883392', 'inbox', 'sarah.jenkins@gmail.com', 'Sarah Jenkins', '["marcus.sterling@ebglobal.com"]', 'Project Proposal & Design Specs v3', 'Hi Marcus,\n\nI have uploaded the specs.', '<p>Hi Marcus</p>', False, '[]', True, True, 'sarah'),
        ('em_2', 'USR_883392', 'inbox', 'david.miller@gmail.com', 'David Miller', '["marcus.sterling@ebglobal.com"]', 'Enterprise SLA', 'Hello Marcus', '<p>Hello</p>', False, '[]', True, True, 'david'),
    ]
    for em in sample_emails:
        try:
            cursor.execute('''
                INSERT INTO email_messages (id, user_id, folder, from_address, from_name, to_addresses, subject, body_text, body_html, has_attachments, attachments_json, is_read, is_starred, linked_contact_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT (id) DO NOTHING
            ''', em)
        except Exception:
            pass

def seed_test_fixtures():
    conn = get_db_connection()
    cursor = conn.cursor()
    _seed_test_fixtures(cursor)
    conn.commit()
    conn.close()

if __name__ == '__main__':
    init_db()
