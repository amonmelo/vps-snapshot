<p align="center">
  <img src="assets/logo.svg" alt="VPS Snapshot" width="480">
</p>

<p align="center">
  <a href="https://github.com/amonmelo/vps-snapshot/releases"><img src="https://img.shields.io/badge/versión-1.0.0-blue?style=flat-square" alt="Versión"></a>
  <a href="https://github.com/amonmelo/vps-snapshot/blob/main/LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-green?style=flat-square" alt="Licencia"></a>
  <a href="https://github.com/amonmelo/vps-snapshot#-inicio-rápido"><img src="https://img.shields.io/badge/instalar-1%20comando-orange?style=flat-square" alt="1 comando"></a>
  <a href="https://github.com/amonmelo/vps-snapshot#-proveedores-soportados"><img src="https://img.shields.io/badge/nube-8%20proveedores-9cf?style=flat-square" alt="Proveedores"></a>
</p>

<p align="center">
  🇧🇷 <a href="README.md">Português</a> · 🇺🇸 <a href="README.en.md">English</a> · 🇪🇸 <strong>Español</strong> · 🇩🇪 <a href="README.de.md">Deutsch</a>
</p>

<p align="center">
  <strong>Backup completo de tu VPS a la nube. Un comando para instalar, un comando para ejecutar.</strong>
</p>

<p align="center">
  <a href="#-inicio-rápido">Inicio Rápido</a> ·
  <a href="#-recursos">Recursos</a> ·
  <a href="#-proveedores-soportados">Proveedores</a> ·
  <a href="#-configuración">Configuración</a> ·
  <a href="#-seguridad">Seguridad</a>
</p>

---

## ¿Por qué VPS Snapshot?

Los proveedores de VPS rara vez ofrecen backups automáticos, y cuando lo hacen, suelen ser costosos y limitados. **VPS Snapshot** resuelve esto creando backups completos de tu servidor directamente a la nube, con compresión, cifrado y verificación de integridad.

**Características principales:**
- 🚀 **Un solo comando** para instalar y ejecutar
- 🔐 **Cifrado GPG** de extremo a extremo (opcional)
- 🗜️ **Compresión pigz** multinúcleo para backups más rápidos
- ☁️ **8 proveedores** en la nube soportados (incluso planes gratuitos)
- ⏰ **Ejecución automática** vía cron con rotación inteligente
- 📋 **Verificación SHA-256** para garantizar integridad de los datos
- 🔄 **Restauración flexible** — restaura archivos individuales o el backup completo
- 🧹 **Limpieza automática** — elimina backups antiguos según la política de retención
- 📊 **Registros detallados** con resumen del backup y estadísticas de transferencia
- 🖥️ **Sin dependencias pesadas** — usa Bun (< 100MB) en lugar de Docker o Node.js

---

## 🚀 Inicio Rápido

### Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | bash
```

### Crear un backup

```bash
vps-snapshot
```

Eso es todo. Tu primer backup estará en la nube en minutos. ⚡

> **Nota:** En la primera ejecución, se te guiará por la configuración de rclone si aún no lo has configurado.

---

## ✨ Recursos

| Recurso | Descripción |
|---------|-------------|
| 🗜️ **Compresión** | Usa pigz para compresión paralela multinúcleo (mucho más rápido que gzip) |
| 🔐 **Cifrado** | Cifrado GPG simétrico opcional con passphrase personalizada |
| 📋 **Verificación** | Hash SHA-256 calculado antes y después del backup para detectar corrupción |
| ⏰ **Programación** | Integración con cron para backups automáticos periódicos |
| 🔄 **Restauración** | Restaura archivos individuales o el backup completo |
| 🧹 **Limpieza** | Rotación automática basada en el número de backups a conservar |
| 📊 **Registros** | Registro detallado con tamaño, duración, checksum y estado de transferencia |
| ⚡ **Rendimiento** | Compresión en paralelo y streaming directo (sin archivos temporales grandes) |

---

## ☁️ Proveedores Soportados

VPS Snapshot funciona con cualquier servicio compatible con rclone. Aquí están los más populares:

| Proveedor | Espacio Gratis | Configuración |
|-----------|---------------|---------------|
| **Google Drive** | 15 GB | `rclone config` →drive |
| **Dropbox** | 2 GB | `rclone config` →dropbox |
| **OneDrive** | 5 GB | `rclone config` →onedrive |
| **Amazon S3** | 5 GB (12 meses) | `rclone config` →s3 |
| **Backblaze B2** | 10 GB | `rclone config` →b2 |
| **MEGA** | 20 GB | `rclone config` →mega |
| **pCloud** | 10 GB | `rclone config` →pcloud |
| **Wasabi** | 30 días de prueba | `rclone config` →wasabi |
| **Cualquier servicio compatible con S3** | Varía | `rclone config` →s3 / otros |

> **Consejo:** ¿Buscas almacenamiento gratuito? **MEGA** ofrece 20 GB gratis, ideal para backups de VPS pequeños. **Google Drive** es otra excelente opción con 15 GB.

---

## ⚙️ Cómo Funciona

```
Tu VPS                              Nube (ej: Google Drive)
┌─────────────────┐                ┌─────────────────────┐
│  /etc           │                │                     │
│  /home          │──┐             │  vps-snapshot/      │
│  /var           │  │  pigz       │  ├── backup.tar.gz  │
│  /root          │  │  compresión │  ├── backup.tar.gz  │
│  /usr/local     │  ├─►           │  ├── backup.sha256  │
│  ...            │  │  (opcional) │  ├── backup.sha256  │
│                 │  │  GPG        │  └── backup.log     │
│                 │  │  cifrado    │                     │
│                 │──┤             │                     │
│                 │  │  rclone     │                     │
│                 │  │  subida     │                     │
└─────────────────┘  └──►          └─────────────────────┘
```

**Flujo del backup:**

1. **Preparación** — Se crea una lista de directorios para excluir archivos temporales y de caché
2. **Compresión** — pigz comprime los datos en paralelo usando todos los núcleos disponibles
3. **Cifrado** (opcional) — GPG cifra el archivo comprimido con tu passphrase
4. **Verificación** — Se calcula el hash SHA-256 antes de la subida
5. **Subida** — rclone transfiere el archivo al proveedor de nube configurado
6. **Verificación final** — Se confirma que el archivo fue transferido correctamente
7. **Limpieza** — Backups antiguos se eliminan según la política de retención
8. **Registro** — Se guarda un archivo de log detallado con todas las estadísticas

---

## ⚙️ Configuración

Todos los ajustes se configuran en `/opt/vps-snapshot/.env`:

```bash
# Configuración del proveedor de nube (rclone)
CLOUD_REMOTE=google Drive           # Nombre del remote de rclone
CLOUD_PATH=vps-snapshot             # Carpeta de destino en la nube
CLOUD_RETENTION=5                   # Número de backups a conservar

# Compresión
COMPRESSION_THREADS=0               # 0 = usar todos los núcleos disponibles

# Cifrado GPG (opcional)
GPG_ENABLED=false                   # true para habilitar cifrado
GPG_PASSPHRASE=                     # Tu passphrase de cifrado (¡guárdala con seguridad!)

# Directorios a respaldar (separados por espacio)
BACKUP_DIRS="/etc /home /var /root /usr/local /opt"

