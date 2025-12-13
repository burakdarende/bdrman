#!/usr/bin/env python3
"""
BDRman Ultimate Telegram Bot v4.8.1
Enterprise server management via Telegram
"""
import os
import sys
import logging
import subprocess
import psutil
import shlex
from datetime import datetime
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, ConversationHandler, MessageHandler, filters

# Configuration
CONFIG_FILE = "/etc/bdrman/telegram.conf"
LOG_FILE = "/var/log/bdrman-bot.log"

# Read version from bdrman script - NO FALLBACK!
def get_version():
    try:
        with open('/usr/local/bin/bdrman', 'r') as f:
            for line in f:
                if line.startswith('VERSION='):
                    return line.split('=')[1].strip().strip('"')
    except Exception as e:
        logger.error(f"Cannot read version from bdrman: {e}")
    # If we can't read version, something is seriously wrong
    return "UNKNOWN"

VERSION = get_version()

# Logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Globals
BOT_TOKEN = ""
CHAT_ID = ""
PIN_CODE = "1234"
SERVER_NAME = ""
COMMANDS = []

def register_command(cmd, desc, cat):
    COMMANDS.append({"cmd": cmd, "desc": desc, "cat": cat})

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

def colorize_log(line):
    if "ERROR" in line or "error" in line.lower():
        return f"🔴 {line}"
    elif "WARN" in line or "warning" in line.lower():
        return f"🟡 {line}"
    elif "INFO" in line or "info" in line.lower():
        return f"🔵 {line}"
    elif "DEBUG" in line:
        return f"⚪ {line}"
    return f"⚫ {line}"

# === HANDLERS ===

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text(
        f"🤖 *BDRman v{VERSION}*\n🖥️ `{SERVER_NAME}`\n\nUse /help for commands",
        parse_mode='Markdown'
    )

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    cats = {}
    for c in COMMANDS:
        if c['cat'] not in cats:
            cats[c['cat']] = []
        cats[c['cat']].append(c)
    
    msg = f"🤖 *BDRman v{VERSION}*\n `{SERVER_NAME}`\n\n"
    for cat, cmds in sorted(cats.items()):
        msg += f"*{cat}*\n"
        for c in cmds:
            msg += f"/{c['cmd']} - {c['desc']}\n"
        msg += "\n"
    await update.message.reply_text(msg, parse_mode='Markdown')

async def version_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    os_info = run_cmd("lsb_release -d | cut -f2")
    kernel = run_cmd("uname -r")
    msg = (
        f"📦 *Version Info*\n\n"
        f"🤖 BDRman: `v{VERSION}`\n"
        f"🐧 OS: `{os_info}`\n"
        f"⚙️ Kernel: `{kernel}`\n"
        f"💻 Server: `{SERVER_NAME}`"
    )
    await update.message.reply_text(msg, parse_mode='Markdown')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    try:
        await update.message.reply_text("📊 Collecting...")
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        uptime = run_cmd("uptime -p")
        load = os.getloadavg()
        
        msg1 = (
            f"📊 *{SERVER_NAME}*\n"
            f"⚙️ BDRman v{VERSION}\n"
            f"━━━━━━━━━━━━━━━━━━\n\n"
            f"⏱️ Uptime: `{uptime}`\n"
            f"📈 Load: `{load[0]:.2f}, {load[1]:.2f}, {load[2]:.2f}`\n\n"
            f"🖥️ CPU: {cpu}% {get_bar(cpu)}\n"
            f"🧠 RAM: {mem.percent}% {get_bar(mem.percent)}\n"
            f"   `{mem.used//1024//1024//1024}GB / {mem.total//1024//1024//1024}GB`\n"
            f"💾 Disk: {disk.percent}% {get_bar(disk.percent)}\n"
            f"   `{disk.free//1024//1024//1024}GB free`"
        )
        await update.message.reply_text(msg1, parse_mode='Markdown')
        
        logs_raw = run_cmd("journalctl -n 10 --no-pager -o short")
        logs_lines = logs_raw.split('\n')[:10]
        msg2 = "📜 *Recent Logs*\n\n"
        for line in logs_lines:
            if line.strip():
                msg2 += colorize_log(line[:100]) + "\n"
        if len(msg2) > 4000:
            msg2 = msg2[:4000] + "\n..."
        await update.message.reply_text(msg2)
    except Exception as e:
        logger.error(f"Status error: {e}")
        await update.message.reply_text(f"❌ Error: {str(e)}")

