#!/usr/bin/env python3
"""
Ultrón. Control de voz - Exclusivo para Antigravity
Escucha en segundo plano y activa llamadas de voz por CDP ante la palabra clave.
"""

import os
import sys
import time
import shutil
import subprocess
import json
import re
import urllib.request
import asyncio
import collections
import threading
import signal
import websockets
import numpy as np
from faster_whisper import WhisperModel

CONFIG_DIR = os.path.expanduser("~/.config/ultron-assistant")
os.makedirs(CONFIG_DIR, exist_ok=True)
PID_FILE = os.path.join(CONFIG_DIR, "ultron.pid")
LOG_FILE = os.path.join(CONFIG_DIR, "assistant.log")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

# Configuración por defecto
DEFAULT_CONFIG = {
    "wake_words": ["hey ultron", "ey ultron", "oye ultron", "hola ultron", "ultron"],
    "mic_preference": "auto",
    "whisper_model": "tiny",
    "vad_filter": True,
    "beam_size": 1,
    "threads": 2,
    "min_amplitude": 0.009,
    "cooldown_seconds": 3.5,
    "feedback_chime": "/System/Library/Sounds/Glass.aiff"
}

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                return {**DEFAULT_CONFIG, **cfg}
        except Exception as e:
            print(f"[!] Error leyendo config.json: {e}. Usando valores por defecto.", flush=True)
    return DEFAULT_CONFIG

CONFIG = load_config()

def find_binary(name, common_paths):
    found = shutil.which(name)
    if found:
        return found
    for p in common_paths:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return name

FFMPEG_BIN = find_binary("ffmpeg", [
    "/opt/homebrew/bin/ffmpeg",
    "/usr/local/bin/ffmpeg",
    os.path.expanduser("~/.local/bin/ffmpeg")
])

EXCLUDE_KEYWORDS = ["mts", "speaker", "parlante", "caixa", "nexus", "hdmi", "display", "screen"]
INTERNAL_KEYWORDS = ["macbook", "built-in", "embutido", "interno", "micrófono", "microfone"]

# Coincidencia precisa que tolera variaciones fonéticas comunes de Whisper ("hay ultrón", "eh ultrón", "un tron", "ultrón")
WAKE_PATTERN = re.compile(
    r'\b(hey|ey|ay|hay|eh|e\s*y|oye|hola|ok)?\s*(ultr[oó]n|el\s*tr[oó]n|un\s*tr[oó]n|outron|altron)\b',
    re.IGNORECASE
)

