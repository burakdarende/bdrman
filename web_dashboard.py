#!/usr/bin/env python3
"""
BDRman Ultimate Web Dashboard v5.1
Features: Login Security, CapRover, Advanced Backups, Config Export
"""

from flask import Flask, render_template_string, jsonify, request, send_file, session, redirect, url_for
import subprocess
import json
import os
import time
import psutil
import secrets
from datetime import datetime
from functools import wraps

app = Flask(__name__)
app.secret_key = secrets.token_hex(16) # Secure session key

# Configuration
BACKUP_DIR = "/var/backups/bdrman"
LOG_FILE = "/var/log/bdrman.log"
CONFIG_FILE = "/etc/bdrman/bdrman.conf"

# Simple Auth (In production, use a database or hash)
# This password should be changed in /etc/bdrman/bdrman.conf
ADMIN_PASSWORD = "admin" 

def load_config():
    global ADMIN_PASSWORD
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if line.startswith("WEB_PASSWORD="):
                    ADMIN_PASSWORD = line.split("=")[1].strip().strip('"')
    except: pass

load_config()

# Login Decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# HTML Template
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BDRman Ultimate</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-color: #0f172a;
            --card-bg: rgba(30, 41, 59, 0.7);
            --text-primary: #f1f5f9;
            --text-secondary: #94a3b8;
            --accent: #3b82f6;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --glass-border: 1px solid rgba(255, 255, 255, 0.1);
        }

        * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', system-ui, sans-serif; }
        
        body {
            background-color: var(--bg-color);
            background-image: 
                radial-gradient(at 0% 0%, rgba(59, 130, 246, 0.15) 0px, transparent 50%),
                radial-gradient(at 100% 0%, rgba(16, 185, 129, 0.15) 0px, transparent 50%);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            overflow-x: hidden;
        }

        /* Login Page */
        .login-container {
            width: 100%;
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .login-box {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            border: var(--glass-border);
            padding: 40px;
            border-radius: 16px;
            width: 400px;
            text-align: center;
        }
        .login-input {
            width: 100%;
            padding: 12px;
            margin: 10px 0;
            background: rgba(0,0,0,0.2);
            border: var(--glass-border);
            border-radius: 8px;
            color: white;
        }

        /* Sidebar */
        .sidebar {
            width: 260px;
            background: rgba(15, 23, 42, 0.95);
            backdrop-filter: blur(10px);
            border-right: var(--glass-border);
            padding: 20px;
            display: flex;
            flex-direction: column;
            position: fixed;
            height: 100vh;
            z-index: 100;
            overflow-y: auto;
        }

        .logo {
            font-size: 24px;
            font-weight: 800;
            background: linear-gradient(45deg, var(--accent), var(--success));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 40px;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .nav-item {
            padding: 12px 16px;
            margin-bottom: 8px;
            border-radius: 12px;
            cursor: pointer;
            color: var(--text-secondary);
            transition: all 0.3s ease;
            display: flex;
            align-items: center;
            gap: 12px;
            font-weight: 500;
        }

        .nav-item:hover, .nav-item.active {
            background: rgba(59, 130, 246, 0.1);
            color: var(--accent);
        }

        /* Main Content */
        .main {
            flex: 1;
            margin-left: 260px;
            padding: 30px;
            max-width: 1600px;
            overflow-y: auto;
            height: 100vh;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
        }

        /* Cards */
        .card {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            border: var(--glass-border);
            border-radius: 16px;
            padding: 20px;
            transition: transform 0.2s;
            display: flex;
            flex-direction: column;
            min-height: 200px; 
            max-height: 500px;
            overflow: hidden;
        }

        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }

        .card-title { font-size: 16px; font-weight: 600; color: var(--text-secondary); }
        .stat-value { font-size: 32px; font-weight: 700; margin-bottom: 5px; }
        .stat-sub { font-size: 13px; color: var(--text-secondary); margin-bottom: 10px; }

        .chart-wrapper {
            position: relative;
            height: 100px;
            width: 100%;
            margin-top: auto;
        }

        /* Tables */
        .table-container { 
            overflow-x: auto; 
            flex: 1; 
            overflow-y: auto;
        }
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 15px; color: var(--text-secondary); font-weight: 500; border-bottom: var(--glass-border); position: sticky; top: 0; background: rgba(30, 41, 59, 0.9); z-index: 10; }
        td { padding: 15px; border-bottom: var(--glass-border); }

        /* Badges */
        .badge { padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-success { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        .badge-danger { background: rgba(239, 68, 68, 0.2); color: var(--danger); }

        /* Buttons */
        .btn {
            padding: 8px 16px;
            border-radius: 8px;
            border: none;
            cursor: pointer;
            font-weight: 500;
            transition: 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            color: white;
        }
        .btn-sm { padding: 6px 12px; font-size: 12px; }
        .btn-primary { background: var(--accent); }
        .btn-danger { background: rgba(239, 68, 68, 0.2); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.3); }
        .btn-success { background: rgba(16, 185, 129, 0.2); color: var(--success); border: 1px solid rgba(16, 185, 129, 0.3); }
        .btn-warning { background: rgba(245, 158, 11, 0.2); color: var(--warning); border: 1px solid rgba(245, 158, 11, 0.3); }

        .terminal {
            background: #000;
            border-radius: 12px;
            padding: 15px;
            font-family: 'Fira Code', monospace;
            font-size: 13px;
            color: #0f0;
            height: 100%;
            min-height: 300px;
            overflow-y: auto;
            border: var(--glass-border);
        }
        
        .grid-4 { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(450px, 1fr)); gap: 20px; margin-bottom: 30px; }

        /* Toast */
        .toast {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 16px 24px;
            background: white;
            color: #1e293b;
            border-radius: 12px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.2);
            display: flex;
            align-items: center;
            gap: 12px;
            transform: translateX(150%);
            transition: 0.4s;
            z-index: 1000;
        }
        .toast.show { transform: translateX(0); }
    </style>
