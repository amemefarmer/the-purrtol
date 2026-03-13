#!/usr/bin/env python3
"""
Captive Portal Server for Facebook Portal Exploit Chain

RISK LEVEL: ZERO (serves web pages, no device modification)

This server intercepts Android connectivity checks and serves a captive portal
page to the Facebook Portal's WebView. The initial page is a reconnaissance
landing that logs the User-Agent (Chrome/WebView version).

Usage:
    sudo python3 server.py [--port 80] [--bind 0.0.0.0] [--exploit]

The --exploit flag switches from recon mode to exploit serving mode.
Requires root (sudo) to bind to port 80.
"""

import argparse
import datetime
import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# Android 9 connectivity check paths
CAPTIVE_PORTAL_PATHS = {
    '/generate_204',
    '/gen_204',
    '/mobile/status.php',          # Facebook Portal (portal.fb.com/mobile/status.php)
    '/hotspot-detect.html',        # Apple devices (for testing with iPhone)
    '/library/test/success.html',  # Apple fallback
    '/connecttest.txt',            # Microsoft (for testing)
}

SCRIPT_DIR = Path(__file__).parent.resolve()
WWW_DIR = SCRIPT_DIR / 'www'
PAYLOAD_DIR = SCRIPT_DIR / 'payloads'
LOG_DIR = SCRIPT_DIR / 'logs'


