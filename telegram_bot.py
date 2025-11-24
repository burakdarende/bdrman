#!/usr/bin/env python3
"""
BDRman Ultimate Telegram Bot
"""
import os
import sys
import time
import logging
import subprocess
import psutil
import socket
import shlex
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, ConversationHandler, MessageHandler, filters

# Configuration
CONFIG_FILE = "/etc/bdrman/telegram.conf"
LOG_FILE = "/var/log/bdrman-bot.log"

# Logging Setup
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    filename=LOG_FILE
)
logger = logging.getLogger(__name__)

# Global Config
BOT_TOKEN = ""
CHAT_ID = ""
PIN_CODE = "1234"

# Command Registry for Dynamic Help
COMMANDS = []

def register_command(command, description, category, handler, has_args=False):
    COMMANDS.append({
        "command": command,
        "description": description,
        "category": category,
        "handler": handler,
        "has_args": has_args
    })

def load_config():
    global BOT_TOKEN, CHAT_ID, PIN_CODE
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if line.startswith("BOT_TOKEN="):
                    BOT_TOKEN = line.split("=")[1].strip().strip('"')
                elif line.startswith("CHAT_ID="):
                    CHAT_ID = line.split("=")[1].strip().strip('"')
                elif line.startswith("PIN_CODE="):
                    PIN_CODE = line.split("=")[1].strip().strip('"')
    except Exception as e:
        logger.error(f"Config load error: {e}")
        sys.exit(1)

def check_auth(update: Update) -> bool:
    user_id = str(update.effective_user.id)
    if user_id != CHAT_ID:
        logger.warning(f"Unauthorized access attempt from {user_id}")
        return False
    return True

def run_command(cmd, shell=False):
    try:
        if shell:
            result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode()
        else:
            args = shlex.split(cmd)
            result = subprocess.check_output(args, stderr=subprocess.STDOUT).decode()
        return result.strip()
    except subprocess.CalledProcessError as e:
        return f"Error: {e.output.decode().strip()}"
    except Exception as e:
        return f"Execution Error: {str(e)}"

def get_progress_bar(percent):
    bar_len = 10
    filled = int(percent / 100 * bar_len)
    return "▓" * filled + "░" * (bar_len - filled)