async def health_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    msg = f"🏥 *Health - {SERVER_NAME}*\n\n"
    services = {"docker": "Docker", "nginx": "Nginx", "ssh": "SSH", "ufw": "Firewall"}
    all_ok = True
    for svc, name in services.items():
        status = run_cmd(f"systemctl is-active {svc} 2>/dev/null || echo inactive")
        if "active" in status:
            msg += f"✅ {name}\n"
        else:
            msg += f"❌ {name}\n"
            all_ok = False
    
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    msg += f"\n📊 *Resources*\n"
    msg += f"CPU: {cpu}% {'✅' if cpu < 80 else '⚠️' if cpu < 95 else '🔴'}\n"
    msg += f"RAM: {mem.percent}% {'✅' if mem.percent < 80 else '⚠️' if mem.percent < 95 else '🔴'}\n"
    msg += f"Disk: {disk.percent}% {'✅' if disk.percent < 80 else '⚠️' if disk.percent < 95 else '🔴'}\n"
    msg += f"\n{'✅ Healthy' if all_ok and cpu < 80 and mem.percent < 80 else '⚠️ Issues'}"
    await update.message.reply_text(msg, parse_mode='Markdown')

async def docker_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    out = run_cmd("docker ps -a --format '{{.Names}}|{{.Status}}'")
    if "Error" in out:
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
    name = shlex.quote(context.args[0])
    logs = run_cmd(f"docker logs --tail 50 {name} 2>&1")
    if len(logs) > 3500:
        logs = logs[-3500:]
    await update.message.reply_text(f"📜 *{name}*\n```\n{logs}\n```", parse_mode='Markdown')

async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /restart <container>")
        return
    name = shlex.quote(context.args[0])
    await update.message.reply_text(f"🔄 Restarting `{name}`...")
    run_cmd(f"docker restart {name}")
    await update.message.reply_text("✅ Restarted")

async def top_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    top = run_cmd("ps aux --sort=-%cpu | head -n 11")
    await update.message.reply_text(f"📊 *Top CPU*\n```\n{top}\n```", parse_mode='Markdown')

async def mem_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    top = run_cmd("ps aux --sort=-%mem | head -n 11")
    await update.message.reply_text(f"🧠 *Top RAM*\n```\n{top}\n```", parse_mode='Markdown')

async def disk_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    df = run_cmd("df -h")
    await update.message.reply_text(f"💾 *Disk*\n```\n{df}\n```", parse_mode='Markdown')

# === CAPROVER MANAGEMENT ===

