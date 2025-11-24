#!/usr/bin/env python3
"""
BDRman Ultimate Telegram Bot
Fully functional with all commands working
"""
import os
import sys
import logging
import subprocess
import psutil
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, ConversationHandler, MessageHandler, filters

# Configuration
CONFIG_FILE = "/etc/bdrman/telegram.conf"
LOG_FILE = "/var/log/bdrman-bot.log"

# Logging Setup
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global Config
BOT_TOKEN = ""
CHAT_ID = ""
PIN_CODE = "1234"
SERVER_NAME = ""

# Command Registry
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
        logger.error(f"Config load error: {e}")
        sys.exit(1)

def check_auth(update: Update) -> bool:
    user_id = str(update.effective_user.id)
    if user_id != CHAT_ID:
        logger.warning(f"Unauthorized: {user_id}")
        return False
    return True

def run_cmd(cmd, timeout=30):
    """Execute command safely with timeout"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        output = result.stdout if result.stdout else result.stderr
        return output.strip() if output else "✅ Command executed (no output)"
    except subprocess.TimeoutExpired:
        return "⏱️ Command timeout"
    except Exception as e:
        return f"❌ Error: {str(e)}"

def get_bar(percent):
    filled = int(percent / 10)
    return "▓" * filled + "░" * (10 - filled)

# === COMMAND HANDLERS ===

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text(
        f"🤖 *BDRman Bot Online*\n"
        f"🖥️ Server: `{SERVER_NAME}`\n\n"
        f"Use /help to see all commands.",
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
    for cat, cmds in cats.items():
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
    
    # Recent logs
    logs = run_cmd("journalctl -n 10 --no-pager -o short-precise")
    if len(logs) > 1500:
        logs = logs[-1500:]
    
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
        f"📜 *Recent Logs (10)*\n"
        f"```\n{logs}\n```"
    )
    await update.message.reply_text(msg, parse_mode='Markdown')

async def docker_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    out = run_cmd("docker ps -a --format '{{.Names}}|{{.Status}}'")
    if "Error" in out or not out:
        await update.message.reply_text(f"❌ {out}")
        return
    
    lines = [l for l in out.split('\n') if l]
    msg = f"🐳 *Docker Containers ({len(lines)})*\n\n"
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
    
    await update.message.reply_text(f"📜 *Logs: {name}*\n```\n{logs}\n```", parse_mode='Markdown')

async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /restart <container>")
        return
    
    name = context.args[0]
    await update.message.reply_text(f"🔄 Restarting `{name}`...")
    res = run_cmd(f"docker restart {name}")
    await update.message.reply_text(f"✅ {res}", parse_mode='Markdown')

async def vpn_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /vpn <username>")
        return
    
    user = context.args[0]
    if not user.isalnum():
        await update.message.reply_text("❌ Username must be alphanumeric")
        return
    
    await update.message.reply_text(f"🔐 Creating VPN user: `{user}`...")
    # Use bdrman CLI if available
    res = run_cmd(f"echo '{user}' | /usr/local/bin/bdrman vpn add", timeout=60)
    await update.message.reply_text(f"Result:\n```\n{res}\n```", parse_mode='Markdown')

async def backup_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("💾 Starting backup...")
    
    # Run in background
    subprocess.Popen(
        ["/usr/local/bin/bdrman", "backup", "create"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    await update.message.reply_text("✅ Backup started in background. Check logs for status.")

async def update_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🔄 Starting system update...")
    
    res = run_cmd("apt update && apt upgrade -y", timeout=300)
    await update.message.reply_text("✅ System updated")

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
    
    cmds = [
        "ufw --force reset",
        "ufw default deny incoming",
        "ufw default allow outgoing",
        f"ufw allow from {ip} to any port 22",
        "ufw --force enable"
    ]
    for cmd in cmds:
        run_cmd(cmd)
    
    await update.message.reply_text("✅ PANIC MODE ACTIVE")

async def unpanic_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🟢 Deactivating panic mode...")
    
    cmds = [
        "ufw --force reset",
        "ufw default deny incoming",
        "ufw default allow outgoing",
        "ufw allow ssh",
        "ufw allow 80/tcp",
        "ufw allow 443/tcp",
        "ufw --force enable"
    ]
    for cmd in cmds:
        run_cmd(cmd)
    
    await update.message.reply_text("✅ Panic mode deactivated")

async def health_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    services = ["docker", "nginx", "ssh"]
    msg = "🏥 *Health Check*\n\n"
    
    for svc in services:
        status = run_cmd(f"systemctl is-active {svc}")
        icon = "✅" if "active" in status else "❌"
        msg += f"{icon} {svc}\n"
    
    disk = psutil.disk_usage('/')
    msg += f"\n💾 Disk: {disk.percent}%"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def firewall_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    status = run_cmd("ufw status")
    await update.message.reply_text(f"🛡️ *Firewall*\n```\n{status}\n```", parse_mode='Markdown')

async def services_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    failed = run_cmd("systemctl --failed --no-pager --no-legend")
    if not failed or "0 loaded" in failed:
        await update.message.reply_text("✅ All services running")
    else:
        await update.message.reply_text(f"⚠️ *Failed Services*\n```\n{failed}\n```", parse_mode='Markdown')

# PIN Protected Commands
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
            await update.message.reply_text("📸 Creating snapshot (background)...")
            subprocess.Popen(
                ["rsync", "-aAX", "--delete", "/", "/var/snapshots/emergency/"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
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
    
    # Register all commands
    register_command("start", "Start bot", "📌 General")
    register_command("help", "Show this help", "📌 General")
    register_command("status", "System status + logs", "📊 Monitoring")
    register_command("docker", "List containers", "🐳 Docker")
    register_command("logs", "Container logs", "🐳 Docker")
    register_command("restart", "Restart container", "🐳 Docker")
    register_command("vpn", "Create VPN user", "🔧 Management")
    register_command("backup", "Create backup", "🔧 Management")
    register_command("update", "System update", "🔧 Management")
    register_command("block", "Block IP", "🛡️ Security")
    register_command("unblock", "Unblock IP", "🛡️ Security")
    register_command("panic", "Panic mode", "🛡️ Security")
    register_command("unpanic", "Exit panic", "🛡️ Security")
    register_command("health", "Health check", "📊 Monitoring")
    register_command("firewall", "Firewall status", "🛡️ Security")
    register_command("services", "Failed services", "📊 Monitoring")
    register_command("snapshot", "Snapshot (PIN)", "🚨 Critical")
    
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("docker", docker_list))
    app.add_handler(CommandHandler("logs", logs_cmd))
    app.add_handler(CommandHandler("restart", restart_cmd))
    app.add_handler(CommandHandler("vpn", vpn_cmd))
    app.add_handler(CommandHandler("backup", backup_cmd))
    app.add_handler(CommandHandler("update", update_cmd))
    app.add_handler(CommandHandler("block", block_cmd))
    app.add_handler(CommandHandler("unblock", unblock_cmd))
    app.add_handler(CommandHandler("panic", panic_cmd))
    app.add_handler(CommandHandler("unpanic", unpanic_cmd))
    app.add_handler(CommandHandler("health", health_cmd))
    app.add_handler(CommandHandler("firewall", firewall_cmd))
    app.add_handler(CommandHandler("services", services_cmd))
    
    # PIN conversation
    conv = ConversationHandler(
        entry_points=[CommandHandler("snapshot", pin_request)],
        states={PIN_STATE: [MessageHandler(filters.TEXT & ~filters.COMMAND, pin_verify)]},
        fallbacks=[CommandHandler("cancel", cancel)]
    )
    app.add_handler(conv)
    
    logger.info(f"Bot started for {SERVER_NAME}")
    print(f"🤖 Bot running for {SERVER_NAME}")
    app.run_polling()

if __name__ == '__main__':
    main()
