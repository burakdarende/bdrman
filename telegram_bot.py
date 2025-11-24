#!/usr/bin/env python3
"""
BDRman Ultimate Telegram Bot - Enterprise Edition
Comprehensive server management with 30+ commands
"""
import os
import sys
import logging
import subprocess
import psutil
import re
from datetime import datetime
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, ConversationHandler, MessageHandler, filters

# Configuration
CONFIG_FILE = "/etc/bdrman/telegram.conf"
LOG_FILE = "/var/log/bdrman-bot.log"

# Logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Globals
BOT_TOKEN = ""
CHAT_ID = ""
PIN_CODE = "1234"
SERVER_NAME = ""
COMMANDS = []

def register_command(command, description, category):
    COMMANDS.append({"cmd": command, "desc": description, "cat": category})

def load_config():
    global BOT_TOKEN, CHAT_ID, PIN_CODE, SERVER_NAME
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if line.startswith("BOT_TOKEN="):
                    BOT_TOKEN = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("CHAT_ID="):
                    CHAT_ID = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("PIN_CODE="):
                    PIN_CODE = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("SERVER_NAME="):
                    SERVER_NAME = line.split("=", 1)[1].strip().strip('"')
        if not SERVER_NAME:
            SERVER_NAME = subprocess.check_output("hostname", shell=True).decode().strip()
    except Exception as e:
        logger.error(f"Config error: {e}")
        sys.exit(1)

def check_auth(update: Update) -> bool:
    user_id = str(update.effective_user.id)
    if user_id != CHAT_ID:
        logger.warning(f"Unauthorized: {user_id}")
        return False
    return True

def run_cmd(cmd, timeout=30):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        output = result.stdout if result.stdout else result.stderr
        return output.strip() if output else "✅ Done"
    except subprocess.TimeoutExpired:
        return "⏱️ Timeout"
    except Exception as e:
        return f"❌ Error: {str(e)}"

def get_bar(percent):
    filled = int(percent / 10)
    return "▓" * filled + "░" * (10 - filled)

def colorize_log_line(line):
    """Add emoji indicators to log lines based on level"""
    if "ERROR" in line or "error" in line.lower():
        return f"🔴 {line}"
    elif "WARN" in line or "warning" in line.lower():
        return f"🟡 {line}"
    elif "INFO" in line or "info" in line.lower():
        return f"🔵 {line}"
    elif "DEBUG" in line:
        return f"⚪ {line}"
    else:
        return f"⚫ {line}"

# === COMMAND HANDLERS ===

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text(
        f"🤖 *BDRman Enterprise Bot*\n"
        f"🖥️ Server: `{SERVER_NAME}`\n\n"
        f"Use /help to see 30+ commands",
        parse_mode='Markdown'
    )

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    cats = {}
    for c in COMMANDS:
        if c['cat'] not in cats:
            cats[c['cat']] = []
        cats[c['cat']].append(c)
    
    msg = f"🤖 *BDRman Commands*\n🖥️ `{SERVER_NAME}`\n\n"
    for cat, cmds in sorted(cats.items()):
        msg += f"*{cat}*\n"
        for c in cmds:
            msg += f"/{c['cmd']} - {c['desc']}\n"
        msg += "\n"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("📊 Collecting data...")
    
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    uptime = run_cmd("uptime -p")
    load = os.getloadavg()
    
    # Colored logs
    logs_raw = run_cmd("journalctl -n 10 --no-pager -o short")
    logs_lines = logs_raw.split('\n')[:10]
    logs_colored = '\n'.join([colorize_log_line(line) for line in logs_lines])
    
    if len(logs_colored) > 1500:
        logs_colored = logs_colored[-1500:]
    
    msg = (
        f"📊 *System Status - {SERVER_NAME}*\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"⏱️ *Uptime:* `{uptime}`\n"
        f"📈 *Load:* `{load[0]:.2f}, {load[1]:.2f}, {load[2]:.2f}`\n\n"
        f"🖥️ *CPU:* {cpu}% {get_bar(cpu)}\n"
        f"🧠 *RAM:* {mem.percent}% {get_bar(mem.percent)}\n"
        f"   `{mem.used//1024//1024//1024}GB / {mem.total//1024//1024//1024}GB`\n"
        f"💾 *Disk:* {disk.percent}% {get_bar(disk.percent)}\n"
        f"   `{disk.free//1024//1024//1024}GB free`\n\n"
        f"📜 *Recent Logs (Colored)*\n"
        f"{logs_colored}"
    )
    await update.message.reply_text(msg, parse_mode='Markdown')

