import os
import json
import smtplib
import urllib.request
import urllib.error
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

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

class EmailService:
    @staticmethod
    def get_config():
        return {
            'resend_api_key': os.environ.get('RESEND_API_KEY', '').strip(),
            'smtp_host': os.environ.get('SMTP_HOST', '').strip(),
            'smtp_port': int(os.environ.get('SMTP_PORT', '587')),
            'smtp_user': os.environ.get('SMTP_USER', '').strip(),
            'smtp_pass': os.environ.get('SMTP_PASS', '').strip(),
            'from_email': os.environ.get('EMAIL_FROM', 'GEBTALK <noreply@gebtalk.com>').strip(),
            'frontend_base_url': os.environ.get('FRONTEND_BASE_URL', 'http://localhost:8080').strip(),
        }

    @classmethod
    def send_email(cls, to_email: str, subject: str, html_content: str, text_content: str | None = None) -> tuple[bool, str]:
        """
        Universal email sender:
        1. Tries Resend API if RESEND_API_KEY is configured.
        2. Tries SMTP (Gmail, AWS SES, Custom SMTP) if SMTP_HOST is configured.
        3. Falls back to simulated local debug logging for effortless development.
        """
        config = cls.get_config()
        if not text_content:
            text_content = subject

        # 1. Resend API
        if config['resend_api_key'] and not config['resend_api_key'].startswith('your_'):
            try:
                payload = {
                    'from': config['from_email'],
                    'to': [to_email],
                    'subject': subject,
                    'html': html_content,
                    'text': text_content
                }
                data = json.dumps(payload).encode('utf-8')
                req = urllib.request.Request(
                    'https://api.resend.com/emails',
                    data=data,
                    headers={
                        'Authorization': f"Bearer {config['resend_api_key']}",
                        'Content-Type': 'application/json',
                        'User-Agent': 'GEBTALK-EmailService/1.0'
                    },
                    method='POST'
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    resp_body = resp.read().decode('utf-8')
                    print(f"[EmailService Resend Success] Delivered to {to_email}: {resp_body}", flush=True)
                    return True, "Email delivered via Resend API"
            except Exception as e:
                print(f"[EmailService Resend Error] {e}", flush=True)

        # 2. SMTP Delivery (Gmail / Custom SMTP)
        if config['smtp_host'] and config['smtp_user'] and not config['smtp_user'].startswith('your_'):
            try:
                msg = MIMEMultipart('alternative')
                msg['Subject'] = subject
                msg['From'] = config['from_email']
                msg['To'] = to_email

                part1 = MIMEText(text_content, 'plain', 'utf-8')
                part2 = MIMEText(html_content, 'html', 'utf-8')
                msg.attach(part1)
                msg.attach(part2)

                if config['smtp_port'] == 465:
                    server = smtplib.SMTP_SSL(config['smtp_host'], config['smtp_port'], timeout=10)
                else:
                    server = smtplib.SMTP(config['smtp_host'], config['smtp_port'], timeout=10)
                    server.starttls()

                server.login(config['smtp_user'], config['smtp_pass'])
                server.sendmail(config['from_email'], [to_email], msg.as_string())
                server.quit()
                print(f"[EmailService SMTP Success] Delivered to {to_email} via {config['smtp_host']}", flush=True)
                return True, f"Email delivered via SMTP ({config['smtp_host']})"
            except Exception as e:
                print(f"[EmailService SMTP Error] {e}", flush=True)

        # 3. Fallback simulated delivery
        print("\n" + "="*70, flush=True)
        print(f"📧 [SIMULATED EMAIL DISPATCH]", flush=True)
        print(f"To: {to_email}", flush=True)
        print(f"Subject: {subject}", flush=True)
        print(f"Body Preview:\n{text_content[:200]}...", flush=True)
        print("="*70 + "\n", flush=True)
        return True, "Email dispatched (Simulated / Debug Mode)"

    # --- Pre-styled HTML Email Templates ---

    @classmethod
    def send_otp_email(cls, to_email: str, otp_code: str, user_name: str = "User") -> tuple[bool, str]:
        subject = f"{otp_code} is your GEBTALK verification code"
        text_content = f"Hello {user_name},\n\nYour GEBTALK verification code is: {otp_code}\nThis code is valid for 10 minutes.\n\nIf you did not request this, you can safely ignore this email."

        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0F172A; color: #F8FAFC; margin: 0; padding: 20px; }}
            .container {{ max-width: 520px; margin: 0 auto; background: #1E293B; border-radius: 16px; border: 1px solid #334155; overflow: hidden; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }}
            .header {{ background: linear-gradient(135deg, #2563EB, #1D4ED8); padding: 28px; text-align: center; }}
            .logo {{ font-size: 24px; font-weight: 800; letter-spacing: 2px; color: #FFFFFF; text-transform: uppercase; margin: 0; }}
            .subtitle {{ color: #BFDBFE; font-size: 13px; margin-top: 4px; }}
            .content {{ padding: 32px 28px; }}
            .greeting {{ font-size: 18px; font-weight: 600; color: #F1F5F9; margin-bottom: 12px; }}
            .desc {{ font-size: 14px; color: #94A3B8; line-height: 1.6; margin-bottom: 24px; }}
            .otp-box {{ background: #0F172A; border: 2px dashed #3B82F6; border-radius: 12px; padding: 20px; text-align: center; margin-bottom: 24px; }}
            .otp-code {{ font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: 900; letter-spacing: 8px; color: #60A5FA; }}
            .note {{ font-size: 12px; color: #64748B; text-align: center; margin-bottom: 8px; }}
            .footer {{ border-top: 1px solid #334155; padding: 18px; text-align: center; font-size: 11px; color: #64748B; background: #111827; }}
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1 class="logo">⚡ GEBTALK</h1>
              <div class="subtitle">Secure Enterprise Communications</div>
            </div>
            <div class="content">
              <div class="greeting">Hello {user_name},</div>
              <div class="desc">Here is your one-time verification code to sign in to your GEBTALK account.</div>
              <div class="otp-box">
                <div class="otp-code">{otp_code}</div>
              </div>
              <div class="note">This code expires in 10 minutes. Do not share it with anyone.</div>
            </div>
            <div class="footer">
              &copy; {2026} GEBTALK Global Communications. All rights reserved.
            </div>
          </div>
        </body>
        </html>
        """
        return cls.send_email(to_email, subject, html_content, text_content)

    @classmethod
    def send_meeting_invite_email(cls, to_email: str, meeting_id: str, host_name: str, host_email: str, subject_title: str = "Video Meeting", call_type: str = "video") -> tuple[bool, str]:
        config = cls.get_config()
        frontend_url = config['frontend_base_url']
        meeting_url = f"{frontend_url}/#/meet?id={meeting_id}"

        subject = f"📹 {host_name} is inviting you to a GEBTALK {call_type.title()} Call: {subject_title}"
        text_content = f"Hello,\n\n{host_name} ({host_email}) has invited you to join a secure {call_type} meeting on GEBTALK.\n\nSubject: {subject_title}\nMeeting ID: {meeting_id}\nJoin URL: {meeting_url}\n\nYou can click the link to join directly in any web browser."

        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0F172A; color: #F8FAFC; margin: 0; padding: 20px; }}
            .container {{ max-width: 540px; margin: 0 auto; background: #1E293B; border-radius: 16px; border: 1px solid #334155; overflow: hidden; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }}
            .header {{ background: linear-gradient(135deg, #059669, #10B981); padding: 28px; text-align: center; }}
            .logo {{ font-size: 22px; font-weight: 800; letter-spacing: 1px; color: #FFFFFF; margin: 0; }}
            .content {{ padding: 32px 28px; }}
            .host-pill {{ display: inline-block; background: #334155; padding: 6px 14px; border-radius: 20px; font-size: 13px; color: #93C5FD; margin-bottom: 16px; }}
            .title {{ font-size: 20px; font-weight: 700; color: #F8FAFC; margin-bottom: 8px; }}
            .details {{ background: #0F172A; border-radius: 12px; padding: 16px 20px; margin: 20px 0; border: 1px solid #1E293B; }}
            .detail-row {{ font-size: 13px; color: #94A3B8; margin: 6px 0; }}
            .detail-row strong {{ color: #E2E8F0; }}
            .btn {{ display: block; width: 100%; box-sizing: border-box; background: #10B981; color: #FFFFFF; text-decoration: none; text-align: center; padding: 16px; border-radius: 12px; font-size: 16px; font-weight: 700; letter-spacing: 0.5px; margin: 24px 0 12px 0; transition: background 0.2s; }}
            .footer {{ border-top: 1px solid #334155; padding: 18px; text-align: center; font-size: 11px; color: #64748B; background: #111827; }}
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1 class="logo">⚡ GEBTALK MEET</h1>
            </div>
            <div class="content">
              <div class="host-pill">Hosted by <strong>{host_name}</strong></div>
              <div class="title">{subject_title}</div>
              <div class="details">
                <div class="detail-row"><strong>Host Email:</strong> {host_email}</div>
                <div class="detail-row"><strong>Call Format:</strong> HD {call_type.title()} & Audio</div>
                <div class="detail-row"><strong>Meeting ID:</strong> <span style="font-family: monospace; color: #60A5FA;">{meeting_id}</span></div>
              </div>
              <a href="{meeting_url}" class="btn" style="color: #ffffff;">🚀 Click Here to Join Meeting</a>
              <div style="font-size: 12px; color: #64748B; text-align: center;">No download required • Works in all browsers</div>
            </div>
            <div class="footer">
              &copy; {2026} GEBTALK Global Communications.
            </div>
          </div>
        </body>
        </html>
        """
        return cls.send_email(to_email, subject, html_content, text_content)

    @classmethod
    def send_missed_call_email(cls, to_email: str, caller_name: str, caller_email_or_phone: str, call_type: str = "video") -> tuple[bool, str]:
        subject = f"🔔 Missed {call_type} call from {caller_name} on GEBTALK"
        text_content = f"Hello,\n\nYou missed a {call_type} call from {caller_name} ({caller_email_or_phone}) on GEBTALK.\n\nOpen your GEBTALK app to view call history and call back."
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0F172A; color: #F8FAFC; margin: 0; padding: 20px; }}
            .container {{ max-width: 500px; margin: 0 auto; background: #1E293B; border-radius: 16px; border: 1px solid #334155; overflow: hidden; }}
            .header {{ background: #DC2626; padding: 20px; text-align: center; color: white; font-weight: bold; font-size: 18px; }}
            .content {{ padding: 28px; }}
            .footer {{ border-top: 1px solid #334155; padding: 14px; text-align: center; font-size: 11px; color: #64748B; background: #111827; }}
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">🔔 Missed {call_type.title()} Call</div>
            <div class="content">
              <p style="font-size: 15px; color: #E2E8F0;">You missed an incoming {call_type} call from <strong>{caller_name}</strong> ({caller_email_or_phone}).</p>
              <p style="font-size: 13px; color: #94A3B8;">Please open your GEBTALK application to return the call or send a message.</p>
            </div>
            <div class="footer">&copy; {2026} GEBTALK Communications</div>
          </div>
        </body>
        </html>
        """
        return cls.send_email(to_email, subject, html_content, text_content)

    @classmethod
    def send_chat_notification_email(cls, to_email: str, sender_name: str, message_snippet: str) -> tuple[bool, str]:
        subject = f"💬 New message from {sender_name} on GEBTALK"
        text_content = f"Hello,\n\n{sender_name} sent you a message on GEBTALK:\n\n\"{message_snippet}\"\n\nSign in to GEBTALK to reply."
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0F172A; color: #F8FAFC; margin: 0; padding: 20px; }}
            .container {{ max-width: 500px; margin: 0 auto; background: #1E293B; border-radius: 16px; border: 1px solid #334155; overflow: hidden; }}
            .header {{ background: #2563EB; padding: 20px; text-align: center; color: white; font-weight: bold; font-size: 18px; }}
            .content {{ padding: 28px; }}
            .bubble {{ background: #0F172A; border-left: 4px solid #3B82F6; padding: 14px 18px; border-radius: 8px; font-size: 14px; color: #E2E8F0; margin: 16px 0; }}
            .footer {{ border-top: 1px solid #334155; padding: 14px; text-align: center; font-size: 11px; color: #64748B; background: #111827; }}
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">💬 New Chat Message</div>
            <div class="content">
              <p style="font-size: 15px; color: #E2E8F0;"><strong>{sender_name}</strong> sent you a message:</p>
              <div class="bubble">"{message_snippet}"</div>
              <p style="font-size: 13px; color: #94A3B8;">Open GEBTALK to read and reply in real time.</p>
            </div>
            <div class="footer">&copy; {2026} GEBTALK Communications</div>
          </div>
        </body>
        </html>
        """
        return cls.send_email(to_email, subject, html_content, text_content)

    @classmethod
    def send_chat_forward_email(cls, to_email: str, sender_name: str, subject: str, chat_text: str, sender_email: str | None = None) -> tuple[bool, str]:
        email_subject = f"📋 [GEBTALK Chat] {subject}"
        text_content = f"Forwarded chat conversation from {sender_name} ({sender_email or 'GEBTALK User'}):\n\n{chat_text}\n\nSent via GEBTALK Unified Communications."
        
        formatted_lines = "".join([f"<div style='background:#0F172A; padding:10px 14px; border-radius:8px; margin:6px 0; font-size:14px; color:#E2E8F0; border-left: 3px solid #3B82F6;'>{line}</div>" for line in chat_text.split('\n') if line.strip()])
        
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0F172A; color: #F8FAFC; margin: 0; padding: 20px; }}
            .container {{ max-width: 540px; margin: 0 auto; background: #1E293B; border-radius: 16px; border: 1px solid #334155; overflow: hidden; }}
            .header {{ background: linear-gradient(135deg, #3B82F6, #1D4ED8); padding: 22px; text-align: center; color: white; }}
            .title {{ font-size: 18px; font-weight: 700; margin: 0; }}
            .content {{ padding: 24px; }}
            .meta {{ font-size: 13px; color: #94A3B8; margin-bottom: 16px; }}
            .footer {{ border-top: 1px solid #334155; padding: 14px; text-align: center; font-size: 11px; color: #64748B; background: #111827; }}
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <div class="title">⚡ GEBTALK Chat Transcript</div>
            </div>
            <div class="content">
              <div class="meta">Forwarded by <strong>{sender_name}</strong> {f'({sender_email})' if sender_email else ''}</div>
              <h3 style="color:#F8FAFC; margin-top:0;">{subject}</h3>
              <div style="margin: 16px 0;">
                {formatted_lines}
              </div>
              <p style="font-size:12px; color:#64748B; margin-top:20px;">You can reply directly to this email or continue this conversation inside the GEBTALK app.</p>
            </div>
            <div class="footer">&copy; {2026} GEBTALK Unified Communications</div>
          </div>
        </body>
        </html>
        """
        return cls.send_email(to_email, email_subject, html_content, text_content)

    @classmethod
    def send_contact_request_email(cls, to_email: str, sender_name: str, sender_email: str, note: str = "") -> tuple[bool, str]:
        subject = f"🤝 {sender_name} wants to connect with you on GEBTALK"
        text_content = f"{sender_name} ({sender_email}) has sent you a connection request on GEBTALK.\n\nNote: {note or 'Let us connect on GEBTALK.'}\n\nSign in to GEBTALK to accept or decline."
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0F172A; color: #F8FAFC; margin: 0; padding: 20px; }}
            .container {{ max-width: 500px; margin: 0 auto; background: #1E293B; border-radius: 16px; border: 1px solid #334155; overflow: hidden; }}
            .header {{ background: #8B5CF6; padding: 22px; text-align: center; color: white; font-weight: bold; font-size: 18px; }}
            .content {{ padding: 26px; }}
            .card {{ background: #0F172A; border-radius: 10px; padding: 16px; margin: 16px 0; border: 1px solid #334155; }}
            .footer {{ border-top: 1px solid #334155; padding: 14px; text-align: center; font-size: 11px; color: #64748B; background: #111827; }}
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">🤝 New Connection Request</div>
            <div class="content">
              <p style="font-size: 15px; color: #E2E8F0;"><strong>{sender_name}</strong> wants to connect with you on GEBTALK.</p>
              <div class="card">
                <div style="font-size: 13px; color: #94A3B8;">Sender: <strong style="color: #E2E8F0;">{sender_name}</strong> ({sender_email})</div>
                {f"<div style='font-size: 13px; color: #CBD5E1; margin-top: 8px;'>&ldquo;{note}&rdquo;</div>" if note else ""}
              </div>
              <p style="font-size: 13px; color: #94A3B8;">Open GEBTALK Contacts to accept this request and start real-time messaging or voice/video calling.</p>
            </div>
            <div class="footer">&copy; {2026} GEBTALK Communications</div>
          </div>
        </body>
        </html>
        """
        return cls.send_email(to_email, subject, html_content, text_content)
