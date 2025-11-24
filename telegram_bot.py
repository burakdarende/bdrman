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
import requests
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, CallbackQueryHandler, MessageHandler, filters

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

def load_config():
    global BOT_TOKEN, CHAT_ID
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if line.startswith("BOT_TOKEN="):
                    BOT_TOKEN = line.split("=")[1].strip().strip('"')
                elif line.startswith("CHAT_ID="):
                    CHAT_ID = line.split("=")[1].strip().strip('"')
    except Exception as e:
        logger.error(f"Config load error: {e}")
        sys.exit(1)

def check_auth(update: Update) -> bool:
    user_id = str(update.effective_user.id)
    if user_id != CHAT_ID:
        logger.warning(f"Unauthorized access attempt from {user_id}")
        return False
    return True

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    await update.message.reply_text(
        "🤖 *BDRman Ultimate Bot Online*\n\n"
        "Available Commands:\n"
        "📊 /status - System Resources\n"
        "🚀 /caprover - CapRover Status\n"
        "🐳 /docker - List Containers\n"
        "🔍 /search <name> - Find Container\n"
        "📜 /logs <name> - View Logs\n"
        "🔄 /restart <name> - Restart Container\n"
        "💻 /exec <cmd> - Execute Command (Careful!)",
        parse_mode='Markdown'
    )

def get_progress_bar(percent):
    bar_len = 10
    filled = int(percent / 100 * bar_len)
    return "▓" * filled + "░" * (bar_len - filled)

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    uptime = subprocess.getoutput("uptime -p")
    load = os.getloadavg()

    msg = (
        "📊 *System Status*\n\n"
        f"🖥 *CPU:* {cpu}% {get_progress_bar(cpu)}\n"
        f"🧠 *RAM:* {mem.percent}% {get_progress_bar(mem.percent)}\n"
        f"   Used: {round(mem.used/1024/1024/1024, 2)}GB / {round(mem.total/1024/1024/1024, 2)}GB\n"
        f"💾 *Disk:* {disk.percent}% {get_progress_bar(disk.percent)}\n"
        f"   Free: {round(disk.free/1024/1024/1024, 2)}GB\n\n"
        f"⏱ *Uptime:* {uptime}\n"
        f"⚖️ *Load:* {load[0]}, {load[1]}, {load[2]}"
    )
    await update.message.reply_text(msg, parse_mode='Markdown')