async def capstatus_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    # Check if CapRover is installed
    caprover_check = run_cmd("docker ps --filter name=captain-captain --format '{{.Status}}'")
    if not caprover_check or "Error" in caprover_check:
        await update.message.reply_text("❌ CapRover not found\nIs it installed?")
        return
    
    # Get CapRover status
    captain_status = run_cmd("docker ps --filter name=captain-captain --format '{{.Names}}|{{.Status}}'")
    nginx_status = run_cmd("docker ps --filter name=captain-nginx --format '{{.Names}}|{{.Status}}'")
    certbot_status = run_cmd("docker ps --filter name=captain-certbot --format '{{.Names}}|{{.Status}}'")
    
    # Count apps
    apps_count = run_cmd("docker ps --filter name=captain-captain --format '{{.Names}}' | grep -v 'captain-captain\|captain-nginx\|captain-certbot' | wc -l")
    
    msg = f"🚢 *CapRover Status*\n\n"
    
    # Core services
    if "Up" in captain_status:
        msg += "✅ Captain: Running\n"
    else:
        msg += "❌ Captain: Down\n"
    
    if "Up" in nginx_status:
        msg += "✅ Nginx: Running\n"
    else:
        msg += "⚠️ Nginx: Down\n"
    
    if "Up" in certbot_status:
        msg += "✅ Certbot: Running\n"
    else:
        msg += "⚠️ Certbot: Down\n"
    
    msg += f"\n📦 Apps: `{apps_count.strip()}` running"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def capapps_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    # Get all CapRover apps (containers starting with captain- but not core services)
    apps = run_cmd("docker ps -a --filter name=captain- --format '{{.Names}}|{{.Status}}' | grep -v 'captain-captain\|captain-nginx\|captain-certbot\|captain-registry'")
    
    if not apps or apps.strip() == "":
        await update.message.reply_text("📦 No apps deployed")
        return
    
    lines = [l for l in apps.split('\n') if l.strip()]
    msg = f"📦 *CapRover Apps ({len(lines)})*\n\n"
    
    for line in lines[:20]:
        parts = line.split('|')
        if len(parts) == 2:
            name, status = parts
            # Remove captain- prefix for readability
            app_name = name.replace('captain-', '')
            icon = "🟢" if "Up" in status else "🔴"
            msg += f"{icon} `{app_name}`\n"
    
    if len(lines) > 20:
        msg += f"\n...and {len(lines) - 20} more"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def caplogs_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text(
            "Usage: /caplogs <app_name>\n\n"
            "Example: /caplogs myapp\n"
            "(Don't include 'captain-' prefix)"
        )
        return
    
    app_name = shlex.quote(context.args[0])
    # Add captain- prefix if not present
    if not app_name.startswith('captain-'):
        container_name = f"captain-{app_name}"
    else:
        container_name = app_name
    
    logs = run_cmd(f"docker logs --tail 50 {container_name} 2>&1")
    
    if "Error" in logs and "No such container" in logs:
        await update.message.reply_text(f"❌ App `{app_name}` not found")
        return
    
    if len(logs) > 3500:
        logs = logs[-3500:]
    
    await update.message.reply_text(f"📜 *{app_name}*\n```\n{logs}\n```", parse_mode='Markdown')

async def caprestart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text(
            "Usage: /caprestart <app_name|all>\n\n"
            "Examples:\n"
            "/caprestart myapp - Restart specific app\n"
            "/caprestart all - Restart CapRover core"
        )
        return
    
    target = shlex.quote(context.args[0])
    
    if target == "all":
        await update.message.reply_text("🔄 Restarting CapRover core...")
        run_cmd("docker restart captain-captain captain-nginx captain-certbot")
        await update.message.reply_text("✅ CapRover core restarted")
    else:
        # Add captain- prefix if not present
        if not target.startswith('captain-'):
            container_name = f"captain-{target}"
        else:
            container_name = target
        
        await update.message.reply_text(f"🔄 Restarting `{target}`...")
        result = run_cmd(f"docker restart {container_name}")
        
        if "Error" in result:
            await update.message.reply_text(f"❌ Failed: {result}")
        else:
            await update.message.reply_text(f"✅ `{target}` restarted")

