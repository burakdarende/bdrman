#!/usr/bin/env python3
"""
BDRman Ultimate Web Dashboard v5.0
The most advanced single-file server management dashboard.
Features: Network, Security, Backups, Services, Docker, Glassmorphism UI
"""

from flask import Flask, render_template_string, jsonify, request, send_file
import subprocess
import json
import os
import time
import psutil
from datetime import datetime

app = Flask(__name__)

# Configuration
BACKUP_DIR = "/var/backups/bdrman"
LOG_FILE = "/var/log/bdrman.log"

# HTML Template (Embedded for single-file portability)
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
            overflow-x: hidden; /* Prevent horizontal scroll */
        }

        /* Sidebar */
        .sidebar {
            width: 260px;
            background: rgba(15, 23, 42, 0.95); /* Less transparent for better contrast */
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

        .nav-item i { width: 20px; text-align: center; }

        /* Main Content */
        .main {
            flex: 1;
            margin-left: 260px;
            padding: 30px;
            max-width: 1600px;
            overflow-y: auto; /* Allow scrolling in main content */
            height: 100vh;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
        }

        .server-info {
            display: flex;
            align-items: center;
            gap: 15px;
        }

        .status-dot {
            width: 10px;
            height: 10px;
            background: var(--success);
            border-radius: 50%;
            box-shadow: 0 0 10px var(--success);
        }

        /* Grid Layouts */
        .grid-4 { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(450px, 1fr)); gap: 20px; margin-bottom: 30px; }

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
            /* IMPORTANT: Prevent card from growing infinitely */
            min-height: 200px; 
            max-height: 500px;
            overflow: hidden;
        }

        .card:hover { transform: translateY(-2px); }

        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }

        .card-title { font-size: 16px; font-weight: 600; color: var(--text-secondary); }
        
        .stat-value { font-size: 32px; font-weight: 700; margin-bottom: 5px; }
        .stat-sub { font-size: 13px; color: var(--text-secondary); margin-bottom: 10px; }

        /* Chart Container - CRITICAL FIX */
        .chart-wrapper {
            position: relative;
            height: 100px; /* Fixed height for charts */
            width: 100%;
            margin-top: auto; /* Push to bottom */
        }

        /* Tables */
        .table-container { 
            overflow-x: auto; 
            flex: 1; /* Take remaining space */
            overflow-y: auto; /* Allow vertical scroll inside card */
        }
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 15px; color: var(--text-secondary); font-weight: 500; border-bottom: var(--glass-border); position: sticky; top: 0; background: rgba(30, 41, 59, 0.9); z-index: 10; }
        td { padding: 15px; border-bottom: var(--glass-border); }
        tr:last-child td { border-bottom: none; }

        /* Badges */
        .badge { padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-success { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        .badge-danger { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
        .badge-warning { background: rgba(245, 158, 11, 0.2); color: var(--warning); }

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
        }
        .btn-sm { padding: 6px 12px; font-size: 12px; }
        .btn-primary { background: var(--accent); color: white; }
        .btn-danger { background: rgba(239, 68, 68, 0.2); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.3); }
        .btn-success { background: rgba(16, 185, 129, 0.2); color: var(--success); border: 1px solid rgba(16, 185, 129, 0.3); }
        .btn:hover { opacity: 0.9; transform: scale(1.02); }

        /* Terminal & Logs */
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
            transition: 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            z-index: 1000;
        }
        .toast.show { transform: translateX(0); }
        .toast-success i { color: var(--success); }
        .toast-error i { color: var(--danger); }

        /* Mobile */
        @media (max-width: 768px) {
            .sidebar { width: 70px; padding: 15px 10px; }
            .nav-item span, .logo span { display: none; }
            .main { margin-left: 70px; padding: 15px; }
            .grid-4, .grid-2 { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="logo">
            <i class="fas fa-layer-group"></i>
            <span>BDRman</span>
        </div>
        <div class="nav-item active" onclick="loadPage('dashboard')">
            <i class="fas fa-chart-pie"></i> <span>Overview</span>
        </div>
        <div class="nav-item" onclick="loadPage('containers')">
            <i class="fas fa-box-open"></i> <span>Containers</span>
        </div>
        <div class="nav-item" onclick="loadPage('services')">
            <i class="fas fa-server"></i> <span>Services</span>
        </div>
        <div class="nav-item" onclick="loadPage('security')">
            <i class="fas fa-shield-alt"></i> <span>Security</span>
        </div>
        <div class="nav-item" onclick="loadPage('backups')">
            <i class="fas fa-save"></i> <span>Backups</span>
        </div>
        <div class="nav-item" onclick="loadPage('logs')">
            <i class="fas fa-terminal"></i> <span>Logs</span>
        </div>
    </div>

    <!-- Main Content -->
    <div class="main">
        <div class="header">
            <div class="server-info">
                <div class="status-dot"></div>
                <div>
                    <h2 id="hostname">Loading...</h2>
                    <div class="stat-sub" id="os-info">Linux Server</div>
                </div>
            </div>
            <div class="stat-sub" id="last-update">Updated: Just now</div>
        </div>

        <!-- DASHBOARD -->
        <div id="page-dashboard" class="page">
            <div class="grid-4">
                <div class="card">
                    <div class="card-title">CPU Usage</div>
                    <div class="stat-value" id="cpu-val">0%</div>
                    <div class="stat-sub" id="cpu-temp">Temp: --°C</div>
                    <div class="chart-wrapper">
                        <canvas id="cpuChart"></canvas>
                    </div>
                </div>
                <div class="card">
                    <div class="card-title">Memory</div>
                    <div class="stat-value" id="mem-val">0%</div>
                    <div class="stat-sub" id="mem-detail">0/0 GB</div>
                    <div class="chart-wrapper">
                        <canvas id="memChart"></canvas>
                    </div>
                </div>
                <div class="card">
                    <div class="card-title">Disk Space</div>
                    <div class="stat-value" id="disk-val">0%</div>
                    <div class="stat-sub" id="disk-detail">0/0 GB Free</div>
                    <div style="height: 4px; background: rgba(255,255,255,0.1); margin-top: auto; border-radius: 2px;">
                        <div id="disk-bar" style="width: 0%; height: 100%; background: var(--accent); border-radius: 2px;"></div>
                    </div>
                </div>
                <div class="card">
                    <div class="card-title">Network (I/O)</div>
                    <div class="stat-value" id="net-val">0 KB/s</div>
                    <div class="stat-sub">Total: <span id="net-total">0 GB</span></div>
                    <div class="chart-wrapper">
                        <canvas id="netChart"></canvas>
                    </div>
                </div>
            </div>

            <div class="grid-2">
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">Active Containers</div>
                        <button class="btn btn-sm btn-primary" onclick="loadPage('containers')">View All</button>
                    </div>
                    <div class="table-container">
                        <table id="dash-containers">
                            <!-- Populated by JS -->
                        </table>
                    </div>
                </div>
                <div class="card">
                    <div class="card-header">
                        <div class="card-title">Quick Actions</div>
                    </div>
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                        <button class="btn btn-primary" onclick="runCmd('status')"><i class="fas fa-info-circle"></i> System Status</button>
                        <button class="btn btn-success" onclick="runCmd('backup create')"><i class="fas fa-plus-circle"></i> Create Backup</button>
                        <button class="btn btn-warning" onclick="runCmd('metrics report')"><i class="fas fa-file-alt"></i> Metrics Report</button>
                        <button class="btn btn-danger" onclick="runCmd('web stop')"><i class="fas fa-power-off"></i> Stop Dashboard</button>
                    </div>
                    <div class="terminal" id="quick-output" style="height: 150px; margin-top: 15px;">Ready...</div>
                </div>
            </div>
        </div>

        <!-- CONTAINERS -->
        <div id="page-containers" class="page" style="display: none;">
            <div class="card" style="height: calc(100vh - 100px);">
                <div class="card-header">
                    <div class="card-title">Docker Containers</div>
                    <button class="btn btn-primary" onclick="refreshContainers()"><i class="fas fa-sync"></i> Refresh</button>
                </div>
                <div class="table-container">
                    <table id="container-table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Image</th>
                                <th>Status</th>
                                <th>Ports</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody></tbody>
                    </table>
                </div>
            </div>
        </div>

        <!-- SERVICES -->
        <div id="page-services" class="page" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">System Services</div>
                    <button class="btn btn-primary" onclick="refreshServices()"><i class="fas fa-sync"></i> Refresh</button>
                </div>
                <div class="grid-4" id="services-grid">
                    <!-- Populated by JS -->
                </div>
            </div>
        </div>

        <!-- SECURITY -->
        <div id="page-security" class="page" style="display: none;">
            <div class="grid-2">
                <div class="card" style="max-height: 600px;">
                    <div class="card-header">
                        <div class="card-title">Firewall (UFW)</div>
                        <div class="badge badge-success" id="ufw-status">Active</div>
                    </div>
                    <div class="table-container">
                        <table id="ufw-table">
                            <thead><tr><th>To</th><th>Action</th><th>From</th></tr></thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
                <div class="card" style="max-height: 600px;">
                    <div class="card-header">
                        <div class="card-title">Fail2Ban Jails</div>
                    </div>
                    <div class="table-container">
                        <table id="f2b-table">
                            <thead><tr><th>Jail</th><th>Banned IPs</th><th>Actions</th></tr></thead>
                            <tbody></tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>

        <!-- BACKUPS -->
        <div id="page-backups" class="page" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">Backup Archives</div>
                    <button class="btn btn-success" onclick="runCmd('backup create')"><i class="fas fa-plus"></i> New Backup</button>
                </div>
                <div class="table-container">
                    <table id="backup-table">
                        <thead><tr><th>Filename</th><th>Size</th><th>Date</th><th>Actions</th></tr></thead>
                        <tbody></tbody>
                    </table>
                </div>
            </div>
        </div>

        <!-- LOGS -->
        <div id="page-logs" class="page" style="display: none;">
            <div class="card" style="height: calc(100vh - 100px);">
                <div class="card-header">
                    <div class="card-title">System Logs</div>
                    <button class="btn btn-primary" onclick="refreshLogs()"><i class="fas fa-sync"></i> Refresh</button>
                </div>
                <div class="terminal" id="log-viewer">Loading...</div>
            </div>
        </div>

    </div>

    <!-- Toast Notification -->
    <div id="toast" class="toast">
        <i class="fas fa-check-circle"></i>
        <span id="toast-msg">Success</span>
    </div>

    <script>
        // --- CHARTS ---
        const chartOptions = {
            responsive: true,
            maintainAspectRatio: false, // Critical for fitting in container
            plugins: { legend: { display: false } },
            scales: { 
                x: { display: false }, 
                y: { display: false, min: 0 } 
            },
            elements: { 
                point: { radius: 0 }, 
                line: { tension: 0.4, borderWidth: 2 } 
            },
            animation: { duration: 0 } // Disable animation for performance
        };

        function createChart(id, color) {
            return new Chart(document.getElementById(id).getContext('2d'), {
                type: 'line',
                data: { 
                    labels: Array(20).fill(''), 
                    datasets: [{ 
                        data: Array(20).fill(0), 
                        borderColor: color, 
                        backgroundColor: color + '20', 
                        fill: true 
                    }] 
                },
                options: chartOptions
            });
        }

        const cpuChart = createChart('cpuChart', '#3b82f6');
        const memChart = createChart('memChart', '#10b981');
        const netChart = createChart('netChart', '#f59e0b');

        // --- NAVIGATION ---
        function loadPage(page) {
            document.querySelectorAll('.page').forEach(el => el.style.display = 'none');
            document.getElementById('page-' + page).style.display = 'block';
            document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
            event.currentTarget.classList.add('active');
            
            if(page === 'containers') refreshContainers();
            if(page === 'services') refreshServices();
            if(page === 'security') refreshSecurity();
            if(page === 'backups') refreshBackups();
            if(page === 'logs') refreshLogs();
        }

        // --- DATA FETCHING ---
        function updateStats() {
            fetch('/api/stats').then(r => r.json()).then(data => {
                // Update Text
                document.getElementById('hostname').textContent = data.hostname;
                document.getElementById('os-info').textContent = data.os;
                document.getElementById('cpu-val').textContent = data.cpu + '%';
                document.getElementById('mem-val').textContent = data.mem.percent + '%';
                document.getElementById('mem-detail').textContent = `${data.mem.used} / ${data.mem.total} GB`;
                document.getElementById('disk-val').textContent = data.disk.percent + '%';
                document.getElementById('disk-detail').textContent = `${data.disk.free} GB Free`;
                document.getElementById('disk-bar').style.width = data.disk.percent + '%';
                document.getElementById('net-val').textContent = data.net.speed;
                document.getElementById('net-total').textContent = data.net.total;

                // Update Charts
                [cpuChart, memChart, netChart].forEach(chart => {
                    chart.data.datasets[0].data.shift();
                });
                cpuChart.data.datasets[0].data.push(data.cpu);
                memChart.data.datasets[0].data.push(data.mem.percent);
                netChart.data.datasets[0].data.push(data.net.speed_raw);
                [cpuChart, memChart, netChart].forEach(c => c.update());
            });
        }

        function refreshContainers() {
            fetch('/api/containers').then(r => r.json()).then(data => {
                const html = data.containers.map(c => `
                    <tr>
                        <td><strong>${c.name}</strong></td>
                        <td style="color:var(--text-secondary)">${c.image}</td>
                        <td><span class="badge ${c.status.includes('Up') ? 'badge-success' : 'badge-danger'}">${c.status}</span></td>
                        <td style="font-size:12px">${c.ports}</td>
                        <td>
                            <button class="btn btn-sm btn-primary" onclick="dockerAction('${c.name}', 'restart')"><i class="fas fa-sync"></i></button>
                            <button class="btn btn-sm ${c.status.includes('Up') ? 'btn-danger' : 'btn-success'}" 
                                onclick="dockerAction('${c.name}', '${c.status.includes('Up') ? 'stop' : 'start'}')">
                                <i class="fas fa-${c.status.includes('Up') ? 'stop' : 'play'}"></i>
                            </button>
                        </td>
                    </tr>
                `).join('');
                document.querySelector('#container-table tbody').innerHTML = html;
                // Update dashboard mini-table too
                document.getElementById('dash-containers').innerHTML = html.split('</tr>').slice(0, 5).join('</tr>');
            });
        }

        function refreshServices() {
            fetch('/api/services').then(r => r.json()).then(data => {
                const html = data.services.map(s => `
                    <div class="card" style="padding:15px">
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
                document.getElementById('services-grid').innerHTML = html;
            });
        }

        function refreshSecurity() {
            fetch('/api/security').then(r => r.json()).then(data => {
                // UFW
                document.querySelector('#ufw-table tbody').innerHTML = data.ufw.map(r => `
                    <tr><td>${r.to}</td><td><span class="badge ${r.action=='ALLOW'?'badge-success':'badge-danger'}">${r.action}</span></td><td>${r.from}</td></tr>
                `).join('');
                
                // Fail2Ban
                document.querySelector('#f2b-table tbody').innerHTML = data.fail2ban.map(j => `
                    <tr><td>${j.name}</td><td>${j.count}</td><td><button class="btn btn-sm btn-warning">Unban All</button></td></tr>
                `).join('');
            });
        }

        function refreshBackups() {
            fetch('/api/backups').then(r => r.json()).then(data => {
                document.querySelector('#backup-table tbody').innerHTML = data.backups.map(b => `
                    <tr>
                        <td>${b.name}</td>
                        <td>${b.size}</td>
                        <td>${b.date}</td>
                        <td>
                            <a href="/api/download/backup/${b.name}" class="btn btn-sm btn-primary" target="_blank"><i class="fas fa-download"></i></a>
                            <button class="btn btn-sm btn-danger" onclick="deleteBackup('${b.name}')"><i class="fas fa-trash"></i></button>
                        </td>
                    </tr>
                `).join('');
            });
        }

        function refreshLogs() {
            fetch('/api/logs').then(r => r.json()).then(data => {
                document.getElementById('log-viewer').textContent = data.logs;
            });
        }

        // --- ACTIONS ---
        function dockerAction(name, action) {
            showToast(`Docker: ${action} ${name}...`, 'info');
            fetch(`/api/docker/${action}/${name}`, {method:'POST'}).then(r=>r.json()).then(res => {
                if(res.success) { showToast('Success', 'success'); refreshContainers(); }
                else showToast('Failed', 'error');
            });
        }

        function serviceAction(name, action) {
            showToast(`Service: ${action} ${name}...`, 'info');
            fetch(`/api/service/${action}/${name}`, {method:'POST'}).then(r=>r.json()).then(res => {
                if(res.success) { showToast('Success', 'success'); refreshServices(); }
                else showToast('Failed', 'error');
            });
        }

        function runCmd(cmd) {
            document.getElementById('quick-output').textContent = "Running...";
            fetch('/api/command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({command: cmd})
            }).then(r=>r.json()).then(data => {
                document.getElementById('quick-output').textContent = data.output;
                if(cmd.includes('backup')) refreshBackups();
            });
        }

        function showToast(msg, type='success') {
            const t = document.getElementById('toast');
            t.innerHTML = `<i class="fas fa-${type=='success'?'check-circle':'exclamation-circle'}"></i> ${msg}`;
            t.className = `toast show toast-${type}`;
            setTimeout(() => t.classList.remove('show'), 3000);
        }

        // Init
        setInterval(updateStats, 2000);
        updateStats();
        refreshContainers();
    </script>
</body>
</html>
"""

# --- API ENDPOINTS ---

@app.route('/')
def index(): return render_template_string(HTML_TEMPLATE)

@app.route('/api/stats')
def stats():
    # CPU
    cpu = psutil.cpu_percent(interval=None)
    
    # Memory
    mem = psutil.virtual_memory()
    
    # Disk
    disk = psutil.disk_usage('/')
    
    # Network
    net = psutil.net_io_counters()
    
    return jsonify({
        'hostname': os.uname()[1],
        'os': f"{os.uname()[0]} {os.uname()[2]}",
        'cpu': cpu,
        'mem': {
            'percent': mem.percent,
            'used': round(mem.used / (1024**3), 1),
            'total': round(mem.total / (1024**3), 1)
        },
        'disk': {
            'percent': disk.percent,
            'free': round(disk.free / (1024**3), 1)
        },
        'net': {
            'speed': "0 KB/s", # Needs state tracking for real speed
            'speed_raw': 0,
            'total': f"{round((net.bytes_sent + net.bytes_recv) / (1024**3), 2)} GB"
        }
    })

@app.route('/api/containers')
def containers():
    try:
        cmd = "docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}'"
        out = subprocess.check_output(cmd, shell=True).decode()
        data = []
        for line in out.strip().split('\n'):
            if line:
                p = line.split('|')
                data.append({'name':p[0], 'image':p[1], 'status':p[2], 'ports':p[3]})
        return jsonify({'containers': data})
    except: return jsonify({'containers': []})

@app.route('/api/docker/<action>/<name>', methods=['POST'])
def docker_ctrl(action, name):
    if action not in ['start', 'stop', 'restart']: return jsonify({'success':False}), 400
    try:
        subprocess.check_call(f"docker {action} {name}", shell=True)
        return jsonify({'success':True})
    except: return jsonify({'success':False})

@app.route('/api/services')
def services():
    # List of services to monitor
    svcs = ['nginx', 'mysql', 'postgresql', 'redis-server', 'ufw', 'ssh', 'cron']
    data = []
    for s in svcs:
        active = subprocess.call(f"systemctl is-active --quiet {s}", shell=True) == 0
        data.append({'name': s, 'active': active})
    return jsonify({'services': data})

@app.route('/api/service/<action>/<name>', methods=['POST'])
def service_ctrl(action, name):
    if action not in ['start', 'stop', 'restart']: return jsonify({'success':False}), 400
    try:
        subprocess.check_call(f"systemctl {action} {name}", shell=True)
        return jsonify({'success':True})
    except: return jsonify({'success':False})

@app.route('/api/security')
def security():
    # UFW
    try:
        ufw_out = subprocess.check_output("ufw status", shell=True).decode()
        ufw_rules = []
        for line in ufw_out.split('\n'):
            if 'ALLOW' in line or 'DENY' in line:
                parts = line.split()
                ufw_rules.append({'to': parts[0], 'action': parts[1], 'from': parts[2] if len(parts)>2 else 'Anywhere'})
    except: ufw_rules = []
    
    # Fail2Ban
    f2b_jails = []
    try:
        if subprocess.call("command -v fail2ban-client", shell=True) == 0:
            jails = subprocess.check_output("fail2ban-client status | grep 'Jail list' | sed 's/.*list://'", shell=True).decode().strip().split(',')
            for jail in jails:
                if jail:
                    count = subprocess.check_output(f"fail2ban-client status {jail} | grep 'Currently banned' | awk '{{print $4}}'", shell=True).decode().strip()
                    f2b_jails.append({'name': jail.strip(), 'count': count})
    except: pass
    
    return jsonify({'ufw': ufw_rules, 'fail2ban': f2b_jails})

@app.route('/api/backups')
def backups():
    try:
        files = []
        if os.path.exists(BACKUP_DIR):
            for f in os.listdir(BACKUP_DIR):
                if f.endswith('.tar.gz'):
                    path = os.path.join(BACKUP_DIR, f)
                    size = round(os.path.getsize(path) / (1024*1024), 2)
                    date = datetime.fromtimestamp(os.path.getmtime(path)).strftime('%Y-%m-%d %H:%M')
                    files.append({'name': f, 'size': f"{size} MB", 'date': date})
        return jsonify({'backups': sorted(files, key=lambda x: x['date'], reverse=True)})
    except: return jsonify({'backups': []})

@app.route('/api/download/backup/<filename>')
def download_backup(filename):
    return send_file(os.path.join(BACKUP_DIR, filename), as_attachment=True)

@app.route('/api/logs')
def logs():
    try:
        logs = subprocess.check_output(f"tail -n 100 {LOG_FILE}", shell=True).decode()
        return jsonify({'logs': logs})
    except: return jsonify({'logs': 'Error reading logs'})

@app.route('/api/command', methods=['POST'])
def command():
    cmd = request.json.get('command')
    if cmd not in ['status', 'backup create', 'metrics report', 'web stop']: return jsonify({'output': 'Forbidden'}), 403
    try:
        out = subprocess.check_output(f"/usr/local/bin/bdrman {cmd}", shell=True).decode()
        return jsonify({'output': out})
    except Exception as e: return jsonify({'output': str(e)})

if __name__ == '__main__':
    # Install psutil if missing
    try: import psutil
    except: 
        print("Installing psutil...")
        subprocess.call("pip3 install psutil", shell=True)
    
    app.run(host='0.0.0.0', port=8443)