# Directorios a excluir (patrones)
EXCLUDE_DIRS="*.tmp *.cache node_modules .cache __pycache__"
```

---

## 📋 Todos los Comandos

```bash
vps-snapshot                    # Crear un backup ahora
vps-snapshot schedule           # Configurar backup automático (cron)
vps-snapshot unschedule         # Eliminar backup automático
vps-snapshot list               # Listar backups disponibles
vps-snapshot restore            # Restaurar el último backup
vps-snapshot restore <archivo>  # Restaurar un backup específico
vps-snapshot pull <ruta>        # Descargar un archivo/directorio específico del backup
vps-snapshot clean              # Eliminar backups antiguos (respetando retención)
vps-snapshot logs               # Ver registros del último backup
vps-snapshot status             # Verificar estado de la configuración
vps-snapshot update             # Actualizar a la última versión
vps-snapshot uninstall          # Desinstalar completamente
```

| Comando | Descripción |
|---------|-------------|
| `vps-snapshot` | Crear un backup completo ahora |
| `vps-snapshot schedule` | Configurar ejecución automática vía cron |
| `vps-snapshot unschedule` | Eliminar la tarea programada de cron |
| `vps-snapshot list` | Listar todos los backups disponibles en la nube |
| `vps-snapshot restore` | Restaurar el último backup completo |
| `vps-snapshot restore <archivo>` | Restaurar un backup específico |
| `vps-snapshot pull <ruta>` | Descargar un archivo o directorio específico |
| `vps-snapshot clean` | Eliminar backups antiguos según la retención configurada |
| `vps-snapshot logs` | Mostrar los registros del último backup |
| `vps-snapshot status` | Verificar el estado de la configuración y rclone |
| `vps-snapshot update` | Actualizar VPS Snapshot a la última versión |
| `vps-snapshot uninstall` | Desinstalar VPS Snapshot completamente |

---

## 🔒 Seguridad

La seguridad es una prioridad en VPS Snapshot. Cada capa añade protección:

| Capa | Implementación |
|------|----------------|
| **Compresión** | pigz reduce el tamaño del backup en 60-80%, menor superficie de ataque |
| **Cifrado** | GPG con cifrado AES-256 simétrico — ni el proveedor puede leer tus datos |
| **Integridad** | Hash SHA-256 verifica que los datos no fueron alterados durante la transferencia |
| **Transporte** | rclone usa TLS para todas las transferencias de datos |
| **Almacenamiento** | Los datos cifrados se almacenan de forma segura en tu proveedor de nube |
| **Local** | Sin archivos temporales sin cifrar — el pipeline fluye directamente |
| **Acceso** | Permisos restrictivos en los archivos de configuración (solo root) |

> **Importante:** La passphrase de GPG es necesaria para restaurar. Sin ella, los datos son irrecuperables. Guárdala en un lugar seguro.

---

## 🏗️ Arquitectura

```
/opt/vps-snapshot/
├── src/
│   ├── index.ts              # Punto de entrada principal
│   ├── backup.ts             # Lógica principal de backup
│   ├── restore.ts            # Lógica de restauración
│   ├── compress.ts           # Compresión pigz
│   ├── encrypt.ts            # Cifrado/descifrado GPG
│   ├── verify.ts             # Verificación SHA-256
│   ├── cloud.ts              # Integración con rclone
│   ├── scheduler.ts          # Gestión de cron
│   ├── config.ts             # Carga de configuración (.env)
│   ├── logger.ts             # Sistema de registros
│   └── utils.ts              # Utilidades varias
├── .env                      # Configuración del usuario
├── vps-snapshot              # Binario compilado
└── logs/                     # Registros de backups
```

El proyecto usa **Bun** como runtime de TypeScript para un rendimiento superior y una huella mínima (< 100MB vs ~400MB de Node.js).

---

## 📋 Requisitos

| Requisito | Versión mínima |
|-----------|---------------|
| **Sistema operativo** | Ubuntu 20.04+, Debian 10+, CentOS 7+ |
| **Acceso** | root o sudo |
| **rclone** | 1.60+ (se instala automáticamente) |
| **pigz** | 2.3+ (se instala automáticamente) |
| **GPG** | 2.0+ (se instala automáticamente, solo si se habilita cifrado) |
| **Bun** | Se instala automáticamente durante la instalación |
| **Memoria RAM** | Mínimo 512MB libres para la compresión |
| **Espacio en disco** | Espacio temporal para el archivo comprimido |
| **Cuenta en la nube** | Cualquier proveedor compatible con rclone |

---

## 🗑️ Desinstalación

Para desinstalar VPS Snapshot completamente:

```bash
vps-snapshot uninstall
```

Esto eliminará:
- El directorio `/opt/vps-snapshot/`
- El enlace simbólico `/usr/local/bin/vps-snapshot`
- La tarea programada de cron (si existe)
- Los archivos binarios de Bun instalados

> **Nota:** Esto **no** elimina tus backups en la nube ni la configuración de rclone.

---

## 📄 Licencia

Este proyecto está licenciado bajo la **MIT License** — consulta el archivo [LICENSE](LICENSE) para más detalles.

---

<p align="center">
  Hecho con <a href="https://bun.sh/">Bun</a> · Potenciado por <a href="https://rclone.org/">rclone</a><br>
  Creado por <a href="https://www.linkedin.com/in/amonmelo/">Amon Melo</a>
</p>
