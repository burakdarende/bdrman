#!/usr/bin/env python3
"""
BDRman Web Dashboard
Lightweight web interface for server management
"""

from flask import Flask, render_template_string, jsonify, request
import subprocess
import json
import os
from datetime import datetime

app = Flask(__name__)

# HTML Template
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>BDRman Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 {
            color: #667eea;
            font-size: 28px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .stat-card {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .stat-card h3 {
            color: #666;
            font-size: 14px;
            margin-bottom: 10px;
        }
        .stat-value {
            font-size: 32px;
            font-weight: bold;
            color: #667eea;
        }
        .progress-bar {
            width: 100%;
            height: 8px;
            background: #e0e0e0;
            border-radius: 4px;
            margin-top: 10px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            transition: width 0.3s;
        }
        .content-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        .panel {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .panel h2 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 20px;
        }
        .container-list {
            list-style: none;
        }
        .container-item {
            padding: 10px;
            background: #f5f5f5;
            margin-bottom: 10px;
            border-radius: 5px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .status-badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
        }
        .status-running { background: #4caf50; color: white; }
        .status-stopped { background: #f44336; color: white; }
        button {
            background: #667eea;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }
        button:hover {
            background: #764ba2;
        }
        .log-viewer {
            background: #1e1e1e;
            color: #00ff00;
            padding: 15px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 400px;
            overflow-y: auto;
        }
        @media (max-width: 768px) {
            .content-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 BDRman Dashboard</h1>
            <p>Server: <strong id="hostname">Loading...</strong> | Last Update: <span id="last-update"></span></p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h3>CPU Load</h3>
                <div class="stat-value" id="cpu-load">-</div>
                <div class="progress-bar">
                    <div class="progress-fill" id="cpu-bar" style="width: 0%"></div>
                </div>
            </div>
            <div class="stat-card">
                <h3>Memory Usage</h3>
                <div class="stat-value" id="memory-usage">-</div>
                <div class="progress-bar">
                    <div class="progress-fill" id="memory-bar" style="width: 0%"></div>
                </div>
            </div>
            <div class="stat-card">
                <h3>Disk Usage</h3>
                <div class="stat-value" id="disk-usage">-</div>
                <div class="progress-bar">
                    <div class="progress-fill" id="disk-bar" style="width: 0%"></div>
                </div>
            </div>
            <div class="stat-card">
                <h3>Uptime</h3>
                <div class="stat-value" id="uptime">-</div>
            </div>
        </div>
        
        <div class="content-grid">
            <div class="panel">
                <h2>🐳 Docker Containers</h2>
                <ul class="container-list" id="container-list">
                    <li>Loading...</li>
                </ul>
            </div>
            
            <div class="panel">
                <h2>📊 System Logs</h2>
                <div class="log-viewer" id="logs">
                    Loading logs...
                </div>
            </div>
        </div>
    </div>
    
    <script>
        function updateStats() {
            fetch('/api/stats')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('hostname').textContent = data.hostname;
                    document.getElementById('cpu-load').textContent = data.cpu_load;
                    document.getElementById('memory-usage').textContent = data.memory_percent + '%';
                    document.getElementById('disk-usage').textContent = data.disk_percent + '%';
                    document.getElementById('uptime').textContent = data.uptime;
                    document.getElementById('last-update').textContent = new Date().toLocaleTimeString();
                    
                    document.getElementById('cpu-bar').style.width = (parseFloat(data.cpu_load) * 10) + '%';
                    document.getElementById('memory-bar').style.width = data.memory_percent + '%';
                    document.getElementById('disk-bar').style.width = data.disk_percent + '%';
                });
        }
        
        function updateContainers() {
            fetch('/api/containers')
                .then(r => r.json())
                .then(data => {
                    const list = document.getElementById('container-list');
                    list.innerHTML = '';
                    data.containers.forEach(c => {
                        const li = document.createElement('li');
                        li.className = 'container-item';
                        li.innerHTML = `
                            <span>${c.name}</span>
                            <span class="status-badge status-${c.status}">${c.status}</span>
                        `;
                        list.appendChild(li);
                    });
                });
        }
        
        function updateLogs() {
            fetch('/api/logs')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('logs').textContent = data.logs;
                });
        }
        
        // Update every 5 seconds
        setInterval(() => {
            updateStats();
            updateContainers();
            updateLogs();
        }, 5000);
        
        // Initial load
        updateStats();
        updateContainers();
        updateLogs();
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
        # CPU Load
        cpu_load = subprocess.check_output("uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ','", shell=True).decode().strip()
        
        # Memory
        mem_output = subprocess.check_output("free | awk '/^Mem:/ {printf \"%.0f\", ($3/$2)*100}'", shell=True).decode().strip()
        
        # Disk
        disk_output = subprocess.check_output("df / | awk 'NR==2 {print $5}' | tr -d '%'", shell=True).decode().strip()
        
        # Uptime
        uptime = subprocess.check_output("uptime -p", shell=True).decode().strip()
        
        # Hostname
        hostname = subprocess.check_output("hostname", shell=True).decode().strip()
        
        return jsonify({
            'cpu_load': cpu_load,
            'memory_percent': mem_output,
            'disk_percent': disk_output,
            'uptime': uptime,
            'hostname': hostname
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/containers')
def api_containers():
    try:
        output = subprocess.check_output("docker ps -a --format '{{.Names}}|{{.Status}}'", shell=True).decode()
        containers = []
        for line in output.strip().split('\n'):
            if line:
                name, status = line.split('|')
                containers.append({
                    'name': name,
                    'status': 'running' if 'Up' in status else 'stopped'
                })
        return jsonify({'containers': containers})
    except Exception as e:
        return jsonify({'containers': []})

@app.route('/api/logs')
def api_logs():
    try:
        logs = subprocess.check_output("tail -n 20 /var/log/bdrman.log 2>/dev/null || echo 'No logs available'", shell=True).decode()
        return jsonify({'logs': logs})
    except Exception as e:
        return jsonify({'logs': 'Error loading logs'})

if __name__ == '__main__':
    print("🌐 BDRman Dashboard starting on http://0.0.0.0:8443")
    print("⚠️  WARNING: This is a development server. Use a production WSGI server for production.")
    app.run(host='0.0.0.0', port=8443, debug=False)