# --- Handlers ---

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text(
        "🤖 *BDRman Ultimate Bot Online*\n\n"
        "Use /help to see all available commands.",
        parse_mode='Markdown'
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    msg = "🤖 *Available Commands*\n\n"
    
    categories = {}
    for cmd in COMMANDS:
        cat = cmd['category']
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(cmd)
    
    for cat, cmds in categories.items():
        msg += f"*{cat}*\n"
        for c in cmds:
            args = " <args>" if c['has_args'] else ""
            msg += f"/{c['command']}{args} - {c['description']}\n"
        msg += "\n"
        
    await update.message.reply_text(msg, parse_mode='Markdown')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    await update.message.reply_text("📊 Collecting system data...", parse_mode='Markdown')
    
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    uptime = run_command("uptime -p", shell=True)
    load = os.getloadavg()
    kernel = run_command("uname -r", shell=True)
    
    # Get last 10 logs
    logs = run_command("journalctl -n 10 --no-pager", shell=True)
    if len(logs) > 1000: logs = logs[-1000:]

    msg = (
        "📊 *System Status*\n"
        "━━━━━━━━━━━━━━━━━━\n"
        f"🖥 *System Info*\n"
        f"• Kernel: `{kernel}`\n"
        f"• Uptime: `{uptime}`\n"
        f"• Load: `{load[0]}, {load[1]}, {load[2]}`\n\n"
        
        f"📈 *Resources*\n"
        f"• CPU:  {cpu}% {get_progress_bar(cpu)}\n"
        f"• RAM:  {mem.percent}% {get_progress_bar(mem.percent)}\n"
        f"• Disk: {disk.percent}% {get_progress_bar(disk.percent)}\n\n"
        
        f"📜 *Recent Logs (Last 10)*\n"
        f"```\n{logs}\n```"
    )
    await update.message.reply_text(msg, parse_mode='Markdown')

async def docker_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    out = run_command("docker ps -a --format '{{.Names}}|{{.Status}}'", shell=True)
    if "Error" in out:
        await update.message.reply_text(f"❌ {out}")
        return

    lines = [l for l in out.split('\n') if l]
    if not lines:
        await update.message.reply_text("No containers found.")
        return

    msg = "🐳 *Docker Containers*\n\n"
    for line in lines[:20]:
        name, status = line.split('|')
        icon = "🟢" if "Up" in status else "🔴"
        msg += f"{icon} `{name}`\n"
    
    await update.message.reply_text(msg, parse_mode='Markdown')

async def docker_logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /logs <container>")
        return
    
    name = context.args[0]
    logs = run_command(f"docker logs --tail 50 {name} 2>&1", shell=True)
    if len(logs) > 3000: logs = logs[-3000:]
    
    await update.message.reply_text(f"📜 *Logs for {name}*\n```\n{logs}\n```", parse_mode='Markdown')

async def docker_restart(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /restart <container>")
        return
    
    name = context.args[0]
    await update.message.reply_text(f"🔄 Restarting `{name}`...")
    res = run_command(f"docker restart {name}", shell=True)
    await update.message.reply_text(f"Result: `{res}`", parse_mode='Markdown')

async def vpn_create(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /vpn <username>")
        return
    
    username = context.args[0]
    if not username.isalnum():
        await update.message.reply_text("❌ Invalid username. Alphanumeric only.")
        return

    await update.message.reply_text(f"🔐 Creating VPN user: {username}...")
    
    # Assuming wireguard-install.sh or bdrman vpn add logic
    # We'll use bdrman CLI if available, or direct script
    cmd = f"bdrman vpn add {username}"
    res = run_command(cmd, shell=True)
    
    await update.message.reply_text(f"✅ Result:\n```\n{res}\n```", parse_mode='Markdown')

async def block_ip(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /block <ip>")
        return
    
    ip = context.args[0]
    run_command(f"ufw deny from {ip}", shell=True)
    await update.message.reply_text(f"🚫 Blocked IP: `{ip}`", parse_mode='Markdown')

async def unblock_ip(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("Usage: /unblock <ip>")
        return
    
    ip = context.args[0]
    run_command(f"ufw delete deny from {ip}", shell=True)
    await update.message.reply_text(f"✅ Unblocked IP: `{ip}`", parse_mode='Markdown')

async def panic_mode(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    if not context.args:
        await update.message.reply_text("⚠️ Usage: /panic <YOUR_IP>")
        return
    
    ip = context.args[0]
    await update.message.reply_text(f"🚨 ACTIVATING PANIC MODE for {ip}...")
    
    cmds = [
        "ufw --force reset",
        "ufw default deny incoming",
        "ufw default allow outgoing",
        f"ufw allow from {ip} to any port 22 proto tcp",
        "ufw --force enable"
    ]
    for cmd in cmds:
        run_command(cmd, shell=True)
        
    await update.message.reply_text("✅ PANIC MODE ACTIVE. All ports closed except SSH for you.")

async def unpanic_mode(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    await update.message.reply_text("🟢 Deactivating Panic Mode...")
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
        run_command(cmd, shell=True)
        
    await update.message.reply_text("✅ Panic Mode Deactivated.")

async def backup_create(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("💾 Starting backup...")
    res = run_command("bdrman backup create", shell=True)
    await update.message.reply_text(f"✅ Backup Result:\n```\n{res}\n```", parse_mode='Markdown')

async def system_update(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text("🔄 Starting system update...")
    res = run_command("apt update && apt upgrade -y", shell=True)
    await update.message.reply_text(f"✅ Update Complete.", parse_mode='Markdown')

# --- PIN Protected Conversation ---
PIN_CHECK = 1

async def pin_request(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return ConversationHandler.END
    
    context.user_data['cmd'] = update.message.text.split()[0]
    await update.message.reply_text("🔒 *PIN REQUIRED*\nEnter 4-digit PIN:", parse_mode='Markdown')
    return PIN_CHECK

async def pin_verify(update: Update, context: ContextTypes.DEFAULT_TYPE):
    pin = update.message.text.strip()
    if pin == PIN_CODE:
        cmd = context.user_data.get('cmd')
        await update.message.reply_text("✅ PIN Accepted.")
        
        if cmd == '/snapshot':
            await update.message.reply_text("📸 Creating Snapshot (this may take time)...")
            # Run in background to avoid timeout
            subprocess.Popen(["bdrman", "backup", "create"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            await update.message.reply_text("✅ Snapshot process started in background.")
            
        elif cmd == '/emergency_exit':
             await unpanic_mode(update, context)
             
        return ConversationHandler.END
    else:
        await update.message.reply_text("❌ Incorrect PIN.")
        return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("🚫 Cancelled.")
    return ConversationHandler.END

# --- Main ---

def main():
    load_config()
    if not BOT_TOKEN:
        print("Error: BOT_TOKEN missing.")
        sys.exit(1)

    app = ApplicationBuilder().token(BOT_TOKEN).build()

    # Register Commands
    register_command("start", "Start Bot", "General", start)
    register_command("help", "Show Help", "General", help_command)
    register_command("status", "System Status & Logs", "Monitoring", status)
    register_command("docker", "List Containers", "Docker", docker_list)
    register_command("logs", "Container Logs", "Docker", docker_logs, True)
    register_command("restart", "Restart Container", "Docker", docker_restart, True)
    register_command("vpn", "Create VPN User", "Management", vpn_create, True)
    register_command("backup", "Create Backup", "Management", backup_create)
    register_command("update", "Update System", "Management", system_update)
    register_command("block", "Block IP", "Security", block_ip, True)
    register_command("unblock", "Unblock IP", "Security", unblock_ip, True)
    register_command("panic", "Panic Mode (Block All)", "Security", panic_mode, True)
    register_command("unpanic", "Disable Panic Mode", "Security", unpanic_mode)
    
    # PIN Protected
    register_command("snapshot", "Create Snapshot (PIN)", "Critical", None) # Handled by Conversation
    register_command("emergency_exit", "Emergency Exit (PIN)", "Critical", None) # Handled by Conversation

    # Add Handlers
    for cmd in COMMANDS:
        if cmd['handler']:
            app.add_handler(CommandHandler(cmd['command'], cmd['handler']))

    # Conversation Handler
    conv_handler = ConversationHandler(
        entry_points=[CommandHandler("snapshot", pin_request), CommandHandler("emergency_exit", pin_request)],
        states={PIN_CHECK: [MessageHandler(filters.TEXT & ~filters.COMMAND, pin_verify)]},
        fallbacks=[CommandHandler("cancel", cancel)]
    )
    app.add_handler(conv_handler)

    print("Bot started...")
    app.run_polling()

if __name__ == '__main__':
    main()