async def capinfo_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    # Get CapRover version
    version = run_cmd("docker exec captain-captain cat /usr/src/app/package.json 2>/dev/null | grep '\"version\"' | head -1 | awk -F'\"' '{print $4}'")
    
    # Get resource usage
    captain_stats = run_cmd("docker stats captain-captain --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}'")
    
    # Get domain from config
    domain = run_cmd("docker exec captain-captain cat /captain/data/config-captain.json 2>/dev/null | grep -o '\"customDomain\":\"[^\"]*\"' | cut -d'\"' -f4")
    
    msg = "🚢 *CapRover Info*\n\n"
    
    # Version with checkmark
    if version and version.strip() and version.strip() != "":
        msg += f"📌 Version: ✅ `{version.strip()}`\n"
    else:
        msg += "📌 Version: ❌ Not found\n"
    
    # Domain with checkmark
    if domain and domain.strip() and domain.strip() != "":
        msg += f"🌐 Domain: ✅ `{domain.strip()}`\n"
    else:
        msg += "🌐 Domain: ❌ Not configured\n"
    
    # Resources
    if captain_stats and "|" in captain_stats:
        parts = captain_stats.split('|')
        if len(parts) == 2:
            cpu, mem = parts
            msg += f"\n📊 *Resources*\n"
            msg += f"CPU: `{cpu.strip()}`\n"
            msg += f"RAM: `{mem.strip()}`\n"
    
    # Get app count
    app_count = run_cmd("docker ps --filter name=captain- --format '{{.Names}}' | grep -v 'captain-captain\|captain-nginx\|captain-certbot\|captain-registry' | wc -l")
    msg += f"\n📦 Total Apps: `{app_count.strip()}`"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def network_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    connections = run_cmd("netstat -an | grep ESTABLISHED | wc -l")
    listening = run_cmd("ss -tuln | grep LISTEN | wc -l")
    ip = run_cmd("hostname -I | awk '{print $1}'")
    msg = f"🌐 *Network*\n\n🔌 Connections: `{connections}`\n👂 Ports: `{listening}`\n🌍 IP: `{ip}`"
    await update.message.reply_text(msg, parse_mode='Markdown')

async def ports_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    ports = run_cmd("ss -tuln | grep LISTEN || netstat -tuln | grep LISTEN 2>/dev/null")
    await update.message.reply_text(f"👂 *Ports*\n```\n{ports}\n```", parse_mode='Markdown')

async def ping_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /ping <host>")
        return
    host = shlex.quote(context.args[0])
    ping = run_cmd(f"ping -c 4 {host}")
    await update.message.reply_text(f"🏓 *Ping {host}*\n```\n{ping}\n```", parse_mode='Markdown')

async def dns_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /dns <domain>")
        return
    domain = shlex.quote(context.args[0])
    dns = run_cmd(f"nslookup {domain}")
    await update.message.reply_text(f"🔍 *DNS: {domain}*\n```\n{dns}\n```", parse_mode='Markdown')

async def speedtest_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🚀 Running speedtest...")
    speed = run_cmd("speedtest-cli --simple 2>/dev/null || echo 'Install: apt install speedtest-cli'", timeout=60)
    await update.message.reply_text(f"📊 *Speed Test*\n```\n{speed}\n```", parse_mode='Markdown')

async def ssl_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /ssl <domain>")
        return
    domain = shlex.quote(context.args[0])
    expiry = run_cmd(f"echo | openssl s_client -servername {domain} -connect {domain}:443 2>/dev/null | openssl x509 -noout -dates")
    await update.message.reply_text(f"🔒 *SSL: {domain}*\n```\n{expiry}\n```", parse_mode='Markdown')

async def cert_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    certs = run_cmd("certbot certificates 2>/dev/null || echo 'Certbot not installed'")
    await update.message.reply_text(f"🔒 *SSL Certificates*\n```\n{certs}\n```", parse_mode='Markdown')

async def users_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    users = run_cmd("who")
    await update.message.reply_text(f"👥 *Logged Users*\n```\n{users}\n```", parse_mode='Markdown')

async def last_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    last = run_cmd("last -n 10")
    await update.message.reply_text(f"🔑 *Last Logins*\n```\n{last}\n```", parse_mode='Markdown')

async def nginx_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    status = run_cmd("systemctl status nginx --no-pager -l")
    await update.message.reply_text(f"🌐 *Nginx*\n```\n{status}\n```", parse_mode='Markdown')
async def reboot_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("⚠️ Rebooting in 1 minute...")
    run_cmd("shutdown -r +1")
    await update.message.reply_text("✅ Reboot scheduled")

