from database import get_db_connection

def wipe_contacts():
    conn = get_db_connection()
    cursor = conn.cursor()

    # 1. Wipe contacts
    cursor.execute('DELETE FROM contacts')

    # 2. Wipe messages and chats
    cursor.execute('DELETE FROM messages')
    cursor.execute('DELETE FROM chat_tags')

    # 3. Wipe call logs
    cursor.execute('DELETE FROM call_logs')

    # 4. Wipe groups and members
    cursor.execute('DELETE FROM group_members')
    cursor.execute('DELETE FROM groups')

    # 5. Wipe channel posts & statuses
    cursor.execute('DELETE FROM channel_posts')
    cursor.execute('DELETE FROM statuses')

    # 6. Wipe contact requests & email messages
    cursor.execute('DELETE FROM contact_requests')
    cursor.execute('DELETE FROM email_messages')

    # 7. Clean users directory keeping only CEO Marcus Sterling
    cursor.execute("DELETE FROM users WHERE LOWER(email) != 'marcus.sterling@ebglobal.com' AND id != 'USR_883392'")

    conn.commit()

    cursor.execute('SELECT COUNT(*) FROM contacts')
    c_count = cursor.fetchone()['count']
    print(f'Remaining contacts count: {c_count}')

    cursor.execute('SELECT COUNT(*) FROM messages')
    m_count = cursor.fetchone()['count']
    print(f'Remaining messages count: {m_count}')

    cursor.execute('SELECT id, name, role, email FROM users')
    users = cursor.fetchall()
    print(f'Remaining users in directory: {users}')

    conn.close()

if __name__ == '__main__':
    wipe_contacts()
