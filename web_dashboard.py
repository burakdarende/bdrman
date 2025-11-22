#!/usr/bin/env python3
"""
BDRman Advanced Web Dashboard v4.0
Features: Real-time metrics, Docker management, Command execution, Logs
"""

from flask import Flask, render_template_string, jsonify, request
import subprocess
import json
import os
import time
from datetime import datetime

app = Flask(__name__)

# HTML Template with Advanced UI
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>BDRman Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --primary: #667eea;
            --secondary: #764ba2;
            --bg: #f4f7f6;
            --card-bg: #ffffff;
            --text: #333;
            --success: #2ecc71;
            --danger: #e74c3c;
            --warning: #f1c40f;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
        }
        .sidebar {
            width: 250px;
            background: linear-gradient(180deg, var(--primary) 0%, var(--secondary) 100%);
            height: 100vh;
            position: fixed;
            color: white;
            padding: 20px;
        }
        .sidebar h2 { margin-bottom: 30px; font-size: 24px; }
        .nav-item {
            padding: 15px;
            cursor: pointer;
            border-radius: 8px;
            margin-bottom: 5px;
            transition: 0.3s;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .nav-item:hover, .nav-item.active {
            background: rgba(255,255,255,0.2);
        }
        .main-content {
            margin-left: 250px;
            padding: 30px;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: var(--card-bg);
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.05);
        }
        .stat-value { font-size: 28px; font-weight: bold; color: var(--primary); }
        .stat-label { color: #666; font-size: 14px; }
        
        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-weight: 500;
            transition: 0.2s;
            color: white;
        }
        .btn-primary { background: var(--primary); }
        .btn-success { background: var(--success); }
        .btn-danger { background: var(--danger); }
        .btn-warning { background: var(--warning); color: #333; }
        .btn:hover { opacity: 0.9; transform: translateY(-1px); }
        
        .container-list { list-style: none; }
        .container-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            border-bottom: 1px solid #eee;
        }
        .status-badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
        }
        .status-running { background: rgba(46, 204, 113, 0.2); color: var(--success); }
        .status-exited { background: rgba(231, 76, 60, 0.2); color: var(--danger); }
        
        .log-viewer {
            background: #1e1e1e;
            color: #00ff00;
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        
        .chart-container { height: 200px; margin-top: 15px; }
        
        /* Toast Notifications */
        .toast {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px 25px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
            display: flex;
            align-items: center;
            gap: 10px;
            transform: translateX(150%);
            transition: 0.3s;
            z-index: 1000;
        }
        .toast.show { transform: translateX(0); }
        .toast.success { border-left: 4px solid var(--success); }
        .toast.error { border-left: 4px solid var(--danger); }
        
        @media (max-width: 768px) {
            .sidebar { width: 70px; padding: 10px; }
            .sidebar h2, .nav-text { display: none; }
            .main-content { margin-left: 70px; }
        }
    </style>
</head>
<body>
    <div class="sidebar">
        <h2>🚀 BDRman</h2>
        <div class="nav-item active" onclick="showPage('dashboard')">
            <i class="fas fa-tachometer-alt"></i> <span class="nav-text">Dashboard</span>
        </div>
        <div class="nav-item" onclick="showPage('containers')">
            <i class="fas fa-box"></i> <span class="nav-text">Containers</span>
        </div>
        <div class="nav-item" onclick="showPage('logs')">
            <i class="fas fa-file-alt"></i> <span class="nav-text">Logs</span>
        </div>
        <div class="nav-item" onclick="showPage('terminal')">
            <i class="fas fa-terminal"></i> <span class="nav-text">Terminal</span>
        </div>
    </div>

    <div class="main-content">
        <div class="header">
            <div>
                <h1 id="page-title">Dashboard</h1>
                <p class="text-muted">Server: <strong id="hostname">Loading...</strong></p>
            </div>
            <div id="last-update">Updating...</div>
        </div>

        <!-- DASHBOARD PAGE -->
        <div id="page-dashboard">
            <div class="stats-grid">
                <div class="card">
                    <div class="stat-label">CPU Load</div>
                    <div class="stat-value" id="cpu-val">-</div>
                    <div class="chart-container">
                        <canvas id="cpuChart"></canvas>
                    </div>
                </div>
                <div class="card">
                    <div class="stat-label">Memory Usage</div>
                    <div class="stat-value" id="mem-val">-</div>
                    <div class="chart-container">
                        <canvas id="memChart"></canvas>
                    </div>
                </div>
                <div class="card">
                    <div class="stat-label">Disk Usage</div>
                    <div class="stat-value" id="disk-val">-</div>
                    <div class="progress-bar" style="margin-top: 20px; background: #eee; height: 10px; border-radius: 5px;">
                        <div id="disk-bar" style="width: 0%; height: 100%; background: var(--primary); border-radius: 5px;"></div>
                    </div>
                </div>
                <div class="card">
                    <div class="stat-label">Uptime</div>
                    <div class="stat-value" id="uptime-val" style="font-size: 20px;">-</div>
                </div>
            </div>
        </div>

        <!-- CONTAINERS PAGE -->
        <div id="page-containers" style="display: none;">
            <div class="card">
                <div style="display: flex; justify-content: space-between; margin-bottom: 20px;">
                    <h3>Docker Containers</h3>
                    <button class="btn btn-primary" onclick="refreshContainers()"><i class="fas fa-sync"></i> Refresh</button>
                </div>
                <div id="container-list">Loading...</div>
            </div>
        </div>

        <!-- LOGS PAGE -->
        <div id="page-logs" style="display: none;">
            <div class="card">
                <h3>System Logs</h3>
                <div class="log-viewer" id="log-content">Loading...</div>
            </div>
        </div>
        
        <!-- TERMINAL PAGE -->
        <div id="page-terminal" style="display: none;">
            <div class="card">
                <h3>Quick Commands</h3>
                <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                    <button class="btn btn-primary" onclick="runCommand('status')">System Status</button>
                    <button class="btn btn-success" onclick="runCommand('backup create')">Create Backup</button>
                    <button class="btn btn-warning" onclick="runCommand('metrics report')">Metrics Report</button>
                </div>
                <div class="log-viewer" id="cmd-output" style="height: 300px;">Output will appear here...</div>
            </div>
        </div>
    </div>

    <div id="toast" class="toast">
        <i class="fas fa-check-circle"></i>
        <span id="toast-msg">Operation successful</span>
    </div>

    <script>
        // Charts Setup
        const ctxCpu = document.getElementById('cpuChart').getContext('2d');
        const ctxMem = document.getElementById('memChart').getContext('2d');
        
        const commonOptions = {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: { y: { beginAtZero: true, max: 100 } }
        };

        const cpuChart = new Chart(ctxCpu, {
            type: 'line',
            data: { labels: [], datasets: [{ label: 'CPU %', data: [], borderColor: '#667eea', tension: 0.4, fill: true, backgroundColor: 'rgba(102, 126, 234, 0.1)' }] },
            options: commonOptions
        });

        const memChart = new Chart(ctxMem, {
            type: 'line',
            data: { labels: [], datasets: [{ label: 'RAM %', data: [], borderColor: '#764ba2', tension: 0.4, fill: true, backgroundColor: 'rgba(118, 75, 162, 0.1)' }] },
            options: commonOptions
        });

        // Navigation
        function showPage(pageId) {
            document.querySelectorAll('[id^="page-"]').forEach(el => el.style.display = 'none');
            document.getElementById('page-' + pageId).style.display = 'block';
            document.getElementById('page-title').textContent = pageId.charAt(0).toUpperCase() + pageId.slice(1);
            
            document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
            event.currentTarget.classList.add('active');
            
            if(pageId === 'containers') refreshContainers();
            if(pageId === 'logs') refreshLogs();
        }

        // Data Updates
        function updateStats() {
            fetch('/api/stats')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('hostname').textContent = data.hostname;
                    document.getElementById('cpu-val').textContent = data.cpu_load;
                    document.getElementById('mem-val').textContent = data.memory_percent + '%';
                    document.getElementById('disk-val').textContent = data.disk_percent + '%';
                    document.getElementById('uptime-val').textContent = data.uptime;
                    document.getElementById('disk-bar').style.width = data.disk_percent + '%';
                    
                    const time = new Date().toLocaleTimeString();
                    
                    // Update Charts
                    if(cpuChart.data.labels.length > 20) {
                        cpuChart.data.labels.shift();
                        cpuChart.data.datasets[0].data.shift();
                        memChart.data.labels.shift();
                        memChart.data.datasets[0].data.shift();
                    }
                    
                    cpuChart.data.labels.push(time);
                    cpuChart.data.datasets[0].data.push(parseFloat(data.cpu_load) * 10); // Approx load to %
                    cpuChart.update();
                    
                    memChart.data.labels.push(time);
                    memChart.data.datasets[0].data.push(data.memory_percent);
                    memChart.update();
                });
        }

        function refreshContainers() {
            fetch('/api/containers')
                .then(r => r.json())
                .then(data => {
                    const list = document.getElementById('container-list');
                    list.innerHTML = '';
                    data.containers.forEach(c => {
                        const statusClass = c.status.includes('Up') ? 'status-running' : 'status-exited';
                        const html = `
                            <div class="container-item">
                                <div>
                                    <strong>${c.name}</strong><br>
                                    <small class="text-muted">${c.image}</small>
                                </div>
                                <div style="display:flex; gap:10px; align-items:center;">
                                    <span class="status-badge ${statusClass}">${c.status}</span>
                                    <button class="btn btn-warning btn-sm" onclick="controlContainer('${c.name}', 'restart')"><i class="fas fa-sync"></i></button>
                                    <button class="btn btn-danger btn-sm" onclick="controlContainer('${c.name}', 'stop')"><i class="fas fa-stop"></i></button>
                                    <button class="btn btn-success btn-sm" onclick="controlContainer('${c.name}', 'start')"><i class="fas fa-play"></i></button>
                                </div>
                            </div>
                        `;
                        list.innerHTML += html;
                    });
                });
        }

        function controlContainer(name, action) {
            showToast('Processing ' + action + '...', 'info');
            fetch('/api/docker/' + action + '/' + name, { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if(data.success) {
                        showToast('Container ' + action + 'ed successfully', 'success');
                        refreshContainers();
                    } else {
                        showToast('Error: ' + data.error, 'error');
                    }
                });
        }
        
        function runCommand(cmd) {
            document.getElementById('cmd-output').textContent = 'Running...';
            fetch('/api/command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({command: cmd})
            })
            .then(r => r.json())
            .then(data => {
                document.getElementById('cmd-output').textContent = data.output;
            });
        }

        function refreshLogs() {
            fetch('/api/logs')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('log-content').textContent = data.logs;
                });
        }

        function showToast(msg, type) {
            const toast = document.getElementById('toast');
            document.getElementById('toast-msg').textContent = msg;
            toast.className = 'toast show ' + type;
            setTimeout(() => toast.classList.remove('show'), 3000);
        }

        // Auto update
        setInterval(updateStats, 2000);
        updateStats();
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/stats')
def api_stats():
    try:
        cpu = subprocess.check_output("uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ','", shell=True).decode().strip()
        mem = subprocess.check_output("free | awk '/^Mem:/ {printf \"%.0f\", ($3/$2)*100}'", shell=True).decode().strip()
        disk = subprocess.check_output("df / | awk 'NR==2 {print $5}' | tr -d '%'", shell=True).decode().strip()
        uptime = subprocess.check_output("uptime -p", shell=True).decode().strip()
        hostname = subprocess.check_output("hostname", shell=True).decode().strip()
        
        return jsonify({
            'cpu_load': cpu,
            'memory_percent': mem,
            'disk_percent': disk,
            'uptime': uptime,
            'hostname': hostname
        })
    except:
        return jsonify({'error': 'Stats failed'}), 500