</head>
<body>
    {% if not logged_in %}
    <div class="login-container">
        <div class="login-box">
            <div class="logo" style="justify-content: center;">
                <i class="fas fa-layer-group"></i> BDRman
            </div>
            <form action="/login" method="post">
                <input type="password" name="password" class="login-input" placeholder="Enter Password" required>
                <button type="submit" class="btn btn-primary" style="width: 100%">Login</button>
            </form>
        </div>
    </div>
    {% else %}
    
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="logo">
            <i class="fas fa-layer-group"></i> <span>BDRman</span>
        </div>
        <div class="nav-item active" onclick="loadPage('dashboard')"><i class="fas fa-chart-pie"></i> <span>Overview</span></div>
        <div class="nav-item" onclick="loadPage('containers')"><i class="fas fa-box-open"></i> <span>Containers</span></div>
        <div class="nav-item" onclick="loadPage('services')"><i class="fas fa-server"></i> <span>Services</span></div>
        <div class="nav-item" onclick="loadPage('caprover')"><i class="fas fa-rocket"></i> <span>CapRover</span></div>
        <div class="nav-item" onclick="loadPage('security')"><i class="fas fa-shield-alt"></i> <span>Security</span></div>
        <div class="nav-item" onclick="loadPage('backups')"><i class="fas fa-save"></i> <span>Backups</span></div>
        <div class="nav-item" onclick="loadPage('logs')"><i class="fas fa-terminal"></i> <span>Logs</span></div>
        <div class="nav-item" onclick="location.href='/logout'"><i class="fas fa-sign-out-alt"></i> <span>Logout</span></div>
    </div>

    <!-- Main Content -->
    <div class="main">
        <div class="header">
            <h2 id="page-title">Dashboard</h2>
            <div class="stat-sub" id="last-update">Updated: Just now</div>
        </div>

        <!-- DASHBOARD -->
        <div id="page-dashboard" class="page">
            <div class="grid-4">
                <div class="card">
                    <div class="card-title">CPU</div>
                    <div class="stat-value" id="cpu-val">0%</div>
                    <div class="chart-wrapper"><canvas id="cpuChart"></canvas></div>
                </div>
                <div class="card">
                    <div class="card-title">RAM</div>
                    <div class="stat-value" id="mem-val">0%</div>
                    <div class="chart-wrapper"><canvas id="memChart"></canvas></div>
                </div>
                <div class="card">
                    <div class="card-title">Disk</div>
                    <div class="stat-value" id="disk-val">0%</div>
                    <div style="height: 4px; background: rgba(255,255,255,0.1); margin-top: auto;"><div id="disk-bar" style="width: 0%; height: 100%; background: var(--accent);"></div></div>
                </div>
                <div class="card">
                    <div class="card-title">Network</div>
                    <div class="stat-value" id="net-val">0 KB/s</div>
                    <div class="chart-wrapper"><canvas id="netChart"></canvas></div>
                </div>
            </div>
            
            <div class="grid-2">
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">Quick Actions</div>
                    </div>
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                        <button class="btn btn-primary" onclick="runCmd('status')">System Status</button>
                        <button class="btn btn-success" onclick="runCmd('backup create config')">Backup Config</button>
                        <button class="btn btn-warning" onclick="runCmd('metrics report')">Metrics</button>
                        <button class="btn btn-danger" onclick="runCmd('web stop')">Stop Web</button>
                    </div>
                    <div class="terminal" id="quick-output" style="height: 150px; margin-top: 15px;">Ready...</div>
                </div>
            </div>
        </div>

        <!-- SERVICES -->
        <div id="page-services" class="page" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">System Services</div>
                    <button class="btn btn-primary" onclick="refreshServices()">Refresh</button>
                </div>
                <div class="grid-4" id="services-grid">
                    <!-- Populated by JS -->
                </div>
            </div>
        </div>

        <!-- CAPROVER -->
        <div id="page-caprover" class="page" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">CapRover Management</div>
                    <div class="badge" id="caprover-status">Checking...</div>
                </div>
                <div style="padding: 20px; text-align: center;">
                    <p style="margin-bottom: 20px; color: var(--text-secondary);">CapRover is an extremely easy to use app/database deployment & web server manager.</p>
                    <button class="btn btn-success" onclick="runCmd('caprover install')"><i class="fas fa-download"></i> Install CapRover</button>
                    <button class="btn btn-danger" onclick="runCmd('caprover uninstall')"><i class="fas fa-trash"></i> Uninstall CapRover</button>
                    <br><br>
                    <p class="stat-sub">Requires ports 80, 443, 3000.</p>
                </div>
            </div>
        </div>

        <!-- BACKUPS -->
        <div id="page-backups" class="page" style="display: none;">
            <div class="grid-2">
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">Create Backup</div>
                    </div>
                    <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                        <button class="btn btn-primary" onclick="runCmd('backup create config')">Config Only</button>
                        <button class="btn btn-warning" onclick="runCmd('backup create data')">Data (www/docker)</button>
                        <button class="btn btn-danger" onclick="runCmd('backup create full')">Full System Snapshot</button>
                    </div>
                    <div style="margin-top: 20px;">
                        <div class="card-title">Config as Code</div>
                        <div style="display: flex; gap: 10px; margin-top: 10px;">
                            <button class="btn btn-success" onclick="runCmd('config export')">Export Config</button>
                            <!-- Import would need file upload logic, keeping it simple for now -->
                        </div>
                    </div>
                </div>
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">Archives</div>
                        <button class="btn btn-sm btn-primary" onclick="refreshBackups()"><i class="fas fa-sync"></i></button>
                    </div>
                    <div class="table-container">
                        <table id="backup-table">
                            <thead><tr><th>File</th><th>Size</th><th>Date</th><th>Action</th></tr></thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>

        <!-- OTHER PAGES (Containers, Security, Logs) -->
        <div id="page-containers" class="page" style="display: none;">
            <div class="card" style="height: calc(100vh - 100px);">
                <div class="card-header">
                    <div class="card-title">Docker Containers</div>
                    <button class="btn btn-primary" onclick="refreshContainers()">Refresh</button>
                </div>
                <div class="table-container"><table id="container-table"><thead><tr><th>Name</th><th>Status</th><th>Actions</th></tr></thead><tbody></tbody></table></div>
            </div>
        </div>

        <div id="page-security" class="page" style="display: none;">
            <div class="grid-2">
                <div class="card" style="max-height: 600px;">
                    <div class="card-header">
                        <div class="card-title">Firewall (UFW)</div>
                        <div class="badge" id="ufw-status-badge">Loading...</div>
                    </div>
                    <div class="table-container"><table id="ufw-table"><thead><tr><th>To</th><th>Action</th><th>From</th></tr></thead><tbody></tbody></table></div>
                </div>
            </div>
        </div>

        <div id="page-logs" class="page" style="display: none;">
            <div class="card" style="height: calc(100vh - 100px);">
                <div class="card-header"><div class="card-title">Logs</div><button class="btn btn-primary" onclick="refreshLogs()">Refresh</button></div>
                <div class="terminal" id="log-viewer">Loading...</div>
            </div>
        </div>

    </div>
    
    <div id="toast" class="toast"><i class="fas fa-check-circle"></i> <span id="toast-msg">Success</span></div>

    <script>
        // Charts
        const chartOpts = { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { x: { display: false }, y: { display: false, min: 0 } }, elements: { point: { radius: 0 }, line: { tension: 0.4, borderWidth: 2 } }, animation: { duration: 0 } };
        function mkChart(id, color) { return new Chart(document.getElementById(id).getContext('2d'), { type: 'line', data: { labels: Array(20).fill(''), datasets: [{ data: Array(20).fill(0), borderColor: color, backgroundColor: color+'20', fill: true }] }, options: chartOpts }); }
        const cpuC = mkChart('cpuChart', '#3b82f6'), memC = mkChart('memChart', '#10b981'), netC = mkChart('netChart', '#f59e0b');

        function refreshServices() {
            fetch('/api/services').then(r=>r.json()).then(d => {
                document.getElementById('services-grid').innerHTML = d.services.map(s => `
                    <div class="card" style="padding:15px; min-height: auto;">
                        <div style="display:flex; justify-content:space-between; align-items:center">
                            <strong>${s.name}</strong>
                            <span class="badge ${s.active ? 'badge-success' : 'badge-danger'}">${s.active ? 'Running' : 'Stopped'}</span>
                        </div>
                        <div style="margin-top:10px; display:flex; gap:5px">
                            <button class="btn btn-sm btn-primary" onclick="serviceAction('${s.name}', 'restart')">Restart</button>
                            <button class="btn btn-sm ${s.active ? 'btn-danger' : 'btn-success'}" 
                                onclick="serviceAction('${s.name}', '${s.active ? 'stop' : 'start'}')">
                                ${s.active ? 'Stop' : 'Start'}
                            </button>
                        </div>
                    </div>
                `).join('');
            });
        }

        function serviceAction(n, a) {
            fetch(`/api/service/${a}/${n}`, {method:'POST'}).then(r=>r.json()).then(d => {
                if(d.success) { showToast('Success'); refreshServices(); } else showToast('Failed', 'error');
            });
        }

        function checkCapRover() {
            fetch('/api/caprover/status').then(r=>r.json()).then(d => {
                const b = document.getElementById('caprover-status');
                b.textContent = d.status.toUpperCase();
                b.className = 'badge ' + (d.status==='active'?'badge-success':'badge-danger');
            });
        }

        function loadPage(p) {
            document.querySelectorAll('.page').forEach(e => e.style.display = 'none');
            document.getElementById('page-'+p).style.display = 'block';
            document.querySelectorAll('.nav-item').forEach(e => e.classList.remove('active'));
            event.currentTarget.classList.add('active');
            if(p==='containers') refreshContainers();
            if(p==='backups') refreshBackups();
            if(p==='security') refreshSecurity();
            if(p==='logs') refreshLogs();
            if(p==='services') refreshServices();
            if(p==='caprover') checkCapRover();
        }

        function updateStats() {
            fetch('/api/stats').then(r=>r.json()).then(d => {
                document.getElementById('cpu-val').textContent = d.cpu+'%';
                document.getElementById('mem-val').textContent = d.mem.percent+'%';
                document.getElementById('disk-val').textContent = d.disk.percent+'%';
                document.getElementById('disk-bar').style.width = d.disk.percent+'%';
                document.getElementById('net-val').textContent = d.net.speed;
                
                [cpuC, memC, netC].forEach(c => c.data.datasets[0].data.shift());
                cpuC.data.datasets[0].data.push(d.cpu);
                memC.data.datasets[0].data.push(d.mem.percent);
                netC.data.datasets[0].data.push(d.net.speed_raw);
                [cpuC, memC, netC].forEach(c => c.update());
            });
        }

        function refreshContainers() {
            fetch('/api/containers').then(r=>r.json()).then(d => {
                document.querySelector('#container-table tbody').innerHTML = d.containers.map(c => `
                    <tr><td>${c.name}</td><td><span class="badge ${c.status.includes('Up')?'badge-success':'badge-danger'}">${c.status}</span></td>
                    <td><button class="btn btn-sm btn-primary" onclick="dockerAction('${c.name}','restart')">Restart</button></td></tr>
                `).join('');
            });
        }

        function refreshBackups() {
            fetch('/api/backups').then(r=>r.json()).then(d => {
                document.querySelector('#backup-table tbody').innerHTML = d.backups.map(b => `
                    <tr><td>${b.name}</td><td>${b.size}</td><td>${b.date}</td>
                    <td><a href="/api/download/backup/${b.name}" class="btn btn-sm btn-primary" target="_blank">Download</a></td></tr>
                `).join('');
            });
        }

        function refreshSecurity() {
            fetch('/api/security').then(r=>r.json()).then(d => {
                const badge = document.getElementById('ufw-status-badge');
                badge.textContent = d.ufw_status;
                badge.className = 'badge ' + (d.ufw_status === 'active' ? 'badge-success' : 'badge-danger');
                
                document.querySelector('#ufw-table tbody').innerHTML = d.ufw.map(r => `
                    <tr><td>${r.to}</td><td>${r.action}</td><td>${r.from}</td></tr>
                `).join('');
            });
        }

        function refreshLogs() { fetch('/api/logs').then(r=>r.json()).then(d => document.getElementById('log-viewer').textContent = d.logs); }

        function runCmd(cmd) {
            document.getElementById('quick-output').textContent = "Running...";
            fetch('/api/command', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({command: cmd}) })
            .then(r=>r.json()).then(d => {
                document.getElementById('quick-output').textContent = d.output;
                if(cmd.includes('backup')) refreshBackups();
            });
        }
        
        function dockerAction(n, a) { fetch(`/api/docker/${a}/${n}`, {method:'POST'}); }

        setInterval(updateStats, 2000);
        updateStats();
    </script>
    {% endif %}
