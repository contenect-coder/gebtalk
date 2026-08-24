from flask import Flask, request, jsonify, send_from_directory, g
from flask_cors import CORS  # type: ignore
import os
import json
import random
import urllib.request
import base64
from datetime import datetime
from functools import wraps
import database
from email_service import EmailService
import threading
import time

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

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}}, supports_credentials=True)

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS, PATCH'
    response.headers['Access-Control-Allow-Headers'] = '*'
    response.headers['Access-Control-Allow-Credentials'] = 'true'
    if request.method == 'OPTIONS':
        response.status_code = 200
    return response

UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), 'uploads')
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

def save_avatar_if_base64(avatar, user_id):
    if not avatar or not isinstance(avatar, str) or not avatar.startswith('data:image'):
        return avatar
    try:
        header, data = avatar.split(';base64,', 1)
        ext = 'png'
        if 'jpeg' in header or 'jpg' in header:
            ext = 'jpg'
        fname = f"{user_id}_{int(time.time())}_avatar.{ext}"
        fpath = os.path.join(UPLOAD_FOLDER, fname)
        with open(fpath, 'wb') as f:
            f.write(base64.b64decode(data))
        return f"/uploads/{fname}"
    except Exception as e:
        print(f"Error saving base64 avatar: {e}")
        return avatar

@app.route('/uploads/<path:filename>')
def serve_uploaded_file(filename):
    response = send_from_directory(UPLOAD_FOLDER, filename)
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    return response

@app.route('/api/health', methods=['GET'])
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok", "service": "gebtalk_backend", "timestamp": int(time.time())})

@app.route('/api/debug/log', methods=['GET'])
def frontend_debug_log():
    msg = request.args.get('msg', '')
    print(f"\n[FRONTEND DEBUG] {msg}\n")
    return jsonify({"status": "ok"})

@app.route('/api/download/<path:filename>')
def download_file(filename):
    """Serve a file with Content-Disposition: attachment to force browser download."""
    response = send_from_directory(UPLOAD_FOLDER, filename, as_attachment=True)
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Access-Control-Expose-Headers'] = 'Content-Disposition'
    return response

# Ensure database is initialized
database.init_db()

def get_db():
    if 'db' not in g or getattr(g.db, 'closed', 0) != 0:
        g.db = database.get_db_connection()
    return g.db

def get_db_connection():
    return database.get_db_connection()

@app.teardown_appcontext
def close_db(error):
    db = g.pop('db', None)
    if db is not None and getattr(db, 'closed', 0) == 0:
        try:
            db.close()
        except Exception:
            pass

@app.before_request
def handle_preflight_and_timer():
    g.start_time = time.perf_counter()
    if request.method == 'OPTIONS':
        response = app.make_default_options_response()
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS, PATCH'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, x-user-phone, x-requested-with, accept, origin'
        return response

@app.after_request
def log_request_timing(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS, PATCH'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, x-user-phone, x-requested-with, accept, origin'
    if hasattr(g, 'start_time'):
        elapsed = (time.perf_counter() - g.start_time) * 1000
        print(f"[API Performance] {request.method} {request.path} took {elapsed:.2f}ms - Status: {response.status_code}", flush=True)
    return response

def normalize_phone(phone):
    return ''.join(c for c in (phone or '') if c.isdigit())

def get_authenticated_phone():
    user_phone = request.headers.get('x-user-phone')
    if not user_phone:
        auth_header = request.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            user_phone = auth_header.split(' ', 1)[1]
    return user_phone.strip() if user_phone else None

def get_user_profile(phone):
    if not phone:
        return None
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM user_profile WHERE phone = %s OR id = %s', (phone, phone))
    row = cursor.fetchone()
    if not row:
        norm = normalize_phone(phone)
        if norm:
            cursor.execute('SELECT * FROM user_profile')
            for r in cursor.fetchall():
                if normalize_phone(r.get('phone') or '') == norm:
                    row = r
                    break
    return dict(row) if row else None

def get_canonical_role(profile):
    """
    Deterministically resolves a user or contact profile into one of the 4 platform roles:
    'CEO' | 'Manager' | 'Staff' | 'Customer'
    """
    if not profile:
        return 'Customer'
        
    role = str(profile.get('role') or '').lower().strip()
    folder = str(profile.get('folder') or '').lower().strip()

    # If role or folder explicitly indicates customer or client -> Customer
    if folder == 'customers' or 'customer' in role or 'client' in role or ' at ' in role or ' of ' in role:
        return 'Customer'

    # If role or folder indicates staff/specialist -> Staff
    if folder == 'staff' or 'staff' in role or 'support' in role or 'specialist' in role or 'developer' in role or 'lead' in role or 'architect' in role or 'member' in role:
        return 'Staff'

    # If role indicates manager -> Manager
    if 'manager' in role or 'supervisor' in role:
        return 'Manager'

    # Check CEO identity or role
    email = str(profile.get('email') or '').lower().strip()
    uid = str(profile.get('id') or '').lower().strip()
    if role in ('ceo', 'founder', 'global ceo') or role.startswith('ceo ') or role.endswith(' ceo') or 'chief executive' in role or email in ('ernestchristo@ebglobal.com', 'marcus.sterling@ebglobal.com'):
        return 'CEO'

    return 'Customer'

def is_caller_ceo(profile):
    if not profile:
        return False
    return get_canonical_role(profile) == 'CEO'

def is_caller_manager(profile):
    if not profile:
        return False
    return get_canonical_role(profile) == 'Manager'

def is_caller_staff(profile):
    if not profile:
        return False
    return get_canonical_role(profile) == 'Staff'

def is_caller_customer(profile):
    if not profile:
        return False
    return get_canonical_role(profile) == 'Customer'

def is_ceo_role(role, profile=None):
    if profile:
        return is_caller_ceo(profile)
    if not role:
        return False
    r = str(role).lower().strip()
    if ' at ' in r or ' of ' in r or 'customer' in r or 'client' in r:
        return False
    return r in ('ceo', 'executive', 'founder', 'global ceo')

def is_admin_role(role, profile=None):
    if profile:
        return get_canonical_role(profile) in ('CEO', 'Manager')
    return is_ceo_role(role) or 'manager' in str(role or '').lower()

def get_caller_profile():
    token = get_authenticated_phone()
    if not token:
        token = request.args.get('phone') or request.args.get('email')
    if not token:
        return None
    token_str = token.strip()
    conn = get_db()
    cursor = conn.cursor()
    
    # 1. Look up in users table
    cursor.execute('''
        SELECT id, name, role, email, phone, avatar, assigned_staff_id, is_active, password
        FROM users 
        WHERE LOWER(email) = %s OR id = %s OR phone = %s OR username = %s
    ''', (token_str.lower(), token_str, token_str, token_str))
    user_row = cursor.fetchone()
    if user_row:
        return dict(user_row)

    # 2. Look up in user_profile table
    cursor.execute('''
        SELECT id, name, role, email, phone, avatar, assigned_staff_id, is_active, password
        FROM user_profile 
        WHERE LOWER(email) = %s OR id = %s OR phone = %s
    ''', (token_str.lower(), token_str, token_str))
    up_row = cursor.fetchone()
    if up_row:
        return dict(up_row)

    # 3. Look up in contacts table
    cursor.execute('''
        SELECT id, name, role, email, phone, avatar, assigned_staff_id, folder
        FROM contacts
        WHERE LOWER(email) = %s OR id = %s OR phone = %s
    ''', (token_str.lower(), token_str, token_str))
    c_row = cursor.fetchone()
    if c_row:
        c_dict = dict(c_row)
        if c_dict.get('folder') == 'customers' or not c_dict.get('role'):
            c_dict['role'] = 'Customer' if c_dict.get('folder') == 'customers' else ('Staff' if c_dict.get('folder') == 'staff' else 'Executive')
        return c_dict

    return None

def resolve_user_contact(contacts, user_profile):
    if not user_profile:
        return None
    user_id = (user_profile.get('id') or '').lower()
    email = (user_profile.get('email') or '').lower()
    norm_phone = normalize_phone(user_profile.get('phone') or '')
    
    for c in contacts:
        cid = (c.get('id') or '').lower()
        cemail = (c.get('email') or '').lower()
        cphone = normalize_phone(c.get('phone') or '')
        if (user_id and cid == user_id) or (email and cemail == email) or (norm_phone and cphone == norm_phone):
            return c
    return None

def filter_contacts_for_user(contacts, user_profile):
    if not user_profile:
        return contacts

    canonical_role = get_canonical_role(user_profile)

    # 1. CEO -> Complete visibility across all managers, staff, customers, groups
    if canonical_role == 'CEO':
        return contacts

    user_contact = resolve_user_contact(contacts, user_profile)
    user_cid = user_contact['id'] if user_contact else user_profile.get('id', '')
    user_aliases = get_all_user_aliases(user_profile)

    # 2. Manager -> View all Staff and all Customers for management & assignment
    if canonical_role == 'Manager':
        allowed_contacts = []
        for c in contacts:
            if c.get('folder') in ('staff', 'customers', 'support') or c.get('id') in ('ebi', 'support', user_cid):
                allowed_contacts.append(c)
        return allowed_contacts

    # 3. Staff -> View all Staff, Managers, CEO, Support, + Customers assigned to them
    if canonical_role == 'Staff':
        allowed_contacts = []
        for c in contacts:
            cid = str(c.get('id') or '').lower()
            folder = str(c.get('folder') or '').lower()
            role = str(c.get('role') or '').lower()
            assigned = str(c.get('assigned_staff_id') or '').lower()
            if folder in ('staff', 'support', 'team', 'management') or role in ('staff', 'manager', 'executive', 'ceo', 'support', 'admin') or cid in ('ebi', 'support') or cid in user_aliases:
                allowed_contacts.append(c)
            elif (folder == 'customers' or role == 'customer') and (assigned in user_aliases):
                allowed_contacts.append(c)
        return allowed_contacts

    # 4. Customer -> View Support + their assigned Staff specialist + Self
    if canonical_role == 'Customer':
        assigned_staff_id = str((user_contact.get('assigned_staff_id') if user_contact else None) or user_profile.get('assigned_staff_id') or '').lower()
        allowed_contacts = []
        for c in contacts:
            cid = str(c.get('id') or '').lower()
            c_aliases = get_all_user_aliases(c)
            if c.get('folder') == 'support' or cid in ('ebi', 'support'):
                allowed_contacts.append(c)
            elif cid in user_aliases:
                allowed_contacts.append(c)
            elif assigned_staff_id and (assigned_staff_id in c_aliases or cid == assigned_staff_id):
                allowed_contacts.append(c)
        return allowed_contacts

    return contacts

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        phone = get_authenticated_phone()
        if not phone:
            return jsonify({'error': 'Authentication required'}), 401
        g.user_phone = phone
        g.caller_profile = get_caller_profile()
        g.user_profile = g.caller_profile or get_user_profile(phone)
        return f(*args, **kwargs)
    return decorated

def stitch_contacts(cursor, contacts):
    cursor.execute('''
        SELECT ct.contact_id, t.id, t.name, t.color 
        FROM tags t
        JOIN chat_tags ct ON ct.tag_id = t.id
    ''')
    tags_rows = cursor.fetchall()
    tags_by_contact = {}
    for trow in tags_rows:
        cid = trow['contact_id']
        tags_by_contact.setdefault(cid, []).append({
            'id': trow['id'], 'name': trow['name'], 'color': trow['color']
        })

    cursor.execute('''
        SELECT DISTINCT ON (contact_id) *
        FROM messages
        ORDER BY contact_id, id DESC
    ''')
    messages_rows = cursor.fetchall()
    messages_by_contact = {}
    for mrow in messages_rows:
        msg_dict = dict(mrow)
        if isinstance(msg_dict['reactions'], str):
            try:
                msg_dict['reactions'] = json.loads(msg_dict['reactions'])
            except Exception:
                msg_dict['reactions'] = []
        messages_by_contact[msg_dict['contact_id']] = msg_dict

    cursor.execute('SELECT id, name, role, email, phone, avatar FROM users')
    users_rows = cursor.fetchall()
    user_map = {}
    for u in users_rows:
        if u.get('email'):
            user_map[u['email'].strip().lower()] = u
        if u.get('id'):
            user_map[u['id'].strip().lower()] = u

    for contact in contacts:
        cid = contact['id']
        cemail = (contact.get('email') or '').strip().lower()
        contact['tags'] = tags_by_contact.get(cid, [])
        contact['last_message'] = messages_by_contact.get(cid, None)

        # Synchronize authoritative role & folder from user account
        matched_user = user_map.get(cemail) or user_map.get(str(cid).strip().lower())
        if matched_user:
            auth_role = matched_user.get('role') or 'Staff'
            contact['role'] = auth_role
            contact['folder'] = 'customers' if auth_role.lower() in ('customer', 'client') else 'staff'
        elif not contact.get('folder'):
            r = (contact.get('role') or '').lower()
            contact['folder'] = 'customers' if ('customer' in r or 'client' in r) else 'staff'

    return contacts

@app.route('/')
def index():
    return jsonify({
        'status': 'online',
        'service': 'GEBTALK Backend API Server',
        'documentation': 'All API endpoints are prefixed with /api',
        'endpoints': [
            '/api/auth/send-otp',
            '/api/auth/verify-otp',
            '/api/folders',
            '/api/tags',
            '/api/contacts',
            '/api/broadcast'
        ]
    })

def generate_and_store_otp(phone):
    code = f"{random.randint(1000, 9999)}"
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO otps (phone, code) VALUES (%s, %s)
        ON CONFLICT (phone) DO UPDATE SET code = EXCLUDED.code
    ''', (phone, code))
    conn.commit()
    conn.close()
    return code

def send_textbee_sms(phone, otp):
    api_key = os.environ.get("TEXTBEE_API_KEY")
    device_id = os.environ.get("TEXTBEE_DEVICE_ID")
    
    if not api_key or not device_id or "here" in api_key or "here" in device_id:
        print(f"[SIMULATED SMS] Phone: {phone}, OTP: {otp}")
        return False, "TextBee credentials not configured in .env"
        
    url = f"https://api.textbee.dev/api/v1/gateway/devices/{device_id}/send-sms"
    payload = {
        "recipients": [phone],
        "message": f"Your GEBTALK verification code is: {otp}"
    }
    data = json.dumps(payload).encode('utf-8')
    try:
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "x-api-key": api_key,
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            },
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            res_body = response.read().decode('utf-8')
            print(f"[TextBee Success] Response: {res_body}")
            return True, "OTP sent successfully via TextBee gateway"
    except Exception as e:
        error_msg = str(e)
        print(f"[TextBee Error] Failed to send SMS: {error_msg}")
        return False, f"Failed to send SMS via TextBee: {error_msg}"

@app.route('/api/auth/send-otp', methods=['POST'])
def send_otp():
    data = request.json or {}
    phone = data.get('phone', '').strip()
    if not phone:
        return jsonify({'error': 'Phone number is required'}), 400
        
    otp = generate_and_store_otp(phone)
    threading.Thread(target=send_textbee_sms, args=(phone, otp), daemon=True).start()

    response_data = {
        'message': 'OTP sent successfully (dispatched)',
        'phone': phone,
        'simulated': False,
    }
    if app.debug:
        response_data['otp_preview'] = otp
    return jsonify(response_data)

@app.route('/api/auth/verify-otp', methods=['POST'])
def verify_otp():
    data = request.json or {}
    phone = str(data.get('phone', '') or '').strip()
    otp = str(data.get('otp', '') or '').strip()
    if not phone or not otp:
        return jsonify({'error': 'Phone number and OTP are required'}), 400
        
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT code FROM otps WHERE phone = %s', (phone,))
    row = cursor.fetchone()
    
    verified = False
    if app.debug and otp in ('1234', '123456'):
        verified = True
    elif row and row['code'] == otp:
        verified = True
        cursor.execute('DELETE FROM otps WHERE phone = %s', (phone,))
        conn.commit()
        
    if verified:
        cursor.execute('SELECT * FROM user_profile WHERE phone = %s OR id = %s', (phone, phone))
        row = cursor.fetchone()
        if not row:
            norm = normalize_phone(phone)
            if norm:
                cursor.execute('SELECT * FROM user_profile')
                for r in cursor.fetchall():
                    if normalize_phone(r.get('phone') or '') == norm or r.get('id') == f"user_{norm}":
                        row = r
                        break
        
        country_code = data.get('country_code', '')
        country_name = data.get('country_name', '')
        country_flag = data.get('country_flag', '')
        name = data.get('name', '').strip()
        
        if not row:
            user_id = 'user_' + (normalize_phone(phone) or str(int(time.time())))
            created_at = datetime.now().strftime('%Y-%m-%d')
            cursor.execute('''
                INSERT INTO user_profile (id, name, role, phone, avatar, email, country_code, country_name, country_flag, created_at, verification_status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET 
                    phone = EXCLUDED.phone,
                    country_code = COALESCE(EXCLUDED.country_code, user_profile.country_code),
                    country_name = COALESCE(EXCLUDED.country_name, user_profile.country_name),
                    country_flag = COALESCE(EXCLUDED.country_flag, user_profile.country_flag),
                    name = COALESCE(NULLIF(EXCLUDED.name, ''), user_profile.name)
            ''', (user_id, name or 'New User', 'Executive', phone, '', '', country_code, country_name, country_flag, created_at, 'Verified'))
            conn.commit()
            user_target_id = user_id
        else:
            user_target_id = row['id']
            if country_code or country_name or country_flag or name:
                cursor.execute('''
                    UPDATE user_profile 
                    SET country_code = COALESCE(%s, country_code), 
                        country_name = COALESCE(%s, country_name), 
                        country_flag = COALESCE(%s, country_flag),
                        name = COALESCE(NULLIF(%s, ''), name)
                    WHERE id = %s
                ''', (country_code or None, country_name or None, country_flag or None, name, user_target_id))
                conn.commit()

        cursor.execute('SELECT * FROM user_profile WHERE id = %s', (user_target_id,))
        row = cursor.fetchone()
        if not row:
            row = get_user_profile(phone)
                
        profile_data = dict(row) if row else {'id': user_target_id, 'name': name or 'User', 'role': 'Executive', 'phone': phone}
        conn.close()
        
        return jsonify({
            'message': 'Verification successful',
            'token': phone,
            'user': {
                'id': profile_data.get('id', user_target_id),
                'name': profile_data.get('name', name or 'User'),
                'role': profile_data.get('role', 'Executive'),
                'avatar': profile_data.get('avatar') or '',
                'phone': profile_data.get('phone', phone),
                'email': profile_data.get('email') or '',
                'country_code': profile_data.get('country_code') or '',
                'country_name': profile_data.get('country_name') or '',
                'country_flag': profile_data.get('country_flag') or '',
                'created_at': profile_data.get('created_at') or '',
                'verification_status': profile_data.get('verification_status') or 'Verified'
            }
        })
    return jsonify({'error': 'Invalid OTP code'}), 401

@app.route('/api/auth/login', methods=['POST'])
@app.route('/api/auth/login-email', methods=['POST'])
def login_email():
    data = request.json or {}
    identifier = (data.get('identifier') or data.get('username') or data.get('email') or '').strip().lower()
    password = (data.get('password') or '').strip()
    
    if not identifier or not password:
        return jsonify({'error': 'Username/Email and password are required'}), 400
        
    conn = get_db()
    cursor = conn.cursor()
    
    # 1. Check users table by username, email, or id
    cursor.execute('''
        SELECT * FROM users 
        WHERE LOWER(email) = %s OR LOWER(username) = %s OR LOWER(id) = %s
    ''', (identifier, identifier, identifier))
    user_row = cursor.fetchone()
    
    # 2. Check user_profile table
    if not user_row:
        cursor.execute('''
            SELECT * FROM user_profile 
            WHERE LOWER(email) = %s OR LOWER(id) = %s
        ''', (identifier, identifier))
        user_row = cursor.fetchone()

    # 3. Check contacts table
    if not user_row:
        cursor.execute('''
            SELECT * FROM contacts 
            WHERE LOWER(email) = %s OR LOWER(username) = %s OR LOWER(id) = %s
        ''', (identifier, identifier, identifier))
        c_row = cursor.fetchone()
        if c_row:
            user_row = dict(c_row)
            if not user_row.get('role'):
                user_row['role'] = 'Staff' if user_row.get('folder') == 'staff' else 'Customer'

    if not user_row:
        conn.close()
        return jsonify({'error': 'Account not found. Please verify your username/email or contact your administrator.'}), 401

    user_dict = dict(user_row)

    # Check password
    account_pwd = user_dict.get('password')
    if account_pwd and account_pwd != password:
        if not (password in ('password123', '1234') and app.debug):
            conn.close()
            return jsonify({'error': 'Invalid password. Please try again.'}), 401

    if user_dict.get('is_active') is False:
        conn.close()
        return jsonify({'error': 'This account has been deactivated. Contact your administrator.'}), 403

    conn.close()
    
    token = user_dict.get('email') or user_dict.get('username') or user_dict.get('phone') or user_dict['id']
    user_payload = {
        'id': user_dict.get('id'),
        'name': user_dict.get('name', 'User'),
        'role': user_dict.get('role', 'Staff'),
        'avatar': user_dict.get('avatar') or '',
        'phone': user_dict.get('phone') or '',
        'email': user_dict.get('email') or identifier,
        'username': user_dict.get('username') or identifier.split('@')[0],
        'assigned_staff_id': user_dict.get('assigned_staff_id'),
        'created_at': str(user_dict.get('created_at', '')),
        'verification_status': 'Verified'
    }
    return jsonify({
        'message': 'Login successful',
        'token': token,
        'user': user_payload,
        'profile': user_payload
    })

def generate_and_store_email_otp(email):
    code = f"{random.randint(100000, 999999)}"
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO email_otps (email, code, created_at) VALUES (%s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (email) DO UPDATE SET code = EXCLUDED.code, created_at = CURRENT_TIMESTAMP
    ''', (email.lower().strip(), code))
    conn.commit()
    conn.close()
    return code

@app.route('/api/auth/send-email-otp', methods=['POST'])
def send_email_otp():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    name = data.get('name', '').strip() or email.split('@')[0].capitalize()
    
    if not email or '@' not in email:
        return jsonify({'error': 'Valid email address is required'}), 400
        
    otp = generate_and_store_email_otp(email)
    threading.Thread(target=EmailService.send_otp_email, args=(email, otp, name), daemon=True).start()

    response_data = {
        'message': f'Verification OTP code dispatched to {email}',
        'email': email,
        'simulated': False,
    }
    if app.debug:
        response_data['otp_preview'] = otp
    return jsonify(response_data)

@app.route('/api/auth/verify-email-otp', methods=['POST'])
def verify_email_otp():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    otp = str(data.get('otp', '') or '').strip()
    name = data.get('name', '').strip()
    
    if not email or not otp:
        return jsonify({'error': 'Email and OTP code are required'}), 400
        
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT code FROM email_otps WHERE email = %s', (email,))
    row = cursor.fetchone()
    
    verified = False
    if app.debug and otp in ('1234', '123456'):
        verified = True
    elif row and row['code'] == otp:
        verified = True
        cursor.execute('DELETE FROM email_otps WHERE email = %s', (email,))
        conn.commit()
        
    if not verified:
        conn.close()
        return jsonify({'error': 'Invalid or expired OTP code'}), 401
        
    # Check if user profile already exists with this email
    cursor.execute('SELECT * FROM user_profile WHERE LOWER(email) = %s', (email,))
    user_row = cursor.fetchone()
    
    email_lower = email.lower()
    if 'ceo' in email_lower:
        target_role = 'CEO'
    elif 'manager' in email_lower:
        target_role = 'Manager'
    elif 'staff' in email_lower:
        target_role = 'Staff'
    elif 'customer' in email_lower or 'client' in email_lower:
        target_role = 'Customer'
    else:
        target_role = 'Executive'
        
    if not user_row:
        user_id = 'user_' + email.replace('@', '_').replace('.', '_')
        phone = '+1 (555) ' + str(random.randint(100, 999)) + '-' + str(random.randint(1000, 9999))
        created_at = datetime.now().strftime('%Y-%m-%d')
        display_name = name or email.split('@')[0].capitalize()
        cursor.execute('''
            INSERT INTO user_profile (id, name, role, phone, avatar, email, created_at, verification_status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email
        ''', (user_id, display_name, target_role, phone, '', email, created_at, 'Verified'))
        conn.commit()
        cursor.execute('SELECT * FROM user_profile WHERE LOWER(email) = %s', (email,))
        user_row = cursor.fetchone()
    else:
        if name and not user_row.get('name'):
            cursor.execute('UPDATE user_profile SET name = %s WHERE id = %s', (name, user_row['id']))
            conn.commit()
            cursor.execute('SELECT * FROM user_profile WHERE id = %s', (user_row['id'],))
            user_row = cursor.fetchone()
            
    profile_data = dict(user_row) if user_row else {'id': email, 'name': name or 'User', 'email': email, 'phone': email, 'role': target_role}
    conn.close()
    
    token = profile_data.get('phone') or profile_data.get('email') or email
    
    return jsonify({
        'message': 'Email verification successful',
        'token': token,
        'user': {
            'id': profile_data.get('id', email),
            'name': profile_data.get('name', name or 'User'),
            'role': profile_data.get('role', 'Executive'),
            'avatar': profile_data.get('avatar') or '',
            'phone': profile_data.get('phone', ''),
            'email': profile_data.get('email', email),
            'country_code': profile_data.get('country_code') or '',
            'country_name': profile_data.get('country_name') or '',
            'country_flag': profile_data.get('country_flag') or '',
            'created_at': profile_data.get('created_at') or '',
            'verification_status': profile_data.get('verification_status') or 'Verified'
        }
    })

@app.route('/api/contacts/search-email', methods=['GET'])
@require_auth
def search_contacts_by_email():
    query = request.args.get('q', '').strip().lower()
    if not query:
        return jsonify([])
        
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, name, email, phone, role, avatar, status, folder 
        FROM contacts 
        WHERE LOWER(email) LIKE %s OR LOWER(name) LIKE %s
        LIMIT 20
    ''', (f"%{query}%", f"%{query}%"))
    results = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/api/init', methods=['GET'])
def batch_init():
    """Batch endpoint: returns folders, tags, contacts (with tags + last messages), and profile in ONE response."""
    phone = request.args.get('phone', '').strip()
    t_total = time.perf_counter()
    conn = get_db()
    cursor = conn.cursor()

    # 1. Folders
    cursor.execute('SELECT * FROM folders')
    folders = [dict(r) for r in cursor.fetchall()]

    # 2. Tags
    cursor.execute('SELECT * FROM tags')
    tags = [dict(r) for r in cursor.fetchall()]

    # 3. Contacts + tags + last messages (same logic as get_contacts)
    cursor.execute('SELECT * FROM contacts')
    contacts = [dict(row) for row in cursor.fetchall()]
    contacts = stitch_contacts(cursor, contacts)

    # 4. Profile
    profile = get_caller_profile()
    if profile:
        for key in ['notifications_enabled', 'notification_sound', 'notification_vibration', 'security_2fa', 'read_receipts', 'last_seen_visible']:
            if key in profile:
                profile[key] = bool(profile[key])
    # 5. Statuses
    cursor.execute('SELECT * FROM statuses ORDER BY created_at DESC')
    status_rows = cursor.fetchall()
    status_map = {}
    for r in status_rows:
        d = dict(r)
        cid = d['contact_id']
        if cid not in status_map:
            status_map[cid] = {
                'contact_id': cid,
                'user_name': d.get('user_name') or cid.capitalize(),
                'user_avatar': d.get('user_avatar') or '',
                'items': []
            }
        status_map[cid]['items'].append(d)
    statuses = list(status_map.values())

    # 6. Call Logs
    cursor.execute('SELECT * FROM call_logs ORDER BY id DESC')
    call_logs = [dict(r) for r in cursor.fetchall()]

    conn.close()
    t_end = time.perf_counter()
    print(f"[API Performance] /api/init batch query took {(t_end-t_total)*1000:.2f}ms", flush=True)

    return jsonify({
        'folders': folders,
        'tags': tags,
        'contacts': contacts,
        'profile': profile,
        'statuses': statuses,
        'call_logs': call_logs
    })

@app.route('/api/upload', methods=['POST'])
@require_auth
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    file = request.files['file']
    if not file or not file.filename:
        return jsonify({'error': 'No selected file'}), 400
    
    import uuid
    ext = os.path.splitext(file.filename)[1]
    unique_filename = f"{uuid.uuid4().hex}{ext}"
    
    file_path = os.path.join(UPLOAD_FOLDER, unique_filename)
    file.save(file_path)
    
    host = request.host
    scheme = 'https' if request.is_secure else 'http'
    url = f"{scheme}://{host}/uploads/{unique_filename}"
    
    return jsonify({
        'url': url,
        'filename': file.filename
    })

@app.route('/api/folders', methods=['GET'])
def get_folders():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM folders')
    rows = cursor.fetchall()
    conn.close()
    return jsonify([dict(r) for r in rows])

@app.route('/api/tags', methods=['GET', 'POST'])
def get_or_create_tags():
    conn = get_db()
    cursor = conn.cursor()
    if request.method == 'POST':
        if not get_authenticated_phone():
            conn.close()
            return jsonify({'error': 'Authentication required'}), 401
        data = request.json or {}
        tag_id = data.get('id', '').lower().strip()
        name = data.get('name', '').strip()
        color = data.get('color', '#3b82f6')
        if not tag_id or not name:
            conn.close()
            return jsonify({'error': 'Tag ID and name are required'}), 400
        cursor.execute('''
            INSERT INTO tags (id, name, color) VALUES (%s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, color = EXCLUDED.color
        ''', (tag_id, name, color))
        conn.commit()
        conn.close()
        return jsonify({'status': 'success', 'tag': {'id': tag_id, 'name': name, 'color': color}})
    
    cursor.execute('SELECT * FROM tags')
    rows = cursor.fetchall()
    conn.close()
    return jsonify([dict(r) for r in rows])
        
@app.route('/api/statuses', methods=['GET'])
def get_statuses():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM statuses ORDER BY created_at DESC')
    rows = cursor.fetchall()
    conn.close()
    
    # Group statuses by contact_id
    status_map = {}
    for r in rows:
        d = dict(r)
        cid = d['contact_id']
        if cid not in status_map:
            status_map[cid] = {
                'contact_id': cid,
                'user_name': d.get('user_name') or cid.capitalize(),
                'user_avatar': d.get('user_avatar') or '',
                'items': []
            }
        status_map[cid]['items'].append(d)
        
    return jsonify(list(status_map.values()))

@app.route('/api/status/create', methods=['POST'])
def create_status():
    data = request.json or {}
    contact_id = data.get('contact_id', 'marcus')
    user_name = data.get('user_name', 'Marcus Sterling')
    user_avatar = data.get('user_avatar', '')
    content_text = data.get('content_text', '')
    media_url = data.get('media_url')
    caption = data.get('caption')
    
    status_id = f"status_{int(time.time()*1000)}"
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO statuses (id, contact_id, user_name, user_avatar, content_text, media_url, caption)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    ''', (status_id, contact_id, user_name, user_avatar, content_text, media_url, caption))
    conn.commit()
    conn.close()
    return jsonify({'status': 'success', 'id': status_id})

@app.route('/api/calls', methods=['GET'])
def get_call_logs():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM call_logs ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    return jsonify([dict(r) for r in rows])

@app.route('/api/calls/log', methods=['POST'])
def log_call():
    data = request.json or {}
    contact_id = data.get('contact_id', '')
    contact_name = data.get('contact_name', '')
    contact_avatar = data.get('contact_avatar', '')
    call_type = data.get('call_type', 'voice') # 'voice' or 'video'
    direction = data.get('direction', 'outgoing') # 'incoming', 'outgoing', 'missed'
    duration = data.get('duration', '00:00')
    time_str = datetime.now().strftime('%I:%M %p')
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO call_logs (contact_id, contact_name, contact_avatar, call_type, direction, time_str, duration)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    ''', (contact_id, contact_name, contact_avatar, call_type, direction, time_str, duration))
    conn.commit()
    conn.close()
    return jsonify({'status': 'success'})

@app.route('/api/messages/edit', methods=['POST'])
def edit_message():
    data = request.json or {}
    msg_id = data.get('message_id')
    new_text = data.get('text', '').strip()
    if not msg_id or not new_text:
        return jsonify({'error': 'message_id and text required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE messages SET text = %s, is_edited = TRUE WHERE id = %s', (new_text, msg_id))
    conn.commit()
    conn.close()
    return jsonify({'status': 'success'})

@app.route('/api/messages/delete', methods=['POST'])
def delete_message():
    data = request.json or {}
    msg_id = data.get('message_id')
    if not msg_id:
        return jsonify({'error': 'message_id required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE messages SET text = 'This message was deleted', is_deleted = TRUE WHERE id = %s", (msg_id,))
    conn.commit()
    conn.close()
    return jsonify({'status': 'success'})

@app.route('/api/polls/create', methods=['POST'])
def create_poll():
    data = request.json or {}
    chat_id = data.get('chat_id', '')
    question = data.get('question', '').strip()
    options = data.get('options', [])
    multiple = data.get('multiple_answers', False)
    
    if not chat_id or not question or not options:
        return jsonify({'error': 'chat_id, question, and options required'}), 400
    
    poll_id = f"poll_{int(time.time()*1000)}"
    options_json = json.dumps([{'text': opt, 'votes': 0} for opt in options])
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO polls (id, chat_id, question, options_json, multiple_answers)
        VALUES (%s, %s, %s, %s, %s)
    ''', (poll_id, chat_id, question, options_json, multiple))
    
    # Send poll message in chat
    time_str = datetime.now().strftime('%I:%M %p')
    cursor.execute('''
        INSERT INTO messages (contact_id, text, is_user, time, poll_id, status)
        VALUES (%s, %s, %s, %s, %s, %s)
    ''', (chat_id, f"📊 Poll: {question}", True, time_str, poll_id, 'sent'))
    
    conn.commit()
    conn.close()
    return jsonify({'status': 'success', 'poll_id': poll_id})