@app.route('/api/containers')
def api_containers():
    try:
        cmd = "docker ps -a --format '{{.Names}}|{{.Status}}|{{.Image}}'"
        output = subprocess.check_output(cmd, shell=True).decode()
        containers = []
        for line in output.strip().split('\n'):
            if line:
                parts = line.split('|')
                if len(parts) >= 3:
                    containers.append({
                        'name': parts[0],
                        'status': parts[1],
                        'image': parts[2]
                    })
        return jsonify({'containers': containers})
    except:
        return jsonify({'containers': []})

@app.route('/api/docker/<action>/<name>', methods=['POST'])
def docker_control(action, name):
    if action not in ['start', 'stop', 'restart']:
        return jsonify({'success': False, 'error': 'Invalid action'}), 400
    
    try:
        subprocess.check_call(f"docker {action} {name}", shell=True)
        return jsonify({'success': True})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/logs')
def api_logs():
    try:
        logs = subprocess.check_output("tail -n 100 /var/log/bdrman.log 2>/dev/null || echo 'No logs'", shell=True).decode()
        return jsonify({'logs': logs})
    except:
        return jsonify({'logs': 'Error'})

@app.route('/api/command', methods=['POST'])
def run_command():
    data = request.json
    cmd = data.get('command')
    
    # Security whitelist
    allowed_commands = ['status', 'backup create', 'metrics report']
    if cmd not in allowed_commands:
        return jsonify({'output': 'Command not allowed'}), 403
        
    try:
        output = subprocess.check_output(f"/usr/local/bin/bdrman {cmd}", shell=True).decode()
        return jsonify({'output': output})
    except subprocess.CalledProcessError as e:
        return jsonify({'output': f"Error: {e.output.decode()}"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443)