async def health_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    msg = f"🏥 *Health Check - {SERVER_NAME}*\n\n"
    
    # Check critical services
    services = {
        "docker": "Docker Engine",
        "nginx": "Web Server",
        "ssh": "SSH Server",
        "ufw": "Firewall"
    }
    
    all_ok = True
    for svc, name in services.items():
        status = run_cmd(f"systemctl is-active {svc} 2>/dev/null || echo inactive")
        if "active" in status:
            msg += f"✅ {name}\n"
        else:
            msg += f"❌ {name} (DOWN)\n"
            all_ok = False
    
    # Resource checks
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    msg += f"\n📊 *Resources*\n"
    msg += f"CPU: {cpu}% {'✅' if cpu < 80 else '⚠️' if cpu < 95 else '🔴'}\n"
    msg += f"RAM: {mem.percent}% {'✅' if mem.percent < 80 else '⚠️' if mem.percent < 95 else '🔴'}\n"
    msg += f"Disk: {disk.percent}% {'✅' if disk.percent < 80 else '⚠️' if disk.percent < 95 else '🔴'}\n"
    
    # Overall status
    msg += f"\n{'✅ *System Healthy*' if all_ok and cpu < 80 and mem.percent < 80 and disk.percent < 80 else '⚠️ *Issues Detected*'}"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def docker_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    out = run_cmd("docker ps -a --format '{{.Names}}|{{.Status}}'")
    if "Error" in out or not out:
        await update.message.reply_text(f"❌ {out}")
        return
    
    lines = [l for l in out.split('\n') if l]
    msg = f"🐳 *Docker ({len(lines)})*\n\n"
    for line in lines[:20]:
        parts = line.split('|')
        if len(parts) == 2:
            name, status = parts
            icon = "🟢" if "Up" in status else "🔴"
            msg += f"{icon} `{name}`\n"
    await update.message.reply_text(msg, parse_mode='Markdown')

async def logs_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /logs <container>")
        return
    name = context.args[0]
    logs = run_cmd(f"docker logs --tail 50 {name} 2>&1")
    if len(logs) > 3500:
        logs = logs[-3500:]
    await update.message.reply_text(f"📜 *{name}*\n```\n{logs}\n```", parse_mode='Markdown')

async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /restart <container>")
        return
    name = context.args[0]
    await update.message.reply_text(f"🔄 Restarting `{name}`...")
    res = run_cmd(f"docker restart {name}")
    await update.message.reply_text(f"✅ {res}")

async def top_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    top = run_cmd("ps aux --sort=-%cpu | head -n 11")
    await update.message.reply_text(f"📊 *Top Processes*\n```\n{top}\n```", parse_mode='Markdown')

async def mem_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    top = run_cmd("ps aux --sort=-%mem | head -n 11")
    await update.message.reply_text(f"🧠 *Memory Hogs*\n```\n{top}\n```", parse_mode='Markdown')

async def disk_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    df = run_cmd("df -h")
    await update.message.reply_text(f"💾 *Disk Usage*\n```\n{df}\n```", parse_mode='Markdown')

async def network_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    # Network stats
    connections = run_cmd("netstat -an | grep ESTABLISHED | wc -l")
    listening = run_cmd("netstat -tuln | grep LISTEN | wc -l")
    ip = run_cmd("hostname -I | awk '{print $1}'")
    
    msg = (
        f"🌐 *Network Status*\n\n"
        f"🔌 Active Connections: `{connections}`\n"
        f"👂 Listening Ports: `{listening}`\n"
        f"🌍 IP Address: `{ip}`\n"
    )
    await update.message.reply_text(msg, parse_mode='Markdown')