@app.route('/api/polls/vote', methods=['POST'])
def vote_poll():
    data = request.json or {}
    poll_id = data.get('poll_id')
    option_index = data.get('option_index')
    user_id = data.get('user_id', 'marcus')
    
    if poll_id is None or option_index is None:
        return jsonify({'error': 'poll_id and option_index required'}), 400
    
    vote_id = f"vote_{int(time.time()*1000)}"
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO poll_votes (id, poll_id, option_index, user_id)
        VALUES (%s, %s, %s, %s)
    ''', (vote_id, poll_id, option_index, user_id))
    conn.commit()
    conn.close()
    return jsonify({'status': 'success'})

@app.route('/api/contacts', methods=['GET'])
def get_contacts():
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM contacts')
    contacts = [dict(row) for row in cursor.fetchall()]
    contacts = stitch_contacts(cursor, contacts)

    caller_profile = get_caller_profile()
    if caller_profile:
        contacts = filter_contacts_for_user(contacts, caller_profile)

    conn.close()
    return jsonify(contacts)

@app.route('/api/admin/accounts/create', methods=['POST'])
@app.route('/api/accounts/create', methods=['POST'])
@require_auth
def create_account():
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller or not (is_caller_ceo(caller) or is_caller_manager(caller)):
        return jsonify({'error': 'Forbidden: Only CEO and Managers can create user accounts'}), 403

    data = request.json or {}
    name = (data.get('name') or '').strip()
    email = (data.get('email') or '').strip().lower()
    password = (data.get('password') or '').strip() or 'password123'
    target_role = (data.get('role') or 'Staff').strip() # 'Manager', 'Staff', 'Customer'
    phone = (data.get('phone') or '').strip()
    assigned_staff_id = data.get('assigned_staff_id')
    notes = data.get('notes', '')

    if not name or not email:
        return jsonify({'error': 'Name and email are required'}), 400

    # Role permission enforcement:
    # CEO can create: Manager, Staff, Customer
    # Manager can create: Staff, Customer (CANNOT create CEO or Manager)
    if is_caller_manager(caller) and not is_caller_ceo(caller):
        if target_role.lower() in ('ceo', 'executive', 'director', 'manager'):
            return jsonify({'error': 'Forbidden: Managers can only create Staff or Customer accounts'}), 403

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute('SELECT 1 FROM users WHERE LOWER(email) = %s', (email,))
    if cursor.fetchone():
        conn.close()
        return jsonify({'error': 'An account with this email already exists'}), 400

    user_id = f"USR_{abs(hash(email)) % 900000 + 100000}"
    username = email.split('@')[0].replace('.', '_').replace('-', '_')
    folder = 'customers' if target_role.lower() in ('customer', 'client') else 'staff'
    if not phone:
        phone = f"+1 (555) 01{random.randint(10, 99)}-{random.randint(1000, 9999)}"

    # If Customer role, validate assigned_staff_id
    if folder == 'customers' and assigned_staff_id:
        cursor.execute('SELECT 1 FROM contacts WHERE id = %s', (assigned_staff_id,))
        if not cursor.fetchone():
            cursor.execute('SELECT 1 FROM users WHERE id = %s', (assigned_staff_id,))
            if not cursor.fetchone():
                assigned_staff_id = None

    # Insert into users table
    cursor.execute('''
        INSERT INTO users (id, email, username, name, phone, role, password, is_active, created_by, assigned_staff_id, is_verified)
        VALUES (%s, %s, %s, %s, %s, %s, %s, TRUE, %s, %s, TRUE)
    ''', (user_id, email, username, name, phone, target_role, password, caller.get('id'), assigned_staff_id))

    # Insert into contacts table
    contact_id = user_id.lower()
    cursor.execute('''
        INSERT INTO contacts (id, name, phone, role, avatar, status, folder, unread_count, assigned_staff_id, email, username, notes)
        VALUES (%s, %s, %s, %s, '', 'Active', %s, 0, %s, %s, %s, %s)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            phone = EXCLUDED.phone,
            role = EXCLUDED.role,
            folder = EXCLUDED.folder,
            assigned_staff_id = EXCLUDED.assigned_staff_id,
            email = EXCLUDED.email,
            username = EXCLUDED.username
    ''', (contact_id, name, phone, target_role, folder, assigned_staff_id, email, f"@{username}", notes))

    # Insert into user_profile table
    cursor.execute('''
        INSERT INTO user_profile (id, name, role, phone, avatar, email, created_at, verification_status, password, is_active, created_by, assigned_staff_id)
        VALUES (%s, %s, %s, %s, '', %s, %s, 'Verified', %s, TRUE, %s, %s)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            role = EXCLUDED.role,
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            password = EXCLUDED.password,
            assigned_staff_id = EXCLUDED.assigned_staff_id
    ''', (user_id, name, target_role, phone, email, datetime.now().strftime('%Y-%m-%d'), password, caller.get('id'), assigned_staff_id))

    conn.commit()
    conn.close()

    return jsonify({
        'success': True,
        'message': f'{target_role} account for {name} created successfully',
        'account': {
            'id': user_id,
            'contact_id': contact_id,
            'name': name,
            'email': email,
            'role': target_role,
            'phone': phone,
            'password': password,
            'assigned_staff_id': assigned_staff_id
        }
    })

@app.route('/api/contacts/<contact_id>/assign', methods=['POST'])
@require_auth
def assign_contact(contact_id):
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller or not (is_caller_ceo(caller) or is_caller_manager(caller)):
        return jsonify({'error': 'Forbidden: Only CEO and Managers can assign or reassign customers'}), 403

    data = request.json or {}
    folder = data.get('folder')
    tag_ids = data.get('tags')
    assigned_staff_id = data.get('assigned_staff_id')
    
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM contacts WHERE id = %s', (contact_id,))
    target_contact = cursor.fetchone()
    if not target_contact:
        conn.close()
        return jsonify({'error': 'Contact not found'}), 404
        
    if folder is not None:
        cursor.execute('UPDATE contacts SET folder = %s WHERE id = %s', (folder, contact_id))
        
    if assigned_staff_id is not None:
        if assigned_staff_id == "" or assigned_staff_id is None:
            cursor.execute('UPDATE contacts SET assigned_staff_id = NULL WHERE id = %s', (contact_id,))
            cursor.execute('UPDATE users SET assigned_staff_id = NULL WHERE id = %s OR LOWER(email) = %s', (contact_id, (target_contact.get('email') or '').lower()))
            cursor.execute('UPDATE user_profile SET assigned_staff_id = NULL WHERE id = %s OR LOWER(email) = %s', (contact_id, (target_contact.get('email') or '').lower()))
        else:
            cursor.execute('SELECT 1 FROM contacts WHERE id = %s', (assigned_staff_id,))
            if not cursor.fetchone():
                cursor.execute('SELECT 1 FROM users WHERE id = %s', (assigned_staff_id,))
                if not cursor.fetchone():
                    conn.close()
                    return jsonify({'error': f'Staff {assigned_staff_id} not found'}), 400
            cursor.execute('UPDATE contacts SET assigned_staff_id = %s WHERE id = %s', (assigned_staff_id, contact_id))
            cursor.execute('UPDATE users SET assigned_staff_id = %s WHERE id = %s OR LOWER(email) = %s', (assigned_staff_id, contact_id, (target_contact.get('email') or '').lower()))
            cursor.execute('UPDATE user_profile SET assigned_staff_id = %s WHERE id = %s OR LOWER(email) = %s', (assigned_staff_id, contact_id, (target_contact.get('email') or '').lower()))
            
    if tag_ids is not None:
        cursor.execute('DELETE FROM chat_tags WHERE contact_id = %s', (contact_id,))
        for tag_id in tag_ids:
            cursor.execute('''
                INSERT INTO chat_tags (contact_id, tag_id) VALUES (%s, %s)
                ON CONFLICT (contact_id, tag_id) DO NOTHING
            ''', (contact_id, tag_id))
            
    conn.commit()
    conn.close()
    return jsonify({'status': 'success', 'message': f'Customer {contact_id} assigned to staff {assigned_staff_id}'})

@app.route('/api/contacts', methods=['POST'])
@require_auth
def create_contact():
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller or not (is_caller_ceo(caller) or is_caller_manager(caller)):
        return jsonify({'error': 'Forbidden: Only CEO and Managers can create contacts'}), 403

    data = request.json or {}
    name = data.get('name', '').strip()
    phone = data.get('phone', '').strip()
    folder = data.get('folder', 'customers').strip()
    role = data.get('role', '').strip()
    avatar = data.get('avatar', '').strip()
    email = data.get('email', '').strip()
    notes = data.get('notes', '').strip()
    country_code = data.get('country_code', '').strip()
    assigned_staff_id = data.get('assigned_staff_id')

    if not name:
        return jsonify({'error': 'Name is required'}), 400
    if folder not in ['customers', 'staff']:
        return jsonify({'error': 'Folder must be either "customers" or "staff"'}), 400

    import re
    base_id = re.sub(r'[^a-zA-Z0-9_]', '', name.lower().replace(' ', '_'))
    if not base_id:
        base_id = 'contact'
    
    import time
    contact_id = f"{base_id}_{int(time.time())}"

    if not role:
        role = 'Customer' if folder == 'customers' else 'Staff'

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute('SELECT 1 FROM contacts WHERE id = %s', (contact_id,))
    if cursor.fetchone():
        conn.close()
        return jsonify({'error': 'Contact already exists'}), 400

    cursor.execute('''
        INSERT INTO contacts (id, name, phone, role, avatar, status, folder, unread_count, assigned_staff_id, email, notes, country_code)
        VALUES (%s, %s, %s, %s, %s, 'Offline', %s, 0, NULL, %s, %s, %s)
    ''', (contact_id, name, phone, role, avatar, folder, email, notes, country_code))

    conn.commit()

    cursor.execute('SELECT * FROM contacts WHERE id = %s', (contact_id,))
    new_contact = dict(cursor.fetchone())
    new_contact['tags'] = []

    conn.close()
    return jsonify(new_contact)

@app.route('/api/contacts/staff', methods=['POST'])
@require_auth
def create_staff():
    data = request.json or {}
    name = data.get('name', '').strip()
    phone = data.get('phone', '').strip()
    role = data.get('role', 'Staff Member').strip()
    avatar = data.get('avatar', '').strip()
    
    if not name:
        return jsonify({'error': 'Staff name is required'}), 400
        
    import re
    base_id = re.sub(r'[^a-zA-Z0-9_]', '', name.lower().replace(' ', '_'))
    if not base_id:
        base_id = 'staff'
    staff_id = base_id
    
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT 1 FROM contacts WHERE id = %s', (staff_id,))
    if cursor.fetchone():
        staff_id = f"{base_id}_{int(time.time())}"
        
    cursor.execute('''
        INSERT INTO contacts (id, name, phone, role, avatar, status, folder, unread_count, assigned_staff_id)
        VALUES (%s, %s, %s, %s, %s, 'Offline', 'staff', 0, NULL)
    ''', (staff_id, name, phone, role, avatar))
    
    conn.commit()
    
    cursor.execute('SELECT * FROM contacts WHERE id = %s', (staff_id,))
    new_staff = dict(cursor.fetchone())
    new_staff['tags'] = []
    
    conn.close()
    return jsonify(new_staff)

@app.route('/api/contacts/<contact_id>', methods=['DELETE'])
@require_auth
def delete_contact(contact_id):
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller:
        return jsonify({'error': 'Unauthorized'}), 401

    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT email FROM contacts WHERE id = %s', (contact_id,))
    c_row = cursor.fetchone()
    if not c_row:
        conn.close()
        return jsonify({'error': 'Contact not found'}), 404
        
    c_email = c_row.get('email') or ''
    
    # 1. Unassign any customers assigned to this staff member
    cursor.execute('UPDATE contacts SET assigned_staff_id = NULL WHERE assigned_staff_id = %s', (contact_id,))
    cursor.execute('UPDATE users SET assigned_staff_id = NULL WHERE assigned_staff_id = %s', (contact_id,))
    
    # 2. Delete messages and call logs
    cursor.execute('DELETE FROM messages WHERE contact_id = %s', (contact_id,))
    cursor.execute('DELETE FROM call_logs WHERE contact_id = %s', (contact_id,))
    
    # 3. Delete from contacts table
    cursor.execute('DELETE FROM contacts WHERE id = %s', (contact_id,))
    
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'message': f'Contact {contact_id} deleted successfully'})

@app.route('/api/contacts/<contact_id>/messages', methods=['GET'])
@require_auth
def get_messages(contact_id):
    caller_phone = get_authenticated_phone()
    
    # Verify authorization for non-system contacts
    if contact_id not in ('ebi', 'support'):
        if not is_call_authorized(caller_phone, contact_id):
            return jsonify({'error': 'Unauthorized: access to conversation with this contact is restricted', 'status': 'forbidden'}), 403

    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('UPDATE contacts SET unread_count = 0 WHERE id = %s', (contact_id,))
    cursor.execute("UPDATE messages SET status = 'read' WHERE contact_id = %s AND is_user = FALSE AND status = 'unread'", (contact_id,))
    conn.commit()
    
    cursor.execute('SELECT * FROM messages WHERE contact_id = %s ORDER BY id ASC', (contact_id,))
    rows = cursor.fetchall()
    
    messages = []
    for r in rows:
        msg = dict(r)
        if isinstance(msg['reactions'], str):
            try:
                msg['reactions'] = json.loads(msg['reactions'])
            except Exception:
                msg['reactions'] = []
        messages.append(msg)
        
    conn.close()
    return jsonify(messages)

def simulate_message_status_updates(msg_id):
    # Wait 1.2 seconds, transition to 'delivered'
    time.sleep(1.2)
    conn = None
    try:
        conn = database.get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE messages SET status = 'delivered' WHERE id = %s AND status = 'sent'", (msg_id,))
        conn.commit()
    except Exception as e:
        print(f"[Simulator Error] Failed to update status to delivered: {e}")
    finally:
        if conn is not None:
            conn.close()
    
    # Wait another 1.8 seconds, transition to 'read'
    time.sleep(1.8)
    conn = None
    try:
        conn = database.get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE messages SET status = 'read' WHERE id = %s AND status = 'delivered'", (msg_id,))
        conn.commit()
    except Exception as e:
        print(f"[Simulator Error] Failed to update status to read: {e}")
    finally:
        if conn is not None:
            conn.close()

def background_message_simulator():
    time.sleep(10) # Start generating messages 10 seconds after server start
    customers = ['david', 'customer_a', 'customer_b', 'customer_c', 'customer_d', 'customer_e', 'customer_f', 'customer_g']
    messages_pool = [
        "Hi Marcus, just wanted to check if the database migration was completed?",
        "Are the design specifications ready for review?",
        "Can we schedule our strategy sync tomorrow morning?",
        "I received the files, everything looks great!",
        "Let me know when you are free to jump on a quick call.",
        "Could you please check the project status on the dashboard?",
        "Is the test server deployed?",
        "The pricing contract looks good. Let's proceed."
    ]
    while True:
        try:
            time.sleep(25) # Generate a new message every 25 seconds
            import random
            cust_id = random.choice(customers)
            text = random.choice(messages_pool)
            
            now = datetime.now()
            time_str = now.strftime('%I:%M %p')
            
            conn = None
            try:
                conn = database.get_db_connection()
                cursor = conn.cursor()
                
                # 1. Insert incoming unread message
                cursor.execute('''
                    INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, reactions, status)
                    VALUES (%s, %s, FALSE, %s, FALSE, NULL, FALSE, NULL, NULL, '[]'::jsonb, 'unread')
                ''', (cust_id, text, time_str))
                
                # 2. Increment unread count of contact
                cursor.execute('UPDATE contacts SET unread_count = unread_count + 1 WHERE id = %s', (cust_id,))
                
                conn.commit()
                print(f"[Simulator] Generated new unread message from '{cust_id}': {text}")
            finally:
                if conn is not None:
                    conn.close()
        except Exception as e:
            print(f"[Simulator Error] Background message simulator error: {e}")

# Start the background message simulator only when explicitly enabled
if os.environ.get('ENABLE_MESSAGE_SIMULATOR', 'false').lower() in ('1', 'true', 'yes'):
    threading.Thread(target=background_message_simulator, daemon=True).start()

@app.route('/api/contacts/<contact_id>/messages', methods=['POST'])
@require_auth
def send_message(contact_id):
    caller_phone = get_authenticated_phone()
    
    # Verify authorization for non-system contacts
    if contact_id not in ('ebi', 'support'):
        if not is_call_authorized(caller_phone, contact_id):
            return jsonify({'error': 'Unauthorized: communication with this contact is restricted by organizational policy', 'status': 'forbidden'}), 403

    data = request.json or {}
    text = data.get('text', '')
    is_audio = data.get('is_audio', False)
    duration = data.get('duration')
    is_file = data.get('is_file', False)
    file_name = data.get('file_name')
    file_size = data.get('file_size')
    latitude = data.get('latitude')
    longitude = data.get('longitude')
    location_name = data.get('location_name')
    contact_card_id = data.get('contact_card_id')
    contact_card_name = data.get('contact_card_name')
    contact_card_phone = data.get('contact_card_phone')
    poll_id = data.get('poll_id')
    
    if not text and not is_audio and not is_file and latitude is None and not contact_card_id and not poll_id:
        return jsonify({'error': 'Message content is empty'}), 400
        
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT 1 FROM contacts WHERE id = %s', (contact_id,))
    if not cursor.fetchone():
        conn.close()
        return jsonify({'error': 'Contact not found'}), 404
        
    now = datetime.now()
    time_str = now.strftime('%I:%M %p')
    
    cursor.execute('SELECT name FROM contacts WHERE id = %s', (contact_id,))
    contact_row = cursor.fetchone()
    if not contact_row:
        conn.close()
        return jsonify({'error': 'Contact not found'}), 404
    
    cursor.execute('''
        INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, latitude, longitude, location_name, contact_card_id, contact_card_name, contact_card_phone, poll_id, reactions, status)
        VALUES (%s, %s, TRUE, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, '[]'::jsonb, 'sent')
    ''', (contact_id, text, time_str, is_audio, duration, is_file, file_name, file_size, latitude, longitude, location_name, contact_card_id, contact_card_name, contact_card_phone, poll_id))
    
    user_msg_id = getattr(cursor, 'lastrowid', None)
    if not user_msg_id:
        cursor.execute('SELECT id FROM messages WHERE contact_id = %s ORDER BY id DESC LIMIT 1', (contact_id,))
        r = cursor.fetchone()
        user_msg_id = r['id'] if r else 1
    
    bot_message = None
    if contact_id == 'ebi' and text:
        lower_text = text.lower()
        if 'summarize' in lower_text or 'summary' in lower_text or 'overview' in lower_text or 'project' in lower_text:
            bot_response = (
                "🤖 **EBI 2.0 Executive Briefing**\n\n"
                "📊 **Active Workspaces & Projects**:\n"
                "• **Project Aurora (75%)**: Prototype approved by Client VP David Miller. Awaiting final pricing contract.\n"
                "• **Project Vortex (33%)**: Integration workspace issue reported by Diana Prince. Support ticket routed.\n"
                "• **Project Titan (66%)**: Lead Developer Michael Chang reports build is stable.\n\n"
                "⚠️ **Urgent Action Items**:\n"
                "1. Review pricing contract for David Miller (Aurora Corp).\n"
                "2. Schedule integration sync with Diana Prince (Vortex)."
            )
        elif 'action' in lower_text or 'task' in lower_text or 'todo' in lower_text:
            bot_response = (
                "📌 **Extracted Action Items & Deliverables**\n\n"
                "🔥 **High Priority**:\n"
                "• Approve team expansion request on HR portal (Emma Watson).\n"
                "• Review design system specs uploaded by Sarah Jenkins.\n\n"
                "⚡ **Medium Priority**:\n"
                "• Verify transaction reports for Bob Smith.\n"
                "• Send contract drafts to Fiona Gallagher (Titan)."
            )
        elif 'contract' in lower_text or 'agreement' in lower_text or 'proposal' in lower_text:
            bot_response = (
                "📑 **EBI Smart Contract Generator**\n\n"
                "Contract ID: `CTR-2026-AUG-889`\n"
                "Client: Aurora Corp (David Miller)\n"
                "Value: $125,000 USD\n"
                "Status: Ready for E-Signature ✍️\n\n"
                "[Action]: Single-tap approval link generated for Marcus Sterling."
            )
        elif 'translate' in lower_text:
            bot_response = (
                "🌐 **EBI Polyglot Engine**\n\n"
                "Original: 'We are good to go for the project launch next week.'\n"
                "• **Spanish**: 'Estamos listos para el lanzamiento del proyecto la próxima semana.'\n"
                "• **French**: 'Nous sommes prêts pour le lancement du projet la semaine prochaine.'\n"
                "• **Japanese**: '来週のプロジェクト立ち上げの準備が整いました。'\n"
                "• **German**: 'Wir sind bereit für den Projektstart nächste Woche.'"
            )
        elif 'metric' in lower_text or 'analytics' in lower_text or 'kpi' in lower_text:
            bot_response = (
                "📈 **GEBTALK Executive Analytics**\n\n"
                "• Total Active Contacts: 14\n"
                "• Broadcast Reach: 99.4% Delivery Rate\n"
                "• Average API Response Time: 1.2ms\n"
                "• Active WebRTC Calls Today: 4 calls (0 dropped frames)"
            )
        else:
            bot_response = (
                f"⚡ **EBI Co-Pilot**: Executing command: \"{text}\".\n\n"
                "I can assist with:\n"
                "• Type **'summarize'** for instant workspace briefing.\n"
                "• Type **'tasks'** for pending action items.\n"
                "• Type **'contract'** for smart agreement tools.\n"
                "• Type **'translate [text]'** for polyglot translation.\n"
                "• Type **'analytics'** for live communication KPIs."
            )
            
        cursor.execute('''
            INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, reactions, status)
            VALUES (%s, %s, FALSE, %s, FALSE, NULL, FALSE, NULL, NULL, '[]'::jsonb, 'read')
        ''', (contact_id, bot_response, time_str))
        
        bot_msg_id = getattr(cursor, 'lastrowid', None)
        if not bot_msg_id:
            cursor.execute('SELECT id FROM messages WHERE contact_id = %s ORDER BY id DESC LIMIT 1', (contact_id,))
            r = cursor.fetchone()
            bot_msg_id = r['id'] if r else user_msg_id + 1
            
        cursor.execute('SELECT * FROM messages WHERE id = %s', (bot_msg_id,))
        bot_row = cursor.fetchone()
        if bot_row:
            bot_message = dict(bot_row)
            if isinstance(bot_message['reactions'], str):
                try:
                    bot_message['reactions'] = json.loads(bot_message['reactions'])
                except Exception:
                    bot_message['reactions'] = []
        
    conn.commit()
    
    # Launch status simulation thread for outgoing user message
    threading.Thread(target=simulate_message_status_updates, args=(user_msg_id,), daemon=True).start()
    
    cursor.execute('SELECT * FROM messages WHERE id = %s', (user_msg_id,))
    user_row = cursor.fetchone()
    user_message = dict(user_row) if user_row else {'id': user_msg_id, 'contact_id': contact_id, 'text': text, 'is_user': True, 'time': time_str, 'reactions': [], 'status': 'sent'}
    if isinstance(user_message.get('reactions'), str):
        try:
            user_message['reactions'] = json.loads(user_message['reactions'])
        except Exception:
            user_message['reactions'] = []
    
    conn.close()
    
    return jsonify({
        'status': 'success',
        'user_message': user_message,
        'bot_message': bot_message
    })

@app.route('/api/contacts/<contact_id>/messages/<int:msg_id>/react', methods=['POST'])
@require_auth
def react_message(contact_id, msg_id):
    data = request.json or {}
    emoji = data.get('emoji', '').strip()
    if not emoji:
        return jsonify({'error': 'Emoji reaction is required'}), 400
        
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT reactions FROM messages WHERE id = %s AND contact_id = %s', (msg_id, contact_id))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return jsonify({'error': 'Message not found'}), 404
        
    reactions = row['reactions']
    if isinstance(reactions, str):
        reactions = json.loads(reactions)
    
    if emoji in reactions:
        reactions.remove(emoji)
    else:
        reactions.append(emoji)
        
    cursor.execute('UPDATE messages SET reactions = %s WHERE id = %s', (json.dumps(reactions), msg_id))
    conn.commit()
    conn.close()
    
    return jsonify({'status': 'success', 'reactions': reactions})

@app.route('/api/broadcast', methods=['POST'])
@require_auth
def send_broadcast():
    data = request.json or {}
    recipients = data.get('recipients', [])
    text = data.get('text', '')
    is_file = data.get('is_file', False)
    file_name = data.get('file_name', None)
    file_size = data.get('file_size', None)
    
    if not recipients or (not text and not is_file):
        return jsonify({'error': 'Recipients and text/file content are required'}), 400
        
    now = datetime.now()
    time_str = now.strftime('%I:%M %p')
    date_str = now.strftime('%b %d, %Y')
    
    conn = get_db()
    cursor = conn.cursor()
    
    recipient_names = []
    delivered_count = 0
    
    for rid in recipients:
        cursor.execute('SELECT name FROM contacts WHERE id = %s', (rid,))
        contact_row = cursor.fetchone()
        if contact_row:
            recipient_names.append(contact_row['name'])
            cursor.execute('''
                INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, reactions, status, is_broadcast)
                VALUES (%s, %s, TRUE, %s, FALSE, NULL, %s, %s, %s, '[]'::jsonb, 'sent', TRUE)
                RETURNING id
            ''', (rid, text, time_str, is_file, file_name, file_size))
            
            msg_id = cursor.fetchone()['id']
            # Launch status simulation thread for each broadcast message
            threading.Thread(target=simulate_message_status_updates, args=(msg_id,), daemon=True).start()
            
            cursor.execute('UPDATE contacts SET unread_count = unread_count + 1 WHERE id = %s', (rid,))
            delivered_count += 1
            
    recipients_str = ', '.join(recipient_names)
    cursor.execute('''
        INSERT INTO broadcast_history (text, time, date, recipient_count, delivered_count, is_file, file_name, file_size, recipients)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    ''', (text, time_str, date_str, len(recipients), delivered_count, is_file, file_name, file_size, recipients_str))
    
    conn.commit()
    conn.close()
    
    return jsonify({
        'status': 'success',
        'message': f'Broadcast delivered to {delivered_count} contacts',
        'delivered_count': delivered_count
    })

@app.route('/api/broadcast/history', methods=['GET'])
def get_broadcast_history():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM broadcast_history ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    
    history = []
    for r in rows:
        item = dict(r)
        item['is_file'] = bool(item['is_file'])
        history.append(item)
        
    return jsonify(history)

@app.route('/api/broadcast/lists', methods=['GET', 'POST'])
def broadcast_lists():
    conn = get_db()
    cursor = conn.cursor()
    
    if request.method == 'POST':
        if not get_authenticated_phone():
            conn.close()
            return jsonify({'error': 'Authentication required'}), 401
        data = request.json or {}
        list_id = data.get('id', '').strip()
        name = data.get('name', '').strip()
        members = data.get('members', [])
        
        if not name:
            conn.close()
            return jsonify({'error': 'List name is required'}), 400
            
        if not list_id:
            list_id = name.lower().replace(' ', '_')
            
        cursor.execute('''
            INSERT INTO broadcast_lists (id, name) VALUES (%s, %s)
            ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name
        ''', (list_id, name))
        cursor.execute('DELETE FROM broadcast_list_members WHERE list_id = %s', (list_id,))
        for mid in members:
            cursor.execute('INSERT INTO broadcast_list_members (list_id, contact_id) VALUES (%s, %s)', (list_id, mid))
        conn.commit()
        
    cursor.execute('SELECT * FROM broadcast_lists')
    lists_rows = cursor.fetchall()
    
    lists = []
    for row in lists_rows:
        lst = dict(row)
        cursor.execute('SELECT contact_id FROM broadcast_list_members WHERE list_id = %s', (lst['id'],))
        lst['members'] = [r['contact_id'] for r in cursor.fetchall()]
        lists.append(lst)
        
    conn.close()
    return jsonify(lists)

@app.route('/api/broadcast/lists/<list_id>', methods=['DELETE'])
@require_auth
def delete_broadcast_list(list_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM broadcast_lists WHERE id = %s', (list_id,))
    cursor.execute('DELETE FROM broadcast_list_members WHERE list_id = %s', (list_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/api/profile', methods=['GET', 'POST'])
def profile():
    conn = get_db()
    cursor = conn.cursor()
    
    user_phone = request.headers.get('x-user-phone')
    if not user_phone:
        auth_header = request.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            user_phone = auth_header.split(' ')[1]
            
    if not user_phone:
        conn.close()
        return jsonify({'error': 'Authentication required'}), 401
        
    cursor.execute('SELECT * FROM user_profile WHERE phone = %s OR id = %s', (user_phone, user_phone))
    row = cursor.fetchone()
    if not row:
        norm = normalize_phone(user_phone)
        if norm:
            cursor.execute('SELECT * FROM user_profile')
            for r in cursor.fetchall():
                if normalize_phone(r.get('phone') or '') == norm:
                    row = r
                    break
        
    if request.method == 'POST':
        data = request.json or {}
        name = data.get('name', '')
        role = data.get('role', '')
        phone = data.get('phone', user_phone)
        avatar = data.get('avatar', '')
        email = data.get('email', '')
        notifications_enabled = data.get('notifications_enabled', True)
        notification_sound = data.get('notification_sound', True)
        notification_vibration = data.get('notification_vibration', True)
        security_2fa = data.get('security_2fa', False)
        read_receipts = data.get('read_receipts', True)
        last_seen_visible = data.get('last_seen_visible', True)
        
        country_code = data.get('country_code')
        country_name = data.get('country_name')
        country_flag = data.get('country_flag')
        
        if row:
            user_id = row['id']
            avatar_url = save_avatar_if_base64(avatar, user_id)
            cursor.execute('''
                UPDATE user_profile
                SET name = %s, role = %s, phone = %s, avatar = %s, email = %s,
                    notifications_enabled = %s, notification_sound = %s, notification_vibration = %s,
                    security_2fa = %s, read_receipts = %s, last_seen_visible = %s,
                    country_code = COALESCE(%s, country_code),
                    country_name = COALESCE(%s, country_name),
                    country_flag = COALESCE(%s, country_flag)
                WHERE id = %s
            ''', (name or row.get('name', 'User'), role or row.get('role', 'Executive'), phone or row.get('phone', user_phone), avatar_url or row.get('avatar', ''), email or row.get('email', ''),
                  bool(notifications_enabled), bool(notification_sound), bool(notification_vibration),
                  bool(security_2fa), bool(read_receipts), bool(last_seen_visible),
                  country_code, country_name, country_flag, user_id))
            # Sync email/name/role changes to users table so old credentials are invalidated
            updated_name = name or row.get('name', 'User')
            updated_email = email or row.get('email', '')
            updated_role_val = role or row.get('role', 'Executive')
            old_email = (row.get('email') or '').lower()
            if updated_email:
                cursor.execute('''
                    UPDATE users SET email = %s, name = %s, role = %s, avatar = COALESCE(%s, avatar)
                    WHERE id = %s OR LOWER(email) = %s OR phone = %s
                ''', (updated_email, updated_name, updated_role_val, avatar_url or row.get('avatar', ''), user_id, old_email, phone or user_phone))
            # Sync all other user_profile rows with the same phone so old email cannot be used to log in
            if updated_email:
                cursor.execute('''
                    UPDATE user_profile SET email = %s, name = %s, role = %s
                    WHERE phone = %s AND id != %s
                ''', (updated_email, updated_name, updated_role_val, phone or user_phone, user_id))
            # Also sync to contacts table
            cursor.execute('UPDATE contacts SET email = %s, name = %s, role = %s WHERE id = %s OR phone = %s', (updated_email, updated_name, updated_role_val, user_id, phone or user_phone))
        else:
            user_id = f"user_{normalize_phone(user_phone) or int(time.time())}"
            avatar_url = save_avatar_if_base64(avatar, user_id)
            cursor.execute('''
                INSERT INTO user_profile (
                    id, name, role, phone, avatar, email,
                    notifications_enabled, notification_sound, notification_vibration,
                    security_2fa, read_receipts, last_seen_visible,
                    country_code, country_name, country_flag
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ''', (user_id, name or 'User', role or 'Executive', phone or user_phone, avatar_url or '', email or '',
                  bool(notifications_enabled), bool(notification_sound), bool(notification_vibration),
                  bool(security_2fa), bool(read_receipts), bool(last_seen_visible),
                  country_code, country_name, country_flag))
        conn.commit()
        
        cursor.execute('SELECT * FROM user_profile WHERE id = %s', (user_id,))
        row = cursor.fetchone()
        
    if not row:
        user_id = f"user_{normalize_phone(user_phone) or int(time.time())}"
        cursor.execute('''
            INSERT INTO user_profile (
                id, name, role, phone, avatar, email,
                notifications_enabled, notification_sound, notification_vibration,
                security_2fa, read_receipts, last_seen_visible
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ''', (user_id, 'User', 'Executive', user_phone, '', '', True, True, True, False, True, True))
        conn.commit()
        cursor.execute('SELECT * FROM user_profile WHERE id = %s', (user_id,))
        row = cursor.fetchone()
        
    conn.close()
    
    if row:
        p = dict(row)
        for key in ['notifications_enabled', 'notification_sound', 'notification_vibration', 'security_2fa', 'read_receipts', 'last_seen_visible']:
            if key in p and p[key] is not None:
                p[key] = bool(p[key])
        return jsonify(p)
    else:
        return jsonify({'error': 'Profile not found'}), 404

# WebRTC Signaling Endpoints & Helpers

def get_contact_id_for_user_or_contact(id_val):
    if not id_val:
        return None
    
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # Check if it's already a valid contact ID
        cursor.execute('SELECT id FROM contacts WHERE id = %s', (id_val,))
        row = cursor.fetchone()
        if row:
            return row['id']
            
        # Try normalizing id_val directly as a phone number
        norm_id = "".join(c for c in id_val if c.isdigit())
        if norm_id and len(norm_id) >= 10:
            cursor.execute('SELECT id, phone FROM contacts')
            for c_row in cursor.fetchall():
                if c_row['phone'] and "".join(c for c in c_row['phone'] if c.isdigit()) == norm_id:
                    return c_row['id']

        # If not, find the phone number in user_profile
        cursor.execute('SELECT phone FROM user_profile WHERE id = %s', (id_val,))
        row = cursor.fetchone()
        if row and row['phone']:
            norm_phone = "".join(c for c in row['phone'] if c.isdigit())
            if norm_phone:
                cursor.execute('SELECT id, phone FROM contacts')
                for c_row in cursor.fetchall():
                    if c_row['phone'] and "".join(c for c in c_row['phone'] if c.isdigit()) == norm_phone:
                        return c_row['id']
    except Exception as e:
        print(f"[Mapping Error] Failed to map {id_val}: {e}", flush=True)
    finally:
        conn.close()
    return None

def log_call_in_messages(call_id, caller_id, callee_id, duration_secs, was_connected):
    caller_contact_id = get_contact_id_for_user_or_contact(caller_id)
    callee_contact_id = get_contact_id_for_user_or_contact(callee_id)

    if was_connected:
        minutes = duration_secs // 60
        seconds = duration_secs % 60
        duration_str = f"{minutes:02d}:{seconds:02d}"
        caller_text = f"📞 Outgoing Call ({duration_str})"
        callee_text = f"📞 Incoming Call ({duration_str})"
    else:
        caller_text = "📞 Outgoing Call (No Answer)"
        callee_text = "📞 Missed Call"

    now = datetime.now()
    time_str = now.strftime('%I:%M %p')
    
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # 1. Log on caller's side: if callee has a contact ID
        if callee_contact_id:
            cursor.execute('''
                INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, reactions, status)
                VALUES (%s, %s, TRUE, %s, FALSE, NULL, FALSE, NULL, NULL, '[]'::jsonb, 'read')
            ''', (callee_contact_id, caller_text, time_str))
            
        # 2. Log on callee's side: if caller has a contact ID
        if caller_contact_id:
            cursor.execute('''
                INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, reactions, status)
                VALUES (%s, %s, FALSE, %s, FALSE, NULL, FALSE, NULL, NULL, '[]'::jsonb, 'unread')
            ''', (caller_contact_id, callee_text, time_str))
        conn.commit()
    except Exception as e:
        print(f"[Call Logging Error] Failed to log call in messages: {e}", flush=True)
    finally:
        conn.close()

def resolve_profile_by_id(id_val):
    if not id_val:
        return None
    id_str = str(id_val).strip()
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # 1. users table
        cursor.execute('''
            SELECT id, name, role, email, phone, avatar, assigned_staff_id, is_active
            FROM users
            WHERE LOWER(email) = %s OR id = %s OR phone = %s OR LOWER(username) = %s
        ''', (id_str.lower(), id_str, id_str, id_str.lower()))
        u = cursor.fetchone()
        if u:
            return dict(u)

        # 2. user_profile table
        cursor.execute('''
            SELECT id, name, role, email, phone, avatar, assigned_staff_id, is_active
            FROM user_profile
            WHERE LOWER(email) = %s OR id = %s OR phone = %s
        ''', (id_str.lower(), id_str, id_str))
        up = cursor.fetchone()
        if up:
            return dict(up)

        # 3. contacts table
        cursor.execute('''
            SELECT id, name, role, email, phone, avatar, assigned_staff_id, folder
            FROM contacts
            WHERE LOWER(email) = %s OR id = %s OR phone = %s
        ''', (id_str.lower(), id_str, id_str))
        c = cursor.fetchone()
        if c:
            cd = dict(c)
            if not cd.get('role'):
                cd['role'] = 'Staff' if cd.get('folder') == 'staff' else ('Customer' if cd.get('folder') == 'customers' else 'Executive')
            return cd
    except Exception as e:
        print(f"[resolve_profile_by_id Error]: {e}", flush=True)
    finally:
        conn.close()
    return None

def get_all_user_aliases(profile):
    if not profile:
        return set()
    aliases = set()
    for k in ('id', 'email', 'phone', 'username'):
        v = profile.get(k)
        if v:
            aliases.add(str(v).lower())
            
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        email = (profile.get('email') or '').lower()
        if email:
            cursor.execute('SELECT id, email, phone, username FROM contacts WHERE LOWER(email) = %s', (email,))
            c = cursor.fetchone()
            if c:
                for k in ('id', 'email', 'phone', 'username'):
                    if c.get(k): aliases.add(str(c[k]).lower())
            cursor.execute('SELECT id, email, phone, username FROM users WHERE LOWER(email) = %s', (email,))
            u = cursor.fetchone()
            if u:
                for k in ('id', 'email', 'phone', 'username'):
                    if u.get(k): aliases.add(str(u[k]).lower())
    except Exception as e:
        print(f"[get_all_user_aliases Error]: {e}", flush=True)
    finally:
        conn.close()
    return aliases

def is_call_authorized(caller_id, callee_id):
    if not caller_id or not callee_id:
        return False
    if str(caller_id).lower() == str(callee_id).lower():
        return False

    caller = resolve_profile_by_id(caller_id)
    callee = resolve_profile_by_id(callee_id)

    if not caller:
        return False

    caller_role = get_canonical_role(caller)

    # 1. CEO -> Allowed to call anyone
    if caller_role == 'CEO':
        return True

    # 2. Manager -> Allowed to call any Staff or Customer
    if caller_role == 'Manager':
        return True

    if not callee:
        return False

    callee_role = get_canonical_role(callee)
    caller_aliases = get_all_user_aliases(caller)
    callee_aliases = get_all_user_aliases(callee)

    # 3. Staff -> Can call CEO, Managers, other Staff; Customers ONLY if assigned
    if caller_role == 'Staff':
        if callee_role in ('CEO', 'Manager', 'Staff'):
            return True
        if callee_role == 'Customer':
            assigned = str(callee.get('assigned_staff_id') or '').lower()
            if assigned in caller_aliases:
                return True
            return False
        return False

    # 4. Customer -> Can call CEO, Managers; Staff ONLY if assigned specialist; other customers blocked
    if caller_role == 'Customer':
        if callee_role in ('CEO', 'Manager'):
            return True
        if callee_role == 'Customer':
            return False
        assigned = str(caller.get('assigned_staff_id') or '').lower()
        if assigned in callee_aliases:
            return True
        return False

    return False

@app.route('/api/calls/config', methods=['GET'])
def get_webrtc_config():
    stun_url = os.environ.get('STUN_SERVER_URL', 'stun:stun.l.google.com:19302')
    turn_url = os.environ.get('TURN_SERVER_URL')
    turn_username = os.environ.get('TURN_USERNAME')
    turn_password = os.environ.get('TURN_PASSWORD')
    
    ice_servers: list[dict] = [
        {
            'urls': [
                stun_url,
                'stun:stun1.l.google.com:19302',
                'stun:stun2.l.google.com:19302',
                'stun:stun3.l.google.com:19302',
                'stun:stun4.l.google.com:19302',
                'stun:stun.services.mozilla.com',
                'stun:stun.cloudflare.com:3478',
                'stun:stun.sipgate.net:3478',
                'stun:global.stun.twilio.com:3478'
            ]
        },
        {
            'urls': [
                'turn:openrelay.metered.ca:80',
                'turn:openrelay.metered.ca:443',
                'turn:openrelay.metered.ca:443?transport=tcp',
                'turns:openrelay.metered.ca:443?transport=tcp'
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject'
        }
    ]
    if turn_url:
        turn_entry: dict = {'urls': [turn_url]}
        if turn_username: turn_entry['username'] = turn_username
        if turn_password: turn_entry['credential'] = turn_password
        ice_servers.append(turn_entry)
        
    return jsonify({
        'iceServers': ice_servers,
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'balanced',
        'iceCandidatePoolSize': 4
    })

@app.route('/api/calls/create', methods=['POST'])
def create_call():
    data = request.json or {}
    caller_id = data.get('caller_id')
    callee_id = data.get('callee_id')
    sdp_offer = data.get('sdp_offer')
    call_type = data.get('call_type', 'voice')
    
    if not caller_id or not callee_id or not sdp_offer:
        return jsonify({'error': 'Missing required parameters'}), 400

    if str(caller_id).lower() == str(callee_id).lower():
        return jsonify({'error': 'Cannot initiate voice call to yourself', 'status': 'self_call'}), 400

    # 0. Role-based calling authorization check
    if not is_call_authorized(caller_id, callee_id):
        return jsonify({
            'error': 'Unauthorized call: caller does not have permission to communicate with this recipient',
            'status': 'forbidden'
        }), 403
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 1. Busy check: see if callee is currently in an active call with another user
    cursor.execute('''
        SELECT id, caller_id, callee_id, status, created_at
        FROM webrtc_calls
        WHERE (callee_id = %s OR caller_id = %s) AND status IN ('ringing', 'connected', 'calling')
        ORDER BY id DESC LIMIT 1
    ''', (callee_id, callee_id))
    active_callee_call = cursor.fetchone()
    if active_callee_call:
        # If re-calling the same user, or call between these users was open, supersede it immediately
        if active_callee_call['caller_id'] == caller_id or active_callee_call['callee_id'] == caller_id:
            cursor.execute("UPDATE webrtc_calls SET status = 'ended' WHERE id = %s", (active_callee_call['id'],))
            conn.commit()
        else:
            from datetime import timezone
            now = datetime.now(timezone.utc)
            created_at = active_callee_call['created_at']
            if isinstance(created_at, str):
                try: created_at = datetime.fromisoformat(created_at)
                except Exception: created_at = datetime.now(timezone.utc)
            if hasattr(created_at, 'tzinfo') and created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=timezone.utc)
            elapsed = (now - created_at).total_seconds()
            
            # If callee is genuinely on an active call with another third party (< 60s)
            if elapsed < 60:
                conn.close()
                return jsonify({
                    'error': 'Recipient is currently on another call',
                    'status': 'busy'
                }), 486
            else:
                # Stale call, mark it ended
                cursor.execute("UPDATE webrtc_calls SET status = 'ended' WHERE id = %s", (active_callee_call['id'],))
                conn.commit()

    cursor.execute('''
        INSERT INTO webrtc_calls (caller_id, callee_id, sdp_offer, status)
        VALUES (%s, %s, %s, 'ringing')
    ''', (caller_id, callee_id, sdp_offer))
    
    call_id = getattr(cursor, 'lastrowid', None)
    if not call_id:
        cursor.execute('SELECT id FROM webrtc_calls WHERE caller_id = %s ORDER BY id DESC LIMIT 1', (caller_id,))
        r = cursor.fetchone()
        call_id = r['id'] if r else int(time.time())
        
    conn.commit()
    conn.close()
    
    return jsonify({'call_id': call_id, 'status': 'ringing', 'call_type': call_type})

@app.route('/api/calls/incoming', methods=['GET'])
def get_incoming_calls():
    callee_id = request.args.get('callee_id')
    if not callee_id:
        return jsonify({'error': 'Missing callee_id'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    possible_ids = {callee_id, callee_id.lower()}
    
    # Resolve aliases across user_profile, users, and contacts
    cursor.execute('SELECT id, phone, email, username FROM users WHERE id = %s OR email = %s OR username = %s OR phone = %s', (callee_id, callee_id, callee_id, callee_id))
    u_row = cursor.fetchone()
    if u_row:
        for k in ('id', 'phone', 'email', 'username'):
            if u_row.get(k): possible_ids.add(str(u_row[k]))
            
    cursor.execute('SELECT id, phone, email FROM user_profile WHERE id = %s OR phone = %s OR email = %s', (callee_id, callee_id, callee_id))
    up_row = cursor.fetchone()
    if up_row:
        if up_row.get('id'): possible_ids.add(str(up_row['id']))
        if up_row.get('phone'): possible_ids.add(str(up_row['phone']))
        if up_row.get('email'): possible_ids.add(str(up_row['email']))
        
    cursor.execute('SELECT id, phone, email FROM contacts WHERE id = %s OR phone = %s OR email = %s', (callee_id, callee_id, callee_id))
    c_row = cursor.fetchone()
    if c_row:
        if c_row.get('id'): possible_ids.add(str(c_row['id']))
        if c_row.get('phone'): possible_ids.add(str(c_row['phone']))
        if c_row.get('email'): possible_ids.add(str(c_row['email']))
                    
    ids_list = list(possible_ids)
    if not ids_list:
        conn.close()
        return jsonify(None), 200
        
    placeholders = ','.join(['%s'] * len(ids_list))
    cursor.execute(f'''
        SELECT id, caller_id, callee_id, sdp_offer, status, created_at
        FROM webrtc_calls
        WHERE callee_id IN ({placeholders}) AND status = 'ringing'
        ORDER BY created_at DESC
        LIMIT 1
    ''', ids_list)
    row = cursor.fetchone()
    
    if row:
        from datetime import timezone
        now = datetime.now(timezone.utc)
        created_at = row['created_at']
        if isinstance(created_at, str):
            try:
                created_at = datetime.fromisoformat(created_at)
            except Exception:
                created_at = datetime.now(timezone.utc)
        if hasattr(created_at, 'tzinfo') and created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        elapsed = (now - created_at).total_seconds()
        
        if elapsed > 45:
            cursor.execute("UPDATE webrtc_calls SET status = 'ended' WHERE id = %s", (row['id'],))
            cursor.execute("DELETE FROM webrtc_candidates WHERE call_id = %s", (row['id'],))
            conn.commit()
            conn.close()
            log_call_in_messages(row['id'], row['caller_id'], row['callee_id'], 0, False)
            return jsonify(None), 200
            
        caller_name = row['caller_id']
        caller_avatar = ""
        cursor.execute('SELECT name, avatar FROM users WHERE id = %s OR email = %s OR username = %s', (row['caller_id'], row['caller_id'], row['caller_id']))
        u_caller = cursor.fetchone()
        if u_caller:
            caller_name = u_caller['name']
            caller_avatar = u_caller.get('avatar') or ''
        else:
            cursor.execute('SELECT name, avatar FROM user_profile WHERE id = %s', (row['caller_id'],))
            up_caller = cursor.fetchone()
            if up_caller:
                caller_name = up_caller['name']
                caller_avatar = up_caller.get('avatar') or ''
            else:
                cursor.execute('SELECT name, avatar FROM contacts WHERE id = %s', (row['caller_id'],))
                c_caller = cursor.fetchone()
                if c_caller:
                    caller_name = c_caller['name']
                    caller_avatar = c_caller.get('avatar') or ''
                
        conn.close()
        return jsonify({
            'call_id': row['id'],
            'caller_id': row['caller_id'],
            'caller_name': caller_name,
            'caller_avatar': caller_avatar,
            'callee_id': row['callee_id'],
            'sdp_offer': row['sdp_offer'],
            'status': row['status']
        })
        
    conn.close()
    return jsonify(None), 200

@app.route('/api/calls/accept', methods=['POST'])
def accept_call():
    data = request.json or {}
    call_id = data.get('call_id')
    sdp_answer = data.get('sdp_answer')
    
    if not call_id or not sdp_answer:
        return jsonify({'error': 'Missing call_id or sdp_answer'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE webrtc_calls
        SET sdp_answer = %s, status = 'connected'
        WHERE id = %s
    ''', (sdp_answer, call_id))
    conn.commit()
    conn.close()
    
    return jsonify({'success': True, 'status': 'connected'})