def get_best_audio_device():
    pref = CONFIG.get("mic_preference", "auto")
    if pref != "auto" and pref:
        print(f"[*] Usando micrófono configurado manualmente: {pref}", flush=True)
        return pref

    try:
        cmd = [FFMPEG_BIN, "-f", "avfoundation", "-list_devices", "true", "-i", ""]
        p = subprocess.run(cmd, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
        audio_section = False
        devices = []
        for line in p.stderr.splitlines():
            if "AVFoundation audio devices:" in line:
                audio_section = True
                continue
            if audio_section:
                m = re.search(r'\[(\d+)\]\s+(.*)', line)
                if m:
                    devices.append((m.group(1), m.group(2).strip()))
        
        # 1. Prioridad: Micrófono interno físico del equipo
        for idx, name in devices:
            name_lower = name.lower()
            if any(ex in name_lower for ex in EXCLUDE_KEYWORDS):
                continue
            if any(inc in name_lower for inc in INTERNAL_KEYWORDS):
                print(f"[*] Micrófono interno físico detectado: [{idx}] {name}", flush=True)
                return f":{idx}"
        
        # 2. Prioridad: Cualquier entrada que indique micrófono o headset
        for idx, name in devices:
            name_lower = name.lower()
            if not any(ex in name_lower for ex in EXCLUDE_KEYWORDS) and any(m in name_lower for m in ["mic", "microf", "headset", "airpods"]):
                print(f"[*] Entrada secundaria seleccionada: [{idx}] {name}", flush=True)
                return f":{idx}"
                
        # 3. Fallback al primer dispositivo de audio disponible
        if devices:
            print(f"[*] Fallback a primer dispositivo detectado: [{devices[0][0]}] {devices[0][1]}", flush=True)
            return f":{devices[0][0]}"
    except Exception as e:
        print(f"[!] Error detectando dispositivos de audio: {e}", flush=True)
    
    return ":0"

def play_chime():
    chime_file = CONFIG.get("feedback_chime", "/System/Library/Sounds/Glass.aiff")
    if os.path.exists(chime_file):
        try:
            subprocess.Popen(["/usr/bin/afplay", chime_file])
        except Exception:
            pass

def get_cdp_port():
    port_file = os.path.expanduser('~/Library/Application Support/Antigravity/DevToolsActivePort')
    if os.path.exists(port_file):
        try:
            with open(port_file, 'r', encoding="utf-8") as f:
                lines = f.read().splitlines()
                if lines:
                    return int(lines[0])
        except Exception:
            pass
    return None

async def _activate_antigravity_voice_async():
    # Nota: NO usamos osascript para activar la ventana para no robar el foco de lo que hace el usuario
    port = get_cdp_port()
    if not port:
        print("[!] No se pudo obtener el puerto CDP de Antigravity.", flush=True)
        return False, "no_port"
    
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/json")
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            targets = json.loads(resp.read().decode())
        page = next((t for t in targets if t.get('type') == 'page' and not t.get('url', '').startswith('data:')), None)
        if not page:
            print("[!] No se encontró página activa en Antigravity.", flush=True)
            return False, "no_page"
        
        async with websockets.connect(page['webSocketDebuggerUrl'], open_timeout=3.0) as ws:
            activate_expr = '''
                (() => {
                    const controls = document.querySelector('[data-testid="voice-call-controls"]');
                    const startBtn = document.querySelector('[data-testid="voice-start-button"]');
                    const muteBtn = document.querySelector('[data-testid="voice-mute-button"]');
                    
                    if (!controls && startBtn) {
                        startBtn.click();
                        return { action: 'clicked_start' };
                    }
                    if (controls && muteBtn) {
                        const aria = muteBtn.getAttribute('aria-label') || '';
                        if (aria === 'Unmute mic' || muteBtn.className.includes('bg-red')) {
                            muteBtn.click();
                            return { action: 'unmuted' };
                        }
                        return { action: 'already_active_unmuted' };
                    }
                    return { action: 'no_controls_found' };
                })()
            '''
            cmd = {'id': 1, 'method': 'Runtime.evaluate', 'params': {'expression': activate_expr, 'returnByValue': True}}
            await ws.send(json.dumps(cmd))
            res = await ws.recv()
            val = json.loads(res).get('result', {}).get('result', {}).get('value', {})
            action = val.get('action', 'done')
            play_chime()
            return True, action
            
    except Exception as e:
        print(f"[!] Error conectando con CDP de Antigravity: {e}", flush=True)
        return False, str(e)

def activate_antigravity_voice():
    try:
        return asyncio.run(_activate_antigravity_voice_async())
    except Exception as e:
        return False, str(e)

def start_ffmpeg_pipe(mic_device):
    cmd = [
        FFMPEG_BIN, "-loglevel", "error",
        "-f", "avfoundation", "-i", mic_device,
        "-ar", "16000", "-ac", "1",
        "-f", "s16le", "-"
    ]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def main():
    with open(PID_FILE, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
        
    print("[*] Ultrón. Control de voz (Segundo plano) iniciado...", flush=True)
    mic_device = get_best_audio_device()
    print(f"[*] Dispositivo vinculado: {mic_device}", flush=True)
    
    threads = CONFIG.get("threads", 2)
    model_name = CONFIG.get("whisper_model", "tiny")
    print(f"[*] Cargando modelo Whisper {model_name} local en CPU ({threads} hilos)...", flush=True)
    model = WhisperModel(model_name, device="cpu", compute_type="int8", cpu_threads=threads)
    
    SAMPLE_RATE = 16000
    BUFFER_SECONDS = 3.0
    BUFFER_SAMPLES = int(SAMPLE_RATE * BUFFER_SECONDS)
    audio_ring = collections.deque(maxlen=BUFFER_SAMPLES)
    ring_lock = threading.Lock()
    running = True

    def handle_signal(sig, frame):
        nonlocal running
        print(f"[*] Señal recibida ({sig}), cerrando centinela limpiamente...", flush=True)
        running = False

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    current_proc = start_ffmpeg_pipe(mic_device)

    def audio_reader_thread():
        nonlocal current_proc, running
        while running:
            if current_proc and current_proc.stdout:
                try:
                    data = current_proc.stdout.read(3200) # 0.1s
                    if data:
                        samples = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
                        with ring_lock:
                            audio_ring.extend(samples)
                    else:
                        time.sleep(0.02)
                except Exception:
                    time.sleep(0.02)
            else:
                time.sleep(0.05)

    t = threading.Thread(target=audio_reader_thread, daemon=True)
    t.start()

    min_amp = CONFIG.get("min_amplitude", 0.009)
    cooldown_secs = CONFIG.get("cooldown_seconds", 3.5)
    print(f"[✓] Centinela activo y escuchando. Di 'Hey Ultrón' o 'Ultrón'.", flush=True)

    try:
        last_eval_time = time.time()
        last_heartbeat = time.time()
        cooldown_until = 0.0

        while running:
            time.sleep(0.15)
            
            with ring_lock:
                buf_len = len(audio_ring)
                if buf_len < int(SAMPLE_RATE * 1.0):
                    continue
                audio_data = np.array(list(audio_ring), dtype=np.float32)
                
            now = time.time()
            max_amp = np.max(np.abs(audio_data))
            
            if now - last_heartbeat >= 15.0:
                print(f"[*] Latido: activo (MaxAmp: {max_amp:.4f})...", flush=True)
                last_heartbeat = now
                
            if now < cooldown_until:
                continue
                
            if now - last_eval_time < 0.8:
                continue
                
            if max_amp < min_amp:
                continue
                
            last_eval_time = now
            
            try:
                segments, _ = model.transcribe(
                    audio_data,
                    language="es",
                    beam_size=CONFIG.get("beam_size", 1),
                    initial_prompt="Ultrón.",
                    vad_filter=CONFIG.get("vad_filter", True)
                )
                text = " ".join([s.text for s in segments]).strip().lower()
                clean_text = re.sub(r'[,.¡!¿?]', '', text).strip()
                
                if clean_text:
                    print(f"[Escuchado]: '{clean_text}' (MaxAmp: {max_amp:.4f})", flush=True)
                
                is_match = bool(WAKE_PATTERN.search(clean_text))
                
                if is_match:
                    print(f"[!] ¡WAKE-WORD DETECTADA ('{clean_text}')! Activando voz de Antigravity...", flush=True)
                    with ring_lock:
                        audio_ring.clear()
                    
                    ok, status = activate_antigravity_voice()
                    print(f"[*] Resultado activación Antigravity: {status} (ok={ok})", flush=True)
                    
                    cooldown_until = time.time() + cooldown_secs
                    last_eval_time = time.time()
                    last_heartbeat = time.time()
                    print("[✓] Centinela listo y escuchando en segundo plano.", flush=True)
            except Exception as ex:
                print(f"[!] Error procesando audio: {ex}", flush=True)

    finally:
        running = False
        if current_proc:
            try:
                current_proc.terminate()
            except Exception:
                pass
        try:
            if os.path.exists(PID_FILE):
                os.remove(PID_FILE)
        except Exception:
            pass

if __name__ == "__main__":
    main()