async def ports_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    ports = run_cmd("netstat -tuln | grep LISTEN")
    await update.message.reply_text(f"👂 *Listening Ports*\n```\n{ports}\n```", parse_mode='Markdown')

async def ssl_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /ssl <domain>")
        return
    
    domain = context.args[0]
    # Check SSL expiry
    expiry = run_cmd(f"echo | openssl s_client -servername {domain} -connect {domain}:443 2>/dev/null | openssl x509 -noout -dates")
    await update.message.reply_text(f"🔒 *SSL: {domain}*\n```\n{expiry}\n```", parse_mode='Markdown')

async def ping_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /ping <host>")
        return
    host = context.args[0]
    ping = run_cmd(f"ping -c 4 {host}")
    await update.message.reply_text(f"🏓 *Ping {host}*\n```\n{ping}\n```", parse_mode='Markdown')

async def dns_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /dns <domain>")
        return
    domain = context.args[0]
    dns = run_cmd(f"nslookup {domain}")
    await update.message.reply_text(f"🔍 *DNS: {domain}*\n```\n{dns}\n```", parse_mode='Markdown')

async def vpn_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /vpn <username>")
        return
    user = context.args[0]
    if not user.isalnum():
        await update.message.reply_text("❌ Alphanumeric only")
        return
    await update.message.reply_text(f"🔐 Creating VPN: `{user}`...")
    res = run_cmd(f"echo '{user}' | /usr/local/bin/bdrman vpn add", timeout=60)
    await update.message.reply_text(f"```\n{res}\n```", parse_mode='Markdown')