async def vpn_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /vpn <username>")
        return
    user = shlex.quote(context.args[0])
    if not user.isalnum():
        await update.message.reply_text("❌ Alphanumeric only")
        return
    await update.message.reply_text(f"🔐 Creating VPN: `{user}`...")
    res = run_cmd(f"echo '{user}' | /usr/local/bin/bdrman vpn add", timeout=60)
    await update.message.reply_text(f"```\n{res}\n```", parse_mode='Markdown')

    # Try to send generated files (PNG and Conf)
    # Check common locations (cwd and /root)
    files_to_check = [
        f"{user}.png",
        f"/root/{user}.png",
        f"{user}.conf", 
        f"/root/{user}.conf"
    ]
    
    sent_files = set()
    for fpath in files_to_check:
        if os.path.exists(fpath) and fpath not in sent_files:
            try:
                if fpath.endswith('.png'):
                    await update.message.reply_photo(photo=open(fpath, 'rb'), caption=f"📱 QR Code: {user}")
                elif fpath.endswith('.conf'):
                    await update.message.reply_document(document=open(fpath, 'rb'), filename=os.path.basename(fpath), caption="📄 Config File")
                sent_files.add(fpath)
                # Avoid sending duplicates if paths resolve to same file
                # (Simple set check of path string is basic, but sufficient for typical setup)
            except Exception as e:
                logger.error(f"Failed to send file {fpath}: {e}")

async def backup_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """
    Manage backups: create, list, download, delete
    """
    if not check_auth(update): return
    
    if not context.args:
        help_text = (
            "📦 *Backup Management*\n\n"
            "`/backup create <type>` - Create backup (full/data/config)\n"
            "`/backup list` - List local backups\n"
            "`/backup download <file>` - Download backup file\n"
            "`/backup restore <file>` - Restore from local backup\n"
            "`/backup delete <file>` - Delete local backup"
        )
        await update.message.reply_text(help_text, parse_mode='Markdown')
        return

    action = context.args[0].lower()
    
    if action == "create":
        if len(context.args) < 2:
            await update.message.reply_text("⚠️ Usage: `/backup create <full|data|config>`", parse_mode='Markdown')
            return
        b_type = shlex.quote(context.args[1])
        await update.message.reply_text(f"⏳ Creating `{b_type}` backup...")
        res = run_cmd(f"/usr/local/bin/bdrman backup create {b_type}", timeout=300)
        await update.message.reply_text(f"✅ Result:\n```\n{res}\n```", parse_mode='Markdown')

    elif action == "list":
        res = run_cmd("/usr/local/bin/bdrman backup list")
        await update.message.reply_text(f"📂 *Local Backups:*\n```\n{res}\n```", parse_mode='Markdown')

    elif action == "download":
        if len(context.args) < 2:
            await update.message.reply_text("⚠️ Usage: `/backup download <filename>`", parse_mode='Markdown')
            return
        filename = shlex.quote(context.args[1])
        filepath = f"/var/backups/bdrman/{filename}"
        
        # Security check: prevent path traversal
        if ".." in filename or "/" in filename:
             await update.message.reply_text("❌ Invalid filename", parse_mode='Markdown')
             return

        if not os.path.exists(filepath):
            await update.message.reply_text(f"❌ File not found: `{filename}`", parse_mode='Markdown')
            return

        await update.message.reply_text(f"⏳ Sending `{filename}`...", parse_mode='Markdown')
        try:
            await update.message.reply_document(document=open(filepath, 'rb'), filename=filename)
        except Exception as e:
            await update.message.reply_text(f"❌ Failed to send file: {str(e)}", parse_mode='Markdown')

    elif action == "restore":
        if len(context.args) < 2:
            await update.message.reply_text("⚠️ Usage: `/backup restore <filename>`", parse_mode='Markdown')
            return
        filename = shlex.quote(context.args[1])
        
        await update.message.reply_text(f"⚠️ Restoring `{filename}`. This might take a while...", parse_mode='Markdown')
        cmd = f"bash -c 'source /usr/local/lib/bdrman/backup.sh; BACKUP_DIR=/var/backups/bdrman; echo -e \"{filename}\\nyes\" | backup_restore'"
        res = run_cmd(cmd, timeout=600)
        await update.message.reply_text(f"Result:\n```\n{res}\n```", parse_mode='Markdown')

    elif action == "delete":
        if len(context.args) < 2:
            await update.message.reply_text("⚠️ Usage: `/backup delete <filename>`", parse_mode='Markdown')
            return
        filename = shlex.quote(context.args[1])
        cmd = f"bash -c 'source /usr/local/lib/bdrman/backup.sh; BACKUP_DIR=/var/backups/bdrman; backup_delete_local {filename}'"
        res = run_cmd(cmd)
        await update.message.reply_text(f"🗑️ Result:\n```\n{res}\n```", parse_mode='Markdown')

    else:
        await update.message.reply_text("❌ Unknown action. Use create, list, download, restore, delete.")