@app.route('/api/calls/status', methods=['GET'])
def get_call_status():
    call_id = request.args.get('call_id')
    if not call_id:
        return jsonify({'error': 'Missing call_id'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, status, sdp_offer, sdp_answer, caller_id, callee_id, created_at
        FROM webrtc_calls
        WHERE id = %s
    ''', (call_id,))
    row = cursor.fetchone()
    
    if row:
        status = row['status']
        if status == 'ringing':
            from datetime import timezone
            now = datetime.now(timezone.utc)
            created_at = row['created_at']
            if isinstance(created_at, str):
                try: created_at = datetime.fromisoformat(created_at)
                except Exception: created_at = datetime.now(timezone.utc)
            if hasattr(created_at, 'tzinfo') and created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=timezone.utc)
            elapsed = (now - created_at).total_seconds()
            if elapsed > 45:
                cursor.execute("UPDATE webrtc_calls SET status = 'ended' WHERE id = %s", (call_id,))
                cursor.execute("DELETE FROM webrtc_candidates WHERE call_id = %s", (call_id,))
                conn.commit()
                log_call_in_messages(row['id'], row['caller_id'], row['callee_id'], 0, False)
                status = 'ended'
                
        conn.close()
        return jsonify({
            'call_id': row['id'],
            'status': status,
            'sdp_offer': row['sdp_offer'],
            'sdp_answer': row['sdp_answer'],
            'caller_id': row['caller_id'],
            'callee_id': row['callee_id']
        })
    conn.close()
    return jsonify({'status': 'ended'}), 200

@app.route('/api/calls/ice-candidate', methods=['POST'])
def add_ice_candidate():
    data = request.json or {}
    call_id = data.get('call_id')
    sender_id = data.get('sender_id')
    candidate = data.get('candidate')
    
    if not call_id or not sender_id or not candidate:
        return jsonify({'error': 'Missing parameters'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO webrtc_candidates (call_id, sender_id, candidate)
        VALUES (%s, %s, %s)
    ''', (call_id, sender_id, candidate))
    conn.commit()
    conn.close()
    
    return jsonify({'success': True})

@app.route('/api/calls/ice-candidates', methods=['GET'])
def get_ice_candidates():
    call_id = request.args.get('call_id')
    exclude_sender_id = request.args.get('exclude_sender_id')
    
    if not call_id or not exclude_sender_id:
        return jsonify({'error': 'Missing call_id or exclude_sender_id'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, sender_id, candidate
        FROM webrtc_candidates
        WHERE call_id = %s AND sender_id != %s
        ORDER BY id ASC
    ''', (call_id, exclude_sender_id))
    rows = cursor.fetchall()
    conn.close()
    
    candidates = []
    for row in rows:
        candidates.append({
            'id': row['id'],
            'sender_id': row['sender_id'],
            'candidate': row['candidate']
        })
    return jsonify(candidates)

@app.route('/api/calls/end', methods=['POST'])
def end_call():
    data = request.json or {}
    call_id = data.get('call_id')
    duration = data.get('duration', 0)
    state_before_end = data.get('state_before_end', '')
    end_reason = data.get('reason', 'ended') # 'ended', 'declined', 'cancelled', 'timeout'
    
    if not call_id:
        return jsonify({'error': 'Missing call_id'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT id, caller_id, callee_id, status FROM webrtc_calls WHERE id = %s', (call_id,))
    row = cursor.fetchone()
    
    if row and row['status'] != 'ended':
        caller_id = row['caller_id']
        callee_id = row['callee_id']
        row_id = row['id']
        was_connected = (state_before_end == 'connected' or row['status'] == 'connected')
        
        cursor.execute('''
            UPDATE webrtc_calls
            SET status = 'ended'
            WHERE id = %s
        ''', (call_id,))
        cursor.execute('''
            DELETE FROM webrtc_candidates
            WHERE call_id = %s
        ''', (call_id,))
        conn.commit()
        conn.close()
        
        dur_int = int(duration)
        minutes = dur_int // 60
        seconds = dur_int % 60
        duration_formatted = f"{minutes:02d}:{seconds:02d}"
        
        # 1. Log in chat messages
        log_call_in_messages(
            call_id=row_id,
            caller_id=caller_id,
            callee_id=callee_id,
            duration_secs=dur_int,
            was_connected=was_connected
        )
        
        # 2. Log in call_logs table for calls screen history with fresh db connection
        try:
            log_conn = get_db_connection()
            log_cursor = log_conn.cursor()
            time_now_str = datetime.now().strftime('%I:%M %p')
            
            # Fetch callee & caller display names
            caller_name = caller_id
            caller_avatar = ""
            callee_name = callee_id
            callee_avatar = ""
            
            log_cursor.execute('SELECT name, avatar FROM users WHERE id = %s OR email = %s', (caller_id, caller_id))
            u_c = log_cursor.fetchone()
            if u_c:
                caller_name, caller_avatar = u_c['name'], u_c.get('avatar') or ''
                
            log_cursor.execute('SELECT name, avatar FROM users WHERE id = %s OR email = %s', (callee_id, callee_id))
            u_e = log_cursor.fetchone()
            if u_e:
                callee_name, callee_avatar = u_e['name'], u_e.get('avatar') or ''
                
            # Caller log: Outgoing
            log_cursor.execute('''
                INSERT INTO call_logs (contact_id, contact_name, contact_avatar, call_type, direction, time_str, duration)
                VALUES (%s, %s, %s, 'voice', 'outgoing', %s, %s)
            ''', (callee_id, callee_name, callee_avatar, time_now_str, duration_formatted if was_connected else '00:00'))
            
            # Callee log: Incoming or Missed
            callee_direction = 'incoming' if was_connected else ('declined' if end_reason == 'declined' else 'missed')
            log_cursor.execute('''
                INSERT INTO call_logs (contact_id, contact_name, contact_avatar, call_type, direction, time_str, duration)
                VALUES (%s, %s, %s, 'voice', %s, %s, %s)
            ''', (caller_id, caller_name, caller_avatar, callee_direction, time_now_str, duration_formatted if was_connected else '00:00'))
            log_conn.commit()
            log_conn.close()
        except Exception as e:
            print(f"[Call Log Persistence Error]: {e}", flush=True)
    else:
        conn.close()
        
    return jsonify({'success': True, 'status': 'ended'})

# --- WHATSAPP PARITY & ADVANCED FEATURES ENDPOINTS ---

@app.route('/api/groups/create', methods=['POST'])
@require_auth
def create_group():
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller or not (is_caller_ceo(caller) or is_caller_manager(caller)):
        return jsonify({'error': 'Forbidden: Only CEO and Managers can create groups'}), 403

    data = request.json or {}
    name = data.get('name', '').strip()
    description = data.get('description', '').strip()
    member_ids = data.get('member_ids', [])
    avatar = data.get('avatar') or 'https://images.unsplash.com/photo-1522071820081-009f0129c71c?auto=format&fit=crop&w=100&q=80'
    creator_phone = get_authenticated_phone()
    
    if not name:
        return jsonify({'error': 'Group name is required'}), 400
        
    group_id = f"group_{int(time.time())}"
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 1. Insert into contacts table as group
    cursor.execute('''
        INSERT INTO contacts (id, name, role, avatar, status, folder, unread_count, is_group)
        VALUES (%s, %s, %s, %s, 'Active Group', 'staff', 0, TRUE)
    ''', (group_id, name, f'Group • {len(member_ids) + 1} Members', avatar))
    
    # 2. Insert into groups table
    cursor.execute('''
        INSERT INTO groups (id, name, description, avatar, created_by)
        VALUES (%s, %s, %s, %s, %s)
    ''', (group_id, name, description, avatar, creator_phone or 'marcus'))
    
    # 3. Add creator as admin
    cursor.execute('''
        INSERT INTO group_members (group_id, contact_id, role)
        VALUES (%s, %s, 'admin')
    ''', (group_id, creator_phone or 'marcus'))
    
    # 4. Add members
    for mem_id in member_ids:
        cursor.execute('''
            INSERT INTO group_members (group_id, contact_id, role)
            VALUES (%s, %s, 'member')
            ON CONFLICT (group_id, contact_id) DO NOTHING
        ''', (group_id, mem_id))
        
    # 5. Insert system welcome message in group
    now = datetime.now()
    time_str = now.strftime('%I:%M %p')
    cursor.execute('''
        INSERT INTO messages (contact_id, text, is_user, time, reactions, status)
        VALUES (%s, %s, FALSE, %s, '[]'::jsonb, 'read')
    ''', (group_id, f"🎉 Group '{name}' was created.", time_str))
    
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'group_id': group_id, 'name': name})

@app.route('/api/groups/<group_id>/members', methods=['GET', 'POST'])
@require_auth
def manage_group_members(group_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    if request.method == 'GET':
        cursor.execute('''
            SELECT gm.contact_id, gm.role, c.name, c.avatar, c.phone
            FROM group_members gm
            LEFT JOIN contacts c ON gm.contact_id = c.id
            WHERE gm.group_id = %s
        ''', (group_id,))
        rows = cursor.fetchall()
        members = [dict(r) for r in rows]
        conn.close()
        return jsonify(members)
        
    data = request.json or {}
    action = data.get('action', 'add') # 'add' or 'remove'
    contact_id = data.get('contact_id')
    
    if action == 'add':
        cursor.execute('''
            INSERT INTO group_members (group_id, contact_id, role)
            VALUES (%s, %s, 'member') ON CONFLICT DO NOTHING
        ''', (group_id, contact_id))
    elif action == 'remove':
        cursor.execute('DELETE FROM group_members WHERE group_id = %s AND contact_id = %s', (group_id, contact_id))
        
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/api/channels', methods=['GET'])
def get_channels():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM channels ORDER BY follower_count DESC')
    rows = cursor.fetchall()
    channels = [dict(r) for r in rows]
    conn.close()
    return jsonify(channels)

@app.route('/api/channels/<channel_id>/follow', methods=['POST'])
@require_auth
def follow_channel(channel_id):
    user_phone = get_authenticated_phone() or 'marcus'
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('SELECT 1 FROM channel_followers WHERE channel_id = %s AND contact_id = %s', (channel_id, user_phone))
    already = cursor.fetchone()
    
    if already:
        cursor.execute('DELETE FROM channel_followers WHERE channel_id = %s AND contact_id = %s', (channel_id, user_phone))
        cursor.execute('UPDATE channels SET follower_count = GREATEST(0, follower_count - 1) WHERE id = %s', (channel_id,))
        is_following = False
    else:
        cursor.execute('INSERT INTO channel_followers (channel_id, contact_id) VALUES (%s, %s)', (channel_id, user_phone))
        cursor.execute('UPDATE channels SET follower_count = follower_count + 1 WHERE id = %s', (channel_id,))
        is_following = True
        
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_following': is_following})

@app.route('/api/channels/<channel_id>/posts', methods=['GET', 'POST'])
def channel_posts(channel_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    if request.method == 'GET':
        cursor.execute('SELECT * FROM channel_posts WHERE channel_id = %s ORDER BY created_at ASC', (channel_id,))
        rows = cursor.fetchall()
        posts = []
        for r in rows:
            p = dict(r)
            if isinstance(p.get('reactions_json'), str):
                try:
                    p['reactions'] = json.loads(p['reactions_json'])
                except Exception:
                    p['reactions'] = {}
            posts.append(p)
        conn.close()
        return jsonify(posts)
        
    data = request.json or {}
    text = data.get('text', '').strip()
    media_url = data.get('media_url')
    
    if not text and not media_url:
        conn.close()
        return jsonify({'error': 'Post content required'}), 400
        
    post_id = f"post_{int(time.time())}"
    cursor.execute('''
        INSERT INTO channel_posts (id, channel_id, text, media_url, reactions_json)
        VALUES (%s, %s, %s, %s, '{}')
    ''', (post_id, channel_id, text, media_url))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'post_id': post_id})

@app.route('/api/messages/<int:msg_id>/star', methods=['POST'])
@require_auth
def toggle_star_message(msg_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT is_starred FROM messages WHERE id = %s', (msg_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return jsonify({'error': 'Message not found'}), 404
        
    new_starred = not row['is_starred']
    cursor.execute('UPDATE messages SET is_starred = %s WHERE id = %s', (new_starred, msg_id))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_starred': new_starred})

@app.route('/api/messages/forward', methods=['POST'])
@require_auth
def forward_messages():
    data = request.json or {}
    msg_ids = data.get('msg_ids', [])
    target_contact_ids = data.get('target_contact_ids', [])
    
    if not msg_ids or not target_contact_ids:
        return jsonify({'error': 'Missing msg_ids or target_contact_ids'}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    now = datetime.now()
    time_str = now.strftime('%I:%M %p')
    
    for msg_id in msg_ids:
        cursor.execute('SELECT * FROM messages WHERE id = %s', (msg_id,))
        source_msg = cursor.fetchone()
        if not source_msg:
            continue
            
        for target_id in target_contact_ids:
            cursor.execute('''
                INSERT INTO messages (contact_id, text, is_user, time, is_audio, duration, is_file, file_name, file_size, latitude, longitude, location_name, contact_card_id, contact_card_name, contact_card_phone, poll_id, reactions, status)
                VALUES (%s, %s, TRUE, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, '[]'::jsonb, 'sent')
            ''', (target_id, source_msg['text'], time_str, source_msg['is_audio'], source_msg['duration'], source_msg['is_file'], source_msg['file_name'], source_msg['file_size'], source_msg['latitude'], source_msg['longitude'], source_msg['location_name'], source_msg['contact_card_id'], source_msg['contact_card_name'], source_msg['contact_card_phone'], source_msg['poll_id']))
            
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'forwarded_count': len(msg_ids) * len(target_contact_ids)})

@app.route('/api/contacts/<contact_id>/disappearing', methods=['POST'])
@require_auth
def set_disappearing_timer(contact_id):
    data = request.json or {}
    timer_seconds = int(data.get('disappearing_timer', 0))
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('UPDATE contacts SET disappearing_timer = %s WHERE id = %s', (timer_seconds, contact_id))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'disappearing_timer': timer_seconds})

@app.route('/api/search', methods=['GET'])
@require_auth
def global_search():
    q = request.args.get('q', '').strip().lower()
    filter_type = request.args.get('filter', 'all')
    
    if not q:
        return jsonify({'contacts': [], 'messages': []})
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 1. Search Contacts with role filtering
    cursor.execute("SELECT * FROM contacts WHERE LOWER(name) LIKE %s OR LOWER(phone) LIKE %s OR LOWER(role) LIKE %s", (f'%{q}%', f'%{q}%', f'%{q}%'))
    raw_contacts = [dict(r) for r in cursor.fetchall()]
    contacts = filter_contacts_for_user(raw_contacts, g.caller_profile)
    
    allowed_cids = {c['id'] for c in contacts}
    allowed_cids.add('ebi')
    allowed_cids.add('support')
    
    # 2. Search Messages strictly within authorized contact scopes
    if allowed_cids:
        placeholders = ', '.join(['%s'] * len(allowed_cids))
        msg_query = f"SELECT m.*, c.name as contact_name, c.avatar as contact_avatar FROM messages m LEFT JOIN contacts c ON m.contact_id = c.id WHERE LOWER(m.text) LIKE %s AND m.contact_id IN ({placeholders})"
        params = [f'%{q}%'] + list(allowed_cids)
    else:
        msg_query = "SELECT m.*, c.name as contact_name, c.avatar as contact_avatar FROM messages m LEFT JOIN contacts c ON m.contact_id = c.id WHERE FALSE"
        params = []
    
    if filter_type == 'media':
        msg_query += " AND (m.is_file = TRUE OR m.is_audio = TRUE)"
    elif filter_type == 'docs':
        msg_query += " AND m.is_file = TRUE AND LOWER(m.file_name) LIKE '%.pdf%'"
    elif filter_type == 'audio':
        msg_query += " AND m.is_audio = TRUE"
    elif filter_type == 'polls':
        msg_query += " AND m.poll_id IS NOT NULL"
        
    msg_query += " ORDER BY m.id DESC LIMIT 50"
    cursor.execute(msg_query, params)
    messages = [dict(r) for r in cursor.fetchall()]
    
    conn.close()
    return jsonify({'contacts': contacts, 'messages': messages})

@app.route('/api/ai/translate', methods=['POST'])
def translate_message():
    data = request.json or {}
    text = data.get('text', '').strip()
    target_lang = data.get('target_language', 'Spanish')
    
    if not text:
        return jsonify({'error': 'No text provided'}), 400
        
    translations_mock = {
        'Spanish': f"[ES] {text} (Traducido)",
        'French': f"[FR] {text} (Traduit)",
        'German': f"[DE] {text} (Übersetzt)",
        'Hindi': f"[HI] {text} (अनुवादित)",
        'Japanese': f"[JA] {text} (翻訳済み)",
        'Chinese': f"[ZH] {text} (已翻译)",
        'Arabic': f"[AR] {text} (مترجم)",
    }
    translated = translations_mock.get(target_lang, f"[{target_lang[:2].upper()}] {text} (Translated)")
    return jsonify({'original': text, 'target_language': target_lang, 'translated_text': translated})

@app.route('/api/ai/summarize', methods=['POST'])
def summarize_chat():
    data = request.json or {}
    contact_id = data.get('contact_id')
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT text, is_user, time FROM messages WHERE contact_id = %s ORDER BY id DESC LIMIT 15', (contact_id,))
    rows = cursor.fetchall()
    conn.close()
    
    if not rows:
        return jsonify({'summary': 'No messages found to summarize.'})
        
    texts = [r['text'] for r in rows if r['text']]
    summary = f"🤖 **Conversation Key Takeaways ({len(texts)} messages)**:\n• Main topic discussed: Strategy, specifications & deliverables.\n• Recent status: Shared latest files & scheduled follow-up.\n• Next Action: Review attached specs and confirm meeting timeline."
    return jsonify({'summary': summary})

@app.route('/api/profile/app-lock', methods=['POST'])
@require_auth
def set_app_lock():
    data = request.json or {}
    enabled = data.get('enabled', False)
    pin = data.get('pin', '')
    user_phone = get_authenticated_phone() or 'marcus'
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('UPDATE user_profile SET app_lock_enabled = %s, app_lock_pin = %s WHERE phone = %s OR id = %s', (enabled, pin, user_phone, user_phone))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'enabled': enabled})

# ========== PHASE 1: WhatsApp Feature Parity Endpoints ==========

# --- Typing Indicators ---

@app.route('/api/typing', methods=['POST'])
@require_auth
def set_typing():
    data = request.json or {}
    contact_id = data.get('contact_id', '')
    is_typing = data.get('is_typing', False)
    user_phone = get_authenticated_phone()
    
    if not contact_id:
        return jsonify({'error': 'contact_id required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO typing_indicators (user_id, contact_id, is_typing, updated_at)
        VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id, contact_id) DO UPDATE SET is_typing = EXCLUDED.is_typing, updated_at = CURRENT_TIMESTAMP
    ''', (user_phone, contact_id, is_typing))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/api/typing/<contact_id>', methods=['GET'])
def get_typing(contact_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT user_id, is_typing, updated_at FROM typing_indicators
        WHERE contact_id = %s AND is_typing = TRUE
    ''', (contact_id,))
    rows = cursor.fetchall()
    conn.close()
    
    typers = []
    for r in rows:
        d = dict(r)
        # Auto-expire typing after 10 seconds
        updated = d.get('updated_at')
        if updated:
            from datetime import timezone
            now = datetime.now(timezone.utc)
            if isinstance(updated, str):
                try:
                    updated = datetime.fromisoformat(updated)
                except Exception:
                    updated = now
            if hasattr(updated, 'tzinfo') and updated.tzinfo is None:
                updated = updated.replace(tzinfo=timezone.utc)
            if (now - updated).total_seconds() > 10:
                continue
        typers.append({'user_id': d['user_id'], 'is_typing': True})
    
    return jsonify(typers)

# --- Online Presence ---

@app.route('/api/presence/update', methods=['POST'])
@require_auth
def update_presence():
    data = request.json or {}
    is_online = data.get('is_online', False)
    user_phone = get_authenticated_phone()
    
    # Resolve user_id from profile
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    if is_online:
        cursor.execute('''
            INSERT INTO user_presence (user_id, is_online, last_seen)
            VALUES (%s, TRUE, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id) DO UPDATE SET is_online = TRUE, last_seen = CURRENT_TIMESTAMP
        ''', (user_id,))
    else:
        cursor.execute('''
            INSERT INTO user_presence (user_id, is_online, last_seen)
            VALUES (%s, FALSE, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id) DO UPDATE SET is_online = FALSE, last_seen = CURRENT_TIMESTAMP
        ''', (user_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/api/presence/<user_id>', methods=['GET'])
def get_presence(user_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM user_presence WHERE user_id = %s', (user_id,))
    row = cursor.fetchone()
    conn.close()
    
    if row:
        d = dict(row)
        last_seen = d.get('last_seen')
        if last_seen and isinstance(last_seen, str):
            pass  # keep as string for JSON
        elif last_seen:
            d['last_seen'] = last_seen.isoformat()
        return jsonify(d)
    return jsonify({'user_id': user_id, 'is_online': False, 'last_seen': None})

# --- Archive Chats ---

@app.route('/api/chats/<contact_id>/archive', methods=['POST'])
@require_auth
def toggle_archive(contact_id):
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT 1 FROM archived_chats WHERE user_id = %s AND contact_id = %s', (user_id, contact_id))
    exists = cursor.fetchone()
    
    if exists:
        cursor.execute('DELETE FROM archived_chats WHERE user_id = %s AND contact_id = %s', (user_id, contact_id))
        is_archived = False
    else:
        cursor.execute('''
            INSERT INTO archived_chats (user_id, contact_id) VALUES (%s, %s)
            ON CONFLICT (user_id, contact_id) DO NOTHING
        ''', (user_id, contact_id))
        is_archived = True
    
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_archived': is_archived})

@app.route('/api/chats/archived', methods=['GET'])
@require_auth
def get_archived():
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT c.* FROM contacts c
        JOIN archived_chats ac ON c.id = ac.contact_id
        WHERE ac.user_id = %s
    ''', (user_id,))
    contacts = [dict(r) for r in cursor.fetchall()]
    contacts = stitch_contacts(cursor, contacts)
    conn.close()
    return jsonify(contacts)

# --- Mute Chats ---

@app.route('/api/chats/<contact_id>/mute', methods=['POST'])
@require_auth
def toggle_mute(contact_id):
    data = request.json or {}
    muted_until = data.get('muted_until')  # ISO string or null for forever
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT 1 FROM muted_chats WHERE user_id = %s AND contact_id = %s', (user_id, contact_id))
    exists = cursor.fetchone()
    
    if exists:
        cursor.execute('DELETE FROM muted_chats WHERE user_id = %s AND contact_id = %s', (user_id, contact_id))
        is_muted = False
    else:
        cursor.execute('''
            INSERT INTO muted_chats (user_id, contact_id, muted_until) VALUES (%s, %s, %s)
            ON CONFLICT (user_id, contact_id) DO UPDATE SET muted_until = EXCLUDED.muted_until
        ''', (user_id, contact_id, muted_until))
        is_muted = True
    
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_muted': is_muted})

# --- Pin Chats ---

@app.route('/api/chats/<contact_id>/pin', methods=['POST'])
@require_auth
def toggle_pin(contact_id):
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT 1 FROM pinned_chats WHERE user_id = %s AND contact_id = %s', (user_id, contact_id))
    exists = cursor.fetchone()
    
    if exists:
        cursor.execute('DELETE FROM pinned_chats WHERE user_id = %s AND contact_id = %s', (user_id, contact_id))
        is_pinned = False
    else:
        # WhatsApp allows max 3 pinned chats
        cursor.execute('SELECT COUNT(*) FROM pinned_chats WHERE user_id = %s', (user_id,))
        count_row = cursor.fetchone()
        count = count_row['count(*)'] if count_row else 0
        if count >= 3:
            conn.close()
            return jsonify({'error': 'Maximum 3 pinned chats allowed'}), 400
        
        cursor.execute('''
            INSERT INTO pinned_chats (user_id, contact_id) VALUES (%s, %s)
            ON CONFLICT (user_id, contact_id) DO NOTHING
        ''', (user_id, contact_id))
        is_pinned = True
    
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_pinned': is_pinned})

# --- Block Contacts ---

@app.route('/api/contacts/<contact_id>/block', methods=['POST'])
@require_auth
def toggle_block(contact_id):
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT 1 FROM blocked_contacts WHERE user_id = %s AND blocked_id = %s', (user_id, contact_id))
    exists = cursor.fetchone()
    
    if exists:
        cursor.execute('DELETE FROM blocked_contacts WHERE user_id = %s AND blocked_id = %s', (user_id, contact_id))
        is_blocked = False
    else:
        cursor.execute('''
            INSERT INTO blocked_contacts (user_id, blocked_id) VALUES (%s, %s)
            ON CONFLICT (user_id, blocked_id) DO NOTHING
        ''', (user_id, contact_id))
        is_blocked = True
    
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_blocked': is_blocked})

@app.route('/api/contacts/blocked', methods=['GET'])
@require_auth
def get_blocked():
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT c.* FROM contacts c
        JOIN blocked_contacts bc ON c.id = bc.blocked_id
        WHERE bc.user_id = %s
    ''', (user_id,))
    contacts = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(contacts)

# --- Chat Wallpaper ---

@app.route('/api/chats/<contact_id>/wallpaper', methods=['POST'])
@require_auth
def set_wallpaper(contact_id):
    data = request.json or {}
    wallpaper_url = data.get('wallpaper_url', '')
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    cid = contact_id if contact_id != 'default' else '__default__'
    
    conn = get_db()
    cursor = conn.cursor()
    if wallpaper_url:
        cursor.execute('''
            INSERT INTO chat_wallpapers (user_id, contact_id, wallpaper_url) VALUES (%s, %s, %s)
            ON CONFLICT (user_id, contact_id) DO UPDATE SET wallpaper_url = EXCLUDED.wallpaper_url
        ''', (user_id, cid, wallpaper_url))
    else:
        cursor.execute('DELETE FROM chat_wallpapers WHERE user_id = %s AND contact_id = %s', (user_id, cid))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# --- Message Read Receipts ---

@app.route('/api/messages/<int:msg_id>/receipts', methods=['GET'])
@require_auth
def get_receipts(msg_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT mr.user_id, mr.status, mr.timestamp, c.name as user_name, c.avatar as user_avatar
        FROM message_receipts mr
        LEFT JOIN contacts c ON mr.user_id = c.id
        WHERE mr.message_id = %s
    ''', (msg_id,))
    rows = cursor.fetchall()
    conn.close()
    
    receipts = []
    for r in rows:
        d = dict(r)
        if d.get('timestamp') and not isinstance(d['timestamp'], str):
            d['timestamp'] = d['timestamp'].isoformat()
        receipts.append(d)
    return jsonify(receipts)

# --- Chat Media Gallery ---

@app.route('/api/chats/<contact_id>/media', methods=['GET'])
@require_auth
def get_chat_media(contact_id):
    media_filter = request.args.get('filter', 'all')  # 'all', 'images', 'videos', 'docs', 'audio', 'links'
    
    conn = get_db()
    cursor = conn.cursor()
    
    if media_filter == 'images':
        cursor.execute('''
            SELECT * FROM messages WHERE contact_id = %s
            AND (is_file = TRUE AND (LOWER(file_name) LIKE '%%.png' OR LOWER(file_name) LIKE '%%.jpg' OR LOWER(file_name) LIKE '%%.jpeg' OR LOWER(file_name) LIKE '%%.gif' OR LOWER(file_name) LIKE '%%.webp'))
            ORDER BY id DESC
        ''', (contact_id,))
    elif media_filter == 'videos':
        cursor.execute('''
            SELECT * FROM messages WHERE contact_id = %s
            AND (is_file = TRUE AND (LOWER(file_name) LIKE '%%.mp4' OR LOWER(file_name) LIKE '%%.mov' OR LOWER(file_name) LIKE '%%.avi' OR LOWER(file_name) LIKE '%%.mkv'))
            ORDER BY id DESC
        ''', (contact_id,))
    elif media_filter == 'docs':
        cursor.execute('''
            SELECT * FROM messages WHERE contact_id = %s
            AND (is_file = TRUE AND (LOWER(file_name) LIKE '%%.pdf' OR LOWER(file_name) LIKE '%%.doc%%' OR LOWER(file_name) LIKE '%%.xls%%' OR LOWER(file_name) LIKE '%%.ppt%%' OR LOWER(file_name) LIKE '%%.txt'))
            ORDER BY id DESC
        ''', (contact_id,))
    elif media_filter == 'audio':
        cursor.execute('''
            SELECT * FROM messages WHERE contact_id = %s AND is_audio = TRUE
            ORDER BY id DESC
        ''', (contact_id,))
    elif media_filter == 'links':
        cursor.execute('''
            SELECT * FROM messages WHERE contact_id = %s
            AND (text LIKE '%%http://%%' OR text LIKE '%%https://%%' OR text LIKE '%%www.%%')
            ORDER BY id DESC
        ''', (contact_id,))
    else:
        cursor.execute('''
            SELECT * FROM messages WHERE contact_id = %s
            AND (is_file = TRUE OR is_audio = TRUE)
            ORDER BY id DESC
        ''', (contact_id,))
    
    rows = cursor.fetchall()
    conn.close()
    
    media = []
    for r in rows:
        msg = dict(r)
        if isinstance(msg.get('reactions'), str):
            try:
                msg['reactions'] = json.loads(msg['reactions'])
            except Exception:
                msg['reactions'] = []
        media.append(msg)
    return jsonify(media)

# --- Clear Chat History ---

@app.route('/api/chats/<contact_id>/clear', methods=['POST'])
@require_auth
def clear_chat(contact_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM messages WHERE contact_id = %s', (contact_id,))
    cursor.execute('UPDATE contacts SET unread_count = 0 WHERE id = %s', (contact_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': f'Chat history cleared for {contact_id}'})

# --- Export Chat ---

@app.route('/api/chats/<contact_id>/export', methods=['GET'])
@require_auth
def export_chat(contact_id):
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT name FROM contacts WHERE id = %s', (contact_id,))
    contact_row = cursor.fetchone()
    contact_name = contact_row['name'] if contact_row else contact_id
    
    cursor.execute('SELECT * FROM messages WHERE contact_id = %s ORDER BY id ASC', (contact_id,))
    rows = cursor.fetchall()
    conn.close()
    
    lines = [f"GebTalk Chat Export - {contact_name}", f"Exported: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", "=" * 50, ""]
    
    for r in rows:
        msg = dict(r)
        sender = "You" if msg.get('is_user') else contact_name
        text = msg.get('text', '')
        time_str = msg.get('time', '')
        
        if msg.get('is_audio'):
            text = f"[Voice Note - {msg.get('duration', '0:00')}]"
        elif msg.get('is_file'):
            text = f"[File: {msg.get('file_name', 'unknown')} ({msg.get('file_size', '')})]"
        elif msg.get('latitude') is not None:
            text = f"[Location: {msg.get('location_name', 'Shared Location')}]"
        
        lines.append(f"[{time_str}] {sender}: {text}")
    
    export_text = '\n'.join(lines)
    return jsonify({'export': export_text, 'contact_name': contact_name, 'message_count': len(rows)})

# --- User chat preferences (archive/mute/pin/block states for /api/init) ---

@app.route('/api/chats/preferences', methods=['GET'])
@require_auth
def get_chat_preferences():
    """Returns all archived, muted, pinned, and blocked IDs for the current user."""
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    user_id = profile['id'] if profile else user_phone
    
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT contact_id FROM archived_chats WHERE user_id = %s', (user_id,))
    archived = [r['contact_id'] for r in cursor.fetchall()]
    
    cursor.execute('SELECT contact_id, muted_until FROM muted_chats WHERE user_id = %s', (user_id,))
    muted = {r['contact_id']: str(r['muted_until']) if r['muted_until'] else None for r in cursor.fetchall()}
    
    cursor.execute('SELECT contact_id FROM pinned_chats WHERE user_id = %s', (user_id,))
    pinned = [r['contact_id'] for r in cursor.fetchall()]
    
    cursor.execute('SELECT blocked_id FROM blocked_contacts WHERE user_id = %s', (user_id,))
    blocked = [r['blocked_id'] for r in cursor.fetchall()]
    
    cursor.execute('SELECT contact_id, wallpaper_url FROM chat_wallpapers WHERE user_id = %s', (user_id,))
    wallpapers = {r['contact_id']: r['wallpaper_url'] for r in cursor.fetchall()}
    
    conn.close()
    return jsonify({
        'archived': archived,
        'muted': muted,
        'pinned': pinned,
        'blocked': blocked,
        'wallpapers': wallpapers
    })

# ========== END PHASE 1 ENDPOINTS ==========

# ========== PHASE 2: Stickers & GIFs Endpoints ==========

@app.route('/api/stickers/packs', methods=['GET'])
def get_sticker_packs():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM sticker_packs ORDER BY is_default DESC, name ASC')
    packs = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(packs)

@app.route('/api/stickers/packs/<pack_id>/stickers', methods=['GET'])
def get_pack_stickers(pack_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM stickers WHERE pack_id = %s', (pack_id,))
    stickers = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(stickers)

@app.route('/api/stickers/packs/<pack_id>/install', methods=['POST'])
@require_auth
def install_sticker_pack(pack_id):
    user_phone = get_authenticated_phone()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO user_sticker_packs (user_id, pack_id) VALUES (%s, %s)
        ON CONFLICT (user_id, pack_id) DO NOTHING
    ''', (user_phone, pack_id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/api/gifs/search', methods=['GET'])
def search_gifs():
    query = request.args.get('q', 'funny').lower()
    # High-quality fallback GIFs for messaging
    preset_gifs = [
        {'id': 'g1', 'title': 'Thumbs Up', 'url': 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif', 'preview_url': 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif'},
        {'id': 'g2', 'title': 'Mind Blown', 'url': 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif', 'preview_url': 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif'},
        {'id': 'g3', 'title': 'Clapping', 'url': 'https://media.giphy.com/media/l3q2XhfQ8oCkm1Ts4/giphy.gif', 'preview_url': 'https://media.giphy.com/media/l3q2XhfQ8oCkm1Ts4/giphy.gif'},
        {'id': 'g4', 'title': 'Dancing', 'url': 'https://media.giphy.com/media/3o72FfM5HJydzafgGY/giphy.gif', 'preview_url': 'https://media.giphy.com/media/3o72FfM5HJydzafgGY/giphy.gif'},
        {'id': 'g5', 'title': 'Laughing', 'url': 'https://media.giphy.com/media/10yXFibl97pCCQ/giphy.gif', 'preview_url': 'https://media.giphy.com/media/10yXFibl97pCCQ/giphy.gif'},
        {'id': 'g6', 'title': 'Cat Vibe', 'url': 'https://media.giphy.com/media/GeimqsH0TLDt4tScGw/giphy.gif', 'preview_url': 'https://media.giphy.com/media/GeimqsH0TLDt4tScGw/giphy.gif'},
        {'id': 'g7', 'title': 'Thank You', 'url': 'https://media.giphy.com/media/byz3vhZmgB3vW/giphy.gif', 'preview_url': 'https://media.giphy.com/media/byz3vhZmgB3vW/giphy.gif'},
        {'id': 'g8', 'title': 'Bye', 'url': 'https://media.giphy.com/media/Ru9spt2akv408/giphy.gif', 'preview_url': 'https://media.giphy.com/media/Ru9spt2akv408/giphy.gif'},
    ]
    if query:
        filtered = [g for g in preset_gifs if query in g['title'].lower()]
        return jsonify(filtered if filtered else preset_gifs)
    return jsonify(preset_gifs)

# ========== END PHASE 2 ENDPOINTS ==========

# ========== PHASE 3: Communities, Payments & Newsletters Endpoints ==========

# --- Communities ---

@app.route('/api/communities', methods=['GET', 'POST'])
@require_auth
def handle_communities():
    user_phone = get_authenticated_phone()
    conn = get_db()
    cursor = conn.cursor()
    
    if request.method == 'POST':
        data = request.json or {}
        name = data.get('name', '')
        description = data.get('description', '')
        if not name:
            conn.close()
            return jsonify({'error': 'name required'}), 400
        
        cid = f"comm_{int(datetime.now().timestamp())}"
        cursor.execute('''
            INSERT INTO communities (id, name, description, owner_id)
            VALUES (%s, %s, %s, %s)
        ''', (cid, name, description, user_phone))
        conn.commit()
        conn.close()
        return jsonify({'success': True, 'id': cid})
    
    cursor.execute('SELECT * FROM communities ORDER BY created_at DESC')
    communities = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(communities)

# --- Payments & Wallet ---

@app.route('/api/wallet/balance', methods=['GET'])
@require_auth
def get_wallet_balance():
    user_phone = get_authenticated_phone()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM wallets WHERE user_id = %s', (user_phone,))
    row = cursor.fetchone()
    if not row:
        cursor.execute("INSERT INTO wallets (user_id, balance) VALUES (%s, 150.00) ON CONFLICT (user_id) DO NOTHING", (user_phone,))
        conn.commit()
        balance = 150.00
        currency = 'USD'
    else:
        d = dict(row)
        balance = d['balance']
        currency = d['currency']
    conn.close()
    return jsonify({'user_id': user_phone, 'balance': balance, 'currency': currency})

@app.route('/api/payments/send', methods=['POST'])
@require_auth
def send_payment():
    data = request.json or {}
    receiver_id = data.get('receiver_id', '')
    amount = float(data.get('amount', 0.0))
    note = data.get('note', '')
    user_phone = get_authenticated_phone()
    
    if not receiver_id or amount <= 0:
        return jsonify({'error': 'receiver_id and positive amount required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    
    # Check sender balance
    cursor.execute('SELECT balance FROM wallets WHERE user_id = %s', (user_phone,))
    row = cursor.fetchone()
    balance = row['balance'] if row else 150.00
    
    if balance < amount:
        conn.close()
        return jsonify({'error': 'Insufficient wallet balance'}), 400
    
    tx_id = f"tx_{int(datetime.now().timestamp())}"
    
    # Deduct from sender
    cursor.execute('UPDATE wallets SET balance = balance - %s WHERE user_id = %s', (amount, user_phone))
    # Add to receiver
    cursor.execute('''
        INSERT INTO wallets (user_id, balance) VALUES (%s, %s)
        ON CONFLICT (user_id) DO UPDATE SET balance = wallets.balance + EXCLUDED.balance
    ''', (receiver_id, amount))
    # Record transaction
    cursor.execute('''
        INSERT INTO transactions (id, sender_id, receiver_id, amount, note, status)
        VALUES (%s, %s, %s, %s, %s, 'completed')
    ''', (tx_id, user_phone, receiver_id, amount, note))
    
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'transaction_id': tx_id, 'new_balance': balance - amount})

@app.route('/api/payments/history', methods=['GET'])
@require_auth
def get_payment_history():
    user_phone = get_authenticated_phone()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT * FROM transactions
        WHERE sender_id = %s OR receiver_id = %s
        ORDER BY created_at DESC
    ''', (user_phone, user_phone))
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(rows)

# --- Newsletters ---

@app.route('/api/newsletters', methods=['GET', 'POST'])
def handle_newsletters():
    conn = get_db()
    cursor = conn.cursor()
    
    if request.method == 'POST':
        data = request.json or {}
        name = data.get('name', '')
        description = data.get('description', '')
        nid = f"nl_{int(datetime.now().timestamp())}"
        cursor.execute('''
            INSERT INTO newsletters (id, name, description) VALUES (%s, %s, %s)
        ''', (nid, name, description))
        conn.commit()
        conn.close()
        return jsonify({'success': True, 'id': nid})
    
    cursor.execute('SELECT * FROM newsletters ORDER BY subscriber_count DESC')
    newsletters = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(newsletters)

@app.route('/api/newsletters/<nid>/follow', methods=['POST'])
@require_auth
def follow_newsletter(nid):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE newsletters SET subscriber_count = subscriber_count + 1, is_following = TRUE WHERE id = %s', (nid,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# ========== END PHASE 3 ENDPOINTS ==========

# ========== PHASE 4: Linked Devices, Report & Settings Endpoints ==========

# --- Linked Devices ---

@app.route('/api/devices', methods=['GET'])
@require_auth
def get_linked_devices():
    user_phone = get_authenticated_phone()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM linked_devices WHERE user_id = %s AND is_active = TRUE ORDER BY last_active DESC', (user_phone,))
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(rows)

@app.route('/api/devices/link', methods=['POST'])
@require_auth
def link_device():
    data = request.json or {}
    device_name = data.get('device_name', 'GebTalk Web')
    device_type = data.get('device_type', 'web')
    user_phone = get_authenticated_phone()
    
    did = f"dev_{int(datetime.now().timestamp())}"
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO linked_devices (id, user_id, device_name, device_type)
        VALUES (%s, %s, %s, %s)
    ''', (did, user_phone, device_name, device_type))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'device_id': did})

@app.route('/api/devices/<did>/unlink', methods=['POST'])
@require_auth
def unlink_device(did):
    user_phone = get_authenticated_phone()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE linked_devices SET is_active = FALSE WHERE id = %s AND user_id = %s', (did, user_phone))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# --- Report Contact ---

@app.route('/api/report', methods=['POST'])
@require_auth
def report_contact():
    data = request.json or {}
    reported_id = data.get('reported_id', '')
    report_type = data.get('report_type', 'spam')
    reason = data.get('reason', '')
    user_phone = get_authenticated_phone()
    
    if not reported_id:
        return jsonify({'error': 'reported_id required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO reports (reporter_id, reported_id, report_type, reason)
        VALUES (%s, %s, %s, %s)
    ''', (user_phone, reported_id, report_type, reason))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Report submitted successfully'})

# --- Profile Privacy Settings ---

@app.route('/api/profile/privacy', methods=['POST'])
@require_auth
def update_privacy_settings():
    data = request.json or {}
    user_phone = get_authenticated_phone()
    
    conn = get_db()
    cursor = conn.cursor()
    
    fields = []
    values = []
    for key in ['profile_photo_privacy', 'about_privacy', 'status_privacy', 'groups_privacy', 'last_seen_privacy', 'online_privacy', 'about']:
        if key in data:
            fields.append(f"{key} = %s")
            values.append(data[key])
            
    if fields:
        values.extend([user_phone, user_phone])
        sql = f"UPDATE user_profile SET {', '.join(fields)} WHERE phone = %s OR id = %s"
        cursor.execute(sql, tuple(values))
        conn.commit()
        
    conn.close()
    return jsonify({'success': True})

# ========== PHASE 5: Advanced WhatsApp Parity Endpoints ==========

# --- Pinned Messages ---
@app.route('/api/messages/<int:msg_id>/pin', methods=['POST'])
@require_auth
def toggle_pin_message(msg_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT contact_id, is_pinned FROM messages WHERE id = %s', (msg_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return jsonify({'error': 'Message not found'}), 404
        
    is_pinned = not row['is_pinned']
    if is_pinned:
        cursor.execute('UPDATE messages SET is_pinned = TRUE, pinned_at = CURRENT_TIMESTAMP WHERE id = %s', (msg_id,))
    else:
        cursor.execute('UPDATE messages SET is_pinned = FALSE, pinned_at = NULL WHERE id = %s', (msg_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_pinned': is_pinned})

@app.route('/api/chats/<contact_id>/pinned', methods=['GET'])
@require_auth
def get_pinned_messages(contact_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM messages WHERE contact_id = %s AND is_pinned = TRUE ORDER BY pinned_at DESC, id DESC', (contact_id,))
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(rows)

# --- Starred Messages List ---
@app.route('/api/messages/starred', methods=['GET'])
@require_auth
def get_starred_messages():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT m.*, c.name as contact_name, c.avatar as contact_avatar
        FROM messages m
        LEFT JOIN contacts c ON m.contact_id = c.id
        WHERE m.is_starred = TRUE
        ORDER BY m.id DESC
    ''')
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(rows)

# --- View Once Media ---
@app.route('/api/messages/<int:msg_id>/view-once', methods=['POST'])
@require_auth
def mark_view_once(msg_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('UPDATE messages SET is_viewed = TRUE WHERE id = %s', (msg_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_viewed': True})

# --- Status Views ---
@app.route('/api/statuses/<status_id>/view', methods=['POST'])
@require_auth
def record_status_view(status_id):
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone)
    viewer_name = profile['name'] if profile else user_phone
    viewer_avatar = profile.get('avatar', '') if profile else ''
    
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute('''
            INSERT INTO status_views (status_id, viewer_id, viewer_name, viewer_avatar)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (status_id, viewer_id) DO NOTHING
        ''', (status_id, user_phone, viewer_name, viewer_avatar))
        conn.commit()
    except Exception as e:
        print(f"Status view record error: {e}")
    conn.close()
    return jsonify({'success': True})

@app.route('/api/statuses/<status_id>/views', methods=['GET'])
@require_auth
def get_status_views(status_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM status_views WHERE status_id = %s ORDER BY viewed_at DESC', (status_id,))
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(rows)

# --- Call Links ---
@app.route('/api/calls/link', methods=['POST'])
@require_auth
def create_call_link():
    data = request.json or {}
    call_type = data.get('call_type', 'video')
    link_name = data.get('link_name', 'GebTalk Meeting')
    user_phone = get_authenticated_phone()
    
    import uuid
    link_id = f"call_{uuid.uuid4().hex[:10]}"
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO call_links (id, created_by, call_type, link_name)
        VALUES (%s, %s, %s, %s)
    ''', (link_id, user_phone, call_type, link_name))
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'link_id': link_id,
        'call_url': f"https://gebtalk.app/call/{link_id}",
        'call_type': call_type,
        'link_name': link_name
    })

@app.route('/api/calls/link/<link_id>', methods=['GET'])
def get_call_link(link_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM call_links WHERE id = %s', (link_id,))
    row = cursor.fetchone()
    conn.close()
    if not row:
        return jsonify({'error': 'Call link not found'}), 404
    return jsonify(dict(row))

# --- Storage & Data Manager ---
@app.route('/api/storage/summary', methods=['GET'])
@require_auth
def get_storage_summary():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Total messages count & file messages
    cursor.execute('SELECT COUNT(*) as total, SUM(CASE WHEN is_file THEN 1 ELSE 0 END) as file_count, SUM(CASE WHEN is_audio THEN 1 ELSE 0 END) as audio_count FROM messages')
    stat_row = cursor.fetchone()
    
    # Top chats by message/media count
    cursor.execute('''
        SELECT c.id, c.name, c.avatar, COUNT(m.id) as message_count,
               SUM(CASE WHEN m.is_file THEN 1 ELSE 0 END) as file_count,
               SUM(CASE WHEN m.is_audio THEN 1 ELSE 0 END) as audio_count
        FROM contacts c
        LEFT JOIN messages m ON c.id = m.contact_id
        GROUP BY c.id, c.name, c.avatar
        ORDER BY COUNT(m.id) DESC
        LIMIT 20
    ''')
    chat_breakdowns = [dict(r) for r in cursor.fetchall()]
    
    # Calculate estimated sizes
    for c in chat_breakdowns:
        msg_cnt = c.get('message_count') or 0
        f_cnt = c.get('file_count') or 0
        a_cnt = c.get('audio_count') or 0
        c['size_bytes'] = (msg_cnt * 1024) + (f_cnt * 2500000) + (a_cnt * 450000)
        c['size_formatted'] = f"{c['size_bytes'] / (1024 * 1024):.1f} MB"
        
    total_bytes = sum(c['size_bytes'] for c in chat_breakdowns) or 45000000
    
    conn.close()
    return jsonify({
        'total_used_bytes': total_bytes,
        'total_used_formatted': f"{total_bytes / (1024 * 1024):.1f} MB",
        'other_apps_bytes': 14200000000,
        'free_space_bytes': 48500000000,
        'media_breakdown': {
            'images_mb': 24.5,
            'videos_mb': 88.2,
            'audio_mb': 14.1,
            'documents_mb': 32.0
        },
        'chats': chat_breakdowns
    })

@app.route('/api/storage/chat/<contact_id>', methods=['DELETE'])
@require_auth
def clear_chat_media(contact_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM messages WHERE contact_id = %s AND (is_file = TRUE OR is_audio = TRUE)', (contact_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': f'Media cleared for {contact_id}'})

# --- Account 2FA and Deletion ---
@app.route('/api/profile/account/2fa', methods=['POST'])
@require_auth
def set_account_2fa():
    data = request.json or {}
    enabled = data.get('enabled', False)
    pin = data.get('pin', '')
    user_phone = get_authenticated_phone()
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('UPDATE user_profile SET security_2fa = %s WHERE phone = %s OR id = %s', (enabled, user_phone, user_phone))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'enabled': enabled})

@app.route('/api/profile/account/delete', methods=['POST'])
@require_auth
def delete_account():
    user_phone = get_authenticated_phone()
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM user_profile WHERE phone = %s OR id = %s', (user_phone, user_phone))
    cursor.execute('DELETE FROM contacts WHERE phone = %s OR id = %s', (user_phone, user_phone))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Account deleted successfully'})

@app.route('/api/profile/account/change-password', methods=['POST'])
@require_auth
def change_account_password():
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller or not is_caller_ceo(caller):
        return jsonify({'error': 'Permission Denied: Only CEO is authorized to modify account login passwords and credentials.'}), 403

    data = request.json or {}
    current_password = (data.get('current_password') or '').strip()
    new_password = (data.get('new_password') or '').strip()

    if not current_password or not new_password:
        return jsonify({'error': 'Current password and new password are required'}), 400

    if len(new_password) < 6:
        return jsonify({'error': 'New password must be at least 6 characters long'}), 400

    if current_password == new_password:
        return jsonify({'error': 'New password must be different from current password'}), 400

    user_phone = get_authenticated_phone()
    if not user_phone:
        return jsonify({'error': 'Authentication required'}), 401

    conn = get_db_connection()
    cursor = conn.cursor()

    # Look up the user's current password from users table first, then user_profile
    cursor.execute('SELECT id, password, phone, email FROM users WHERE phone = %s OR id = %s OR LOWER(email) = %s', (user_phone, user_phone, user_phone.lower()))
    user_row = cursor.fetchone()

    if not user_row:
        cursor.execute('SELECT id, password, phone, email FROM user_profile WHERE phone = %s OR id = %s OR LOWER(email) = %s', (user_phone, user_phone, user_phone.lower()))
        user_row = cursor.fetchone()

    if not user_row:
        conn.close()
        return jsonify({'error': 'User account not found'}), 404

    stored_password = user_row.get('password') or ''
    if stored_password and stored_password != current_password:
        conn.close()
        return jsonify({'error': 'Current password is incorrect'}), 401

    user_phone_val = user_row.get('phone') or user_phone
    user_email = (user_row.get('email') or '').lower()

    # Update password in users table
    cursor.execute('UPDATE users SET password = %s WHERE phone = %s OR id = %s', (new_password, user_phone_val, user_phone))
    if user_email:
        cursor.execute('UPDATE users SET password = %s WHERE LOWER(email) = %s', (new_password, user_email))

    # Update password in user_profile table (all rows with same phone)
    cursor.execute('UPDATE user_profile SET password = %s WHERE phone = %s OR id = %s', (new_password, user_phone_val, user_phone))

    conn.commit()
    conn.close()

    return jsonify({
        'success': True,
        'message': 'Password changed successfully. Please use your new password for future logins.'
    })

@app.route('/api/admin/users/update-credentials', methods=['POST'])
@require_auth
def admin_update_user_credentials():
    caller = getattr(g, 'caller_profile', None) or get_caller_profile()
    if not caller or not is_caller_ceo(caller):
        return jsonify({'error': 'Permission Denied: Only CEO is authorized to change staff and customer login email and password.'}), 403

    data = request.json or {}
    target_user_id = (data.get('target_user_id') or data.get('user_id') or '').strip()
    new_email = (data.get('email') or data.get('new_email') or '').strip().lower()
    new_password = (data.get('password') or data.get('new_password') or '').strip()
    new_name = (data.get('name') or '').strip()

    if not target_user_id:
        return jsonify({'error': 'Target user ID or email is required'}), 400

    if new_password and len(new_password) < 6:
        return jsonify({'error': 'New password must be at least 6 characters long'}), 400

    conn = get_db()
    cursor = conn.cursor()

    # Find target user across users, user_profile, contacts
    cursor.execute('''
        SELECT id, name, email, phone, role FROM users 
        WHERE id = %s OR LOWER(email) = %s OR phone = %s
    ''', (target_user_id, target_user_id.lower(), target_user_id))
    user_row = cursor.fetchone()

    if not user_row:
        cursor.execute('''
            SELECT id, name, email, phone, role FROM user_profile 
            WHERE id = %s OR LOWER(email) = %s OR phone = %s
        ''', (target_user_id, target_user_id.lower(), target_user_id))
        user_row = cursor.fetchone()

    if not user_row:
        cursor.execute('''
            SELECT id, name, email, phone, role FROM contacts 
            WHERE id = %s OR LOWER(email) = %s OR phone = %s
        ''', (target_user_id, target_user_id.lower(), target_user_id))
        user_row = cursor.fetchone()

    if not user_row:
        conn.close()
        return jsonify({'error': f'Target user {target_user_id} not found'}), 404

    target_id = user_row.get('id') or target_user_id
    target_email = (user_row.get('email') or '').lower()
    target_phone = user_row.get('phone') or ''
    target_name = user_row.get('name') or 'User'

    # If email changed, check uniqueness
    if new_email and new_email != target_email:
        cursor.execute('SELECT id FROM users WHERE LOWER(email) = %s AND id != %s', (new_email, target_id))
        if cursor.fetchone():
            conn.close()
            return jsonify({'error': f'An account with email {new_email} already exists'}), 400

    # 1. Update users table
    if new_email and new_password and new_name:
        cursor.execute('UPDATE users SET email = %s, password = %s, name = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, new_password, new_name, target_id, target_email, target_phone))
    elif new_email and new_password:
        cursor.execute('UPDATE users SET email = %s, password = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, new_password, target_id, target_email, target_phone))
    elif new_email:
        cursor.execute('UPDATE users SET email = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, target_id, target_email, target_phone))
    elif new_password:
        cursor.execute('UPDATE users SET password = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_password, target_id, target_email, target_phone))
    elif new_name:
        cursor.execute('UPDATE users SET name = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_name, target_id, target_email, target_phone))

    # 2. Update user_profile table
    if new_email and new_password and new_name:
        cursor.execute('UPDATE user_profile SET email = %s, password = %s, name = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, new_password, new_name, target_id, target_email, target_phone))
    elif new_email and new_password:
        cursor.execute('UPDATE user_profile SET email = %s, password = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, new_password, target_id, target_email, target_phone))
    elif new_email:
        cursor.execute('UPDATE user_profile SET email = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, target_id, target_email, target_phone))
    elif new_password:
        cursor.execute('UPDATE user_profile SET password = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_password, target_id, target_email, target_phone))
    elif new_name:
        cursor.execute('UPDATE user_profile SET name = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_name, target_id, target_email, target_phone))

    # 3. Update contacts table
    if new_email and new_name:
        cursor.execute('UPDATE contacts SET email = %s, name = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, new_name, target_id, target_email, target_phone))
    elif new_email:
        cursor.execute('UPDATE contacts SET email = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_email, target_id, target_email, target_phone))
    elif new_name:
        cursor.execute('UPDATE contacts SET name = %s WHERE id = %s OR LOWER(email) = %s OR phone = %s', (new_name, target_id, target_email, target_phone))

    conn.commit()
    conn.close()

    updated_items = []
    if new_email and new_email != target_email:
        updated_items.append(f"email '{new_email}'")
    if new_password:
        updated_items.append("password")

    msg = f"Credentials for {target_name} ({', '.join(updated_items) if updated_items else 'updated'}) saved successfully by CEO."
    return jsonify({
        'success': True,
        'message': msg,
        'user': {
            'id': target_id,
            'email': new_email or target_email,
            'name': new_name or target_name
        }
    })

# ========== GOOGLE MEET-STYLE EMAIL CALLING & INVITES ==========

def generate_meeting_id():
    import uuid
    u = uuid.uuid4().hex[:8]
    return f"geb-meet-{u[:4]}-{u[4:]}"

def build_meeting_html_email(meeting):
    join_url = meeting.get('join_url', f"http://127.0.0.1:3000/#/meet/{meeting['id']}")
    subject = meeting.get('subject', 'GebTalk HD Video Meeting')
    host_name = meeting.get('host_name', 'GebTalk Staff Member')
    host_email = meeting.get('host_email', 'staff@gebtalk.com')
    call_type = (meeting.get('call_type') or 'video').capitalize()
    pin = meeting.get('security_pin', '123456')
    
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0A0E18; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #FFFFFF;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #0A0E18; padding: 30px 10px;">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="background: linear-gradient(145deg, #111827 0%, #0D131F 100%); border-radius: 24px; border: 1px solid #1E293B; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.6);">
          <tr>
            <td style="padding: 28px 36px; background: linear-gradient(90deg, #08615B 0%, #0F8278 50%, #0D9488 100%);">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td>
                    <span style="font-size: 20px; font-weight: 900; letter-spacing: 2px; color: #FFFFFF;">⚡ GEBTALK MEET</span>
                    <div style="font-size: 11px; font-weight: 700; letter-spacing: 1.5px; color: rgba(255,255,255,0.8); margin-top: 2px;">SECURE QUANTUM COMMUNICATIONS</div>
                  </td>
                  <td align="right">
                    <span style="background: rgba(255,255,255,0.2); color: #FFFFFF; padding: 4px 12px; border-radius: 20px; font-size: 11px; font-weight: 700; text-transform: uppercase;">
                      {call_type} Meeting
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding: 36px 36px 20px 36px;">
              <h1 style="font-size: 22px; font-weight: 800; margin: 0 0 12px 0; color: #FFFFFF; letter-spacing: -0.5px;">
                {subject}
              </h1>
              <div style="background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 18px; margin: 20px 0;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  <tr>
                    <td width="48" style="vertical-align: middle;">
                      <div style="width: 44px; height: 44px; background: #0D9488; border-radius: 50%; text-align: center; line-height: 44px; font-weight: 800; font-size: 18px; color: #FFFFFF;">
                        {host_name[0].upper() if host_name else 'S'}
                      </div>
                    </td>
                    <td style="padding-left: 14px; vertical-align: middle;">
                      <div style="font-size: 15px; font-weight: 700; color: #FFFFFF;">{host_name}</div>
                      <div style="font-size: 12px; color: #94A3B8; margin-top: 2px;">Staff Host &bull; {host_email}</div>
                    </td>
                  </tr>
                </table>
              </div>
              <p style="font-size: 14px; line-height: 1.6; color: #CBD5E1; margin: 20px 0;">
                You have been invited to an encrypted, ultra-high-definition {call_type.lower()} meeting on GebTalk. No software installation required—tap below to join directly from your browser.
              </p>
              <div style="text-align: center; margin: 32px 0;">
                <a href="{join_url}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #0D9488 0%, #14B8A6 100%); color: #000000; font-weight: 800; font-size: 16px; text-decoration: none; padding: 16px 36px; border-radius: 30px; box-shadow: 0 10px 25px rgba(20, 184, 166, 0.4); letter-spacing: 0.5px;">
                  🚀 Join {call_type} Meeting
                </a>
              </div>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background: #0B0F19; border-radius: 14px; border: 1px solid #1E293B; margin: 20px 0; font-size: 12px;">
                <tr>
                  <td style="padding: 14px 18px; border-bottom: 1px solid #1E293B; color: #94A3B8;">Meeting ID:</td>
                  <td align="right" style="padding: 14px 18px; border-bottom: 1px solid #1E293B; font-family: monospace; font-weight: 700; color: #2DD4BF;">{meeting['id']}</td>
                </tr>
                <tr>
                  <td style="padding: 14px 18px; color: #94A3B8;">Security Code / PIN:</td>
                  <td align="right" style="padding: 14px 18px; font-family: monospace; font-weight: 700; color: #2DD4BF;">{pin}</td>
                </tr>
              </table>
              <div style="font-size: 11px; color: #64748B; line-height: 1.5; margin-top: 20px; text-align: center;">
                Direct Meeting URL: <a href="{join_url}" style="color: #2DD4BF; word-break: break-all;">{join_url}</a>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding: 24px 36px; background-color: #070A11; text-align: center; border-top: 1px solid #1E293B; font-size: 11px; color: #475569;">
              Powered by <strong style="color: #94A3B8;">GebTalk Quantum WebRTC</strong> &bull; End-to-End Encrypted<br>
              &copy; 2026 EB Global Tech. All rights reserved.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

def dispatch_meeting_email(recipient_email, subject, html_content):
    import smtplib
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText
    
    smtp_server = os.environ.get('SMTP_SERVER')
    smtp_port = int(os.environ.get('SMTP_PORT', 587))
    smtp_user = os.environ.get('SMTP_USER')
    smtp_pass = os.environ.get('SMTP_PASSWORD') or ''
    sender = os.environ.get('SMTP_FROM', 'meetings@gebtalk.com')
    
    if not smtp_server or not smtp_user or not smtp_pass or 'your_' in smtp_user:
        print(f"[SIMULATED EMAIL MEETING INVITE] To: {recipient_email}, Subject: {subject}", flush=True)
        return True, "Email invite dispatched (Development Simulation)"
        
    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From'] = f"GebTalk Meetings <{sender}>"
        msg['To'] = recipient_email
        msg.attach(MIMEText(html_content, 'html'))
        
        with smtplib.SMTP(smtp_server, smtp_port, timeout=10) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.sendmail(sender, [recipient_email], msg.as_string())
            print(f"[EMAIL SUCCESS] Sent meeting invite to {recipient_email}", flush=True)
            return True, "Email sent successfully"
    except Exception as e:
        print(f"[EMAIL ERROR] Failed to send to {recipient_email}: {e}", flush=True)
        return False, str(e)

@app.route('/api/calls/email/start', methods=['POST'])
@require_auth
def start_email_call():
    data = request.json or {}
    recipient_email = data.get('recipient_email', '').strip()
    recipient_name = data.get('recipient_name', '').strip() or recipient_email.split('@')[0].capitalize()
    contact_id = data.get('contact_id')
    subject = data.get('subject', 'GebTalk HD Video Meeting').strip()
    call_type = data.get('call_type', 'video').lower()
    
    if not recipient_email or '@' not in recipient_email:
        return jsonify({'error': 'Valid recipient email is required'}), 400
        
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone) or {}
    host_id = profile.get('id') or user_phone
    host_name = profile.get('name', 'GebTalk Staff Specialist')
    host_email = profile.get('email', 'staff@gebtalk.com')
    host_avatar = profile.get('avatar', '')
    
    meeting_id = generate_meeting_id()
    security_pin = str(random.randint(100000, 999999))
    frontend_base = EmailService.get_config()['frontend_base_url']
    join_url = f"{frontend_base}/#/meet?id={meeting_id}"
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO email_call_invites (
            id, host_id, host_name, host_email, host_avatar,
            recipient_email, recipient_name, contact_id,
            call_type, subject, security_pin, status
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    ''', (
        meeting_id, host_id, host_name, host_email, host_avatar,
        recipient_email, recipient_name, contact_id,
        call_type, subject, security_pin, 'ringing'
    ))
    
    # Also log to call logs
    time_str = datetime.now().strftime('Today, %I:%M %p')
    cursor.execute('''
        INSERT INTO call_logs (contact_id, contact_name, contact_avatar, call_type, direction, time_str, duration)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    ''', (contact_id or meeting_id, f"{recipient_name} ({recipient_email})", '', call_type, 'outgoing', time_str, 'Ringing...'))
    
    conn.commit()
    conn.close()
    
    # Dispatch email asynchronously via universal EmailService
    threading.Thread(
        target=EmailService.send_meeting_invite_email,
        args=(recipient_email, meeting_id, host_name, host_email, subject, call_type),
        daemon=True
    ).start()
    
    return jsonify({
        'success': True,
        'meeting_id': meeting_id,
        'join_url': join_url,
        'security_pin': security_pin,
        'recipient_email': recipient_email,
        'recipient_name': recipient_name,
        'subject': subject,
        'call_type': call_type,
        'status': 'ringing'
    })

@app.route('/api/calls/email/meeting/<meeting_id>', methods=['GET'])
def get_email_meeting_info(meeting_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM email_call_invites WHERE id = %s', (meeting_id,))
    row = cursor.fetchone()
    conn.close()
    if not row:
        return jsonify({'error': 'Meeting room not found or expired'}), 404
    return jsonify(dict(row))

@app.route('/api/calls/email/meeting/<meeting_id>/join', methods=['POST'])
def join_email_meeting(meeting_id):
    data = request.json or {}
    guest_name = data.get('guest_name', 'Client Guest').strip()
    
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM email_call_invites WHERE id = %s', (meeting_id,))
    row = cursor.fetchone()
    if not row:
        conn.close()
        return jsonify({'error': 'Meeting not found'}), 404
        
    cursor.execute("UPDATE email_call_invites SET status = 'connected' WHERE id = %s", (meeting_id,))
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'meeting_id': meeting_id,
        'host_id': row['host_id'],
        'host_name': row['host_name'],
        'call_type': row['call_type'],
        'guest_name': guest_name,
        'status': 'connected'
    })

@app.route('/api/calls/email/meeting/<meeting_id>/end', methods=['POST'])
def end_email_meeting(meeting_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE email_call_invites SET status = 'completed' WHERE id = %s", (meeting_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Meeting ended'})

@app.route('/api/calls/email/history', methods=['GET'])
@require_auth
def get_email_calls_history():
    user_phone = get_authenticated_phone()
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM email_call_invites ORDER BY created_at DESC LIMIT 50')
    rows = [dict(r) for r in cursor.fetchall()]
    conn.close()
    return jsonify(rows)

# ========== EMAIL IDENTITY, OTP VERIFICATION & MISSED CALL ALERTS ==========

def build_email_otp_html(otp, user_name='GebTalk User'):
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GebTalk Verification Code</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0A0E18; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #FFFFFF;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #0A0E18; padding: 30px 10px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="background: linear-gradient(145deg, #111827 0%, #0D131F 100%); border-radius: 24px; border: 1px solid #1E293B; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.6);">
          <tr>
            <td style="padding: 24px 32px; background: linear-gradient(90deg, #08615B 0%, #0D9488 100%);">
              <span style="font-size: 20px; font-weight: 900; letter-spacing: 2px; color: #FFFFFF;">⚡ GEBTALK SECURE ID</span>
            </td>
          </tr>
          <tr>
            <td style="padding: 36px 32px;">
              <h1 style="font-size: 22px; font-weight: 800; margin: 0 0 10px 0; color: #FFFFFF;">Verify Your Email Address</h1>
              <p style="font-size: 14px; color: #94A3B8; line-height: 1.6; margin: 0 0 24px 0;">
                Hello {user_name}, use the verification code below to link this email to your GebTalk profile and enable email-based VoIP calling:
              </p>
              <div style="background: #0B0F19; border: 1px solid #1E293B; border-radius: 16px; padding: 24px; text-align: center; margin: 24px 0;">
                <div style="font-size: 11px; font-weight: 700; letter-spacing: 2px; color: #14B8A6; text-transform: uppercase; margin-bottom: 8px;">6-DIGIT VERIFICATION CODE</div>
                <div style="font-size: 38px; font-weight: 900; letter-spacing: 12px; color: #FFFFFF; font-family: monospace;">{otp}</div>
              </div>
              <p style="font-size: 12px; color: #64748B; line-height: 1.5; margin: 20px 0 0 0;">
                ⏱️ This code will expire in <strong>10 minutes</strong>. If you did not request this verification, you can safely ignore this email.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding: 20px 32px; background-color: #070A11; text-align: center; border-top: 1px solid #1E293B; font-size: 11px; color: #475569;">
              Powered by <strong>GebTalk Quantum Encryption</strong> &bull; &copy; 2026 EB Global Tech.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

def build_missed_call_html(caller_name, caller_avatar, call_type, timestamp, callback_url):
    c_type = (call_type or 'voice').upper()
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Missed VoIP Call Alert</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0A0E18; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #FFFFFF;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #0A0E18; padding: 30px 10px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="background: linear-gradient(145deg, #111827 0%, #0D131F 100%); border-radius: 24px; border: 1px solid #1E293B; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.6);">
          <tr>
            <td style="padding: 24px 32px; background: linear-gradient(90deg, #991B1B 0%, #DC2626 50%, #EF4444 100%);">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td><span style="font-size: 18px; font-weight: 900; letter-spacing: 1.5px; color: #FFFFFF;">📞 MISSED {c_type} CALL</span></td>
                  <td align="right"><span style="background: rgba(0,0,0,0.3); color: #FFFFFF; padding: 4px 10px; border-radius: 12px; font-size: 11px; font-weight: 700;">OFFLINE ALERT</span></td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px 32px 24px 32px;">
              <h1 style="font-size: 20px; font-weight: 800; margin: 0 0 16px 0; color: #FFFFFF;">You missed a call from {caller_name}</h1>
              <div style="background: #0B0F19; border: 1px solid #1E293B; border-radius: 16px; padding: 20px; margin: 16px 0;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  <tr>
                    <td width="48" style="vertical-align: middle;">
                      <div style="width: 44px; height: 44px; background: #DC2626; border-radius: 50%; text-align: center; line-height: 44px; font-weight: 800; font-size: 18px; color: #FFFFFF;">
                        {caller_name[0].upper() if caller_name else 'U'}
                      </div>
                    </td>
                    <td style="padding-left: 14px; vertical-align: middle;">
                      <div style="font-size: 15px; font-weight: 700; color: #FFFFFF;">{caller_name}</div>
                      <div style="font-size: 12px; color: #94A3B8; margin-top: 2px;">{c_type} Call &bull; {timestamp}</div>
                    </td>
                  </tr>
                </table>
              </div>
              <p style="font-size: 14px; color: #CBD5E1; line-height: 1.6; margin: 20px 0;">
                {caller_name} attempted to connect with you via GebTalk VoIP. Tap the callback button below to reconnect instantly in your browser.
              </p>
              <div style="text-align: center; margin: 28px 0;">
                <a href="{callback_url}" target="_blank" style="display: inline-block; background: linear-gradient(135deg, #0D9488 0%, #14B8A6 100%); color: #000000; font-weight: 800; font-size: 15px; text-decoration: none; padding: 14px 32px; border-radius: 25px; box-shadow: 0 8px 20px rgba(20, 184, 166, 0.3);">
                  🚀 Call Back Now on GebTalk
                </a>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding: 18px 32px; background-color: #070A11; text-align: center; border-top: 1px solid #1E293B; font-size: 11px; color: #475569;">
              Powered by <strong>GebTalk Quantum WebRTC</strong> &bull; &copy; 2026 EB Global Tech.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""

def dispatch_transactional_email(recipient_email, subject, html_content):
    import smtplib
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText
    
    smtp_server = os.environ.get('SMTP_SERVER')
    smtp_port = int(os.environ.get('SMTP_PORT', 587))
    smtp_user = os.environ.get('SMTP_USER')
    smtp_pass = os.environ.get('SMTP_PASSWORD') or ''
    sender = os.environ.get('SMTP_FROM', 'notifications@gebtalk.com')
    
    if not smtp_server or not smtp_user or not smtp_pass or 'your_' in smtp_user:
        print(f"[SIMULATED TRANSACTIONAL EMAIL] To: {recipient_email}, Subject: {subject}", flush=True)
        return True, "Dispatched (Development Simulation)"
        
    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From'] = f"GebTalk Notifications <{sender}>"
        msg['To'] = recipient_email
        msg.attach(MIMEText(html_content, 'html'))
        
        with smtplib.SMTP(smtp_server, smtp_port, timeout=10) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.sendmail(sender, [recipient_email], msg.as_string())
            print(f"[TRANSACTIONAL EMAIL SUCCESS] Sent to {recipient_email}", flush=True)
            return True, "Email sent successfully"
    except Exception as e:
        print(f"[TRANSACTIONAL EMAIL ERROR] Failed to send to {recipient_email}: {e}", flush=True)
        return False, str(e)

def resolve_email_to_target(email_str):
    if not email_str or '@' not in email_str:
        return None
    email_clean = email_str.strip().lower()
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 1. Search in user_profile
    cursor.execute('SELECT * FROM user_profile WHERE LOWER(email) = %s', (email_clean,))
    up_row = cursor.fetchone()
    if up_row:
        up = dict(up_row)
        user_id = up.get('id') or up.get('phone')
        
        # Check presence
        cursor.execute('SELECT is_online FROM user_presence WHERE user_id = %s', (user_id,))
        pres_row = cursor.fetchone()
        is_online = bool(pres_row['is_online']) if pres_row else True
        
        conn.close()
        return {
            'type': 'user_profile',
            'id': user_id,
            'user_id': user_id,
            'name': up.get('name', 'GebTalk User'),
            'avatar': up.get('avatar', ''),
            'phone': up.get('phone', ''),
            'email': up.get('email', email_clean),
            'role': up.get('role', ''),
            'is_online': is_online,
            'session_token': f"session_{user_id}"
        }
        
    # 2. Search in contacts
    cursor.execute('SELECT * FROM contacts WHERE LOWER(email) = %s', (email_clean,))
    c_row = cursor.fetchone()
    if c_row:
        c = dict(c_row)
        cid = c.get('id')
        is_online = 'active' in (c.get('status') or '').lower() or 'online' in (c.get('status') or '').lower()
        conn.close()
        return {
            'type': 'contact',
            'id': cid,
            'user_id': cid,
            'name': c.get('name', 'Contact'),
            'avatar': c.get('avatar', ''),
            'phone': c.get('phone', ''),
            'email': c.get('email', email_clean),
            'role': c.get('role', ''),
            'is_online': is_online,
            'session_token': f"session_{cid}"
        }
        
    conn.close()
    return None

@app.route('/api/profile/email/send-otp', methods=['POST'])
@require_auth
def send_profile_email_otp():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    
    if not email or '@' not in email or '.' not in email:
        return jsonify({'error': 'A valid email address is required'}), 400
        
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone) or {}
    user_name = profile.get('name', 'GebTalk User')
    
    # Check if email is already claimed by another user profile
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('SELECT id, phone FROM user_profile WHERE LOWER(email) = %s', (email,))
    existing = cursor.fetchone()
    if existing and existing['phone'] != user_phone and existing['id'] != user_phone:
        conn.close()
        return jsonify({'error': 'This email address is already linked to another GebTalk account'}), 409
        
    otp = str(random.randint(100000, 999999))
    from datetime import timedelta
    expires_at = datetime.now() + timedelta(minutes=10)
    
    cursor.execute('''
        INSERT INTO email_verifications (user_phone, email, otp, expires_at, is_verified)
        VALUES (%s, %s, %s, %s, FALSE)
    ''', (user_phone, email, otp, expires_at))
    conn.commit()
    conn.close()
    
    # Send verification email asynchronously
    html_content = build_email_otp_html(otp, user_name)
    threading.Thread(
        target=dispatch_transactional_email,
        args=(email, f"⚡ Your GebTalk Verification Code: {otp}", html_content),
        daemon=True
    ).start()
    
    return jsonify({
        'success': True,
        'message': f'Verification OTP sent to {email}',
        'email': email,
        'dev_otp': otp
    })

@app.route('/api/profile/email/verify-otp', methods=['POST'])
@require_auth
def verify_profile_email_otp():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    otp = data.get('otp', '').strip()
    
    if not email or not otp:
        return jsonify({'error': 'Email and 6-digit OTP are required'}), 400
        
    user_phone = get_authenticated_phone()
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT * FROM email_verifications
        WHERE user_phone = %s AND LOWER(email) = %s AND otp = %s AND is_verified = FALSE
        ORDER BY id DESC LIMIT 1
    ''', (user_phone, email, otp))
    v_row = cursor.fetchone()
    
    if not v_row:
        conn.close()
        return jsonify({'error': 'Invalid verification code or code has already been used'}), 400
        
    # Mark verified in email_verifications
    cursor.execute('UPDATE email_verifications SET is_verified = TRUE WHERE id = %s', (v_row['id'],))
    
    # Commit email update to user_profile (update ALL profile rows with same phone to prevent stale old-email login)
    cursor.execute('''
        UPDATE user_profile
        SET email = %s, verification_status = 'Verified'
        WHERE phone = %s OR id = %s
    ''', (email, user_phone, user_phone))
    # Also update any profile rows that still reference the old email
    cursor.execute('''
        UPDATE user_profile SET email = %s
        WHERE phone = %s AND LOWER(email) != %s
    ''', (email, user_phone, email))
    
    # Sync new email to users table so old email can no longer be used to log in
    cursor.execute('''
        UPDATE users SET email = %s
        WHERE id = %s OR LOWER(email) = (SELECT LOWER(email) FROM users WHERE id = %s OR phone = %s LIMIT 1)
    ''', (email, user_phone, user_phone, user_phone))
    
    # Update associated contact record if exists
    cursor.execute('UPDATE contacts SET email = %s WHERE phone = %s OR id = %s', (email, user_phone, user_phone))
    
    conn.commit()
    
    # Fetch updated profile
    cursor.execute('SELECT * FROM user_profile WHERE phone = %s OR id = %s', (user_phone, user_phone))
    profile_row = cursor.fetchone()
    updated_profile = dict(profile_row) if profile_row else {}
    for key in ['notifications_enabled', 'notification_sound', 'notification_vibration', 'security_2fa', 'read_receipts', 'last_seen_visible']:
        if key in updated_profile:
            updated_profile[key] = bool(updated_profile[key])
            
    conn.close()
    
    return jsonify({
        'success': True,
        'message': 'Email address successfully verified and linked!',
        'profile': updated_profile
    })

@app.route('/api/calls/lookup-target', methods=['POST'])
def lookup_call_target():
    data = request.json or {}
    target = data.get('target', '').strip()
    
    if not target:
        return jsonify({'error': 'Target identifier (email, phone, or contact ID) is required'}), 400
        
    # 1. Check if target is an email address
    if '@' in target:
        resolved = resolve_email_to_target(target)
        if resolved:
            return jsonify({
                'found': True,
                'type': 'email',
                'target': target,
                'resolved': resolved
            })
        return jsonify({
            'found': False,
            'type': 'email',
            'target': target,
            'message': 'No registered GebTalk user with this email address'
        })
        
    # 2. Check if target is a phone number or contact ID
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('SELECT * FROM user_profile WHERE phone = %s OR id = %s', (target, target))
    up = cursor.fetchone()
    if up:
        d = dict(up)
        uid = d.get('id') or d.get('phone')
        cursor.execute('SELECT is_online FROM user_presence WHERE user_id = %s', (uid,))
        pres = cursor.fetchone()
        conn.close()
        return jsonify({
            'found': True,
            'type': 'user',
            'target': target,
            'resolved': {
                'user_id': uid,
                'name': d.get('name'),
                'avatar': d.get('avatar'),
                'phone': d.get('phone'),
                'email': d.get('email'),
                'is_online': bool(pres['is_online']) if pres else True,
                'session_token': f"session_{uid}"
            }
        })
        
    cursor.execute('SELECT * FROM contacts WHERE id = %s OR phone = %s', (target, target))
    c = cursor.fetchone()
    conn.close()
    if c:
        cd = dict(c)
        return jsonify({
            'found': True,
            'type': 'contact',
            'target': target,
            'resolved': {
                'user_id': cd.get('id'),
                'name': cd.get('name'),
                'avatar': cd.get('avatar'),
                'phone': cd.get('phone'),
                'email': cd.get('email'),
                'is_online': True,
                'session_token': f"session_{cd.get('id')}"
            }
        })
        
    return jsonify({'found': False, 'target': target, 'message': 'Target not found'})

@app.route('/api/calls/notify-missed', methods=['POST'])
@require_auth
def notify_missed_call():
    data = request.json or {}
    callee_email = data.get('callee_email', '').strip().lower()
    call_type = data.get('call_type', 'voice').lower()
    callback_url = data.get('callback_url', 'http://127.0.0.1:3000/#/calls')
    
    if not callee_email or '@' not in callee_email:
        return jsonify({'error': 'Valid recipient email address is required'}), 400
        
    user_phone = get_authenticated_phone()
    profile = get_user_profile(user_phone) or {}
    caller_name = profile.get('name', 'GebTalk User')
    caller_avatar = profile.get('avatar', '')
    
    timestamp = datetime.now().strftime('%b %d, %Y at %I:%M %p')
    
    # Build HTML email
    html_content = build_missed_call_html(caller_name, caller_avatar, call_type, timestamp, callback_url)
    
    # Dispatch email asynchronously
    threading.Thread(
        target=dispatch_transactional_email,
        args=(callee_email, f"📞 Missed {call_type.upper()} Call from {caller_name}", html_content),
        daemon=True
    ).start()
    
    # Log missed call in call_logs table
    conn = get_db_connection()
    cursor = conn.cursor()
    time_str = datetime.now().strftime('Today, %I:%M %p')
    cursor.execute('''
        INSERT INTO call_logs (contact_id, contact_name, contact_avatar, call_type, direction, time_str, duration)
        VALUES (%s, %s, %s, %s, 'missed', %s, 'Missed')
    ''', (callee_email, f"{caller_name} (Missed Call)", caller_avatar, call_type, time_str))
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'message': f'Missed call notification dispatched to {callee_email}',
        'callee_email': callee_email,
        'timestamp': timestamp
    })

# ========== EMAIL-FIRST UNIFIED COMMUNICATIONS API ENDPOINTS ==========

@app.route('/api/users/search', methods=['GET'])
def search_users_directory():
    query = request.args.get('q', '').strip().lower()
    if not query:
        return jsonify({'users': []})

    caller = get_caller_profile()

    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Search in users table
    cursor.execute('''
        SELECT id, email, username, name, phone, avatar, role, status_text, about, presence, is_verified, assigned_staff_id 
        FROM users 
        WHERE LOWER(email) LIKE %s OR LOWER(username) LIKE %s OR LOWER(name) LIKE %s
        LIMIT 20
    ''', (f"%{query}%", f"%{query}%", f"%{query}%"))
    users = cursor.fetchall()
    
    # Also check contacts table for any additional contacts
    cursor.execute('''
        SELECT id, name, phone, email, username, role, avatar, status, presence, connection_status, assigned_staff_id, folder
        FROM contacts 
        WHERE is_group = FALSE AND (LOWER(email) LIKE %s OR LOWER(name) LIKE %s OR (username IS NOT NULL AND LOWER(username) LIKE %s))
        LIMIT 20
    ''', (f"%{query}%", f"%{query}%", f"%{query}%"))
    contacts = cursor.fetchall()

    results = []
    seen_emails = set()

    caller_aliases = get_all_user_aliases(caller) if caller else set()

    for u in users:
        em = u.get('email') or ''
        uid = str(u.get('id') or '').lower()
        role = (u.get('role') or '').lower()
        
        # Enforce RBAC filtering if caller is staff or customer
        if caller:
            if is_caller_staff(caller) and not (is_caller_ceo(caller) or is_caller_manager(caller)):
                # Staff can only search self or customers assigned to them
                assigned = str(u.get('assigned_staff_id') or '').lower()
                if uid not in caller_aliases and (not assigned or assigned not in caller_aliases):
                    continue
            elif is_caller_customer(caller):
                # Customer can only search self or their assigned staff
                assigned = str(caller.get('assigned_staff_id') or '').lower()
                callee_aliases = get_all_user_aliases(u)
                if uid not in caller_aliases and (not assigned or assigned not in callee_aliases):
                    continue

        if em and em.lower() not in seen_emails:
            seen_emails.add(em.lower())
            results.append({
                'id': u.get('id'),
                'email': em,
                'username': u.get('username') or ('@' + em.split('@')[0]),
                'name': u.get('name'),
                'avatar': u.get('avatar') or '',
                'role': u.get('role') or 'User',
                'status_text': u.get('status_text') or 'Available',
                'about': u.get('about') or 'Using GEBTALK',
                'presence': u.get('presence') or 'online',
                'is_verified': bool(u.get('is_verified')),
                'is_connected': True
            })

    for c in contacts:
        em = c.get('email') or ''
        cid = str(c.get('id') or '').lower()
        
        # Enforce RBAC filtering
        if caller:
            if is_caller_staff(caller) and not (is_caller_ceo(caller) or is_caller_manager(caller)):
                assigned = str(c.get('assigned_staff_id') or '').lower()
                if cid not in caller_aliases and (not assigned or assigned not in caller_aliases):
                    continue
            elif is_caller_customer(caller):
                assigned = str(caller.get('assigned_staff_id') or '').lower()
                c_aliases = get_all_user_aliases(c)
                if cid not in caller_aliases and (not assigned or assigned not in c_aliases):
                    continue

        if em and em.lower() not in seen_emails:
            seen_emails.add(em.lower())
            results.append({
                'id': c.get('id'),
                'email': em,
                'username': c.get('username') or ('@' + em.split('@')[0]),
                'name': c.get('name'),
                'avatar': c.get('avatar') or '',
                'role': c.get('role') or 'Contact',
                'status_text': c.get('status') or 'Available',
                'about': 'GEBTALK Contact',
                'presence': c.get('presence') or 'online',
                'is_verified': True,
                'is_connected': c.get('connection_status') != 'pending'
            })
            seen_emails.add(em.lower())
            results.append({
                'id': c.get('id'),
                'email': em,
                'username': c.get('username') or ('@' + em.split('@')[0]),
                'name': c.get('name'),
                'avatar': c.get('avatar') or '',
                'role': c.get('role') or 'Contact',
                'status_text': c.get('status') or 'Available',
                'about': 'GEBTALK Contact',
                'presence': c.get('presence') or 'online',
                'is_verified': True,
                'is_connected': c.get('connection_status') != 'pending'
            })

    conn.close()
    return jsonify({'users': results})

@app.route('/api/contacts/request', methods=['POST'])
def send_contact_request():
    data = request.json or {}
    target_email = data.get('target_email', '').strip().lower()
    target_id = data.get('target_id', '').strip()
    message = data.get('message', 'Would love to connect with you on GEBTALK.').strip()

    if not target_email and not target_id:
        return jsonify({'error': 'Target email or User ID is required'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    # Find sender profile (defaulting to current user profile)
    cursor.execute("SELECT id, name, email, avatar, username FROM user_profile LIMIT 1")
    sender = cursor.fetchone()
    sender_id = sender.get('id') if sender else 'USR_883392'
    sender_name = sender.get('name') if sender else 'Marcus Sterling'
    sender_email = sender.get('email') if sender else 'marcus.sterling@ebglobal.com'
    sender_avatar = sender.get('avatar') if sender else ''
    sender_username = sender.get('username') if sender else 'marcus_sterling'

    # Determine receiver ID
    receiver_id = target_id
    if not receiver_id and target_email:
        cursor.execute("SELECT id FROM users WHERE LOWER(email) = %s LIMIT 1", (target_email,))
        ru = cursor.fetchone()
        if ru:
            receiver_id = ru.get('id')
        else:
            receiver_id = f"ext_{abs(hash(target_email)) % 100000}"

    try:
        cursor.execute('''
            INSERT INTO contact_requests (sender_id, receiver_id, sender_name, sender_email, sender_avatar, sender_username, status, message)
            VALUES (%s, %s, %s, %s, %s, %s, 'pending', %s)
            ON CONFLICT (sender_id, receiver_id) DO UPDATE SET status = 'pending', message = EXCLUDED.message
        ''', (sender_id, receiver_id, sender_name, sender_email, sender_avatar, sender_username, message))
        conn.commit()
    except Exception as e:
        print(f"Error inserting contact request: {e}")

    conn.close()

    # Asynchronously dispatch notification email
    if target_email:
        threading.Thread(
            target=EmailService.send_contact_request_email,
            args=(target_email, sender_name, sender_email, message),
            daemon=True
        ).start()

    return jsonify({
        'success': True,
        'message': f'Connection request sent to {target_email or target_id}',
        'sender_id': sender_id,
        'receiver_id': receiver_id
    })

@app.route('/api/contacts/requests', methods=['GET'])
def get_contact_requests():
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute('''
        SELECT id, sender_id, receiver_id, sender_name, sender_email, sender_avatar, sender_username, status, message, created_at
        FROM contact_requests
        WHERE status = 'pending'
        ORDER BY created_at DESC
    ''')
    requests_rows = cursor.fetchall()
    conn.close()

    incoming = []
    outgoing = []

    for r in requests_rows:
        req_item = {
            'id': r.get('id'),
            'sender_id': r.get('sender_id'),
            'receiver_id': r.get('receiver_id'),
            'sender_name': r.get('sender_name') or 'User',
            'sender_email': r.get('sender_email') or '',
            'sender_avatar': r.get('sender_avatar') or '',
            'sender_username': r.get('sender_username') or '',
            'status': r.get('status'),
            'message': r.get('message') or '',
            'created_at': str(r.get('created_at') or '')
        }
        # For demonstration / local active user
        if r.get('receiver_id') in ['USR_883392', 'marcus', 'current_user']:
            incoming.append(req_item)
        else:
            incoming.append(req_item) # Allow user to test incoming request directly

    return jsonify({
        'incoming': incoming,
        'outgoing': outgoing,
        'total_pending': len(incoming)
    })

@app.route('/api/contacts/respond', methods=['POST'])
def respond_contact_request():
    data = request.json or {}
    req_id = data.get('request_id')
    action = data.get('action', 'accept').lower() # 'accept' or 'decline'

    if not req_id:
        return jsonify({'error': 'request_id is required'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM contact_requests WHERE id = %s", (req_id,))
    req_row = cursor.fetchone()
    if not req_row:
        conn.close()
        return jsonify({'error': 'Request not found'}), 404

    new_status = 'accepted' if action == 'accept' else 'declined'
    cursor.execute("UPDATE contact_requests SET status = %s WHERE id = %s", (new_status, req_id))

    if action == 'accept':
        sender_id = req_row.get('sender_id') or 'USR_105'
        sender_name = req_row.get('sender_name') or 'Alex Turner'
        sender_email = req_row.get('sender_email') or 'alex.turner@quantum.dev'
        sender_avatar = req_row.get('sender_avatar') or ''

        # Insert or update contact in contacts table
        contact_id = sender_id.lower().replace('usr_', 'user_')
        cursor.execute('''
            INSERT INTO contacts (id, name, email, avatar, role, status, folder, connection_status, is_group)
            VALUES (%s, %s, %s, %s, 'Connected Contact', 'Active Now', 'all', 'connected', FALSE)
            ON CONFLICT (id) DO UPDATE SET connection_status = 'connected', status = 'Active Now'
        ''', (contact_id, sender_name, sender_email, sender_avatar))

    conn.commit()
    conn.close()

    return jsonify({
        'success': True,
        'status': new_status,
        'message': f'Connection request {new_status}'
    })

# ========== INTEGRATED EMAIL CLIENT ENDPOINTS ==========

@app.route('/api/emails', methods=['GET'])
def get_emails():
    folder = request.args.get('folder', 'inbox').lower()
    search = request.args.get('search', '').strip().lower()

    conn = get_db_connection()
    cursor = conn.cursor()

    if folder == 'starred':
        query_sql = "SELECT * FROM email_messages WHERE is_starred = TRUE"
        params = []
    else:
        query_sql = "SELECT * FROM email_messages WHERE folder = %s"
        params = [folder]

    if search:
        query_sql += " AND (LOWER(subject) LIKE %s OR LOWER(from_address) LIKE %s OR LOWER(from_name) LIKE %s OR LOWER(body_text) LIKE %s)"
        params.extend([f"%{search}%", f"%{search}%", f"%{search}%", f"%{search}%"])

    query_sql += " ORDER BY received_at DESC"

    cursor.execute(query_sql, params)
    rows = cursor.fetchall()

    # Get folder counts and unread count
    cursor.execute("SELECT folder, COUNT(*) as cnt FROM email_messages GROUP BY folder")
    folder_counts = {r.get('folder'): r.get('cnt') for r in cursor.fetchall()}

    cursor.execute("SELECT COUNT(*) as unread FROM email_messages WHERE folder = 'inbox' AND is_read = FALSE")
    unread_row = cursor.fetchone()
    unread_count = unread_row.get('unread') if unread_row else 0

    cursor.execute("SELECT COUNT(*) as starred FROM email_messages WHERE is_starred = TRUE")
    starred_row = cursor.fetchone()
    folder_counts['starred'] = starred_row.get('starred') if starred_row else 0

    emails = []
    for r in rows:
        attachments = []
        att_json = r.get('attachments_json') or '[]'
        try:
            attachments = json.loads(att_json)
        except Exception:
            attachments = []

        emails.append({
            'id': r.get('id'),
            'folder': r.get('folder'),
            'from_address': r.get('from_address'),
            'from_name': r.get('from_name') or r.get('from_address'),
            'to_addresses': r.get('to_addresses'),
            'subject': r.get('subject') or '(No Subject)',
            'body_text': r.get('body_text') or '',
            'body_html': r.get('body_html') or '',
            'has_attachments': bool(r.get('has_attachments')),
            'attachments': attachments,
            'is_read': bool(r.get('is_read')),
            'is_starred': bool(r.get('is_starred')),
            'linked_contact_id': r.get('linked_contact_id'),
            'received_at': str(r.get('received_at') or '')
        })

    conn.close()
    return jsonify({
        'emails': emails,
        'unread_count': unread_count,
        'counts': {
            'inbox': folder_counts.get('inbox', 0),
            'sent': folder_counts.get('sent', 0),
            'drafts': folder_counts.get('drafts', 0),
            'starred': folder_counts.get('starred', 0),
            'trash': folder_counts.get('trash', 0),
        }
    })

@app.route('/api/emails/<email_id>', methods=['GET'])
def get_email_detail(email_id):
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM email_messages WHERE id = %s", (email_id,))
    r = cursor.fetchone()
    if not r:
        conn.close()
        return jsonify({'error': 'Email not found'}), 404

    # Mark as read
    cursor.execute("UPDATE email_messages SET is_read = TRUE WHERE id = %s", (email_id,))
    conn.commit()

    attachments = []
    try:
        attachments = json.loads(r.get('attachments_json') or '[]')
    except Exception:
        pass

    # Check if sender has a GEBTALK account for 1-tap chat bridge
    sender_email = (r.get('from_address') or '').strip()
    cursor.execute("SELECT id, name, avatar, phone, username FROM contacts WHERE LOWER(email) = %s LIMIT 1", (sender_email.lower(),))
    linked_contact = cursor.fetchone()

    conn.close()

    return jsonify({
        'id': r.get('id'),
        'folder': r.get('folder'),
        'from_address': r.get('from_address'),
        'from_name': r.get('from_name') or r.get('from_address'),
        'to_addresses': r.get('to_addresses'),
        'subject': r.get('subject'),
        'body_text': r.get('body_text'),
        'body_html': r.get('body_html'),
        'has_attachments': bool(r.get('has_attachments')),
        'attachments': attachments,
        'is_read': True,
        'is_starred': bool(r.get('is_starred')),
        'linked_contact': dict(linked_contact) if linked_contact else None,
        'can_chat_in_app': linked_contact is not None,
        'received_at': str(r.get('received_at') or '')
    })

@app.route('/api/emails/send', methods=['POST'])
def send_email_message():
    data = request.json or {}
    to_email = data.get('to_email', '').strip().lower()
    subject = data.get('subject', '').strip()
    body_text = data.get('body_text', '').strip()
    body_html = data.get('body_html', '') or f"<p>{body_text.replace(chr(10), '<br>')}</p>"
    attachments = data.get('attachments', [])

    if not to_email or '@' not in to_email:
        return jsonify({'error': 'Valid recipient email is required'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT name, email FROM user_profile LIMIT 1")
    u = cursor.fetchone()
    sender_name = u.get('name') if u else 'Marcus Sterling'
    sender_email = u.get('email') if u else 'marcus.sterling@ebglobal.com'

    email_id = f"em_{int(time.time())}_{random.randint(100, 999)}"
    has_att = len(attachments) > 0
    att_json = json.dumps(attachments)

    cursor.execute('''
        INSERT INTO email_messages (id, user_id, folder, from_address, from_name, to_addresses, subject, body_text, body_html, has_attachments, attachments_json, is_read, is_starred)
        VALUES (%s, 'USR_883392', 'sent', %s, %s, %s, %s, %s, %s, %s, %s, TRUE, FALSE)
    ''', (email_id, sender_email, sender_name, json.dumps([to_email]), subject, body_text, body_html, has_att, att_json))
    conn.commit()
    conn.close()

    # Dispatch via EmailService
    threading.Thread(
        target=EmailService.send_email,
        args=(to_email, subject, body_html, body_text),
        daemon=True
    ).start()

    return jsonify({
        'success': True,
        'email_id': email_id,
        'message': f'Email dispatched successfully to {to_email}'
    })

@app.route('/api/emails/<email_id>/star', methods=['POST'])
def toggle_email_star(email_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE email_messages SET is_starred = NOT is_starred WHERE id = %s", (email_id,))
    conn.commit()
    cursor.execute("SELECT is_starred FROM email_messages WHERE id = %s", (email_id,))
    row = cursor.fetchone()
    conn.close()
    return jsonify({'success': True, 'is_starred': bool(row.get('is_starred')) if row else False})

@app.route('/api/emails/<email_id>/read', methods=['POST'])
def toggle_email_read(email_id):
    data = request.json or {}
    is_read = data.get('is_read', True)
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE email_messages SET is_read = %s WHERE id = %s", (bool(is_read), email_id))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'is_read': bool(is_read)})

@app.route('/api/emails/<email_id>', methods=['DELETE'])
def delete_email(email_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT folder FROM email_messages WHERE id = %s", (email_id,))
    row = cursor.fetchone()
    if row and row.get('folder') != 'trash':
        cursor.execute("UPDATE email_messages SET folder = 'trash' WHERE id = %s", (email_id,))
    else:
        cursor.execute("DELETE FROM email_messages WHERE id = %s", (email_id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': 'Email deleted / moved to trash'})

# ========== BIDIRECTIONAL EMAIL ⇄ CHAT CONVERSION BRIDGE ==========

@app.route('/api/emails/convert-to-chat', methods=['POST'])
def convert_email_to_chat():
    data = request.json or {}
    email_id = data.get('email_id')
    if not email_id:
        return jsonify({'error': 'email_id is required'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM email_messages WHERE id = %s", (email_id,))
    email_row = cursor.fetchone()
    if not email_row:
        conn.close()
        return jsonify({'error': 'Email not found'}), 404

    sender_email = (email_row.get('from_address') or '').strip().lower()
    sender_name = email_row.get('from_name', '') or sender_email
    subject = email_row.get('subject', 'Email Conversation')
    body_snippet = (email_row.get('body_text') or '')[:180]

    # Resolve or create contact
    cursor.execute("SELECT * FROM contacts WHERE LOWER(email) = %s LIMIT 1", (sender_email,))
    contact = cursor.fetchone()
    if not contact:
        contact_id = f"c_{abs(hash(sender_email)) % 100000}"
        cursor.execute('''
            INSERT INTO contacts (id, name, email, avatar, role, status, folder, connection_status)
            VALUES (%s, %s, %s, '', 'Email Contact', 'Online', 'all', 'connected')
        ''', (contact_id, sender_name, sender_email))
        cursor.execute("SELECT * FROM contacts WHERE id = %s", (contact_id,))
        contact = cursor.fetchone()
    else:
        contact_id = contact.get('id')

    # Insert bridge message referencing email
    bridge_text = f"✉️ [Ref: {subject}]\n\"{body_snippet}...\""
    time_str = datetime.now().strftime('%I:%M %p')

    cursor.execute('''
        INSERT INTO messages (contact_id, text, is_user, time, status, email_ref_id)
        VALUES (%s, %s, FALSE, %s, 'read', %s)
    ''', (contact_id, bridge_text, time_str, email_id))
    conn.commit()

    cursor.execute("SELECT * FROM messages WHERE contact_id = %s ORDER BY id DESC LIMIT 1", (contact_id,))
    latest_msg = cursor.fetchone()

    conn.close()

    return jsonify({
        'success': True,
        'contact': dict(contact) if contact else {},
        'message': dict(latest_msg) if latest_msg else None,
        'prompt': f'Started in-app chat bridging email: "{subject}"'
    })

@app.route('/api/chat/forward-to-email', methods=['POST'])
def forward_chat_to_email():
    data = request.json or {}
    to_email = data.get('to_email', '').strip().lower()
    contact_id = data.get('contact_id', '').strip()
    custom_subject = data.get('subject', 'GEBTALK Chat Transcript').strip()
    message_ids = data.get('message_ids', [])

    if not to_email or '@' not in to_email:
        return jsonify({'error': 'Valid destination email is required'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    # Get sender profile
    cursor.execute("SELECT name, email FROM user_profile LIMIT 1")
    u = cursor.fetchone()
    sender_name = u.get('name') if u else 'Marcus Sterling'
    sender_email = u.get('email') if u else 'marcus.sterling@ebglobal.com'

    # Get chat history
    if message_ids:
        placeholders = ', '.join(['%s'] * len(message_ids))
        cursor.execute(f"SELECT * FROM messages WHERE id IN ({placeholders}) ORDER BY id ASC", message_ids)
    elif contact_id:
        cursor.execute("SELECT * FROM messages WHERE contact_id = %s ORDER BY id ASC LIMIT 25", (contact_id,))
    else:
        conn.close()
        return jsonify({'error': 'contact_id or message_ids is required'}), 400

    msgs = cursor.fetchall()
    if not msgs:
        conn.close()
        return jsonify({'error': 'No messages found to forward'}), 404

    # Build formatted transcript
    lines = []
    for m in msgs:
        who = "You" if m.get('is_user') else (contact_id.title())
        t = m.get('time') or ''
        txt = m.get('text') or (f"[File: {m.get('file_name')}]" if m.get('is_file') else "[Audio Voice Note]")
        lines.append(f"[{t}] {who}: {txt}")

    chat_transcript = "\n".join(lines)

    # Save outgoing email in sent folder
    email_id = f"em_fwd_{int(time.time())}"
    cursor.execute('''
        INSERT INTO email_messages (id, user_id, folder, from_address, from_name, to_addresses, subject, body_text, body_html, has_attachments, is_read, is_starred)
        VALUES (%s, 'USR_883392', 'sent', %s, %s, %s, %s, %s, %s, FALSE, TRUE, FALSE)
    ''', (email_id, sender_email, sender_name, json.dumps([to_email]), custom_subject, chat_transcript, f"<pre>{chat_transcript}</pre>"))
    conn.commit()
    conn.close()

    # Dispatch email
    threading.Thread(
        target=EmailService.send_chat_forward_email,
        args=(to_email, sender_name, custom_subject, chat_transcript, sender_email),
        daemon=True
    ).start()

    return jsonify({
        'success': True,
        'message': f'Chat transcript ({len(msgs)} messages) successfully forwarded to {to_email}',
        'email_id': email_id
    })

# ========== END ADVANCED ENDPOINTS ==========

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)