async def backup_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("💾 Starting backup...")
    subprocess.Popen(["/usr/local/bin/bdrman", "backup", "create"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    await update.message.reply_text("✅ Backup started in background")

async def update_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🔄 Updating system...")
    res = run_cmd("apt update && apt upgrade -y", timeout=300)
    await update.message.reply_text("✅ Updated")

async def block_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /block <ip>")
        return
    ip = context.args[0]
    run_cmd(f"ufw deny from {ip}")
    await update.message.reply_text(f"🚫 Blocked: `{ip}`", parse_mode='Markdown')

async def unblock_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /unblock <ip>")
        return
    ip = context.args[0]
    run_cmd(f"ufw delete deny from {ip}")
    await update.message.reply_text(f"✅ Unblocked: `{ip}`", parse_mode='Markdown')

async def panic_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("⚠️ Usage: /panic <your_ip>")
        return
    ip = context.args[0]
    await update.message.reply_text(f"🚨 PANIC MODE for {ip}...")
    cmds = ["ufw --force reset", "ufw default deny incoming", "ufw default allow outgoing", f"ufw allow from {ip} to any port 22", "ufw --force enable"]
    for cmd in cmds:
        run_cmd(cmd)
    await update.message.reply_text("✅ PANIC MODE ACTIVE")

async def unpanic_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🟢 Deactivating...")
    cmds = ["ufw --force reset", "ufw default deny incoming", "ufw default allow outgoing", "ufw allow ssh", "ufw allow 80/tcp", "ufw allow 443/tcp", "ufw --force enable"]
    for cmd in cmds:
        run_cmd(cmd)
    await update.message.reply_text("✅ Normal mode")

async def firewall_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    status = run_cmd("ufw status numbered")
    await update.message.reply_text(f"🛡️ *Firewall*\n```\n{status}\n```", parse_mode='Markdown')

async def services_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    failed = run_cmd("systemctl --failed --no-pager --no-legend")
    if not failed or "0 loaded" in failed:
        await update.message.reply_text("✅ All services OK")
    else:
        await update.message.reply_text(f"⚠️ *Failed*\n```\n{failed}\n```", parse_mode='Markdown')

async def reboot_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("⚠️ Rebooting in 10 seconds...")
    run_cmd("shutdown -r +1")
    await update.message.reply_text("✅ Reboot scheduled")

async def uptime_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    uptime = run_cmd("uptime -p")
    since = run_cmd("uptime -s")
    await update.message.reply_text(f"⏱️ *Uptime*\n{uptime}\nSince: `{since}`", parse_mode='Markdown')

async def kernel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    kernel = run_cmd("uname -a")
    await update.message.reply_text(f"🐧 *Kernel*\n```\n{kernel}\n```", parse_mode='Markdown')

async def users_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    users = run_cmd("who")
    await update.message.reply_text(f"👥 *Logged Users*\n```\n{users}\n```", parse_mode='Markdown')

async def last_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    last = run_cmd("last -n 10")
    await update.message.reply_text(f"🔑 *Last Logins*\n```\n{last}\n```", parse_mode='Markdown')

async def speedtest_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🚀 Running speedtest...")
    speed = run_cmd("speedtest-cli --simple 2>/dev/null || echo 'Install: apt install speedtest-cli'", timeout=60)
    await update.message.reply_text(f"📊 *Speed Test*\n```\n{speed}\n```", parse_mode='Markdown')

async def cert_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    certs = run_cmd("certbot certificates 2>/dev/null || echo 'Certbot not installed'")
    await update.message.reply_text(f"🔒 *SSL Certificates*\n```\n{certs}\n```", parse_mode='Markdown')

async def nginx_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    status = run_cmd("systemctl status nginx --no-pager -l")
    await update.message.reply_text(f"🌐 *Nginx*\n```\n{status}\n```", parse_mode='Markdown')

async def alerts_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    msg = "🚨 *System Alerts*\n\n"
    
    # Check high CPU
    cpu = psutil.cpu_percent(interval=1)
    if cpu > 80:
        msg += f"🔴 High CPU: {cpu}%\n"
    
    # Check high memory
    mem = psutil.virtual_memory()
    if mem.percent > 80:
        msg += f"🔴 High RAM: {mem.percent}%\n"
    
    # Check disk
    disk = psutil.disk_usage('/')
    if disk.percent > 80:
        msg += f"🔴 Low Disk: {disk.percent}% used\n"
    
    # Check failed services
    failed = run_cmd("systemctl --failed --no-pager --no-legend | wc -l")
    if int(failed) > 0:
        msg += f"🔴 {failed} failed services\n"
    
    if msg == "🚨 *System Alerts*\n\n":
        msg += "✅ No alerts"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

# PIN Protected
PIN_STATE = 1

async def pin_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return ConversationHandler.END
    context.user_data['cmd'] = update.message.text.split()[0]
    await update.message.reply_text("🔒 Enter PIN:")
    return PIN_STATE

async def pin_verify(update: Update, context: ContextTypes.DEFAULT_TYPE):
    pin = update.message.text.strip()
    if pin == PIN_CODE:
        cmd = context.user_data.get('cmd')
        await update.message.reply_text("✅ PIN OK")
        
        if cmd == '/snapshot':
            await update.message.reply_text("📸 Creating snapshot...")
            subprocess.Popen(["rsync", "-aAX", "--delete", "/", "/var/snapshots/emergency/"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            await update.message.reply_text("✅ Snapshot started")
        
        return ConversationHandler.END
    else:
        await update.message.reply_text("❌ Wrong PIN")
        return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("🚫 Cancelled")
    return ConversationHandler.END

def main():
    load_config()
    if not BOT_TOKEN:
        print("❌ BOT_TOKEN missing")
        sys.exit(1)
    
    # Register commands
    register_command("start", "Start bot", "📌 General")
    register_command("help", "Show all commands", "📌 General")
    register_command("status", "System status + colored logs", "📊 Monitoring")
    register_command("health", "Health check", "📊 Monitoring")
    register_command("alerts", "Active alerts", "📊 Monitoring")
    register_command("top", "Top CPU processes", "📊 Monitoring")
    register_command("mem", "Memory usage", "📊 Monitoring")
    register_command("disk", "Disk usage", "📊 Monitoring")
    register_command("uptime", "System uptime", "📊 Monitoring")
    register_command("users", "Logged users", "📊 Monitoring")
    register_command("last", "Last logins", "📊 Monitoring")
    
    register_command("docker", "List containers", "🐳 Docker")
    register_command("logs", "Container logs", "🐳 Docker")
    register_command("restart", "Restart container", "🐳 Docker")
    
    register_command("network", "Network stats", "🌐 Network")
    register_command("ports", "Listening ports", "🌐 Network")
    register_command("ping", "Ping host", "🌐 Network")
    register_command("dns", "DNS lookup", "🌐 Network")
    register_command("speedtest", "Internet speed", "🌐 Network")
    
    register_command("ssl", "Check SSL cert", "🔒 SSL")
    register_command("cert", "List certificates", "🔒 SSL")
    
    register_command("firewall", "Firewall status", "🛡️ Security")
    register_command("block", "Block IP", "🛡️ Security")
    register_command("unblock", "Unblock IP", "🛡️ Security")
    register_command("panic", "Panic mode", "🛡️ Security")
    register_command("unpanic", "Exit panic", "🛡️ Security")
    
    register_command("vpn", "Create VPN user", "🔧 Management")
    register_command("backup", "Create backup", "🔧 Management")
    register_command("update", "System update", "🔧 Management")
    register_command("services", "Failed services", "🔧 Management")
    register_command("nginx", "Nginx status", "🔧 Management")
    register_command("kernel", "Kernel info", "🔧 Management")
    register_command("reboot", "Reboot server", "🔧 Management")
    
    register_command("snapshot", "Snapshot (PIN)", "🚨 Critical")
    
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    
    # Add all handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("health", health_cmd))
    app.add_handler(CommandHandler("alerts", alerts_cmd))
    app.add_handler(CommandHandler("top", top_cmd))
    app.add_handler(CommandHandler("mem", mem_cmd))
    app.add_handler(CommandHandler("disk", disk_cmd))
    app.add_handler(CommandHandler("uptime", uptime_cmd))
    app.add_handler(CommandHandler("users", users_cmd))
    app.add_handler(CommandHandler("last", last_cmd))
    app.add_handler(CommandHandler("docker", docker_list))
    app.add_handler(CommandHandler("logs", logs_cmd))
    app.add_handler(CommandHandler("restart", restart_cmd))
    app.add_handler(CommandHandler("network", network_cmd))
    app.add_handler(CommandHandler("ports", ports_cmd))
    app.add_handler(CommandHandler("ping", ping_cmd))
    app.add_handler(CommandHandler("dns", dns_cmd))
    app.add_handler(CommandHandler("speedtest", speedtest_cmd))
    app.add_handler(CommandHandler("ssl", ssl_cmd))
    app.add_handler(CommandHandler("cert", cert_cmd))
    app.add_handler(CommandHandler("firewall", firewall_cmd))
    app.add_handler(CommandHandler("block", block_cmd))
    app.add_handler(CommandHandler("unblock", unblock_cmd))
    app.add_handler(CommandHandler("panic", panic_cmd))
    app.add_handler(CommandHandler("unpanic", unpanic_cmd))
    app.add_handler(CommandHandler("vpn", vpn_cmd))
    app.add_handler(CommandHandler("backup", backup_cmd))
    app.add_handler(CommandHandler("update", update_cmd))
    app.add_handler(CommandHandler("services", services_cmd))
    app.add_handler(CommandHandler("nginx", nginx_cmd))
    app.add_handler(CommandHandler("kernel", kernel_cmd))
    app.add_handler(CommandHandler("reboot", reboot_cmd))
    
    # PIN conversation
    conv = ConversationHandler(
        entry_points=[CommandHandler("snapshot", pin_request)],
        states={PIN_STATE: [MessageHandler(filters.TEXT & ~filters.COMMAND, pin_verify)]},
        fallbacks=[CommandHandler("cancel", cancel)]
    )
    app.add_handler(conv)
    
    logger.info(f"Bot started: {SERVER_NAME}")
    print(f"🤖 Enterprise Bot running for {SERVER_NAME}")
    print(f"📊 {len(COMMANDS)} commands registered")
    app.run_polling()

if __name__ == '__main__':
    main()