async def update_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🔄 Updating packages...")
    run_cmd("apt update && apt upgrade -y", timeout=300)
    await update.message.reply_text("✅ Updated")

async def updatebdr_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args or context.args[0] != 'confirm':
        current_version = VERSION
        msg = (
            f"🔄 *BDRman Update*\n\n"
            f"📌 Current: `v{current_version}`\n"
            f"📥 Will update to latest from GitHub\n\n"
            f"⚠️ *Bot will restart*\n\n"
            f"To confirm, send:\n"
            f"`/updatebdr confirm`"
        )
        await update.message.reply_text(msg, parse_mode='Markdown')
        return
    
    await update.message.reply_text("🔄 *Starting Update...*", parse_mode='Markdown')
    
    update_script = f"""#!/bin/bash
exec > /tmp/bdrman_update.log 2>&1
cd /tmp
echo "Starting update process..."
sleep 2
systemctl stop bdrman-telegram
curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh -o bdrman_update.sh
echo "yes" | bash bdrman_update.sh
systemctl daemon-reload
systemctl restart bdrman-telegram
"""
    with open('/tmp/bdrman_updater.sh', 'w') as f:
        f.write(update_script)
    run_cmd("chmod +x /tmp/bdrman_updater.sh")
    subprocess.Popen(["setsid", "/bin/bash", "/tmp/bdrman_updater.sh"], start_new_session=True)
    
    await update.message.reply_text("⏳ *Update in progress...*", parse_mode='Markdown')

async def export_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    try:
        import json
        await update.message.reply_text("📤 Exporting...")
        config = {
            "exported_at": datetime.now().isoformat(),
            "server": SERVER_NAME,
            "bdrman_version": VERSION,
            "telegram": {"chat_id": CHAT_ID},
            "firewall": run_cmd("ufw status numbered | tail -n +5"),
            "services": {
                "docker": run_cmd("systemctl is-active docker"),
                "nginx": run_cmd("systemctl is-active nginx")
            }
        }
        config_file = f"/tmp/bdrman_config_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(config_file, 'w') as f:
            f.write(json.dumps(config, indent=2))
        await update.message.reply_document(
            document=open(config_file, 'rb'),
            filename=f"bdrman_{SERVER_NAME}.json",
            caption="📋 Config Export"
        )
        run_cmd(f"rm {config_file}")
    except Exception as e:
        await update.message.reply_text(f"❌ Export failed: {str(e)}")

async def import_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("📥 *Import*\n\nSend JSON file to import\n⚠️ Coming soon!", parse_mode='Markdown')

async def block_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /block <ip>")
        return
    ip = shlex.quote(context.args[0])
    run_cmd(f"ufw deny from {ip}")
    await update.message.reply_text(f"🚫 Blocked: `{ip}`", parse_mode='Markdown')

