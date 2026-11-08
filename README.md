# 🎙️ Ultrón. Control de voz

> [!IMPORTANT]
> **Compatibilidad:** Diseñado **única y exclusivamente para Antigravity** en macOS. No es compatible con otros entornos o navegadores estándar, ya que se acopla directamente al protocolo CDP interno de Antigravity.

Sistema autónomo y ultraligero (<1% CPU en reposo) de **control de voz para Antigravity**. Escucha en segundo plano desde el micrófono de tu Mac y, al detectar **"Hey Ultrón"**, despierta instantáneamente la llamada de voz nativa de Antigravity vía Chrome DevTools Protocol (CDP) sin colisiones de hardware.

---

## ⚡ Instalación Rápida (1 Comando)

### Método A: Directo desde la Nube (curl)
```bash
curl -fsSL https://raw.githubusercontent.com/kevinjandro-pro/ultron-assistant/main/install.sh | bash
```

### Método B: Clonar Repositorio
```bash
git clone https://github.com/kevinjandro-pro/ultron-assistant.git
cd ultron-assistant
./install.sh
```

El instalador cuenta con **Protocolo de Cero Suposiciones (Zero-Assumption Protocol)**:
- Diagnostica si hay micrófonos conectados. Si no encuentra ninguno (ej. Mac en modo cerrado o Mac Studio), te guía para conectar uno externo o reintentar sin fallar a ciegas.
- Comprueba permisos de privacidad en macOS y se ofrece a abrir la configuración si están bloqueados.
- Detecta y enlaza automáticamente con la ventana activa de Antigravity.
- Aísla las dependencias en un entorno virtual propio (`~/.config/ultron-assistant/.venv`).

---

## 🛠️ Comandos de Control (CLI)

Una vez instalado, controla a Ultrón desde cualquier parte de tu terminal:

| Comando | Acción |
| :--- | :--- |
| `ultron on` | Inicia la escucha en segundo plano como centinela invisible. |
| `ultron off` | Detiene el centinela por completo y libera el micrófono. |
| `ultron status` | Muestra estado en tiempo real, PID, tiempo activo y consumo de CPU/RAM. |
| `ultron logs` | Muestra los últimos eventos y transcripciones de escucha. |
| `ultron test` | Ejecuta un autodiagnóstico de conexión con Antigravity. |
| `ultron restart` | Reinicia el centinela. |

---

## ⚙️ Configuración Personalizada

Puedes ajustar la sensibilidad o cambiar las palabras clave en `~/.config/ultron-assistant/config.json`:

```json
{
  "wake_words": ["hey ultron", "ey ultron", "oye ultron", "hola ultron", "ultron"],
  "mic_preference": "auto",
  "whisper_model": "tiny",
  "vad_filter": true,
  "beam_size": 1,
  "threads": 2,
  "min_amplitude": 0.008,
  "feedback_chime": "/System/Library/Sounds/Glass.aiff"
}
```

---

## 📋 Arquitectura Técnica

1. **Captura:** `ffmpeg` lee audio en formato PCM s16le a 16kHz en un ring buffer en memoria (3 segundos).
2. **Filtro de Energía & VAD:** Si la amplitud es inferior a `min_amplitude` (silencio o ruido de fondo leve), el modelo Whisper no se ejecuta, manteniendo el uso de CPU prácticamente en cero.
3. **Inferencia Local:** Modelo `faster-whisper` (`tiny` cuantizado en `int8` en CPU) corriendo offline.
4. **Disparo de Antigravity:** Localiza `DevToolsActivePort` y envía un payload JSON-RPC WebSocket para hacer clic en el botón de llamada y desmutear el micrófono.
5. **Liberación de Audio:** Durante la llamada con Antigravity, el centinela apaga el pipe de `ffmpeg` para que no compita por el micrófono, y lo reanuda automáticamente al colgar.