class CaptivePortalHandler(BaseHTTPRequestHandler):
    """HTTP handler that intercepts connectivity checks and serves exploit pages."""

    exploit_mode = False

    def log_request_details(self, note=''):
        """Log full request details to file and console."""
        timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')
        user_agent = self.headers.get('User-Agent', 'UNKNOWN')
        host = self.headers.get('Host', 'UNKNOWN')

        log_entry = {
            'timestamp': timestamp,
            'method': self.command,
            'path': self.path,
            'host': host,
            'user_agent': user_agent,
            'client': f'{self.client_address[0]}:{self.client_address[1]}',
            'headers': dict(self.headers),
            'note': note,
        }

        # Console output
        chrome_ver = 'N/A'
        if 'Chrome/' in user_agent:
            try:
                chrome_ver = user_agent.split('Chrome/')[1].split(' ')[0]
            except IndexError:
                pass

        print(f'\n{"="*70}')
        print(f'  [{timestamp}] {self.command} {host}{self.path}')
        print(f'  Client: {self.client_address[0]}')
        print(f'  User-Agent: {user_agent}')
        print(f'  Chrome Version: {chrome_ver}')
        if note:
            print(f'  Note: {note}')
        print(f'{"="*70}')

        # File log
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        log_file = LOG_DIR / f'requests_{datetime.date.today().isoformat()}.jsonl'
        with open(log_file, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')

        # Save User-Agent to dedicated file for quick reference
        ua_file = LOG_DIR / 'user_agents.txt'
        with open(ua_file, 'a') as f:
            f.write(f'{timestamp} | {self.client_address[0]} | {user_agent}\n')

        return chrome_ver

    def is_connectivity_check(self):
        """Check if this request is an Android/iOS connectivity check."""
        parsed = urlparse(self.path)
        return parsed.path in CAPTIVE_PORTAL_PATHS

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        # Connectivity check — serve exploit/recon page directly (no redirect)
        # Previous approach used 302 redirect to http://portal.local/... but
        # .local TLD uses mDNS which Android may not resolve via our dnsmasq.
        # Serving inline avoids all redirect/DNS issues.
        if self.is_connectivity_check():
            if self.exploit_mode:
                serve_file = WWW_DIR / 'exploit' / 'rce_chrome86.html'
                note = 'CONNECTIVITY CHECK — serving EXPLOIT page directly'
            else:
                serve_file = WWW_DIR / 'index.html'
                note = 'CONNECTIVITY CHECK — serving recon page directly'
            chrome_ver = self.log_request_details(note)
            if serve_file.is_file():
                content = serve_file.read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
                self.send_header('Pragma', 'no-cache')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(b'<html><body><h1>Captive Portal</h1><p>Exploit file not found.</p></body></html>')
            return

        # API endpoint for JS to report device info (GET with query params = Image beacon)
        if path == '/api/report':
            params = parse_qs(parsed.query)
            stage = params.get('stage', [''])[0]
            status = params.get('status', [''])[0]
            detail = params.get('detail', [''])[0]
            beacon = params.get('beacon', [''])[0]

            if beacon:
                note = f'BEACON: {beacon}'
            elif stage:
                note = f'EXPLOIT REPORT: stage={stage} status={status} detail={detail[:200]}'
            else:
                note = 'DEVICE INFO REPORT (GET)'

            self.log_request_details(note)

            # Save exploit reports to dedicated log
            if stage or beacon:
                LOG_DIR.mkdir(parents=True, exist_ok=True)
                exploit_log = LOG_DIR / 'exploit_reports.jsonl'
                with open(exploit_log, 'a') as f:
                    timestamp = datetime.datetime.now().isoformat()
                    f.write(json.dumps({
                        'timestamp': timestamp,
                        'type': 'beacon' if beacon else 'report',
                        'beacon': beacon,
                        'stage': stage,
                        'status': status,
                        'detail': detail,
                        'client': self.client_address[0],
                    }) + '\n')

                # Print to console in a prominent way
                print(f'\n{"*"*70}')
                if beacon:
                    print(f'  BEACON: {beacon}')
                else:
                    print(f'  EXPLOIT STAGE: {stage}')
                    print(f'  STATUS: {status}')
                    print(f'  DETAIL: {detail[:300]}')
                print(f'{"*"*70}\n')

            # Return 1x1 transparent PNG for Image beacons
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Cache-Control', 'no-store')
            # 1x1 transparent PNG
            pixel = (b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01'
                     b'\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4'
                     b'\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05'
                     b'\x00\x01\r\n\xb4\x00\x00\x00\x00IEND\xaeB`\x82')
            self.send_header('Content-Length', str(len(pixel)))
            self.end_headers()
            self.wfile.write(pixel)
            return

        # Serve stage2 binary from payloads directory
        if path.startswith('/payloads/'):
            payload_name = path.split('/payloads/', 1)[1]
            payload_path = PAYLOAD_DIR / payload_name
            if payload_path.is_file():
                self.log_request_details(f'Serving PAYLOAD: {payload_name}')
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('Access-Control-Allow-Origin', '*')
                content = payload_path.read_bytes()
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

        # Serve static files from www/
        if path == '/' or path == '':
            if self.exploit_mode:
                path = '/exploit/rce_chrome86.html'
            else:
                path = '/index.html'

        file_path = WWW_DIR / path.lstrip('/')
        if file_path.is_file():
            self.log_request_details(f'Serving: {file_path.name}')
            self.send_response(200)

            # Content type mapping
            ext = file_path.suffix.lower()
            content_types = {
                '.html': 'text/html; charset=utf-8',
                '.js': 'application/javascript; charset=utf-8',
                '.css': 'text/css; charset=utf-8',
                '.json': 'application/json',
                '.png': 'image/png',
                '.ico': 'image/x-icon',
                '.wasm': 'application/wasm',
            }
            self.send_header('Content-Type', content_types.get(ext, 'application/octet-stream'))
            # No caching — we want fresh loads every time
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Access-Control-Allow-Origin', '*')

            content = file_path.read_bytes()
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            return

        # 404 — but still log it (useful for discovering what the Portal requests)
        self.log_request_details(f'404 NOT FOUND')
        self.send_response(200)  # Return 200 with info page instead of 404
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        body = f'''<!DOCTYPE html>
<html><body>
<h3>Portal Captive Portal Server</h3>
<p>Requested path: <code>{path}</code></p>
<p><a href="/index.html">Go to main page</a></p>
</body></html>'''
        self.wfile.write(body.encode())

    def do_POST(self):
        """Handle POST requests (device info reports from JS)."""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else b''

        parsed = urlparse(self.path)

        if parsed.path == '/api/report':
            body_str = body.decode('utf-8', errors='replace')[:500]
            self.log_request_details(f'POST DEVICE REPORT: {body_str}')

            # Parse and prominently display exploit stage reports
            try:
                report_data = json.loads(body_str)
                stage = report_data.get('stage', '')
                status = report_data.get('status', '')
                detail = report_data.get('detail', '')
                if stage:
                    print(f'\n{"*"*70}')
                    print(f'  EXPLOIT STAGE (POST): {stage}')
                    print(f'  STATUS: {status}')
                    print(f'  DETAIL: {str(detail)[:300]}')
                    print(f'{"*"*70}\n')
                    # Also save to exploit log
                    exploit_log = LOG_DIR / 'exploit_reports.jsonl'
                    with open(exploit_log, 'a') as f:
                        f.write(json.dumps({
                            'timestamp': datetime.datetime.now().isoformat(),
                            'type': 'post_report',
                            'stage': stage,
                            'status': status,
                            'detail': str(detail),
                            'client': self.client_address[0],
                        }) + '\n')
            except (json.JSONDecodeError, AttributeError):
                pass

            # Save device report
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            report_file = LOG_DIR / 'device_reports.jsonl'
            with open(report_file, 'a') as f:
                timestamp = datetime.datetime.now().isoformat()
                f.write(json.dumps({
                    'timestamp': timestamp,
                    'client': self.client_address[0],
                    'user_agent': self.headers.get('User-Agent', ''),
                    'report': body.decode('utf-8', errors='replace'),
                }) + '\n')

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(b'{"status":"received"}')
            return

        self.log_request_details(f'POST to unknown path')
        self.send_response(404)
        self.end_headers()

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def log_message(self, format, *args):
        """Suppress default access log (we have our own)."""
        pass


def main():
    parser = argparse.ArgumentParser(description='Portal Captive Portal Server')
    parser.add_argument('--port', type=int, default=80, help='Port to listen on (default: 80)')
    parser.add_argument('--bind', default='0.0.0.0', help='Address to bind to (default: 0.0.0.0)')
    parser.add_argument('--exploit', action='store_true', help='Enable exploit serving mode')
    args = parser.parse_args()

    CaptivePortalHandler.exploit_mode = args.exploit

    if args.port < 1024 and os.geteuid() != 0:
        print(f'ERROR: Port {args.port} requires root. Run with: sudo python3 server.py')
        sys.exit(1)

    # Ensure www directory exists
    WWW_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    HTTPServer.allow_reuse_address = True
    server = HTTPServer((args.bind, args.port), CaptivePortalHandler)

    mode = 'EXPLOIT' if args.exploit else 'RECON'
    print(f'''
╔══════════════════════════════════════════════════════════╗
║         Portal Captive Portal Server                     ║
║                                                          ║
║  Mode:    {mode:<46s}  ║
║  Listen:  {args.bind}:{args.port:<40}  ║
║  WWW:     {str(WWW_DIR):<46s}  ║
║  Logs:    {str(LOG_DIR):<46s}  ║
║                                                          ║
║  Intercepting connectivity checks:                       ║
║    /generate_204, /gen_204, /hotspot-detect.html         ║
║                                                          ║
║  Waiting for Portal to connect to WiFi hotspot...        ║
╚══════════════════════════════════════════════════════════╝
''')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down server...')
        server.shutdown()


if __name__ == '__main__':
    main()