async def unblock_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /unblock <ip>")
        return
    ip = shlex.quote(context.args[0])
    run_cmd(f"ufw delete deny from {ip}")
    await update.message.reply_text(f"✅ Unblocked: `{ip}`", parse_mode='Markdown')

async def panic_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("⚠️ Usage: /panic <your_ip>")
        return
    ip = shlex.quote(context.args[0])
    await update.message.reply_text(f"🚨 PANIC MODE for {ip}...")
    cmds = ["ufw --force reset", "ufw default deny incoming", "ufw default allow outgoing", f"ufw allow from {ip} to any port 22", "ufw --force enable"]
    for cmd in cmds:
        run_cmd(cmd)
    await update.message.reply_text("✅ PANIC ACTIVE")

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
    key_services = ["docker", "nginx", "ssh", "ufw", "cron"]
    running = []
    stopped = []
    for svc in key_services:
        status = run_cmd(f"systemctl is-active {svc} 2>/dev/null || echo inactive")
        if "active" in status:
            running.append(svc)
        else:
            stopped.append(svc)
    
    msg = f"⚙️ *Services*\n\n✅ Running ({len(running)})\n"
    for svc in running:
        msg += f"  • {svc}\n"
    if stopped:
        msg += f"\n⚠️ Stopped ({len(stopped)})\n"
        for svc in stopped:
            msg += f"  • {svc}\n"
    if failed and "0 loaded" not in failed:
        msg += f"\n❌ Failed\n```\n{failed[:500]}\n```"
    else:
        msg += "\n✅ No failures"
    await update.message.reply_text(msg, parse_mode='Markdown')

async def running_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    running = run_cmd("systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}'")
    services = running.split('\n')[:20]
    msg = f"✅ *Running ({len(services)})*\n\n"
    for svc in services:
        if svc.strip():
            svc_name = svc.replace('.service', '')
            msg += f"• `{svc_name}`\n"
    total = len(running.split('\n'))
    if total > 20:
        msg += f"\n...and {total - 20} more"
    await update.message.reply_text(msg, parse_mode='Markdown')

async def uptime_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    uptime = run_cmd("uptime -p")
    since = run_cmd("uptime -s")
    await update.message.reply_text(f"⏱️ *Uptime*\n{uptime}\nSince: `{since}`", parse_mode='Markdown')

async def kernel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    kernel = run_cmd("uname -a")
    await update.message.reply_text(f"🐧 *Kernel*\n```\n{kernel}\n```", parse_mode='Markdown')