async def caprover(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    try:
        # Check Container
        is_running = subprocess.call("docker inspect caprover >/dev/null 2>&1", shell=True) == 0
        status_icon = "🟢" if is_running else "🔴"
        status_text = "Running" if is_running else "Stopped"
        
        # Check Ports
        ports_msg = ""
        for port in [80, 443, 3000]:
            res = subprocess.call(f"nc -z 127.0.0.1 {port}", shell=True)
            p_icon = "✅" if res == 0 else "❌"
            ports_msg += f"Port {port}: {p_icon}\n"

        msg = (
            f"🚀 *CapRover Status*\n\n"
            f"Status: {status_icon} *{status_text}*\n\n"
            f"*Port Checks:*\n{ports_msg}"
        )
        await update.message.reply_text(msg, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"Error checking CapRover: {str(e)}")

async def docker_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    try:
        out = subprocess.check_output("docker ps -a --format '{{.Names}}|{{.Status}}'", shell=True).decode()
        lines = [l for l in out.split('\n') if l]
        
        if not lines:
            await update.message.reply_text("No containers found.")
            return

        msg = "🐳 *Docker Containers*\n\n"
        for line in lines[:15]: # Limit to 15 to avoid msg limit
            name, status = line.split('|')
            icon = "🟢" if "Up" in status else "🔴"
            msg += f"{icon} `{name}`\n"
        
        if len(lines) > 15:
            msg += f"\n...and {len(lines)-15} more."
            
        await update.message.reply_text(msg, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"Error: {str(e)}")

async def search_container(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text("Usage: /search <name>")
        return
    
    query = context.args[0]
    try:
        out = subprocess.check_output(f"docker ps -a --format '{{{{.Names}}}}|{{{{.Status}}}}' | grep -i '{query}'", shell=True).decode()
        lines = [l for l in out.split('\n') if l]
        
        if not lines:
            await update.message.reply_text(f"No containers found matching '{query}'")
            return

        msg = f"🔍 *Search Results for '{query}'*\n\n"
        for line in lines[:10]:
            name, status = line.split('|')
            icon = "🟢" if "Up" in status else "🔴"
            msg += f"{icon} `{name}`\n"
            
        await update.message.reply_text(msg, parse_mode='Markdown')
    except:
        await update.message.reply_text("No matches found or error occurred.")

async def get_logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text("Usage: /logs <container_name>")
        return
    
    name = context.args[0]
    try:
        logs = subprocess.check_output(f"docker logs --tail 20 {name} 2>&1", shell=True).decode()
        # Telegram max message length is 4096
        if len(logs) > 3000: logs = logs[-3000:]
        
        await update.message.reply_text(f"📜 *Logs for {name}*\n```\n{logs}\n```", parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"Error fetching logs: {str(e)}")

async def restart_container(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text("Usage: /restart <container_name>")
        return
    
    name = context.args[0]
    await update.message.reply_text(f"🔄 Restarting `{name}`...", parse_mode='Markdown')
    
    try:
        subprocess.check_call(f"docker restart {name}", shell=True)
        await update.message.reply_text(f"✅ `{name}` restarted successfully!", parse_mode='Markdown')
    except:
        await update.message.reply_text(f"❌ Failed to restart `{name}`.")

async def exec_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text("Usage: /exec <command>")
        return
        
    cmd = " ".join(context.args)
    
    # Security Blocklist
    forbidden = ['rm -rf', 'mkfs', 'dd', ':(){ :|:& };:']
    if any(x in cmd for x in forbidden):
        await update.message.reply_text("⛔ Command blocked for security reasons.")
        return

    try:
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode()
        if len(output) > 3000: output = output[:3000] + "\n...truncated"
        if not output: output = "Success (No Output)"
        await update.message.reply_text(f"💻 *Output:*\n```\n{output}\n```", parse_mode='Markdown')
    except subprocess.CalledProcessError as e:
        await update.message.reply_text(f"❌ Error:\n```\n{e.output.decode()}\n```", parse_mode='Markdown')

async def network_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    try:
        # Active connections
        active = subprocess.check_output("netstat -an | grep ESTABLISHED | wc -l", shell=True).decode().strip()
        
        # Top IPs
        top_ips = subprocess.check_output("netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 10", shell=True).decode()
        
        msg = (
            f"🌐 *Network Statistics*\n\n"
            f"🔌 Active Connections: `{active}`\n\n"
            f"🏆 *Top Connecting IPs:*\n"
            f"```\n{top_ips}\n```"
        )
        await update.message.reply_text(msg, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"Error: {str(e)}")

async def security_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    try:
        # Fail2Ban Status (if installed)
        f2b_status = "Not Installed"
        if subprocess.call("command -v fail2ban-client", shell=True) == 0:
            f2b_status = subprocess.check_output("fail2ban-client status sshd | grep 'Currently banned' | awk '{print $4}'", shell=True).decode().strip()
        
        # Last Logins
        last_logins = subprocess.check_output("last -n 5 -a | head -n 5", shell=True).decode()
        
        msg = (
            f"🛡️ *Security Overview*\n\n"
            f"🚫 Banned IPs (SSHD): `{f2b_status}`\n\n"
            f"🔑 *Last 5 Logins:*\n"
            f"```\n{last_logins}\n```"
        )
        await update.message.reply_text(msg, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"Error: {str(e)}")

async def panic_mode(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    if not context.args:
        await update.message.reply_text("⚠️ Usage: /panic <YOUR_IP>\nThis will BLOCK ALL TRAFFIC except SSH from your IP.")
        return
    
    trusted_ip = context.args[0]
    await update.message.reply_text(f"🚨 ACTIVATING PANIC MODE for IP: `{trusted_ip}`...", parse_mode='Markdown')
    
    try:
        # Execute panic mode commands directly
        cmds = [
            "ufw --force reset",
            "ufw default deny incoming",
            "ufw default allow outgoing",
            f"ufw allow from {trusted_ip} to any port 22 proto tcp",
            "ufw --force enable"
        ]
        for cmd in cmds:
            subprocess.check_call(cmd, shell=True)
            
        await update.message.reply_text(f"✅ PANIC MODE ACTIVE. Only `{trusted_ip}` can access via SSH.", parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"❌ Failed to activate Panic Mode: {str(e)}")

async def unpanic_mode(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    await update.message.reply_text("🟢 Deactivating Panic Mode...", parse_mode='Markdown')
    
    try:
        cmds = [
            "ufw --force reset",
            "ufw default deny incoming",
            "ufw default allow outgoing",
            "ufw allow ssh",
            "ufw allow 80/tcp",
            "ufw allow 443/tcp",
            "ufw allow 3000/tcp",
            "ufw --force enable"
        ]
        for cmd in cmds:
            subprocess.check_call(cmd, shell=True)
            
        await update.message.reply_text("✅ Panic Mode Deactivated. Default rules restored.", parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"❌ Failed to deactivate: {str(e)}")

async def resources(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not check_auth(update): return
    
    try:
        # Top 5 CPU
        top_cpu = subprocess.check_output("ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 6", shell=True).decode()
        
        msg = (
            f"📉 *Top Processes (CPU)*\n"
            f"```\n{top_cpu}\n```"
        )
        await update.message.reply_text(msg, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"Error: {str(e)}")

if __name__ == '__main__':
    load_config()
    
    if not BOT_TOKEN or not CHAT_ID:
        print("Error: BOT_TOKEN or CHAT_ID missing in config.")
        sys.exit(1)

    app = ApplicationBuilder().token(BOT_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("caprover", caprover))
    app.add_handler(CommandHandler("docker", docker_list))
    app.add_handler(CommandHandler("search", search_container))
    app.add_handler(CommandHandler("logs", get_logs))
    app.add_handler(CommandHandler("restart", restart_container))
    app.add_handler(CommandHandler("exec", exec_cmd))
    
    # New Handlers
    app.add_handler(CommandHandler("network", network_stats))
    app.add_handler(CommandHandler("security", security_stats))
    app.add_handler(CommandHandler("panic", panic_mode))
    app.add_handler(CommandHandler("unpanic", unpanic_mode))
    app.add_handler(CommandHandler("resources", resources))
    
    print("Bot started...")
    app.run_polling()