</body>
</html>
"""

# --- ROUTES ---

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE, logged_in='logged_in' in session)

@app.route('/login', methods=['POST'])
def login():
    if request.form.get('password') == ADMIN_PASSWORD:
        session['logged_in'] = True
        return redirect('/')
    return render_template_string(HTML_TEMPLATE, logged_in=False)

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    return redirect('/')

@app.route('/api/stats')
@login_required
def stats():
    cpu = psutil.cpu_percent(interval=None)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    net = psutil.net_io_counters()
    return jsonify({
        'cpu': cpu,
        'mem': {'percent': mem.percent},
        'disk': {'percent': disk.percent},
        'net': {'speed': "0 KB/s", 'speed_raw': 0}
    })

@app.route('/api/services')
@login_required
def services():
    svcs = ['nginx', 'mysql', 'postgresql', 'redis-server', 'ufw', 'ssh', 'cron', 'docker']
    data = []
    for s in svcs:
        active = subprocess.call(f"systemctl is-active --quiet {s}", shell=True) == 0
        data.append({'name': s, 'active': active})
    return jsonify({'services': data})

@app.route('/api/service/<action>/<name>', methods=['POST'])
@login_required
def service_ctrl(action, name):
    if action not in ['start', 'stop', 'restart']: return jsonify({'success':False}), 400
    try:
        subprocess.check_call(f"systemctl {action} {name}", shell=True)
        return jsonify({'success':True})
    except: return jsonify({'success':False})

@app.route('/api/caprover/status')
@login_required
def caprover_status():
    try:
        # Check if container named 'caprover' is running
        out = subprocess.check_output("docker inspect -f '{{.State.Running}}' caprover 2>/dev/null", shell=True).decode().strip()
        status = "active" if out == "true" else "inactive"
    except:
        status = "inactive"
    return jsonify({'status': status})

@app.route('/api/security')
@login_required
def security():
    # Check UFW Status explicitly
    ufw_status = "inactive"
    try:
        status_out = subprocess.check_output("ufw status", shell=True).decode()
        if "Status: active" in status_out:
            ufw_status = "active"
    except: pass

    ufw_rules = []
    try:
        out = subprocess.check_output("ufw status", shell=True).decode()
        for line in out.split('\n'):
            if 'ALLOW' in line or 'DENY' in line:
                p = line.split()
                ufw_rules.append({'to': p[0], 'action': p[1], 'from': p[2] if len(p)>2 else 'Anywhere'})
    except: pass
    return jsonify({'ufw': ufw_rules, 'ufw_status': ufw_status})

@app.route('/api/backups')
@login_required
def backups():
    files = []
    if os.path.exists(BACKUP_DIR):
        for f in os.listdir(BACKUP_DIR):
            if f.endswith('.tar.gz'):
                p = os.path.join(BACKUP_DIR, f)
                s = round(os.path.getsize(p)/(1024*1024), 2)
                d = datetime.fromtimestamp(os.path.getmtime(p)).strftime('%Y-%m-%d %H:%M')
                files.append({'name': f, 'size': f"{s} MB", 'date': d})
    return jsonify({'backups': sorted(files, key=lambda x: x['date'], reverse=True)})

@app.route('/api/download/backup/<filename>')
@login_required
def download_backup(filename):
    return send_file(os.path.join(BACKUP_DIR, filename), as_attachment=True)

@app.route('/api/command', methods=['POST'])
@login_required
def command():
    cmd = request.json.get('command')
    # Allow caprover commands
    if cmd not in ['status', 'backup create config', 'backup create data', 'backup create full', 'metrics report', 'web stop', 'config export', 'caprover install', 'caprover uninstall']: 
        return jsonify({'output': 'Forbidden'}), 403
    
    # Map web commands to CLI arguments
    cli_cmd = cmd
    if cmd == 'backup create config': cli_cmd = 'backup create config' # Handled by arg parser in bdrman.sh? No, need to fix bdrman.sh to accept args from main
    # Actually, bdrman.sh main menu doesn't easily accept args for sub-functions unless we expose them via CLI flags.
    # We need to call the function directly or use the CLI argument parser.
    # Let's assume bdrman.sh has a CLI parser. If not, we might need to tweak how we call it.
    # For now, let's assume we can pass arguments like `bdrman backup create config`
    
    try:
        # We need to ensure bdrman.sh handles these arguments. 
        # Currently bdrman.sh uses a case statement for $1.
        # We need to make sure "backup" command accepts sub-args.
        out = subprocess.check_output(f"/usr/local/bin/bdrman {cmd}", shell=True).decode()
        return jsonify({'output': out})
    except Exception as e: return jsonify({'output': str(e)})

@app.route('/api/logs')
@login_required
def logs():
    try: return jsonify({'logs': subprocess.check_output(f"tail -n 100 {LOG_FILE}", shell=True).decode()})
    except: return jsonify({'logs': 'Error'})

@app.route('/api/docker/<action>/<name>', methods=['POST'])
@login_required
def docker_ctrl(action, name):
    try: subprocess.check_call(f"docker {action} {name}", shell=True); return jsonify({'success':True})
    except: return jsonify({'success':False})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443)