async def alerts_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    msg = "🚨 *Alerts*\n\n"
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    if cpu > 80:
        msg += f"🔴 High CPU: {cpu}%\n"
    if mem.percent > 80:
        msg += f"🔴 High RAM: {mem.percent}%\n"
    if disk.percent > 80:
        msg += f"🔴 Low Disk: {disk.percent}%\n"
    failed = run_cmd("systemctl --failed --no-pager --no-legend | wc -l")
    if int(failed) > 0:
        msg += f"🔴 {failed} failed services\n"
    if msg == "🚨 *Alerts*\n\n":
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
    
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    
    # Register commands for Help Menu
    register_command("start", "Start bot", "General")
    register_command("help", "Show this menu", "General")
    register_command("version", "Show version info", "General")
    register_command("status", "System status dashboard", "Monitoring")
    register_command("health", "Health check", "Monitoring")
    register_command("alerts", "Show active alerts", "Monitoring")
    register_command("top", "Top CPU processes", "Monitoring")
    register_command("mem", "Top RAM processes", "Monitoring")
    register_command("disk", "Disk usage", "Monitoring")
    register_command("uptime", "System uptime", "Monitoring")
    register_command("docker", "List containers", "Docker")
    register_command("logs", "View container logs", "Docker")
    register_command("restart", "Restart container", "Docker")
    register_command("network", "Network stats", "Network")
    register_command("ports", "Open ports", "Network")
    register_command("ping", "Ping host", "Network")
    register_command("dns", "DNS lookup", "Network")
    register_command("speedtest", "Run speedtest", "Network")
    register_command("ssl", "Check SSL expiry", "Security")
    register_command("cert", "List Certbot certs", "Security")
    register_command("firewall", "Show UFW status", "Security")
    register_command("block", "Block IP", "Security")
    register_command("unblock", "Unblock IP", "Security")
    register_command("panic", "Enable Panic Mode", "Security")
    register_command("unpanic", "Disable Panic Mode", "Security")
    register_command("vpn", "Create VPN user", "Security")
    register_command("backup", "Backup management", "System")
    register_command("update", "Update system packages", "System")
    register_command("updatebdr", "Update BDRman", "System")
    register_command("export", "Export config", "System")
    register_command("services", "Service status", "System")
    register_command("running", "Running services", "System")
    register_command("nginx", "Nginx status", "System")
    register_command("kernel", "Kernel info", "System")
    register_command("reboot", "Reboot server", "System")
    register_command("capstatus", "CapRover status", "CapRover")
    register_command("capapps", "List CapRover apps", "CapRover")
    register_command("caplogs", "App logs", "CapRover")
    register_command("caprestart", "Restart app/core", "CapRover")
    register_command("capinfo", "CapRover info", "CapRover")
    register_command("snapshot", "Create system snapshot", "System")

    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("version", version_cmd))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("health", health_cmd))
    app.add_handler(CommandHandler("alerts", alerts_cmd))
    app.add_handler(CommandHandler("top", top_cmd))
    app.add_handler(CommandHandler("mem", mem_cmd))
    app.add_handler(CommandHandler("disk", disk_cmd))
    app.add_handler(CommandHandler("uptime", uptime_cmd))
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
    app.add_handler(CommandHandler("updatebdr", updatebdr_cmd))
    app.add_handler(CommandHandler("export", export_cmd))
    app.add_handler(CommandHandler("import", import_cmd))
    app.add_handler(CommandHandler("services", services_cmd))
    app.add_handler(CommandHandler("running", running_cmd))
    app.add_handler(CommandHandler("nginx", nginx_cmd))
    app.add_handler(CommandHandler("kernel", kernel_cmd))
    app.add_handler(CommandHandler("reboot", reboot_cmd))
    app.add_handler(CommandHandler("users", users_cmd))
    app.add_handler(CommandHandler("last", last_cmd))
    
    # CapRover handlers
    app.add_handler(CommandHandler("capstatus", capstatus_cmd))
    app.add_handler(CommandHandler("capapps", capapps_cmd))
    app.add_handler(CommandHandler("caplogs", caplogs_cmd))
    app.add_handler(CommandHandler("caprestart", caprestart_cmd))
    app.add_handler(CommandHandler("capinfo", capinfo_cmd))
    
    # PIN conversation
    conv = ConversationHandler(
        entry_points=[CommandHandler("snapshot", pin_request)],
        states={PIN_STATE: [MessageHandler(filters.TEXT & ~filters.COMMAND, pin_verify)]},
        fallbacks=[CommandHandler("cancel", cancel)]
    )
    app.add_handler(conv)
    
    # Startup notification
    if BOT_TOKEN and CHAT_ID:
        try:
            import requests
            requests.post(
                f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
                data={
                    "chat_id": CHAT_ID, 
                    "text": f"🤖 *BDRman Bot Started*\\n\\nVersion: `{VERSION}`\\nServer: `{SERVER_NAME}`\\n\\nReady for commands!", 
                    "parse_mode": "Markdown"
                }
            )
        except Exception as e:
            logger.error(f"Startup notification failed: {e}")

    logger.info(f"Bot v{VERSION} started for {SERVER_NAME}")
    print(f"✅ Bot started on {SERVER_NAME}")
    print(f"📊 {len(COMMANDS)} commands registered")
    app.run_polling()

if __name__ == '__main__':
    main()
